import Foundation

/// Cloud AI seam (§14: "Cloud AI for transcription, semantic search, synthesis,
/// and dialogue reasoning").
///
/// This is the drop-in replacement for `LocalOceanAIService`. It conforms to the
/// same `OceanAIService` protocol, so switching Ocean to a hosted model is a
/// one-line change in `InspireOceanApp` — no UI changes required.
///
/// V1 ships on-device, so until an endpoint + key are configured this delegates
/// to the local service. The `TODO`s mark exactly where network calls go.
final class CloudOceanAIService: OceanAIService {

    struct Configuration {
        var baseURL: URL
        var apiKey: String
    }

    private let configuration: Configuration?
    private let fallback = LocalOceanAIService()

    init(configuration: Configuration? = nil) {
        self.configuration = configuration
    }

    var isConfigured: Bool { configuration != nil }

    func transcribe(audioURL: URL) async -> String? {
        guard configuration != nil else { return await fallback.transcribe(audioURL: audioURL) }
        // TODO: POST the audio to the transcription endpoint and return the text.
        return await fallback.transcribe(audioURL: audioURL)
    }

    func detectThemes(for text: String) -> [String] {
        // Theme detection is cheap and private; keep it on-device regardless.
        fallback.detectThemes(for: text)
    }

    func relatedNodeIDs(to node: Node, among nodes: [Node], limit: Int) -> [UUID] {
        // TODO: use cloud embeddings when configured; on-device is a fine default.
        fallback.relatedNodeIDs(to: node, among: nodes, limit: limit)
    }

    func respond(to query: String, history: [DialogueTurn], mode: DialogueMode, nodes: [Node]) async -> OceanResponse {
        guard configuration != nil else {
            return await fallback.respond(to: query, history: history, mode: mode, nodes: nodes)
        }
        // TODO: retrieve top-k nodes locally, send them (plus the recent turns)
        // as grounding context to the dialogue endpoint, and map the response
        // into `OceanResponse`. Always pass the source node ids through so
        // responses stay evidence-based.
        return await fallback.respond(to: query, history: history, mode: mode, nodes: nodes)
    }

    func conciseTitle(for text: String) async -> String {
        // Title generation stays on-device (private + cheap) regardless of config.
        await fallback.conciseTitle(for: text)
    }
}
