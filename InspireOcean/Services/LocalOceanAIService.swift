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

    // MARK: Transcription

    func transcribe(audioURL: URL) async -> String? {
        await transcriber.transcribe(url: audioURL)
    }

    // MARK: Themes

    func detectThemes(for text: String) -> [String] {
        ThemeDetector.themes(from: text)
    }

    // MARK: Concise titles

    func conciseTitle(for text: String) async -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "Untitled drift" }

        if #available(iOS 26, *), let modelTitle = await foundationModelTitle(for: cleaned) {
            return TitleDistiller.tidy(modelTitle)
        }
        return TitleDistiller.essence(from: cleaned)
    }

    /// Apple's on-device foundation model (Apple Intelligence). Returns nil when
    /// the model isn't available on the device, so the caller can fall back.
    @available(iOS 26, *)
    private func foundationModelTitle(for text: String) async -> String? {
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else { return nil }
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

    // MARK: Related nodes

    func relatedNodeIDs(to node: Node, among nodes: [Node], limit: Int) -> [UUID] {
        let candidates = nodes
            .filter { $0.id != node.id && !$0.isArchived }
            .map { (id: $0.id, text: $0.searchableText) }
        return embeddings.rank(query: node.searchableText, candidates: candidates, limit: limit)
    }

    // MARK: Dialogue

    func respond(to query: String, mode: DialogueMode, nodes: [Node]) async -> OceanResponse {
        let active = nodes.filter { !$0.isArchived }

        // 1. Retrieve the fragments most relevant to the query.
        let ranked = embeddings.rank(
            query: query,
            candidates: active.map { (id: $0.id, text: $0.searchableText) },
            limit: 5
        )
        let byID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        let sources = ranked.compactMap { byID[$0] }

        // 2. Sense the themes shared across those fragments.
        let themeCounts = sources
            .flatMap { $0.themes }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let topThemes = themeCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }

        // 3. Compose a grounded reflection in the chosen mode.
        let reflection = compose(
            mode: mode,
            query: query,
            sources: sources,
            themes: topThemes,
            totalNodes: active.count
        )

        let patternSummary: String? = topThemes.isEmpty
            ? nil
            : "Recurring threads: " + topThemes.joined(separator: " · ")

        let branches = suggestBranches(mode: mode, query: query, themes: topThemes, sources: sources)

        return OceanResponse(
            reflection: reflection,
            sourceNodeIDs: sources.map { $0.id },
            patternSummary: patternSummary,
            suggestedBranches: branches
        )
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
            return "I surfaced \(sources.count) fragment\(sources.count == 1 ? "" : "s") that drift near this — closest is \(titles.first ?? "").\(themePhrase) Tap a source below to revisit it."

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
            out.append(SuggestedBranch(title: "What connects these fragments?", type: .question))
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
