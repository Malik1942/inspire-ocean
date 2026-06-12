import Foundation
import SwiftUI
import SwiftData
import Observation

// MARK: - CaptureDraft

/// Everything one release needs, gathered by the presenting surface.
///
/// The draft outlives the release: it is what `undoRelease()` hands back so a
/// taken-back thought lands on the surface intact — words, recording, image
/// and all. Nothing is ever reconstructed from the deleted node.
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

    /// Fast Capture's rule: voice if a recording exists, image if an image is
    /// all there is, text otherwise.
    static func inferKind(text: String, transcript: String, audioData: Data?, imageData: Data?) -> NodeKind {
        if audioData != nil { return .voice }
        if imageData != nil, text.trimmed.isEmpty, transcript.trimmed.isEmpty { return .image }
        return .text
    }
}

// MARK: - CaptureEngine

/// The one capture state machine behind both surfaces (the Capture tab and
/// the Fast Capture overlay). The surfaces keep their own presentation —
/// attachments, mode switching, layout — and delegate every behavior that
/// must never drift between them:
///
/// - the recording lifecycle (permission → record → stop → review)
/// - the review lifecycle, including Fast Capture's auto-release rhythm
/// - the save pipeline — **verified**: "Safe in your Ocean" is shown only
///   after `context.save()` succeeded; failure becomes an explicit,
///   actionable attention moment, never a silent success
/// - the understanding pipeline (post-hoc transcription, title + themes)
/// - the post-capture trust moment and its timings
/// - taking a release back (undo) with full draft restoration
@MainActor
@Observable
final class CaptureEngine {

    // MARK: Recording & review state

    let transcriber = LiveTranscriber()
    private(set) var isReviewing = false
    var transcriptDraft = ""
    private(set) var recordedAudioData: Data?
    private(set) var recordedURL: URL?

    // MARK: Trust moment

    private(set) var moment: PostCaptureMoment?

    // MARK: Review policy

    /// Fast Capture sets this; an untouched review then releases itself.
    var autoReleaseDelay: TimeInterval?
    /// When the auto-release will fire — the surface renders the draining
    /// hairline from this, so the rhythm is visible, never a hidden timer.
    private(set) var autoReleaseDeadline: Date?
    var onAutoRelease: (() -> Void)?

    var autoReleasePending: Bool { autoReleaseDeadline != nil }

    // MARK: Host hooks

    /// Save verified — the surface clears its form.
    var onReleased: ((UUID) -> Void)?
    /// The moment finished its arc — the surface may dismiss or close.
    var onSettled: (() -> Void)?

    /// How long each phase of the moment lingers. The tab takes its time (the
    /// takeback should be reachable); the overlay stays brisk and hands the
    /// takeback to the global undo current after it closes.
    struct Timings {
        var catchingBeat: TimeInterval = 0.7
        var safe: TimeInterval
        var understood: TimeInterval
        var related: TimeInterval

        static let capture = Timings(safe: 5.0, understood: 6.5, related: 7.0)
        static let fastCapture = Timings(catchingBeat: 0.5, safe: 1.6, understood: 3.6, related: 4.2)
    }
    var timings: Timings = .capture

    // MARK: Wiring

    private var context: ModelContext?
    private var ai: (any OceanAIService)?

    private(set) var releasedNodeID: UUID?
    private var pendingNode: Node?        // inserted but unverified (save failed)
    private var lastDraft: CaptureDraft?
    private var catchTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var understandingTask: Task<Void, Never>?
    private var autoReleaseTask: Task<Void, Never>?

    func configure(context: ModelContext, ai: any OceanAIService) {
        self.context = context
        self.ai = ai
    }

    // MARK: Recording lifecycle

    enum RecordingStart {
        case started
        /// The mic permission is off — the surface says so and offers Settings,
        /// instead of a button that silently does nothing.
        case permissionDenied
        case failed
    }

    func startRecording() async -> RecordingStart {
        guard !transcriber.isRecording else { return .started }
        guard await transcriber.requestMicPermission() else { return .permissionDenied }
        clearReview()
        let url = AudioRecorder.url(for: "drift-\(UUID().uuidString).m4a")
        return await transcriber.start(writingTo: url) ? .started : .failed
    }

