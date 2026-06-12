import Foundation
import SwiftUI
import SwiftData

/// Everything one release needs, gathered by the presenting surface.
///
/// The draft outlives the release: it is what undo hands back, so a
/// taken-back thought lands on the surface intact — words, recording, image
/// and all. Nothing is reconstructed from a deleted node.
/// (Idea kept from the parked CaptureEngine draft at 106d579.)
struct CaptureDraft {
    var kind: NodeKind = .text
    var text: String = ""
    var transcript: String = ""
    var audioData: Data? = nil
    /// Temp file backing the recording — only needed when no live transcript
    /// exists and the post-hoc recognizer must listen again.
    var audioTempURL: URL? = nil
    var imageData: Data? = nil
    var linkURLString: String? = nil

    var isEmpty: Bool {
        text.trimmed.isEmpty
            && transcript.trimmed.isEmpty
            && audioData == nil
            && imageData == nil
            && (linkURLString ?? "").isEmpty
    }
}

/// The shared capture pipeline behind both surfaces (the Capture tab and the
/// Fast Capture overlay). The surfaces keep their own presentation — capsule
/// rhythms, moments, layout — and delegate the behaviors that must never
/// drift between them:
///
/// - the recording lifecycle (permission → record → stop / cancel / interrupt)
/// - the one save path, verified: a refused save returns nil and the surface
///   keeps the draft — never a silent loss
/// - review-edit application with ownership marking
/// - the understanding pipeline (post-hoc transcription fallback, title +
///   themes from the words the user kept)
/// - undo with draft restoration, valid while a surface still offers it
@MainActor
@Observable
final class CaptureSession {

    let transcriber = LiveTranscriber()

    private var context: ModelContext?
    private var ai: (any OceanAIService)?

    /// The last release, held as the undo window — cleared by the next
    /// recording or release, not by a timer: the *surface* decides how long
    /// to offer undo (its moment), the session just honors it.
    private(set) var lastReleased: (nodeID: UUID, draft: CaptureDraft)?
    private var understandingTask: Task<Void, Never>?

    /// The interpreted title landed — the surface advances its moment.
    var onUnderstood: ((UUID, String) -> Void)?

    func configure(context: ModelContext, ai: any OceanAIService) {
        self.context = context
        self.ai = ai
    }

    // MARK: Recording lifecycle

    enum RecordingStart {
        case started
        case permissionDenied
        case failed
    }

    func startRecording(onInterruption: @escaping () -> Void) async -> RecordingStart {
        guard !transcriber.isRecording else { return .started }
        guard await transcriber.requestMicPermission() else { return .permissionDenied }
        transcriber.onInterruption = onInterruption
        let url = AudioRecorder.url(for: "drift-\(UUID().uuidString).m4a")
        return await transcriber.start(writingTo: url) ? .started : .failed
    }

    func stopRecording() async -> (audioURL: URL?, transcript: String) {
        await transcriber.stop()
    }

    func cancelRecording() async {
        await transcriber.cancel()
    }

    static func readAudio(_ url: URL?) -> Data? {
        url.flatMap { try? Data(contentsOf: $0) }
    }

    // MARK: Release — the one save path

    /// Composes, inserts, and saves. Returns nil when the draft is empty or
    /// the store refused the save — the surface keeps its draft and says so.
    @discardableResult
    func release(_ draft: CaptureDraft) -> UUID? {
        guard let context, !draft.isEmpty else { return nil }
        let meaning = [draft.text, draft.transcript]
            .map(\.trimmed).filter { !$0.isEmpty }.joined(separator: " ")
        let node = NodeComposer.make(
            kind: draft.kind,
            text: draft.text.trimmed,
            transcription: draft.transcript.trimmed.isEmpty ? nil : draft.transcript.trimmed,
            linkURLString: draft.linkURLString,
            audioData: draft.audioData,
            imageData: draft.imageData,
            detectThemes: !meaning.isEmpty
        )
        context.insert(node)
        do {
            try context.save()
        } catch {
            // Take the unverified node back out so a retry can't double it.
            context.delete(node)
            return nil
        }
        lastReleased = (node.id, draft)
        return node.id
    }

