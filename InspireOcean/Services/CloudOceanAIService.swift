import Foundation

/// Cloud AI seam (§14: "Cloud AI for transcription, semantic search, synthesis,
/// and dialogue reasoning"), wired to the Anthropic Claude API.
///
/// Division of labor — privacy- and latency-sensitive work stays on-device:
/// - **Retrieval, themes, transcription**: always on-device. Only the handful
///   of fragments that retrieval already selected ever leave the device, and
///   only when a key is configured.
/// - **Dialogue reflection + concise titles**: composed by Claude when
///   configured; otherwise the on-device path runs exactly as before.
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
        static func fromEnvironment() -> Configuration? {
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

    func detectThemes(for text: String) -> [String] {
        fallback.detectThemes(for: text)
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

        guard let configuration, !scaffold.sourceNodeIDs.isEmpty else { return scaffold }

        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let sources = scaffold.sourceNodeIDs.compactMap { byID[$0] }
        guard !sources.isEmpty else { return scaffold }

        do {
            let reflection = try await reflect(
                query: query, history: history, mode: mode,
                sources: sources, configuration: configuration
            )
            guard !reflection.isEmpty else { return scaffold }
            var response = scaffold
            response.reflection = reflection
            return response
        } catch {
            // Network or API failure: the grounded on-device response stands.
            return scaffold
        }
    }

    private func reflect(
        query: String,
        history: [DialogueTurn],
        mode: DialogueMode,
        sources: [Node],
        configuration: Configuration
    ) async throws -> String {
        let fragments = sources.prefix(5).map { node -> String in
            var line = "“\(node.displayTitle)”"
            if let parent = node.parent {
                line += " (a branch of “\(parent.displayTitle)”)"
            }
            let body = node.searchableText.prefix(300)
            if !body.isEmpty { line += ": \(body)" }
            return "- " + line
        }.joined(separator: "\n")

        let recentTurns = history.suffix(4).map {
            ($0.isUser ? "They said: " : "You said: ") + $0.text.prefix(200)
        }.joined(separator: "\n")

        let modeFraming: String = switch mode {
        case .search:    "They are looking for something they captured."
        case .synthesis: "They want to see the thread running through these fragments."
        case .expansion: "They want to grow these thoughts further."
        case .research:  "They want directions worth exploring next."
        }

        let system = """
        You are the quiet, reflective voice of a personal inspiration space \
        called the Ocean. You answer ONLY from the user's own captured \
        fragments, provided below. Write 2 to 4 calm sentences in plain \
        prose — no lists, no headers, no advice-column tone, no exclamation \
        marks. Refer to fragments by their quoted titles. If a pattern or \
        question sits underneath the fragments, name it plainly. Never \
        invent fragments that are not provided.
        """

        let prompt = """
        \(modeFraming)
        \(recentTurns.isEmpty ? "" : "Recent conversation:\n\(recentTurns)\n")
        Their fragments:
        \(fragments)

        Their question: \(query)
        """

        let text = try await completeText(
            system: system,
            user: prompt,
            maxTokens: 1024,
            adaptiveThinking: true,
            configuration: configuration
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Concise titles

    func conciseTitle(for text: String) async -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let configuration, !cleaned.isEmpty else {
            return await fallback.conciseTitle(for: text)
        }

        let system = """
        You create very short titles for entries in a personal inspiration journal.
        Reply with ONLY the title — at most 6 words, no quotation marks, no trailing \
        punctuation. Capture the essence or feeling rather than restating the text.
        """

        do {
            let title = try await completeText(
                system: system,
                user: "Entry:\n\(cleaned)",
                maxTokens: 64,
                adaptiveThinking: false,
                configuration: configuration
            )
            let tidied = TitleDistiller.tidy(title)
            return tidied.isEmpty ? await fallback.conciseTitle(for: text) : tidied
        } catch {
            return await fallback.conciseTitle(for: text)
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