    func stopRecording() async {
        guard transcriber.isRecording else { return }
        let (url, transcript) = await transcriber.stop()
        recordedURL = url
        recordedAudioData = url.flatMap { try? Data(contentsOf: $0) }
        transcriptDraft = transcript
        withAnimation(.snappy) { isReviewing = true }
        startAutoRelease()
    }

    /// Stops and deletes — nothing entered the Ocean.
    func cancelRecording() async {
        await transcriber.cancel()
    }

    func discardReview() {
        if let recordedURL { try? FileManager.default.removeItem(at: recordedURL) }
        withAnimation(.snappy) { clearReview() }
    }

    private func clearReview() {
        pauseAutoRelease()
        recordedURL = nil
        recordedAudioData = nil
        transcriptDraft = ""
        isReviewing = false
    }

    /// Returns the surface to the moment before release: words and recording
    /// back on the table, and nothing auto-releasing them this time — a
    /// taken-back thought is held, not hurried.
    func restoreReview(transcript: String, audioData: Data?, tempURL: URL? = nil) {
        pauseAutoRelease()
        transcriptDraft = transcript
        recordedAudioData = audioData
        if let audioData {
            let url = tempURL ?? AudioRecorder.url(for: "drift-\(UUID().uuidString).m4a")
            if !FileManager.default.fileExists(atPath: url.path) {
                try? audioData.write(to: url)
            }
            recordedURL = url
        } else {
            recordedURL = nil
        }
        isReviewing = audioData != nil || !transcript.trimmed.isEmpty
    }

    // MARK: Auto-release (Fast Capture's rhythm)

