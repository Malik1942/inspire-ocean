import Foundation

/// Cloud AI seam (§14: "Cloud AI for transcription, semantic search, synthesis,
/// and dialogue reasoning"), wired to the Anthropic Claude API.
///
/// Division of labor — privacy- and latency-sensitive work stays on-device:
/// - **Retrieval, themes, transcription**: always on-device. Only the handful
///   of fragments that retrieval already selected ever leave the device, and
///   only when a key is configured.
/// - **Dialogue reflection, Research's outward step + concise titles**:
///   composed by Claude when configured; otherwise the on-device path runs
///   exactly as before.
///
/// Unconfigured (no API key), this service is behaviorally identical to
/// `LocalOceanAIService` — so it can safely be the app's default. Configure by
/// launching with the `ANTHROPIC_API_KEY` environment variable (simulator:
/// `SIMCTL_CHILD_ANTHROPIC_API_KEY=… xcrun simctl launch …`) or an
/// `AnthropicAPIKey` Info.plist entry injected from a local xcconfig.
/// **Never commit a key.**
final class CloudOceanAIService: OceanAIService {

    struct Configuration {
        var apiKey: String
        var model: String = "claude-opus-4-8"
        var baseURL = URL(string: "https://api.anthropic.com")!

        /// Reads the key from the process environment (`ANTHROPIC_API_KEY`)
        /// or Info.plist (`AnthropicAPIKey`); nil when neither is set, which
        /// leaves the service in pure on-device mode.
        ///
        /// DEBUG-only by construction: a raw Anthropic key must never ride in
        /// a distributable bundle (Info.plist ships as plaintext — trivially
        /// extractable from any IPA), so Release builds compile this to nil
        /// and run pure on-device until a backend proxy carries the key
        /// server-side. The environment path was already dev-only (apps
        /// launched from SpringBoard receive no custom environment), but the
        /// plist path would have worked in TestFlight — this closes it.
        static func fromEnvironment() -> Configuration? {
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            let key = env["ANTHROPIC_API_KEY"]
                ?? Bundle.main.object(forInfoDictionaryKey: "AnthropicAPIKey") as? String
            guard let key, !key.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            var configuration = Configuration(apiKey: key)
            if let model = env["OCEAN_CLOUD_MODEL"], !model.isEmpty {
                configuration.model = model
            }
            if let base = env["OCEAN_CLOUD_BASE_URL"], let url = URL(string: base) {
                configuration.baseURL = url
            }
            return configuration
            #else
            return nil
            #endif
        }
    }

    private let configuration: Configuration?
    private let fallback = LocalOceanAIService()

    init(configuration: Configuration? = nil) {
        self.configuration = configuration
    }

    var isConfigured: Bool { configuration != nil }

    // MARK: On-device always (private + cheap)

    func transcribe(audioURL: URL) async -> String? {
        await fallback.transcribe(audioURL: audioURL)
    }

    func relatedNodeIDs(to node: Node, among nodes: [Node], limit: Int) -> [UUID] {
        fallback.relatedNodeIDs(to: node, among: nodes, limit: limit)
    }

    // MARK: Dialogue

    func respond(to query: String, history: [DialogueTurn], mode: DialogueMode, nodes: [Node]) async -> OceanResponse {
        // The local service does the retrieval, themes, pattern summary, and
        // branch suggestions — all on-device, all kept. (On Apple-Intelligence
        // hardware its reflection is already model-composed; the cloud
        // reflection below simply replaces it when configured.)
        let scaffold = await fallback.respond(to: query, history: history, mode: mode, nodes: nodes)

        guard let configuration else { return scaffold }

        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let sources = scaffold.sourceNodeIDs.compactMap { byID[$0] }

        // The scaffold already carries the retrieval floor's verdict: empty
        // sources mean the on-device path chose the honest empty state (its
        // .noSources provenance), so the cloud grounds no reflection here and
        // must not manufacture one. A long question is shortened for the cloud
        // too, and the reply stays marked degraded even when Claude answers it
        // well. (Research's outward step still runs on an empty Ocean; open
        // water is exactly where an empty Ocean can't reach.)
        let (query, degraded) = LocalOceanAIService.boundedQuery(query)

        // Search is a pure find — the sources are the answer, nothing to
        // compose. Research's outward step runs concurrently with the
        // grounded reflection; either may fail independently, and whatever
        // the cloud doesn't deliver, the on-device scaffold already covers.
        let reflectionExpected = mode != .search && !sources.isEmpty
        async let composedReflection = reflectIfNeeded(
            query: query, history: history, mode: mode, sources: sources,
            configuration: configuration,
            enabled: reflectionExpected
        )
        async let composedOutward = outwardIfNeeded(
            query: query, sources: sources,
            configuration: configuration,
            enabled: mode == .research
        )
        async let composedBranches = branchesIfNeeded(
            query: query, sources: sources,
            configuration: configuration,
            enabled: mode == .expansion && !sources.isEmpty
        )

        var response = scaffold
        if let reflection = await composedReflection {
            response.reflection = reflection
            response.provenance = degraded ? .degraded : .cloud
        } else if reflectionExpected {
            // The cloud was supposed to answer and couldn't — the scaffold
            // stands, and the reply should quietly say where it came from.
            response.provenance = degraded ? .degraded : .offlineFallback
        }
        if let outward = await composedOutward {
            response.outwardNote = outward
        }
        if let branches = await composedBranches {
            response.suggestedBranches = branches
        }
        return response
    }

