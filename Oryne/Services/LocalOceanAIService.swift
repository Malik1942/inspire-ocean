import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device implementation of the Ocean AI seam for V1.
///
/// Everything it returns is grounded in the user's actual nodes (the core
/// mitigation against "AI feels generic"). It uses `EmbeddingService` for
/// semantic ranking and `ThemeDetector` for themes, and composes reflective,
/// evidence-based responses rather than free-floating generation.
final class LocalOceanAIService: OceanAIService {

    private let embeddings = EmbeddingService.shared
    private let transcriber = DriftTranscriber()

    init() {
        // Prime the foundation-model availability check off the critical path —
        // the first query can take over a second on ineligible hardware, which
        // would otherwise delay the first capture's title past the post-capture
        // moment's window.
        if #available(iOS 26, *) {
            Task.detached(priority: .utility) { _ = Self.foundationModelAvailable }
        }
    }

    // MARK: Transcription

    func transcribe(audioURL: URL) async -> String? {
        await transcriber.transcribe(url: audioURL)
    }

    func transcribeDetailed(audioURL: URL, vocabulary: [String]) async -> TranscriptOutcome? {
        await transcriber.transcribe(url: audioURL, vocabulary: vocabulary)
    }

    /// The reading of a long whisper: the substance in 2 or 3 sentences, in
    /// the note's own language, first person kept. On-device model only; no
    /// template stands in for it, because a summary that is not a reading of
    /// the words would be a lie with good intentions (§5).
    func summarizeTranscript(_ text: String) async -> String? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 200 else { return nil }
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            guard Self.foundationModelAvailable else { return nil }
            do {
                let session = LanguageModelSession {
                    """
                    You condense a spoken note into its substance. Reply with two or three \
                    plain sentences in the same language the note is in (if it mixes Chinese \
                    and English, answer in the language most of it is in). Keep the speaker's \
                    first person: "I" stays "I". No preamble, no list, no quotation marks, \
                    no heading. Say what they are getting at, not that they said it.
                    """
                }
                let response = try await session.respond(to: String(cleaned.prefix(6000)))
                let summary = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return summary.isEmpty ? nil : summary
            } catch {
                return nil
            }
            #else
            return nil
            #endif
        }
        return nil
    }

    // MARK: Understanding

    /// Raw thought → semantic understanding → essence + conceptual themes.
    /// The foundation model interprets freely when available; otherwise the
    /// concept-space fallback (`SemanticThemes`) still maps meaning, not words.
    ///
    /// With the model available, a second constrained question asks which of
    /// `currents` the thought is about (`FoundationCurrentPicker`), run
    /// alongside the themes call; a pick leads the themes so the thought
    /// joins that current (`CurrentSnap.resolve`). The concept fallback has
    /// no trustworthy signal for joining, so it leaves grouping as it was.
    func understand(_ text: String, currents: [CurrentCandidate]) async -> ThoughtUnderstanding {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return ThoughtUnderstanding(essence: "Untitled drift", themes: [], mood: nil)
        }

        if #available(iOS 26, *), Self.foundationModelAvailable {
            async let pick = FoundationCurrentPicker.pick(entry: cleaned, candidates: currents)
            var understanding = await foundationModelUnderstanding(for: cleaned)
            // The current it joins: the model's constrained pick; failing
            // that, its own English theme key when a current already has
            // it (the bridge across languages); failing that, it founds one.
            let joined = CurrentSnap.joinKey(pick: await pick, candidates: currents, entry: cleaned)
            let ownKey = understanding.themeKeys.first
            let existing = Set(currents.map(\.key))
            understanding.currentKey = joined
                ?? (ownKey.map { existing.contains($0) } == true ? ownKey : nil)
                ?? ownKey
                ?? understanding.themes.first.map(ThoughtReading.slug)
            return understanding
        }
        return SemanticThemes.understand(cleaned)
    }

    /// The full understanding record from one guided call
    /// (`FoundationThoughtReader`), cleaned by `ThoughtReading`. When the
    /// guided call declines (a guardrail, the context), the two older
    /// free-text calls still give a title and themes, and the record stays
    /// partial so a later pass can complete it.
    @available(iOS 26, *)
    private func foundationModelUnderstanding(for text: String) async -> ThoughtUnderstanding {
        let language = ThoughtReading.language(of: text)
        let mood = ThemeDetector.mood(from: text)

        if let reading = await FoundationThoughtReader.read(entry: text) {
            let title = TitleDistiller.tidy(reading.title)
            let essence = (!title.isEmpty && TitleDistiller.speaksLike(title, entry: text))
                ? title
                : TitleDistiller.essence(from: text)
            // Themes are held to the entry's script the way the title is;
            // an English entry whose themes came back Chinese takes the
            // model's own English rendering of them.
            let inScript = ThoughtReading.themesInEntryScript(reading.themes, english: reading.themesInEnglish, entry: text)
            let modelThemes = SemanticThemes.tidyThemeList(inScript.joined(separator: ", "))
            let themes = modelThemes.isEmpty ? SemanticThemes.themes(for: text, essence: essence) : modelThemes
            return ThoughtUnderstanding(
                essence: essence,
                themes: themes,
                mood: mood,
                // Form decides quote, question and link; the model the rest.
                category: ThoughtReading.formalCategory(for: text) ?? reading.category,
                language: language,
                gistOther: ThoughtReading.tidyGist(reading.gistInOtherLanguage, entryLanguage: language),
                entities: ThoughtReading.tidyEntities(reading.entities),
                themeKeys: ThoughtReading.keys(fromEnglish: reading.themesInEnglish, fallbackLabels: themes),
                source: .model
            )
        }

        let modelTitle = await foundationModelTitle(for: text)
            .map(TitleDistiller.tidy)
            .flatMap { TitleDistiller.speaksLike($0, entry: text) ? $0 : nil }
        let essence = modelTitle ?? TitleDistiller.essence(from: text)
        let modelThemes = await foundationModelThemes(for: text)
        let themes = modelThemes.isEmpty ? SemanticThemes.themes(for: text, essence: essence) : modelThemes
        return ThoughtUnderstanding(
            essence: essence,
            themes: themes,
            mood: mood,
            language: language,
            themeKeys: ThoughtReading.keys(fromEnglish: [], fallbackLabels: themes),
            source: .model
        )
    }

    /// Cached once per process: the availability query itself is slow on
    /// ineligible hardware, and the answer doesn't change mid-session.
    @available(iOS 26, *)
    private static let foundationModelAvailable: Bool = OnDeviceModel.isReadyCached

    /// Apple's on-device foundation model (Apple Intelligence). Returns nil when
    /// the model isn't available on the device, so the caller can fall back.
    @available(iOS 26, *)
    private func foundationModelTitle(for text: String) async -> String? {
        #if canImport(FoundationModels)
        guard Self.foundationModelAvailable else { return nil }
        do {
            let session = LanguageModelSession {
                """
                You create very short titles for entries in a personal inspiration journal.
                Reply with ONLY the title — at most 6 words, no quotation marks, no trailing \
                punctuation. Capture the essence or feeling rather than restating the text. \
                Reply in the same language as the entry. If the entry is in Chinese, keep \
                the title to about 6 to 10 characters.
                """
            }
            let response = try await session.respond(to: "Entry:\n\(text)")
            return response.content
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Free conceptual themes from the on-device foundation model. Returns []
    /// on ineligible devices or any failure so concept mapping takes over.
    @available(iOS 26, *)
    private func foundationModelThemes(for text: String) async -> [String] {
        #if canImport(FoundationModels)
        guard Self.foundationModelAvailable else { return [] }
        do {
            let session = LanguageModelSession {
                """
                You label entries from a personal inspiration journal with conceptual \
                themes. A theme names the underlying concept, intention, emotion, or \
                domain — what the entry is really about, never words copied from it. \
                Examples: creative direction, career uncertainty, recurring thoughts, \
                social energy, emotional friction, personal reflection. Reply with \
                ONLY 1 to 3 themes, comma-separated, each one to three lowercase words. \
                Reply in the same language as the entry.
                """
            }
            let response = try await session.respond(to: "Entry:\n\(text)")
            return SemanticThemes.tidyThemeList(response.content)
        } catch {
            return []
        }
        #else
        return []
        #endif
    }

    // MARK: Related nodes

    /// Meaning-level neighbors: blended embedding similarity, conceptual-theme
    /// overlap and mood (`SemanticThemes.relatedness`), with a floor so a
    /// single shared surface word can never manufacture a connection. Direct
    /// branches get a small kinship boost — they are related by construction.
    func relatedNodeIDs(to node: Node, among nodes: [Node], limit: Int) -> [UUID] {
        let scored = nodes.compactMap { other -> (id: UUID, score: Double)? in
            guard other.id != node.id, !other.isArchived else { return nil }
            var score = SemanticThemes.relatedness(
                textA: node.meaningText, themesA: node.themes, moodA: node.mood,
                textB: other.meaningText, themesB: other.themes, moodB: other.mood
            )
            if other.parent?.id == node.id || node.parent?.id == other.id {
                score += 0.15
            }
            guard score >= SemanticThemes.relatednessFloor else { return nil }
            return (other.id, score)
        }
        return scored.sorted { $0.score > $1.score }.prefix(limit).map(\.id)
    }

    // MARK: Dialogue

    /// How wide a net each mode casts. Search and Synthesis sweep broadly —
    /// one to find, one to read across; Expansion stays close to a single
    /// idea; Research gathers enough footing to look outward from.
    private func retrievalLimit(for mode: DialogueMode) -> Int {
        switch mode {
        case .search: return 10
        case .synthesis: return 12
        case .expansion: return 5
        case .research: return 6
        }
    }

    func respond(to rawQuery: String, history: [DialogueTurn], mode: DialogueMode, nodes: [Node]) async -> OceanResponse {
        let active = nodes.filter { !$0.isArchived }

        // A very long question is the only unbounded input (fragments and
        // history are already capped), so it is the one thing that can overflow
        // the model. Work from a shortened version and remember to say so, so
        // the reply never presents itself as a full read of the question.
        let (query, degraded) = Self.boundedQuery(rawQuery)

        // 0. On the phone's one lens, the model works as an agent: it finds,
        //    lists and reads the thoughts itself (`AskAgent`). Nil means it
        //    never used a tool or failed, and the grounded path below stands.
        if mode == .synthesis, #available(iOS 26, *), Self.foundationModelAvailable,
           let answer = await AskAgent.answer(
               query: query,
               history: history.map { AskAgent.Turn(isUser: $0.isUser, text: $0.text) },
               thoughts: active.map(AskAgent.Thought.init(node:)),
               aboutPerson: await MainActor.run { Consolidation.preamble(context: Persistence.shared.mainContext) }
           ) {
            let byID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
            // What the answer cited; failing that, what it read in full and
            // what it names by title. Never the whole surfaced set: what a
            // tool returned is not what the answer drew on, and "Drawn from"
            // must not claim more than the words warrant.
            let sourceIDs = answer.cited.isEmpty
                ? Array((answer.read + answer.named.filter { !answer.read.contains($0) }).prefix(12))
                : answer.cited
            let sources = sourceIDs.compactMap { byID[$0] }
            // Open sea only when the Ocean had nothing: a list of two bugs
            // is a complete answer, and a note "beyond" it reads as a lecture
            // (observed 2026-10-22: "what bugs have I noted" drew three
            // paragraphs on malware). An answer that surfaced thoughts but
            // cited none is still the Ocean's, just without a sources list.
            let oceanHadNothing = answer.surfaced.isEmpty
            var outward: String?
            if oceanHadNothing {
                outward = await foundationModelOutward(query: query, sources: [])
            }
            return OceanResponse(
                reflection: answer.text,
                sourceNodeIDs: sources.map(\.id),
                patternSummary: nil,
                suggestedBranches: [],
                outwardNote: outward,
                provenance: oceanHadNothing ? .noSources : (degraded ? .degraded : .onDevice)
            )
        }

        // 1. Retrieve only the fragments that clear the relevance floor.
        //    Follow-ups that merely point back ("tell me more") borrow the
        //    previous user turn; a fresh question retrieves on its own words.
        let retrievalQuery = expandedRetrievalQuery(query, history: history)
        let ranked = embeddings.rank(
            query: retrievalQuery,
            candidates: active.map { (id: $0.id, texts: $0.retrievalTexts) },
            limit: retrievalLimit(for: mode),
            floor: EmbeddingService.dialogueRetrievalFloor
        )
        let byID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        let sources = ranked.compactMap { byID[$0] }

        // 2. Nothing cleared the floor: say honestly that nothing matches
        //    rather than grounding in noise or inventing a fragment. Every mode
        //    takes this exit, and none of the grounded extras apply.
        if sources.isEmpty {
            return OceanResponse(
                reflection: await emptyStateReflection(query: query, mode: mode),
                sourceNodeIDs: [],
                patternSummary: nil,
                suggestedBranches: [],
                outwardNote: nil,
                provenance: .noSources
            )
        }

        // 3. Sense the themes shared across those fragments.
        let themeCounts = sources
            .flatMap { $0.themes }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let topThemes = themeCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }

        // 4. Compose the reflection: genuine on-device synthesis when the
        //    foundation model is available, grounded templates otherwise.
        //    Search skips composition entirely — it is a pure find, and the
        //    sources themselves are the answer.
        var reflection: String?
        if mode != .search, #available(iOS 26, *) {
            reflection = await foundationModelReflection(
                query: query, history: history, mode: mode, sources: sources
            )
        }
        let finalReflection = reflection ?? compose(
            mode: mode,
            query: query,
            sources: sources,
            themes: topThemes,
            totalNodes: active.count
        )

        let patternSummary: String? = (mode == .search || topThemes.isEmpty)
            ? nil
            : "Recurring threads: " + topThemes.joined(separator: " · ")

        // Expansion's branches are creative leaps, so the model proposes them
        // when it can; the grounded templates remain the floor.
        var branches = suggestBranches(mode: mode, query: query, themes: topThemes, sources: sources)
        if mode == .expansion, #available(iOS 26, *),
           let grown = await foundationModelBranches(query: query, sources: sources) {
            branches = grown
        }

        // 5. Research alone steps outward: directions from beyond the user's
        //    notes, composed on-device when the foundation model is available
        //    (the cloud service replaces this with Claude when configured).
        var outwardNote: String?
        if Self.looksOutward(mode: mode, sourceCount: sources.count), #available(iOS 26, *) {
            outwardNote = await foundationModelOutward(query: query, sources: sources)
        }

        return OceanResponse(
            reflection: finalReflection,
            sourceNodeIDs: sources.map { $0.id },
            patternSummary: patternSummary,
            suggestedBranches: branches,
            outwardNote: outwardNote,
            provenance: Self.provenance(composed: reflection != nil, mode: mode, degraded: degraded)
        )
    }

    /// Where a reply's words came from. A template stands in only when no
    /// model could compose, and the reply says so: a canned reading marked
    /// as on-device would hide that nothing read the question (§3). Search
    /// is a pure find, so its fixed line is the honest answer, not a stand-in.
    static func provenance(composed: Bool, mode: DialogueMode, degraded: Bool) -> ResponseProvenance {
        if !composed && mode != .search { return .template }
        return degraded ? .degraded : .onDevice
    }

    /// When an answer steps beyond the user's notes. Research always does;
    /// the one merged Ask mode (synthesis) does only when the water was thin,
    /// so a question the Ocean can barely answer still gets a direction,
    /// marked apart (docs/plans/phone-refocus/SPEC.md, "Ask: one mode").
    static func looksOutward(mode: DialogueMode, sourceCount: Int) -> Bool {
        switch mode {
        case .research: return true
        case .synthesis: return sourceCount <= 2
        case .search, .expansion: return false
        }
    }

    /// The fixed question behind Summarize: the set is already chosen, so the
    /// model is asked only to read across it.
    static var summaryQuery: String {
        String(localized: "What runs through these thoughts? Say what they share, where they pull apart, and what sits underneath. Speak to me directly, as you, never as the user.")
    }

    func summarize(_ nodes: [Node]) async -> OceanResponse {
        let sources = Array(nodes.filter { !$0.isArchived }.prefix(12))
        guard !sources.isEmpty else {
            return OceanResponse(reflection: String(localized: "Nothing to read across yet."),
                                 sourceNodeIDs: [], patternSummary: nil, suggestedBranches: [],
                                 outwardNote: nil, provenance: .noSources)
        }
        let themeCounts = sources
            .flatMap { $0.themes }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let topThemes = themeCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }

        var reflection: String?
        if #available(iOS 26, *) {
            reflection = await foundationModelReflection(
                query: Self.summaryQuery, history: [], mode: .synthesis, sources: sources
            )
        }
        let finalReflection = reflection ?? compose(
            mode: .synthesis, query: Self.summaryQuery, sources: sources,
            themes: topThemes, totalNodes: nodes.count
        )
        return OceanResponse(
            reflection: finalReflection,
            sourceNodeIDs: sources.map { $0.id },
            patternSummary: topThemes.isEmpty ? nil : "Recurring threads: " + topThemes.joined(separator: " · "),
            suggestedBranches: [],
            outwardNote: nil,
            provenance: reflection == nil ? .template : .onDevice
        )
    }

    /// The longest question the model reads in full. Fragments and history are
    /// already bounded, so the question is the only input that can overflow the
    /// context; past this it is shortened and the reply is marked degraded.
    static let queryCharCap = 2000

    /// Shorten an over-long question to stay inside the context window,
    /// reporting whether it had to be cut so the caller can mark the reply.
    static func boundedQuery(_ query: String) -> (query: String, degraded: Bool) {
        guard query.count > queryCharCap else { return (query, false) }
        return (String(query.prefix(queryCharCap)), true)
    }

    /// Expand retrieval with the previous user turn only when the new question
    /// is purely referential ("tell me more", "why is that") and carries no
    /// topic of its own. If any content word survives after removing anaphora
    /// and stopwords, the question stands alone and retrieves fresh, so a new
    /// short question ("that thought about tide pools") is never dragged back
    /// to the previous turn's subject. (Referential markers here are English;
    /// other languages retrieve fresh until a later pass teaches this the
    /// difference.)
    private func expandedRetrievalQuery(_ query: String, history: [DialogueTurn]) -> String {
        guard let lastUser = history.last(where: { $0.isUser })?.text, !lastUser.isEmpty else {
            return query
        }
        let referential: Set<String> = [
            "that", "this", "they", "them", "those", "these", "one", "more",
            "and", "why", "tell", "about", "continue", "the", "same", "what",
            "you", "think", "say", "again", "how", "does", "did"
        ]
        let content = query.lowercased()
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count > 2 && !referential.contains($0) }
        return content.isEmpty ? lastUser + "\n" + query : query
    }

    /// The honest empty state. Search is a pure find, so it simply says nothing
    /// surfaced; composing modes ask the model to say so in the Ocean's voice,
    /// with a fixed line as the floor when the model is unavailable or fails.
    private func emptyStateReflection(query: String, mode: DialogueMode) async -> String {
        if mode == .search {
            return String(localized: "Nothing in your Ocean drifts near this yet.")
        }
        if #available(iOS 26, *), let composed = await foundationModelEmptyState(query: query) {
            return composed
        }
        return String(localized: "Nothing in your Ocean speaks to that yet. As you capture more, this question will have more to surface from.")
    }

    /// The empty state in the Ocean's voice: a tightly scoped call whose only
    /// job is to say, gently, that nothing in the user's captures matches. It
    /// is fenced off from answering the question itself, so an empty Ocean can
    /// never leak a world-knowledge reply or a fabricated fragment.
    @available(iOS 26, *)
    private func foundationModelEmptyState(query: String) async -> String? {
        #if canImport(FoundationModels)
        guard Self.foundationModelAvailable else { return nil }
        do {
            let session = LanguageModelSession { Self.emptyStateVoice }
            let response = try await session.respond(to: "Their question: \(query)")
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// True synthesis on Apple-Intelligence-eligible hardware: answer from the
    /// retrieved fragments only, in the Ocean's ambient voice. Returns nil on
    /// ineligible devices or any failure so the template path takes over.
    @available(iOS 26, *)
    private func foundationModelReflection(
        query: String,
        history: [DialogueTurn],
        mode: DialogueMode,
        sources: [Node]
    ) async -> String? {
        #if canImport(FoundationModels)
        guard Self.foundationModelAvailable else { return nil }

        let fragments = Self.fragmentLines(sources)

        let recentTurns = history.suffix(4).map {
            ($0.isUser ? "They said: " : "You said: ") + $0.text.prefix(200)
        }.joined(separator: "\n")

        let modeFraming = Self.modeFraming(for: mode)

        do {
            let session = LanguageModelSession { Self.reflectionVoice }
            let prompt = """
            \(modeFraming)
            Their question: \(query)

            Their fragments:
            \(fragments)
            \(recentTurns.isEmpty ? "" : "\nEarlier in this conversation (context only, do not answer this in place of the current question):\n\(recentTurns)")

            \(Self.secondPersonReminder)
            """
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : AnswerLength.capped(text)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: Shared prompt language (used by the cloud seam too, so the two
    // model paths never drift apart)

    /// One fragment per line, annotated with when it was captured and its
    /// mood — the raw material for noticing drift over time. Synthesis reads
    /// across up to 12 fragments, so body excerpts shrink as the set grows.
    static func fragmentLines(_ sources: [Node]) -> String {
        sources.map { node -> String in
            var line = "“\(node.displayTitle)”"
            if let parent = node.parent {
                line += " (a branch of “\(parent.displayTitle)”)"
            }
            var annotations = [node.createdAt.formatted(.relative(presentation: .named))]
            if let mood = node.mood { annotations.append(mood) }
            line += " (\(annotations.joined(separator: " · ")))"
            let body = node.searchableText.prefix(sources.count > 6 ? 180 : 300)
            if !body.isEmpty { line += ": \(body)" }
            return "- " + line
        }.joined(separator: "\n")
    }

    static func modeFraming(for mode: DialogueMode) -> String {
        switch mode {
        case .search:
            return "They are looking for something they captured."
        case .synthesis:
            return "They want to see the thread running through these fragments — how it has drifted over time, where it tightens, what stays unresolved. Name the quiet pattern underneath, gently; interpret rather than summarize."
        case .expansion:
            return "They want to grow these thoughts further. Offer one unexpected angle — a bridge to another domain, a metaphorical reframing, or a physical form it could take — without losing their voice."
        case .research:
            return "They want directions worth exploring next."
        }
    }

    /// Last in the prompt, where the small on-device model weighs it most:
    /// the framing above speaks about "them", and without this the answer
    /// copied it ("The user is exploring…").
    static let secondPersonReminder = """
    Reply to the person who captured these fragments in at most three short \
    sentences, saying only what the fragments say. Call them "you", as in \
    "You keep returning to…"; never write "the user", "they" or "the person". \
    Answer in the language the question is written in.
    """

    static let reflectionVoice = """
    You are the quiet, reflective voice of a personal inspiration space \
    called the Ocean. You answer ONLY from the user's own captured \
    fragments, provided below. Write 2 to 4 calm sentences in plain \
    prose — no lists, no headers, no advice-column tone, no exclamation \
    marks. Speak to the person directly as "you"; never write "the user" \
    or describe them in the third person. Never exceed four sentences. Refer to fragments by their quoted titles. Each fragment notes \
    when it was captured and its mood — you may quietly draw on how the \
    thread has moved over time. If a pattern or question sits underneath \
    the fragments, name it plainly. Never invent fragments that are not \
    provided. Answer the user's current question; any earlier conversation \
    is context only, and you must never answer a previous question in place \
    of the current one. The user's question is not a fragment and is not \
    evidence of anything they have captured; cite only the fragments above, \
    and if the question mentions something no fragment supports, never repeat \
    that content as if it were their thought. Write in the language the \
    question is written in; if it mixes languages, use the one most of the \
    fragments are in.
    """

    /// The empty-state voice: a fenced-off call whose only job is to say,
    /// gently, that nothing in the user's captures matches. It must not answer
    /// the question or imply any fragment, so an empty Ocean stays honest.
    static let emptyStateVoice = """
    You are the quiet, reflective voice of a personal inspiration space \
    called the Ocean. Nothing in the user's captured fragments matches their \
    question. Say so plainly and gently in one or two calm sentences: there \
    is nothing in their Ocean about this yet. Do NOT answer the question from \
    general knowledge. Do NOT invent, quote, or imply any fragment. No lists, \
    no exclamation marks. Reply in the language of their question.
    """

    /// The growth-direction language for Expansion's model-suggested branches,
    /// shared with the cloud seam. Replies parse as `kind: title` lines.
    static let branchVoice = """
    You suggest growth directions ("branches") for thoughts in a personal \
    inspiration space. Reply with EXACTLY two or three lines, each formatted \
    `kind: title` and nothing else. kind is one of question, concept, \
    project, research. Each title is at most nine words, concrete and \
    speculative, and each line should be a different kind of leap — a bridge \
    to another domain, a metaphorical reframing, or a physical form it could \
    take. Never restate their fragments. Write the titles in the language of \
    the question.
    """

    /// Research's outward voice, shared with the cloud seam. Open sea is the
    /// one place the answer is not grounded in the user's words, so the
    /// prompt trades reach for honesty: a direction without a name over a
    /// name the model is not sure of.
    static let outwardVoice = """
    You are the outward-looking voice of a personal inspiration space called \
    the Ocean. The user's own notes are answered separately; you bring what \
    lies beyond them. From general knowledge, name two or three specific \
    directions worth exploring: thinkers, works, fields, or open questions \
    that genuinely extend their interest. Write 2 to 4 calm sentences in \
    plain prose, no lists, no exclamation marks. Name only people, works and \
    fields you are certain exist; when you are not certain, describe the \
    direction without a name. Never invent a name, a title or a quotation, \
    and never pretend to quote their notes. Write in the language of the \
    question.
    """

    /// Parse `kind: title` lines into branches; nil when nothing usable came
    /// back so callers can keep their grounded templates.
    static func parseBranchLines(_ raw: String) -> [SuggestedBranch]? {
        let branches = raw
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> SuggestedBranch? in
                let parts = line.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard parts.count == 2, !parts[1].isEmpty,
                      let type = BranchType(rawValue: parts[0].lowercased())
                else { return nil }
                return SuggestedBranch(title: parts[1], type: type)
            }
        return branches.isEmpty ? nil : Array(branches.prefix(3))
    }

    /// Expansion's creative leaps, on-device: the model proposes the branches
    /// instead of templates. Returns nil on ineligible devices or failure.
    @available(iOS 26, *)
    private func foundationModelBranches(query: String, sources: [Node]) async -> [SuggestedBranch]? {
        #if canImport(FoundationModels)
        guard Self.foundationModelAvailable else { return nil }
        do {
            let session = LanguageModelSession { Self.branchVoice }
            let prompt = """
            Their question: \(query)
            Their fragments:
            \(Self.fragmentLines(sources))
            """
            let response = try await session.respond(to: prompt)
            return Self.parseBranchLines(response.content)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Research's outward step, on-device: name what lies beyond the user's
    /// notes — thinkers, works, fields, questions — from the model's general
    /// knowledge. Returns nil on ineligible devices or failure; the response
    /// then simply has no outward note (never a fabricated one).
    @available(iOS 26, *)
    private func foundationModelOutward(query: String, sources: [Node]) async -> String? {
        #if canImport(FoundationModels)
        guard Self.foundationModelAvailable else { return nil }

        let titles = sources.prefix(6).map { "“\($0.displayTitle)”" }.joined(separator: ", ")
        do {
            let session = LanguageModelSession { Self.outwardVoice }
            let prompt = titles.isEmpty
                ? "They are exploring: \(query)"
                : "They are exploring: \(query)\nTheir related notes touch on: \(titles)"
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - Composition

    private func compose(
        mode: DialogueMode,
        query: String,
        sources: [Node],
        themes: [String],
        totalNodes: Int
    ) -> String {
        guard !sources.isEmpty else {
            return "I couldn't find a fragment in your Ocean that speaks to that yet. As you capture more drifts, this question will have more to resurface from."
        }

        let titles = sources.prefix(3).map { "“\($0.displayTitle)”" }
        let first = titles.first ?? ""
        let joinedTitles = joinNaturally(titles)
        let themePhrase: String? = themes.isEmpty
            ? nil
            : String(localized: "They keep circling \(joinNaturally(themes)).")

        // Fixed copy, so it is UI copy: localized, and no dashes (the model's
        // own prose is exempt, this is not the model's).
        let sentences: [String?]
        switch mode {
        case .search:
            // A pure find: no interpretation, just where the water carried it.
            if sources.count == 1 {
                sentences = [String(localized: "One fragment drifts near this: \(first). Tap it below to revisit.")]
            } else {
                sentences = [String(localized: "\(sources.count) fragments drift near this. The closest is \(first). Tap a source below to revisit.")]
            }

        case .synthesis:
            sentences = [
                String(localized: "Reading across \(joinedTitles), a shared current emerges."),
                themePhrase,
                String(localized: "These are not separate notes. They are the same idea, returning in different forms. The thread underneath seems to be about how these pieces want to connect.")
            ]

        case .expansion:
            sentences = [
                String(localized: "Starting from \(first), there is room to grow."),
                themePhrase,
                String(localized: "You could push it further, question its assumption, or pull it toward something concrete. The suggested branches below are places it could go without losing the original.")
            ]

        case .research:
            sentences = [
                String(localized: "If you want to go deeper, \(joinedTitles) point toward a few open directions."),
                themePhrase,
                String(localized: "The branches below frame what would be worth exploring next.")
            ]
        }
        // Chinese sentences close with their own full stop and take no space.
        let kept = sentences.compactMap { $0 }
        return kept.joined(separator: CurrentSnap.isChinese(kept.first ?? "") ? "" : " ")
    }

    private func suggestBranches(
        mode: DialogueMode,
        query: String,
        themes: [String],
        sources: [Node]
    ) -> [SuggestedBranch] {
        let anchor = themes.first ?? sources.first?.displayTitle ?? query
        var out: [SuggestedBranch] = []

        switch mode {
        case .search:
            // Pure find — the sources are the answer; no growth nudges.
            break
        case .synthesis:
            out.append(SuggestedBranch(title: "A concept tying \(anchor) together", type: .concept))
            out.append(SuggestedBranch(title: "What pattern am I not seeing in \(anchor)?", type: .question))
        case .expansion:
            out.append(SuggestedBranch(title: "Push \(anchor) one step further", type: .concept))
            out.append(SuggestedBranch(title: "Turn \(anchor) into something I can make", type: .project))
        case .research:
            out.append(SuggestedBranch(title: "Explore \(anchor) more deeply", type: .research))
            out.append(SuggestedBranch(title: "What do I not yet understand about \(anchor)?", type: .question))
        }
        return out
    }

    /// "A, B, and C" in English, "A、B和C" in Chinese: the list follows the
    /// app's language the way the sentence around it does.
    private func joinNaturally(_ items: [String]) -> String {
        ListFormatter.localizedString(byJoining: items)
    }
}

// MARK: - Node → agent snapshot

@available(iOS 26, *)
extension AskAgent.Thought {
    /// A value snapshot of a thought for the agent's tools.
    init(node: Node) {
        self.init(
            id: node.id,
            title: node.displayTitle,
            body: [node.text, node.transcription ?? "", node.linkContext, node.pictureContext]
                .filter { !$0.isEmpty }
                .joined(separator: "\n"),
            gist: node.gistOther,
            summary: node.summary,
            createdAt: node.createdAt,
            category: node.category,
            kind: node.kind,
            themes: node.themes,
            themeKeys: node.themeKeys,
            entities: node.entities,
            hasPictures: node.hasImages,
            status: node.status
        )
    }
}
