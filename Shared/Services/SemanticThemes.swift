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
    ///
    /// **Open gap, not closed by this pass**: prototypes are English-only.
    /// `EmbeddingService`'s two candidate backends (contextual and dual
    /// per-language `NLEmbedding`) were both measured to give Chinese and
    /// English *separate, non-comparable* vector spaces (see that file's
    /// doc comment) — so a Chinese thought's content words are compared
    /// against these English prototypes across two unrelated spaces, which
    /// scores near-zero contrast for every concept regardless of true
    /// meaning, not just weak matches. Concept-mapping for Chinese text is
    /// effectively unusable until either the prototypes gain Chinese
    /// synonyms (embedded per-language, like the concept centroid would
    /// need to become per-language too) or a translation bridge exists.
    /// Flagged as an open question rather than fixed here: it's a content
    /// pass, not a tokenization or backend-seam fix.
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

    /// Tuned on the contrast scale (cosine above the word's mean affinity to
    /// all concepts): a concept a distinctive word genuinely evokes clears
    /// this; flat, everything-ish affinities do not.
    static let conceptThreshold = 0.10
    /// Runner-up concepts must hold this fraction of the top concept's score,
    /// so one strong concept isn't padded with weak ones.
    static let runnerUpRatio = 0.70

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
        let scored = scoredConcepts(for: basis)

        if let best = scored.first, best.score >= conceptThreshold {
            let floor = Swift.max(conceptThreshold, best.score * runnerUpRatio)
            return scored.prefix(while: { $0.score >= floor })
                .prefix(max)
                .map { $0.label }
        }

        // Last resort (no embeddings, or nothing conceptual): clean keywords.
        return Array(ThemeDetector.themes(from: basis).prefix(2))
    }

    /// Every concept scored against the text, strongest first.
    ///
    /// A word's vote for a concept is its *contrast*: cosine to that concept
    /// minus its mean cosine to all concepts. Generic words ("felt", "keeps")
    /// sit moderately near everything, so their contrast is ~0 everywhere and
    /// they cannot create a theme; only distinctive words carry meaning in.
    /// A concept's score is the mean of its two strongest word votes — one
    /// evocative word can carry a short thought, two confirm it.
    static func scoredConcepts(for text: String) -> [(label: String, score: Double)] {
        let words = contentWords(in: text)
        guard !words.isEmpty else { return [] }
        let vectors = words.compactMap { EmbeddingService.shared.vector(for: $0) }
        guard !vectors.isEmpty else { return [] }

        let centroids = conceptCentroids()
        guard !centroids.isEmpty else { return [] }

        // contrasts[w][c] = cos(word w, concept c) − mean over c
        var contrasts: [[Double]] = []
        for v in vectors {
            let sims = centroids.map { EmbeddingService.cosine(v, $0.vector) }
            let mean = sims.reduce(0, +) / Double(sims.count)
            contrasts.append(sims.map { $0 - mean })
        }

        var scored: [(label: String, score: Double)] = []
        for (c, centroid) in centroids.enumerated() {
            let votes = contrasts.map { $0[c] }.sorted(by: >)
            let top = votes.prefix(2)
            scored.append((centroid.label, top.reduce(0, +) / Double(top.count)))
        }
        return scored.sorted { $0.score > $1.score }
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

    /// Cleans a model-produced theme list ("1. Creative Direction, Memory…")
    /// into chip-ready labels: lowercase, at most three words each, deduped,
    /// capped at three. Returns [] when nothing usable survives, so callers
    /// can fall back to concept mapping.
    static func tidyThemeList(_ raw: String) -> [String] {
        var seen = Set<String>()
        let trimSet = CharacterSet(charactersIn: "-–—•*\"'“”‘’.:;0123456789() ")
        let cleaned = raw
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "·" || $0.isNewline })
            .compactMap { piece -> String? in
                let s = piece.trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: trimSet)
                    .lowercased()
                guard !s.isEmpty, s.count <= 28,
                      s.split(separator: " ").count <= 3,
                      seen.insert(s).inserted
                else { return nil }
                return s
            }
        return Array(cleaned.prefix(3))
    }

    // MARK: Relatedness

    /// Floor below which two thoughts are simply not related — better to show
    /// nothing than a stretch. Averaged word vectors give any two English
    /// sentences a baseline ~0.3–0.4; genuine meaning-level neighbors clear
    /// 0.48 and unrelated pairs stay under 0.41 on the blended scale.
    ///
    /// Derived against the (then English-only) `NLEmbedding` backend, pre
    /// bilingual-voice. `Scripts/embedding-floor-sweep/sweep.swift` now also
    /// reports candidate floors for the contextual and dual-per-language
    /// backends over a small zh/en/mixed fixture set — re-derive this value
    /// from those numbers once a backend is picked; this task intentionally
    /// leaves it unchanged.
    static let relatednessFloor = 0.45

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
    ///
    /// Already used `NLTokenizer` rather than a whitespace split (Chinese has
    /// no whitespace word boundaries, so a `.split(separator: " ")`-style
    /// approach would silently treat an entire Chinese sentence as one
    /// token), but the length filter was not CJK-aware: `token.count > 2`
    /// requires three-plus Latin letters, while most Chinese content words
    /// are exactly two characters — the same filter that correctly drops
    /// English filler ("of", "in") would have dropped nearly every Chinese
    /// word too. The minimum is now 1 for tokens containing a CJK ideograph
    /// (i.e. any token with 2+ Han characters passes) and 2 otherwise,
    /// unchanged from before for non-CJK text.
    ///
    /// `ThemeDetector.grammaticalWords` (the stopword filter below) is
    /// English-only, so Chinese function words (的/了/是/在/和, …) are not
    /// excluded here — a smaller, separate gap from the tokenization fix,
    /// also left open (see `concepts`'s doc comment for the larger reason
    /// this doesn't fully fix Chinese theme detection on its own).
    static func contentWords(in text: String) -> [String] {
        let lowered = text.lowercased()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = lowered

        var seen = Set<String>()
        var words: [String] = []
        tokenizer.enumerateTokens(in: lowered.startIndex..<lowered.endIndex) { range, _ in
            let token = String(lowered[range])
            let isCJK = token.unicodeScalars.contains { $0.properties.isIdeographic }
            let minLength = isCJK ? 1 : 2
            guard token.count > minLength,
                  !ThemeDetector.grammaticalWords.contains(token),
                  token.rangeOfCharacter(from: .letters) != nil,
                  seen.insert(token).inserted
            else { return true }
            words.append(token)
            return true
        }
        return words
    }
}