    /// Applies review-capsule edits to the saved node, marking ownership only
    /// for words the user actually changed.
    func applyReviewEdits(nodeID: UUID, transcript: String, note: String? = nil) {
        guard let node = fetch(nodeID) else { return }
        var changed = false
        let edited = transcript.trimmed
        if edited != (node.transcription ?? "") {
            node.transcription = edited.isEmpty ? nil : edited
            node.transcriptEditedByUser = true
            changed = true
        }
        if let note, note.trimmed != node.text {
            node.text = note.trimmed
            changed = true
        }
        if changed {
            node.updatedAt = .now
            try? context?.save()
        }
    }

    // MARK: Understanding

    /// Title + themes derived from the words the user kept. Voice thoughts
    /// with no transcript go through the post-hoc recognizer first; words the
    /// user has touched are never overwritten (ownership contract).
    func beginUnderstanding(nodeID: UUID) {
        guard let ai else { return }
        let tempURL = lastReleased?.nodeID == nodeID ? lastReleased?.draft.audioTempURL : nil
        understandingTask?.cancel()
        understandingTask = Task { [weak self] in
            guard let self, let node = self.fetch(nodeID) else { return }
            if node.kind == .voice, (node.transcription ?? "").isEmpty {
                await self.transcribeThenUnderstand(nodeID: nodeID, tempURL: tempURL, ai: ai)
            } else {
                // A confirmed transcript wins — the temp file has no further use.
                if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
                await self.understand(nodeID: nodeID, ai: ai)
            }
        }
    }

    private func transcribeThenUnderstand(nodeID: UUID, tempURL: URL?, ai: any OceanAIService) async {
        // The recognizer wants a file URL; recreate one from the stored bytes
        // when the temp didn't survive (a restored draft, re-released).
        let url: URL
        if let tempURL, FileManager.default.fileExists(atPath: tempURL.path) {
            url = tempURL
        } else if let data = fetch(nodeID)?.audioData {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("transcribe-\(UUID().uuidString).m4a")
            guard (try? data.write(to: url)) != nil else { return }
        } else {
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }

        guard let transcript = await ai.transcribe(audioURL: url), !transcript.isEmpty else { return }
        guard !Task.isCancelled, let node = fetch(nodeID) else { return }
        // Ownership: never overwrite words the user has touched.
        guard !node.transcriptEditedByUser else { return }
        node.transcription = transcript
        node.updatedAt = .now
        try? context?.save()
        await understand(nodeID: nodeID, ai: ai)
    }

    private func understand(nodeID: UUID, ai: any OceanAIService) async {
        guard let node = fetch(nodeID) else { return }
        let basis = node.meaningText
        guard !basis.isEmpty else { return }
        let understanding = await ai.understand(basis)
        guard !Task.isCancelled, let fresh = fetch(nodeID) else { return }
        NodeComposer.applyUnderstanding(understanding, to: fresh)
        try? context?.save()
        onUnderstood?(nodeID, understanding.essence)
    }

    // MARK: Undo

    func undoAvailable(for nodeID: UUID) -> Bool {
        lastReleased?.nodeID == nodeID
    }

    /// Take the released thought back. Returns the draft so the surface can
    /// restore it — the thought isn't lost, it just never entered the Ocean.
    @discardableResult
    func undoLastRelease() -> CaptureDraft? {
        guard let context, let (nodeID, draft) = lastReleased else { return nil }
        understandingTask?.cancel()
        if let node = fetch(nodeID) {
            context.delete(node)
            try? context.save()
        }
        if let url = draft.audioTempURL { try? FileManager.default.removeItem(at: url) }
        lastReleased = nil
        var restored = draft
        restored.audioTempURL = nil   // gone; re-release rebuilds it from the bytes
        return restored
    }

    private func fetch(_ id: UUID) -> Node? {
        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == id })
        return try? context?.fetch(descriptor).first
    }
}