    /// Expansion's creative leaps via Claude — the model proposes the
    /// branches instead of templates. nil keeps the scaffold's templates.
    private func branchesIfNeeded(
        query: String,
        sources: [Node],
        configuration: Configuration,
        enabled: Bool
    ) async -> [SuggestedBranch]? {
        guard enabled else { return nil }
        let prompt = """
        Their question: \(query)
        Their fragments:
        \(LocalOceanAIService.fragmentLines(sources))
        """
        do {
            let raw = try await completeText(
                system: LocalOceanAIService.branchVoice,
                user: prompt,
                maxTokens: 160,
                adaptiveThinking: false,
                configuration: configuration
            )
            return LocalOceanAIService.parseBranchLines(raw)
        } catch {
            return nil
        }
    }

    /// The grounded reflection via Claude; nil (so the scaffold stands) when
    /// disabled, when the call fails, or when the reply is empty.
    private func reflectIfNeeded(
        query: String,
        history: [DialogueTurn],
        mode: DialogueMode,
        sources: [Node],
        configuration: Configuration,
        enabled: Bool
    ) async -> String? {
        guard enabled else { return nil }
        do {
            let reflection = try await reflect(
                query: query, history: history, mode: mode,
                sources: sources, configuration: configuration
            )
            return reflection.isEmpty ? nil : reflection
        } catch {
            return nil
        }
    }

