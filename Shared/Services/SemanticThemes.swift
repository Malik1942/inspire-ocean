import Foundation
import NaturalLanguage

/// A semantic understanding of one captured thought — the product of the
/// understanding step that runs before anything is labelled or matched:
/// raw thought → understanding → concise essence → conceptual themes.
struct ThoughtUnderstanding {
    /// The thought's concise interpreted essence (also used as its title).
    var essence: String
    /// 1–3 short conceptual themes (concepts, intentions, emotions, domains).
    var themes: [String]
    /// Soft emotional tone ("bright" / "deep"), nil when there is no signal.
    var mood: String?
}

/// On-device conceptual theme detection.
///
/// Instead of extracting words from the text, this maps the thought's meaning
/// onto a curated vocabulary of human-readable concepts using `NLEmbedding`
/// word vectors: each concept is described by prototype words, and a thought
/// expresses a concept when its content words live near that concept's
/// embedding centroid. "The tide keeps returning my ideas" lands on
/// *recurring thoughts* because "returning" sits near return/repeat/cycle —
/// no shared surface word required.
///
/// The on-device foundation model replaces this with freely generated themes
/// when available (`LocalOceanAIService.understand`); this is the strongest
/// fallback that still reasons about meaning. Keyword extraction
/// (`ThemeDetector`) remains only as the last resort when embeddings are
/// unavailable (e.g. non-English text).
enum SemanticThemes {

    // MARK: Concept vocabulary

    /// Human-readable concepts and the prototype words that anchor them in
    /// embedding space. Labels are what the user sees as theme chips; the
    /// prototypes are never shown.
    static let concepts: [(label: String, prototypes: String)] = [
        ("creative direction", "create design draw paint sketch compose style imagine craft inspiration artistic"),
        ("product clarity", "product app feature interface prototype tool software user release build"),
        ("career uncertainty", "career job role promotion resign interview salary workplace profession"),
        ("personal reflection", "myself identity self introspection journal realize meaning who am"),
        ("emotional friction", "anxious stuck frustrated doubt worry fear tension restless overwhelmed"),
        ("social energy", "friends conversation people gathering team family community together belonging"),
        ("recurring thoughts", "returning repeat cycle rhythm pattern again resurface loop revisit"),
        ("water & ocean", "ocean sea tide river rain wave shore water swim depths"),
        ("nature & landscape", "mountain forest tree garden bird field soil wilderness landscape"),
        ("light & atmosphere", "light glow dusk dawn shadow sky cloud color luminous"),
        ("time & memory", "memory remember past childhood yesterday nostalgia history moment"),
        ("learning & curiosity", "learn study read research question understand curious knowledge explore"),
        ("technology", "computer code software algorithm digital machine data screen"),
        ("body & movement", "body walking running breath dance muscle exercise physical"),
        ("rest & stillness", "calm quiet still rest sleep slow pause silence peaceful"),
        ("play & wonder", "play wonder joy delight magic fun game whimsical"),
        ("growth & change", "grow change transform evolve becoming begin renewal transition"),
        ("home & place", "home room city street house neighborhood kitchen belonging"),
        ("money & security", "money rent savings budget cost debt afford financial"),
        ("love & closeness", "love tenderness partner heart warmth intimacy affection care"),
        ("loss & longing", "loss grief missing gone longing absence farewell mourning"),
        ("words & stories", "words language sentence story writing narrative poem voice"),
        ("sound & music", "music song melody rhythm sound listening chord harmony"),
        ("food & taste", "food cooking taste meal flavor recipe kitchen delicious"),
        ("travel & elsewhere", "travel journey road train map distant foreign wander"),
        ("decisions & direction", "decide choice direction path option crossroads whether deciding"),
        ("ambition & drive", "goal ambition dream achieve push drive success determined")
    ]

    /// Tuned on the word-vector scale: a content word within ~this cosine of a
    /// concept centroid genuinely evokes it; below, the link is noise.
    static let conceptThreshold = 0.42
    /// Runner-up concepts must hold this fraction of the top concept's score,
    /// so one strong concept isn't padded with weak ones.
    static let runnerUpRatio = 0.82

    private static let centroidLock = NSLock()
    private static var centroids: [(label: String, vector: [Double])]?