    private func startAutoRelease() {
        guard let delay = autoReleaseDelay else { return }
        autoReleaseTask?.cancel()
        autoReleaseDeadline = Date.now.addingTimeInterval(delay)
        autoReleaseTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            autoReleaseDeadline = nil
            onAutoRelease?()
        }
    }

    /// The pause on the zero-friction path: the user reached for the words,
    /// so the fragment is held back until they release it themselves.
    func pauseAutoRelease() {
        autoReleaseTask?.cancel()
        autoReleaseTask = nil
        autoReleaseDeadline = nil
    }

    // MARK: Release — the one save pipeline

    func release(_ draft: CaptureDraft) {
        guard let context, !draft.isEmpty else { return }
        pauseAutoRelease()

        // A draft edited after a failed save replaces the failed node —
        // retrying stale content would save words the user no longer means.
        if let stale = pendingNode {
            context.delete(stale)
            pendingNode = nil
        }
        lastDraft = draft

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
            pendingNode = node
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                moment = PostCaptureMoment(
                    id: node.id, phase: .attention("Couldn’t save this thought"))
            }
            return
        }
        didRelease(node, draft: draft)
    }

    func retry() {
        guard let context, let node = pendingNode, let draft = lastDraft else { return }
        do {
            try context.save()
        } catch {
            return  // the attention capsule stays — still explicit, still actionable
        }
        pendingNode = nil
        didRelease(node, draft: draft)
    }

    /// The attention capsule was waved away: take the unverified node back out
    /// so a later release doesn't double it. The draft stays on the surface.
    func dismissAttention() {
        if let pendingNode, let context {
            context.delete(pendingNode)
        }
        pendingNode = nil
        withAnimation { moment = nil }
    }

    private func didRelease(_ node: Node, draft: CaptureDraft) {
        releasedNodeID = node.id

        // The engine's review state clears; the surface clears its own form
        // in onReleased. The temp file survives — the pipeline may need it.
        recordedURL = nil
        recordedAudioData = nil
        transcriptDraft = ""
        isReviewing = false
        onReleased?(node.id)

        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            moment = .catching(for: node.id)
        }

        // A breath of "catching…", then the verified truth.
        catchTask?.cancel()
        catchTask = Task {
            try? await Task.sleep(for: .seconds(timings.catchingBeat))
            guard !Task.isCancelled, moment?.id == node.id, moment?.phase == .catching else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                moment?.phase = .safe
            }
            scheduleSettle(after: timings.safe)
        }

        startUnderstanding(nodeID: node.id, draft: draft)
    }

    // MARK: Undo

    /// Take the released thought back. Returns the draft so the surface can
    /// restore it — the thought isn't lost, it just never entered the Ocean.
    @discardableResult
    func undoRelease() -> CaptureDraft? {
        guard let context, let id = releasedNodeID else { return nil }
        understandingTask?.cancel()
        catchTask?.cancel()
        settleTask?.cancel()

        if let node = fetch(id) {
            context.delete(node)
            try? context.save()
        }
        releasedNodeID = nil
        withAnimation { moment = nil }
        let draft = lastDraft
        lastDraft = nil
        return draft
    }

    // MARK: Understanding pipeline

    private func startUnderstanding(nodeID: UUID, draft: CaptureDraft) {
        guard let ai else { return }
        understandingTask?.cancel()
        understandingTask = Task {
            if draft.kind == .voice, draft.transcript.trimmed.isEmpty, let url = draft.audioTempURL {
                // No live transcript (speech off, or nothing recognized):
                // the post-hoc pass is the fallback; it reclaims the temp file.
                await transcribeThenUnderstand(nodeID: nodeID, url: url, ai: ai)
            } else {
                // A user-confirmed transcript wins — skip re-transcription.
                if let url = draft.audioTempURL {
                    try? FileManager.default.removeItem(at: url)
                }
                await understandAndApply(nodeID: nodeID, ai: ai)
            }
            if moment?.id == nodeID {
                withAnimation { moment?.interpreting = false }
            }
        }
    }

    private func transcribeThenUnderstand(nodeID: UUID, url: URL, ai: any OceanAIService) async {
        defer { try? FileManager.default.removeItem(at: url) }
        guard let transcript = await ai.transcribe(audioURL: url),
              !transcript.isEmpty, !Task.isCancelled,
              let context, let node = fetch(nodeID)
        else { return }
        node.transcription = transcript
        node.updatedAt = .now
        try? context.save()
        await understandAndApply(nodeID: nodeID, ai: ai)
    }

    private func understandAndApply(nodeID: UUID, ai: any OceanAIService) async {
        guard let context, let node = fetch(nodeID) else { return }
        // The typed note and the transcript both carry the meaning — themes
        // and the title derive from everything the user confirmed.
        let combined = [node.text, node.transcription ?? ""]
            .filter { !$0.isEmpty }.joined(separator: "\n")
        let basis = combined.isEmpty ? node.rawContent : combined
        guard !basis.isEmpty else { return }

        let titleBefore = node.title
        let understanding = await ai.understand(basis)
        guard !Task.isCancelled, let node = fetch(nodeID) else { return }

        // Memory stabilization: a title the user set while the Ocean was
        // thinking is theirs — interpretation never overwrites it.
        let userRetitled = node.title != titleBefore && !node.title.trimmed.isEmpty
        NodeComposer.applyUnderstanding(understanding, to: node, preserveTitle: userRetitled)
        try? context.save()
        advanceMoment(nodeID: nodeID, title: userRetitled ? node.title : understanding.essence)
    }

    // MARK: Moment progression

    private func advanceMoment(nodeID: UUID, title: String) {
        guard moment?.id == nodeID, let context, let ai else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            moment?.phase = .safe
            moment?.title = title
        }
        scheduleSettle(after: timings.understood)

        if let hint = PostCaptureMoment.strongRelatedHint(for: nodeID, context: context, ai: ai),
           moment?.id == nodeID {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                moment?.related = hint
            }
            scheduleSettle(after: timings.related)
        }
    }

    private func scheduleSettle(after seconds: TimeInterval) {
        settleTask?.cancel()
        settleTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            settle()
        }
    }

    /// Keep the moment up (e.g. while a sheet grown from it is open).
    func holdMoment() {
        settleTask?.cancel()
    }

    /// End the moment's arc now; the host's `onSettled` runs.
    func settle() {
        settleTask?.cancel()
        catchTask?.cancel()
        withAnimation { moment = nil }
        onSettled?()
    }

    // MARK: Helpers

    private func fetch(_ id: UUID) -> Node? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
