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
    let player: WatchPlayer
    private let sync: TakeSync
    @ObservationIgnored private var current: (id: UUID, startedAt: Date)?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var sceneIsActive = true
    #if DEBUG
    /// The demo `caught` screen waits for the scene to go active: the view's
    /// first scene-phase report is `inactive`, which would release it.
    @ObservationIgnored private var demoStageAwaitingActive: Stage?
    #endif

    init(queue: TakeQueue, sync: TakeSync, player: WatchPlayer) {
        self.queue = queue
        self.sync = sync
        self.player = player
        recorder.onEndedBySystem = { [weak self] in
            Task { await self?.finish() }
        }
    }

    var statusLine: WatchStatusLine {
        .derive(from: queue.state)
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
        // The idle disc and the retry button call this directly; a second
        // start must never replace the take in progress.
        guard stage != .starting, stage != .recording else { return }
        // Capture wins (PHILOSOPHY §1): a replay stops before the mic opens.
        player.stop()
        releaseHeldTake()
        stage = .starting
        let id = UUID()
        switch await recorder.start(writingTo: queue.audioURL(for: id)) {
        case .started:
            // Timed from when recording began, not from before the microphone prompt.
            current = (id, .now)
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
        WKInterfaceDevice.current().play(.success)
        // Caught off screen (the cap, or a call, with the wrist down): nobody
        // can tap Undo, so it goes now.
        guard sceneIsActive else { stage = .idle; Task { await sync.flush() }; return }
        sync.heldTakeID = take.id
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

    /// A tap on "Nothing was caught". The notice never leaves on its own
    /// (PHILOSOPHY: failure never auto-fades).
    func dismissNotice() {
        if stage == .nothingCaught { stage = .idle }
    }

    /// Wrist down: a recording keeps going (spec §1); a take held for Undo
    /// sends now.
    func sceneBecameInactive() {
        sceneIsActive = false
        if case .caught = stage { releaseHeldTake() }
    }

    func sceneBecameActive() async {
        sceneIsActive = true
        #if DEBUG
        if let demo = demoStageAwaitingActive {
            demoStageAwaitingActive = nil
            stage = demo
        }
        #endif
        // Recovery once the microphone has been allowed in Settings.
        if stage == .denied, !recorder.permissionDenied { stage = .idle }
        sync.requestSnapshot()
        await sync.flush()
    }

    func backgroundRefresh() async {
        await sync.flush()
    }

    // MARK: Helpers

    private func discardRecording(_ id: UUID) {
        queue.deleteAudio(id)
    }

    /// Stays until tapped (`dismissNotice()`) or a new take begins.
    private func showNothingCaught() {
        stage = .nothingCaught
        WKInterfaceDevice.current().play(.failure)
    }

    private static func isDecodable(_ url: URL) -> Bool {
        ((try? AVAudioPlayer(contentsOf: url))?.duration ?? 0) > 0
    }

    #if DEBUG
    /// Screenshot seams (`SIMCTL_CHILD_` prefix on `simctl launch`):
    /// `ORYNE_WATCH_DEMO=empty|waiting|onItsWay|inOcean|recent|today` shows a
    /// sample queue (`recent` and `today` add a sample snapshot);
    /// `ORYNE_WATCH_STAGE=recording|caught|denied|failed|nothing` shows that screen;
    /// `ORYNE_WATCH_DEMO_TITLE` names the sample's last whisper.
    func applyDemoEnvironment(library: WristLibrary) {
        let env = ProcessInfo.processInfo.environment
        let now = Date()
        func take(_ secondsAgo: TimeInterval) -> WatchTake {
            WatchTake(id: UUID(), createdAt: now.addingTimeInterval(-secondsAgo), duration: 8)
        }
        var demo = TakeQueueState()
        // The thought page opens the newest recent row. On these seams that
        // row is the named lighthouse take; the untitled take waits behind
        // it. Other seams keep the named take ten minutes back.
        let named = take(env["ORYNE_WATCH_DEMO"] == "recent" || env["ORYNE_WATCH_DEMO"] == "today" ? 30 : 600)
        let title = env["ORYNE_WATCH_DEMO_TITLE"] ?? "Lighthouse café"
        demo.add(named, phoneReachableAtStop: true)
        demo.apply([WatchConfirmation(id: named.id, title: title)])
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
        case "recent", "today":
            demo.add(take(600), phoneReachableAtStop: false)
            queue.showDemo(demo)
            library.showDemo(Self.demoSnapshot(named: named, title: title, now: now, withToday: env["ORYNE_WATCH_DEMO"] == "today"))
        default:
            break
        }
        switch env["ORYNE_WATCH_STAGE"] {
        case "recording": Task { await begin() }
        case "caught": demoStageAwaitingActive = .caught(UUID())
        case "denied": stage = .denied
        case "failed": stage = .failed
        case "nothing": stage = .nothingCaught
        default: break
        }
    }

    private static func demoSnapshot(named: WatchTake, title: String, now: Date, withToday: Bool) -> WristSnapshot {
        var whisper = WristThought(id: named.id, title: title, createdAt: named.createdAt)
        whisper.reading = "Warm light on the counter at closing time, the menu chalked in two languages. A room that tells you to stay."
        whisper.readingIsSummary = true
        whisper.hasTranscript = true
        whisper.isVoice = true
        whisper.hasAudio = true
        var today = WristThought(id: UUID(), title: "Warm to cool, not a filter", createdAt: now.addingTimeInterval(-40 * 86_400))
        today.reading = "Grade the photo by the time of day it was taken, not by a preset."
        return WristSnapshot(
            recent: [whisper], today: withToday ? today : nil, todayDay: withToday ? now : nil,
            deletedIDs: [], generatedAt: now
        )
    }
    #endif
}
