import Foundation
import SwiftData

/// The understanding pass for one saved thought: a voice thought with no
/// transcript is transcribed first (from the temp file when it survives,
/// else from the stored bytes), then title and themes come from the words
/// the user kept. Shared by in-app capture (`CaptureSession`) and wrist
/// takes (`WatchTakeImporter`) so the two can never drift.
///
/// Ownership: a transcript the user edited is never overwritten, and every
/// interpretation goes through `NodeComposer.applyUnderstanding`.
/// Cancellation is honored between steps (Undo cancels the capture's task).
@MainActor
enum VoiceUnderstanding {

    /// Returns the essence (the interpreted title), or nil when there were no
    /// words to understand, the user owns the transcript, or the node is gone.
    @discardableResult
    static func run(
        nodeID: UUID,
        audioTempURL: URL?,
        context: ModelContext,
        ai: any OceanAIService
    ) async -> String? {
        guard let node = fetch(nodeID, in: context) else { return nil }
        if node.kind == .voice, (node.transcription ?? "").isEmpty {
            guard await transcribe(nodeID: nodeID, tempURL: audioTempURL, context: context, ai: ai) else {
                return nil
            }
        } else if let audioTempURL {
            // A confirmed transcript wins — the temp file has no further use.
            try? FileManager.default.removeItem(at: audioTempURL)
        }
        return await understand(nodeID: nodeID, context: context, ai: ai)
    }

    /// True when a transcript landed on the node.
    private static func transcribe(
        nodeID: UUID,
        tempURL: URL?,
        context: ModelContext,
        ai: any OceanAIService
    ) async -> Bool {
        // The recognizer wants a file URL; recreate one from the stored bytes
        // when the temp didn't survive (a restored draft, re-released, or a
        // wrist take whose audio lives only in the store).
        let url: URL
        if let tempURL, FileManager.default.fileExists(atPath: tempURL.path) {
            url = tempURL
        } else if let data = fetch(nodeID, in: context)?.audioData {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("transcribe-\(UUID().uuidString).m4a")
            guard (try? data.write(to: url)) != nil else { return false }
        } else {
            return false
        }
        defer { try? FileManager.default.removeItem(at: url) }

        guard let transcript = await ai.transcribe(audioURL: url), !transcript.isEmpty else { return false }
        guard !Task.isCancelled, let node = fetch(nodeID, in: context) else { return false }
        // Ownership: never overwrite words the user has touched.
        guard !node.transcriptEditedByUser else { return false }
        node.transcription = transcript
        node.updatedAt = .now
        try? context.save()
        return true
    }

    private static func understand(nodeID: UUID, context: ModelContext, ai: any OceanAIService) async -> String? {
        guard let node = fetch(nodeID, in: context) else { return nil }
        let basis = node.meaningText
        guard !basis.isEmpty else { return nil }
        let understanding = await ai.understand(basis)
        guard !Task.isCancelled, let fresh = fetch(nodeID, in: context) else { return nil }
        NodeComposer.applyUnderstanding(understanding, to: fresh)
        try? context.save()
        return understanding.essence
    }

    private static func fetch(_ id: UUID, in context: ModelContext) -> Node? {
        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
