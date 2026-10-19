import Foundation
import SwiftData

/// The understanding pass for one saved thought: a voice thought with no
/// transcript is transcribed first (from the temp file when it survives,
/// else from the stored bytes), with the user's own vocabulary and both
/// languages kept; then title and themes come from the words the user kept,
/// joining an existing current when one fits; a long whisper also gets its
/// reading above the words. Shared by in-app capture (`CaptureSession`) and
/// wrist takes (`WatchTakeImporter`) so the two can never drift.
///
/// Ownership: a transcript the user edited is never overwritten, and every
/// interpretation goes through `NodeComposer.applyUnderstanding`.
/// Cancellation is honored between steps (Undo cancels the capture's task).
@MainActor
enum VoiceUnderstanding {

    /// The labels the Library backfill can have stamped on an untitled voice
    /// thought, in every language the app ships ("Whisper", 语音): a
    /// placeholder, never a name.
    static let whisperPlaceholders: Set<String> = {
        var labels: Set<String> = ["Whisper", NodeKind.voice.label]
        for language in Bundle.main.localizations {
            guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { continue }
            labels.insert(bundle.localizedString(forKey: "Whisper", value: nil, table: nil))
        }
        return labels
    }()

    /// Returns the essence (the interpreted title), or nil when there were no
    /// words to understand (no recording, the recognizer heard nothing or
    /// failed), the user owns the transcript, the pass was cancelled, or the
    /// node is gone. `audioTempURL` is consumed: it is deleted on every path
    /// past the node lookup.
    @discardableResult
    static func run(
        nodeID: UUID,
        audioTempURL: URL?,
        context: ModelContext,
        ai: any OceanAIService,
        vocabulary: [String]
    ) async -> String? {
        guard let node = fetch(nodeID, in: context) else { return nil }
        if node.kind == .voice, (node.transcription ?? "").isEmpty {
            guard await transcribe(
                nodeID: nodeID, tempURL: audioTempURL, context: context, ai: ai, vocabulary: vocabulary
            ) else { return nil }
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
        ai: any OceanAIService,
        vocabulary: [String]
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

        guard let outcome = await ai.transcribeDetailed(audioURL: url, vocabulary: vocabulary) else { return false }
        guard !Task.isCancelled, let node = fetch(nodeID, in: context) else { return false }
        // Ownership: never overwrite words the user has touched.
        guard !node.transcriptEditedByUser else { return false }
        node.transcription = outcome.text
        node.transcriptLocale = outcome.localeID
        node.alternateTranscription = outcome.alternateText
        node.alternateTranscriptLocale = outcome.alternateLocaleID
        node.updatedAt = .now
        try? context.save()
        return true
    }

    private static func understand(nodeID: UUID, context: ModelContext, ai: any OceanAIService) async -> String? {
        guard let node = fetch(nodeID, in: context) else { return nil }
        // A voice thought understood late may carry the Library's "Whisper"
        // stamp: a placeholder, not words, so it never leads the basis or
        // becomes part of the title.
        if node.kind == .voice, !node.titleEditedByUser, whisperPlaceholders.contains(node.title.trimmed) {
            node.title = ""
        }
        let basis = node.meaningText
        guard !basis.isEmpty else { return nil }
        let currents = CurrentSnap.candidates(in: context, excluding: nodeID, forEntry: basis)
        let understanding = await ai.understand(basis, currents: currents)
        guard !Task.isCancelled, let fresh = fetch(nodeID, in: context) else { return nil }
        NodeComposer.applyUnderstanding(understanding, to: fresh)
        try? context.save()
        await summarizeIfLong(nodeID: nodeID, context: context, ai: ai)
        return understanding.essence
    }

    /// A long whisper gets a reading above its words. Only voice thoughts,
    /// only when long, only once; the user's own text is never summarized.
    private static func summarizeIfLong(nodeID: UUID, context: ModelContext, ai: any OceanAIService) async {
        guard let node = fetch(nodeID, in: context), node.kind == .voice, node.summary == nil,
              let transcript = node.transcription, transcript.count >= CaptureSession.summaryThreshold
        else { return }
        guard let summary = await ai.summarizeTranscript(transcript), !Task.isCancelled,
              let fresh = fetch(nodeID, in: context), fresh.summary == nil else { return }
        fresh.summary = summary
        try? context.save()
    }

    private static func fetch(_ id: UUID, in context: ModelContext) -> Node? {
        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
