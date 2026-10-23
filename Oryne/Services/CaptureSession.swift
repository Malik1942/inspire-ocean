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
    /// The pictures on the card, in the order they were added (at most
    /// `Node.maxImages`).
    var imageDatas: [Data] = []
    /// The link a release attaches, sensed in the words. `text` keeps the
    /// words as typed (for Undo); `release` lifts the link out of the
    /// thought's words when it sits at their start or end.
    var linkURLString: String? = nil
    /// Links the user took off the card: they stay words, and Undo brings
    /// them back that way.
    var dismissedLinks: Set<String> = []

    /// When set, the released node is spatially anchored to this current
    /// (`Node.anchorThemeKey`) at creation — placement is the user's intent;
    /// AI understanding still adds theme chips but never relocates it.
    /// Not part of `isEmpty`: an anchor alone is not content.
    var anchorThemeKey: String? = nil

    var isEmpty: Bool {
        text.trimmed.isEmpty
            && transcript.trimmed.isEmpty
            && audioData == nil
            && imageDatas.isEmpty
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

    /// How long a released thought can be taken back. The moment may fade
    /// sooner — the surfaces keep a quiet Undo pill alive until this expires.
    static let undoWindow: TimeInterval = 10

    /// The last release, held as the undo window — cleared by the next
    /// recording or release. `at` stamps the save (refreshed when a review
    /// commits edits), so "undo within ~10 seconds" means seconds the user
    /// actually had.
    private(set) var lastReleased: (nodeID: UUID, draft: CaptureDraft, at: Date)?
    private var understandingTask: Task<Void, Never>?

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

    /// The user's own words, built once per session and handed to every
    /// recognizer pass as hints.
    private var vocabulary: [String] = []
    private var vocabularyBuilt = false

    private func ensureVocabulary() {
        guard !vocabularyBuilt, let context else { return }
        vocabularyBuilt = true
        vocabulary = CaptureVocabulary.build(context: context)
        transcriber.contextualStrings = vocabulary
    }

    func startRecording(onInterruption: @escaping () -> Void) async -> RecordingStart {
        guard !transcriber.isRecording else { return .started }
        ensureVocabulary()
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
        // A link at the start or end of the words leaves them: its card
        // carries it.
        let link = draft.linkURLString
        let text = LinkSensing.words(draft.text, lifting: link)
        let transcript = LinkSensing.words(draft.transcript, lifting: link)
        let meaning = [text, transcript].filter { !$0.isEmpty }.joined(separator: " ")
        let node = NodeComposer.make(
            // What it holds names it: a whisper, a thought, or (with no
            // words) its pictures or its link.
            kind: NodeKind.captured(
                voice: draft.kind == .voice || draft.audioData != nil,
                words: meaning,
                images: draft.imageDatas.count,
                link: link != nil
            ),
            text: text,
            transcription: transcript.isEmpty ? nil : transcript,
            linkURLString: link,
            audioData: draft.audioData,
            imageDatas: draft.imageDatas,
            detectThemes: !meaning.isEmpty
        )
        // The user's placement intent, applied before insert and independent of
        // understanding: nil for ordinary capture (unchanged), a current's key
        // when captured into one. Understanding still runs and adds chips, but
        // layout groups by `anchorThemeKey` first, so the node never relocates.
        node.anchorThemeKey = draft.anchorThemeKey
        context.insert(node)
        do {
            try context.save()
        } catch {
            // Take the unverified node back out so a retry can't double it.
            context.delete(node)
            return nil
        }
        lastReleased = (node.id, draft, .now)
        ReviewPrompt.shared.recordCapture()   // a verified save nudges the review ask
        return node.id
    }

    /// Applies review-capsule edits to the saved node, marking ownership only
    /// for words the user actually changed. Also refreshes the undo draft and
    /// clock: a thought committed after editing restores *as edited*, and the
    /// undo seconds count from the moment it left the user's hands.
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
        if lastReleased?.nodeID == nodeID {
            lastReleased?.draft.transcript = edited
            if let note { lastReleased?.draft.text = note.trimmed }
            lastReleased?.at = .now
        }
    }

    // MARK: Understanding

    /// Title + themes derived from the words the user kept. Voice thoughts
    /// with no transcript go through the post-hoc recognizer first; words the
    /// user has touched are never overwritten (ownership contract). The pass
    /// itself lives in `VoiceUnderstanding`, shared with wrist takes. A link
    /// is enriched alongside, so what its page says joins the meaning.
    func beginUnderstanding(nodeID: UUID) {
        guard let ai, let context else { return }
        let tempURL = lastReleased?.nodeID == nodeID ? lastReleased?.draft.audioTempURL : nil
        let node = fetch(nodeID)
        // Only a whisper still to be transcribed needs the user's words as hints.
        if let node, WhisperRules.needsTranscription(node) {
            ensureVocabulary()
        }
        let vocabulary = self.vocabulary
        understandingTask?.cancel()
        understandingTask = Task {
            await VoiceUnderstanding.run(
                nodeID: nodeID, audioTempURL: tempURL, context: context, ai: ai, vocabulary: vocabulary
            )
        }
        // A link becomes a rich card, and what its page says joins the
        // thought's meaning (best effort; a link alone is named by its page).
        if node?.linkURL != nil {
            LinkEnrichmentService.shared.enrich(nodeID: nodeID, context: context, ai: ai)
        }
    }

    /// A long whisper gets a reading above its words (`VoiceUnderstanding`
    /// writes it; the Library backfill and the thought page read the bar).
    static let summaryThreshold = 240

    // MARK: Undo

    /// Whether the quiet Undo affordance should still be offered — within the
    /// window, for the surface's own release. (A review's header Undo doesn't
    /// go through this: while the review is open, taking back is always fair.)
    func undoAvailable(for nodeID: UUID) -> Bool {
        guard let last = lastReleased, last.nodeID == nodeID else { return false }
        return Date.now.timeIntervalSince(last.at) < Self.undoWindow
    }

    /// Take the released thought back. Returns the draft so the surface can
    /// restore it — the thought isn't lost, it just never entered the Ocean.
    @discardableResult
    func undoLastRelease() -> CaptureDraft? {
        guard let context, let (nodeID, draft, _) = lastReleased else { return nil }
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
