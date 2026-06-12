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
    private let transcriber = SpeechTranscriber()

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

    // MARK: Understanding

    /// Raw thought → semantic understanding → essence + conceptual themes.
    /// The foundation model interprets freely when available; otherwise the
    /// concept-space fallback (`SemanticThemes`) still maps meaning, not words.
    func understand(_ text: String) async -> ThoughtUnderstanding {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return ThoughtUnderstanding(essence: "Untitled drift", themes: [], mood: nil)
        }

        if #available(iOS 26, *), Self.foundationModelAvailable {
            let modelTitle = await foundationModelTitle(for: cleaned).map(TitleDistiller.tidy)
            let essence = modelTitle ?? TitleDistiller.essence(from: cleaned)
            let modelThemes = await foundationModelThemes(for: cleaned)
            return ThoughtUnderstanding(
                essence: essence,
                themes: modelThemes.isEmpty
                    ? SemanticThemes.themes(for: cleaned, essence: essence)
                    : modelThemes,
                mood: ThemeDetector.mood(from: cleaned)
            )
        }
        return SemanticThemes.understand(cleaned)
    }

    /// Cached once per process: the availability query itself is slow on
    /// ineligible hardware, and the answer doesn't change mid-session.
    @available(iOS 26, *)
    private static let foundationModelAvailable: Bool = {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }()

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
                punctuation. Capture the essence or feeling rather than restating the text.
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
                ONLY 1 to 3 themes, comma-separated, each one to three lowercase words.
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

    func respond(to query: String, history: [DialogueTurn], mode: DialogueMode, nodes: [Node]) async -> OceanResponse {
        let active = nodes.filter { !$0.isArchived }

        // 1. Retrieve the fragments most relevant to the query. Follow-up
        //    queries lean on the previous user turn so "tell me more" still
        //    points at something.
        let retrievalQuery = expandedRetrievalQuery(query, history: history)
        let ranked = embeddings.rank(
            query: retrievalQuery,
            candidates: active.map { (id: $0.id, text: $0.searchableText) },
            limit: retrievalLimit(for: mode)
        )
        let byID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        let sources = ranked.compactMap { byID[$0] }

        // 2. Sense the themes shared across those fragments.
        let themeCounts = sources
            .flatMap { $0.themes }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let topThemes = themeCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }

        // 3. Compose the reflection: genuine on-device synthesis when the
        //    foundation model is available, grounded templates otherwise.
        //    Search skips composition entirely — it is a pure find, and the
        //    sources themselves are the answer.
        var reflection: String?
        if mode != .search, #available(iOS 26, *), !sources.isEmpty {
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
        if mode == .expansion, !sources.isEmpty, #available(iOS 26, *),
           let grown = await foundationModelBranches(query: query, sources: sources) {
            branches = grown
        }

        // 4. Research alone steps outward: directions from beyond the user's
        //    notes, composed on-device when the foundation model is available
        //    (the cloud service replaces this with Claude when configured).
        var outwardNote: String?
        if mode == .research, #available(iOS 26, *) {
            outwardNote = await foundationModelOutward(query: query, sources: sources)
        }

        return OceanResponse(
            reflection: finalReflection,
            sourceNodeIDs: sources.map { $0.id },
            patternSummary: patternSummary,
            suggestedBranches: branches,
            outwardNote: outwardNote,
            // Search is a pure find — an empty result needs no caveat; for
            // composing modes, an ungrounded reply must say so.
            provenance: (sources.isEmpty && mode != .search) ? .noSources : .onDevice
        )
    }

    /// A short query expansion for follow-ups: when the new message is brief
    /// and deictic ("tell me more", "why is that"), blend in the previous user
    /// turn so retrieval has real words to work with.
    private func expandedRetrievalQuery(_ query: String, history: [DialogueTurn]) -> String {
        let words = query.split(separator: " ").count
        guard words <= 6,
              let lastUser = history.last(where: { $0.isUser })?.text,
              !lastUser.isEmpty
        else { return query }
        return lastUser + "\n" + query
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
            \(recentTurns.isEmpty ? "" : "Recent conversation:\n\(recentTurns)\n")
            Their fragments:
            \(fragments)

            Their question: \(query)
            """
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

    static let reflectionVoice = """
    You are the quiet, reflective voice of a personal inspiration space \
    called the Ocean. You answer ONLY from the user's own captured \
    fragments, provided below. Write 2 to 4 calm sentences in plain \
    prose — no lists, no headers, no advice-column tone, no exclamation \
    marks. Refer to fragments by their quoted titles. Each fragment notes \
    when it was captured and its mood — you may quietly draw on how the \
    thread has moved over time. If a pattern or question sits underneath \
    the fragments, name it plainly. Never invent fragments that are not \
    provided.
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
    take. Never restate their fragments.
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
            let session = LanguageModelSession {
                """
                You are the outward-looking voice of a personal inspiration \
                space called the Ocean. The user's own notes are answered \
                separately — you bring what lies beyond them. From general \
                knowledge, name two or three specific directions worth \
                exploring: thinkers, works, fields, or open questions that \
                genuinely extend their interest. Write 2 to 4 calm sentences \
                in plain prose — no lists, no exclamation marks. Be concrete \
                with names. Never pretend to quote their notes.
                """
            }
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
        let themePhrase = themes.isEmpty ? "" : " They keep circling \(joinNaturally(themes))."

        switch mode {
        case .search:
            // A pure find: no interpretation, just where the water carried it.
            if sources.count == 1 {
                return "One fragment drifts near this — \(titles.first ?? ""). Tap it below to revisit."
            }
            return "\(sources.count) fragments drift near this — closest is \(titles.first ?? ""). Tap a source below to revisit."

        case .synthesis:
            return "Reading across \(joinNaturally(titles)), a shared current emerges.\(themePhrase) These aren't separate notes — they're the same idea, returning in different forms. The thread underneath seems to be about how these pieces want to connect."

        case .expansion:
            return "Starting from \(titles.first ?? "this fragment"), there's room to grow.\(themePhrase) You could push it further, question its assumption, or pull it toward something concrete. The suggested branches below are places it could go without losing the original."

        case .research:
            return "If you want to go deeper, \(joinNaturally(titles)) point toward a few open directions.\(themePhrase) The branches below frame what would be worth exploring next."
        }
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

    private func joinNaturally(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return "\(head), and \(items.last!)"
        }
    }
}