    private static func conceptCentroids() -> [(label: String, vector: [Double])] {
        centroidLock.lock()
        defer { centroidLock.unlock() }
        if let centroids { return centroids }
        let computed = concepts.compactMap { concept -> (String, [Double])? in
            guard let v = EmbeddingService.shared.vector(for: concept.prototypes) else { return nil }
            return (concept.label, v)
        }
        centroids = computed
        return computed
    }

    // MARK: Themes

    /// Conceptual themes for a thought. `essence` (the interpreted title, when
    /// already known) is blended in so the understood meaning — not just the
    /// raw wording — drives the mapping.
    static func themes(for text: String, essence: String = "", max: Int = 3) -> [String] {
        let basis = [essence, text].filter { !$0.isEmpty }.joined(separator: " ")
        let words = contentWords(in: basis)
        guard !words.isEmpty else { return [] }

        let centroids = conceptCentroids()
        if !centroids.isEmpty {
            let vectors = words.compactMap { EmbeddingService.shared.vector(for: $0) }
            if !vectors.isEmpty {
                var scored: [(label: String, score: Double)] = []
                for (label, centroid) in centroids {
                    // Mean of the two strongest word→concept affinities: one
                    // evocative word can carry a short thought, two confirm it.
                    let sims = vectors.map { EmbeddingService.cosine($0, centroid) }.sorted(by: >)
                    let top = sims.prefix(2)
                    let score = top.reduce(0, +) / Double(top.count)
                    scored.append((label, score))
                }
                scored.sort { $0.score > $1.score }

                if let best = scored.first, best.score >= conceptThreshold {
                    let floor = Swift.max(conceptThreshold, best.score * runnerUpRatio)
                    return scored.prefix(while: { $0.score >= floor })
                        .prefix(max)
                        .map { $0.label }
                }
            }
        }

        // Last resort (no embeddings, or nothing conceptual): clean keywords.
        return Array(ThemeDetector.themes(from: basis).prefix(2))
    }

    /// The full understanding fallback used when no language model is
    /// available: essence from the distiller, themes from concept mapping,
    /// mood from the light valence heuristic.
    static func understand(_ text: String) -> ThoughtUnderstanding {
        let essence = TitleDistiller.essence(from: text)
        return ThoughtUnderstanding(
            essence: essence,
            themes: themes(for: text, essence: essence),
            mood: ThemeDetector.mood(from: text)
        )
    }

    // MARK: Relatedness

    /// Floor below which two thoughts are simply not related — better to show
    /// nothing than a stretch.
    static let relatednessFloor = 0.34

    /// How strongly two thoughts belong near each other, in ~[0, 1].
    ///
    /// Blends meaning-level signals: embedding similarity of the full content,
    /// overlap of conceptual themes, and shared emotional tone. Pure text
    /// overlap can only enter through the embedding term, where averaging
    /// dilutes a single shared surface word.
    static func relatedness(
        textA: String, themesA: [String], moodA: String?,
        textB: String, themesB: [String], moodB: String?
    ) -> Double {
        let sim = max(0, EmbeddingService.shared.similarity(textA, textB))

        let setA = Set(themesA), setB = Set(themesB)
        let themeOverlap: Double
        if setA.isEmpty || setB.isEmpty {
            themeOverlap = 0
        } else {
            themeOverlap = Double(setA.intersection(setB).count) / Double(setA.union(setB).count)
        }

        let moodMatch: Double = (moodA != nil && moodA == moodB) ? 1 : 0

        return 0.60 * sim + 0.32 * themeOverlap + 0.08 * moodMatch
    }

    // MARK: Tokenization

    /// Meaning-bearing words: everything except function words and very short
    /// tokens. Verbs and adjectives stay — "returning" and "anxious" carry the
    /// concept even though they'd never make a keyword theme.
    static func contentWords(in text: String) -> [String] {
        let lowered = text.lowercased()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = lowered

        var seen = Set<String>()
        var words: [String] = []
        tokenizer.enumerateTokens(in: lowered.startIndex..<lowered.endIndex) { range, _ in
            let token = String(lowered[range])
            guard token.count > 2,
                  !ThemeDetector.functionWords.contains(token),
                  token.rangeOfCharacter(from: .letters) != nil,
                  seen.insert(token).inserted
            else { return true }
            words.append(token)
            return true
        }
        return words
    }
}
