import Foundation
import AVFoundation
import Observation
import WatchKit

/// The wrist capture flow as one state machine (spec §1): idle, recording,
/// caught (with Undo), and the honest failure states. The Action Button,
/// Siri, and the complication all call `toggle()`; the app icon only opens.
@MainActor
@Observable
final class WatchCaptureModel {

    enum Stage: Equatable {
        case idle
        case starting
        case recording
        case caught(UUID)
        case denied
        case failed
        case nothingCaught
    }

    /// A reflex press shouldn't mint a take.
    static let minimumDuration: TimeInterval = 0.6
    static let undoWindow: TimeInterval = 5

    private(set) var stage: Stage = .idle
    let recorder = WatchRecorder()
    let queue: TakeQueue
    private let sync: TakeSync
    @ObservationIgnored private var current: (id: UUID, startedAt: Date)?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    init(queue: TakeQueue, sync: TakeSync) {
        self.queue = queue
        self.sync = sync
        recorder.onEndedBySystem = { [weak self] in
            Task { await self?.finish() }
        }
    }

    var statusLine: WatchStatusLine {
        .derive(from: queue.state)
    }

    var lastTitle: String? {
        WatchStatusLine.lastTitle(from: queue.state)
    }

    /// The one rule every trigger shares: idle or caught → record (a take
    /// held for Undo sends at once); recording → stop and catch.
    func toggle() async {
        switch stage {
        case .recording: await finish()
        case .starting: break
        default: await begin()
        }
    }

    func begin() async {
        releaseHeldTake()
        noticeTask?.cancel()
        stage = .starting
        let id = UUID()
        current = (id, .now)
        switch await recorder.start(writingTo: queue.audioURL(for: id)) {
        case .started:
            stage = .recording
        case .permissionDenied:
            discardRecording(id)
            stage = .denied
        case .failed:
            discardRecording(id)
            stage = .failed
        }
    }

    func finish() async {
        guard stage == .recording, let current else { return }
        // Claimed before any await: a second stop arriving together (the cap
        // and a tap) finds nothing to finish, instead of deleting this file.
        self.current = nil
        // The reading at stop decides whether the take also goes to iCloud now.
        let reachable = sync.isPhoneReachable
        let finished = await recorder.stop()

        guard let finished else {
            discardRecording(current.id)
            showNothingCaught()
            return
        }
        if finished.duration < Self.minimumDuration {
            discardRecording(current.id)
            stage = .idle   // a reflex press, discarded silently
            return
        }
        guard Self.isDecodable(finished.url) else {
            discardRecording(current.id)
            showNothingCaught()
            return
        }

        let take = WatchTake(id: current.id, createdAt: current.startedAt, duration: finished.duration)
        queue.change { $0.add(take, phoneReachableAtStop: reachable) }
        sync.heldTakeID = take.id
        WKInterfaceDevice.current().play(.success)
        stage = .caught(take.id)

        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoWindow))
            guard !Task.isCancelled else { return }
            self?.releaseHeldTake()
        }
    }

    /// Undo inside the window: nothing was sent, so nothing exists anywhere else.
    func undo() {
        guard case .caught(let id) = stage else { return }
        undoTask?.cancel()
        sync.heldTakeID = nil
        queue.change { $0.remove(id) }   // leaving the queue deletes its audio
        stage = .idle
    }

    /// Ends the Undo window (it ran out, the screen went off, or a new take
    /// began) and sends.
    func releaseHeldTake() {
        undoTask?.cancel()
        let wasHolding = sync.heldTakeID != nil
        sync.heldTakeID = nil
        if case .caught = stage { stage = .idle }
        if wasHolding { Task { await sync.flush() } }
    }

    /// Wrist down: a recording keeps going (spec §1); a take held for Undo
    /// sends now.
    func sceneBecameInactive() {
        if case .caught = stage { releaseHeldTake() }
    }

    func sceneBecameActive() async {
        // Recovery once the microphone has been allowed in Settings.
        if stage == .denied, !recorder.permissionDenied { stage = .idle }
        await sync.flush()
    }

    func backgroundRefresh() async {
        await sync.flush()
    }

    // MARK: Helpers

    private func discardRecording(_ id: UUID) {
        queue.deleteAudio(id)
    }

    private func showNothingCaught() {
        stage = .nothingCaught
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, self?.stage == .nothingCaught else { return }
            self?.stage = .idle
        }
    }

    private static func isDecodable(_ url: URL) -> Bool {
        ((try? AVAudioPlayer(contentsOf: url))?.duration ?? 0) > 0
    }

    #if DEBUG
    /// Screenshot seams (`SIMCTL_CHILD_` prefix on `simctl launch`):
    /// `ORYNE_WATCH_DEMO=empty|waiting|onItsWay|inOcean` shows a sample queue;
    /// `ORYNE_WATCH_STAGE=recording|caught|denied|failed|nothing` shows that screen.
    func applyDemoEnvironment() {
        let env = ProcessInfo.processInfo.environment
        let now = Date()
        func take(_ secondsAgo: TimeInterval) -> WatchTake {
            WatchTake(id: UUID(), createdAt: now.addingTimeInterval(-secondsAgo), duration: 8)
        }
        var demo = TakeQueueState()
        let named = take(600)
        demo.add(named, phoneReachableAtStop: true)
        demo.apply([WatchConfirmation(id: named.id, title: "Lighthouse café")])
        switch env["ORYNE_WATCH_DEMO"] {
        case "empty":
            queue.showDemo(TakeQueueState())
        case "waiting":
            demo.add(take(60), phoneReachableAtStop: false)
            demo.add(take(30), phoneReachableAtStop: false)
            queue.showDemo(demo)
        case "onItsWay":
            let clouded = take(60)
            demo.add(clouded, phoneReachableAtStop: false)
            demo.markInICloud(clouded.id)
            queue.showDemo(demo)
        case "inOcean":
            queue.showDemo(demo)
        default:
            break
        }
        switch env["ORYNE_WATCH_STAGE"] {
        case "recording": Task { await begin() }
        case "caught": stage = .caught(UUID())
        case "denied": stage = .denied
        case "failed": stage = .failed
        case "nothing": stage = .nothingCaught
        default: break
        }
    }
    #endif
}