    /// Research's outward step via Claude's general knowledge: specific
    /// directions beyond the user's notes, returned separately from the
    /// grounded reflection so the UI can mark its provenance. Works even on
    /// an empty Ocean — outward is exactly where an empty Ocean can't reach.
    private func outwardIfNeeded(
        query: String,
        sources: [Node],
        configuration: Configuration,
        enabled: Bool
    ) async -> String? {
        guard enabled else { return nil }

        let titles = sources.prefix(6).map { "“\($0.displayTitle)”" }.joined(separator: ", ")
        let system = """
        You are the outward-looking voice of a personal inspiration space \
        called the Ocean. The user's own notes are answered separately — you \
        bring what lies beyond them. From your general knowledge, name two or \
        three specific directions worth exploring: thinkers, works, fields, \
        or open questions that genuinely extend their interest. Write 2 to 4 \
        calm sentences in plain prose — no lists, no exclamation marks. Be \
        concrete with names. Never pretend to quote their notes, and never \
        invent notes.
        """
        let prompt = titles.isEmpty
            ? "They are exploring: \(query)"
            : "They are exploring: \(query)\nTheir related notes touch on: \(titles)"

        do {
            let text = try await completeText(
                system: system,
                user: prompt,
                maxTokens: 512,
                adaptiveThinking: true,
                configuration: configuration
            )
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }

    private func reflect(
        query: String,
        history: [DialogueTurn],
        mode: DialogueMode,
        sources: [Node],
        configuration: Configuration
    ) async throws -> String {
        // Prompt language is shared with the on-device path (fragment lines
        // annotated with capture time + mood, per-mode framing, the Ocean's
        // reflective voice) so the two model seams never drift apart.
        let fragments = LocalOceanAIService.fragmentLines(sources)

        let recentTurns = history.suffix(4).map {
            ($0.isUser ? "They said: " : "You said: ") + $0.text.prefix(200)
        }.joined(separator: "\n")

        let prompt = """
        \(LocalOceanAIService.modeFraming(for: mode))
        Their question: \(query)

        Their fragments:
        \(fragments)
        \(recentTurns.isEmpty ? "" : "\nEarlier in this conversation (context only, do not answer this in place of the current question):\n\(recentTurns)")
        """

        let text = try await completeText(
            system: LocalOceanAIService.reflectionVoice,
            user: prompt,
            maxTokens: 1024,
            adaptiveThinking: true,
            configuration: configuration
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Understanding

    /// One Claude call interprets the fragment into essence + conceptual
    /// themes; mood stays on-device. Any failure or unusable reply falls back
    /// to the local understanding path unchanged.
    ///
    /// `existingThemes` (the ocean's current vocabulary, see `ThemeVocabulary`)
    /// is passed into the prompt so the model *reuses* a theme that already
    /// fits instead of coining a near-synonym. Without it, isolated
    /// interpretation scatters related thoughts — "yummy drink" → `taste`,
    /// "best burger" → `food curiosity` — into separate currents, since
    /// currents match theme strings exactly (`OceanLayoutEngine`).
    func understand(_ text: String, existingThemes: [String] = []) async -> ThoughtUnderstanding {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let configuration, !cleaned.isEmpty else {
            return await fallback.understand(text, existingThemes: existingThemes)
        }

        let vocabulary = existingThemes.isEmpty
            ? "The journal has no themes yet — you are naming its first ones."
            : "The journal already uses these themes:\n"
                + existingThemes.map { "- \($0)" }.joined(separator: "\n")

        let system = """
        You interpret entries in a personal inspiration journal.
        Reply with EXACTLY two lines and nothing else.
        Line 1: a title of at most 6 words — capture the essence or feeling \
        rather than restating the text; no quotation marks, no trailing punctuation.
        Line 2: 1 to 3 conceptual themes, comma-separated, each one to three \
        lowercase words. A theme names the underlying concept, intention, \
        emotion, or domain.

        \(vocabulary)

        Consistency matters more than novelty. When an entry belongs with an \
        existing theme, reuse that theme's exact wording rather than coining a \
        near-synonym: a journal where "yummy drink" and "best burger" both sit \
        under one "food" theme is far more useful than one that scatters them \
        across "taste" and "food curiosity". Coin a NEW theme only when none of \
        the existing ones genuinely fit, and keep new themes broad enough that \
        future related entries can reuse them (prefer "food" over "food \
        curiosity", "work" over "career uncertainty"). But a theme must still \
        distinguish the entry from unrelated ones: never attach a catch-all \
        that could fit most entries — "desire", "wanting", "thoughts", \
        "feelings", "life". The entry's domain (food, work, nature) matters \
        more than the stance it takes toward it. Write each theme in the \
        language of the entry.
        """

        do {
            let raw = try await completeText(
                system: system,
                user: "Entry:\n\(cleaned)",
                maxTokens: 96,
                adaptiveThinking: false,
                configuration: configuration
            )
            let lines = raw
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard let titleLine = lines.first else {
                return await fallback.understand(text, existingThemes: existingThemes)
            }

            let essence = TitleDistiller.tidy(titleLine)
            guard !essence.isEmpty else {
                return await fallback.understand(text, existingThemes: existingThemes)
            }

            let themes = lines.dropFirst().first.map(SemanticThemes.tidyThemeList) ?? []
            return ThoughtUnderstanding(
                essence: essence,
                themes: themes.isEmpty
                    ? SemanticThemes.themes(for: cleaned, essence: essence)
                    : themes,
                mood: ThemeDetector.mood(from: cleaned)
            )
        } catch {
            return await fallback.understand(text, existingThemes: existingThemes)
        }
    }

    // MARK: - Anthropic Messages API (raw HTTP — no official Swift SDK)

    private struct MessagesRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct Thinking: Encodable {
            let type: String
        }
        let model: String
        let maxTokens: Int
        let system: String
        let messages: [Message]
        let thinking: Thinking?

        enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case messages
            case thinking
        }
    }

    private struct MessagesResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
    }

    private struct APIErrorResponse: Decodable {
        struct Detail: Decodable {
            let message: String
        }
        let error: Detail
    }

    enum CloudError: Error {
        case api(String)
    }

    /// One non-streaming Messages API call; returns the concatenated text
    /// blocks. Bounded outputs only (≤ ~1K tokens), well under HTTP timeouts.
    private func completeText(
        system: String,
        user: String,
        maxTokens: Int,
        adaptiveThinking: Bool,
        configuration: Configuration
    ) async throws -> String {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("/v1/messages"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body = MessagesRequest(
            model: configuration.model,
            maxTokens: maxTokens,
            system: system,
            messages: [.init(role: "user", content: user)],
            thinking: adaptiveThinking ? .init(type: "adaptive") : nil
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error.message
                ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
            throw CloudError.api(message)
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        return decoded.content
            .filter { $0.type == "text" }
            .compactMap { $0.text }
            .joined()
    }
}
