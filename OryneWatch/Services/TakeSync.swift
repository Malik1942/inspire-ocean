import Foundation

/// The phone as `TakeSync` reaches it: `PhoneLink` (WatchConnectivity), or
/// a test's fake.
@MainActor
protocol PhoneLinking: AnyObject {
    var onConfirmations: (@MainActor ([WatchConfirmation]) -> Void)? { get set }
    var onTransferFinished: (@MainActor (_ id: UUID, _ delivered: Bool) -> Void)? { get set }
    var onActivated: (@MainActor () -> Void)? { get set }
    var onSnapshot: (@MainActor (WristSnapshot) -> Void)? { get set }
    var isReachable: Bool { get }
    var outstandingTakeIDs: Set<UUID> { get }
    func activate()
    func send(_ take: WatchTake, audioURL: URL) -> Bool
    func wake(_ id: UUID)
    /// Asks the phone for a fresh wrist snapshot; nothing when it's out of reach.
    func requestSnapshot()
}

/// The iCloud inbox as `TakeSync` reaches it: `CloudInbox`, or a test's fake.
@MainActor
protocol CloudInboxUploading: AnyObject {
    func upload(_ take: WatchTake, audioURL: URL) async -> Bool
}

/// Moves takes off the watch (spec §2): WatchConnectivity for every take,
/// the iCloud inbox for takes the phone may not reach soon. It acts on what
/// `TakeQueueState` says each take still needs, and holds back the take
/// inside its Undo window.
///
/// No watch API in here: SharedTests compiles this file (see project.yml),
/// so the background refresh is asked for through `scheduleRefresh`.
@MainActor
final class TakeSync {
    static let refreshIdentifier = "oryne.takes"

    private let queue: TakeQueue
    private let link: any PhoneLinking
    private let cloud: (any CloudInboxUploading)?
    private let library: WristLibrary
    private let scheduleRefresh: @MainActor (Date) -> Void
    private var flushTask: Task<Void, Never>?
    private var flushAgain = false

    /// The take inside its Undo window: never sent until released.
    var heldTakeID: UUID?

    /// `scheduleRefresh` asks the system to wake the app for
    /// `refreshIdentifier` around the given date.
    init(
        queue: TakeQueue,
        link: any PhoneLinking,
        cloud: (any CloudInboxUploading)?,
        library: WristLibrary,
        scheduleRefresh: @escaping @MainActor (Date) -> Void
    ) {
        self.queue = queue
        self.link = link
        self.cloud = cloud
        self.library = library
        self.scheduleRefresh = scheduleRefresh
        link.onConfirmations = { [weak self] confirmations in
            self?.queue.change { $0.apply(confirmations) }
        }
        link.onSnapshot = { [weak self] snapshot in
            // A reply and a context update can cross: only a newer snapshot
            // changes anything.
            guard let self, self.library.receive(snapshot) else { return }
            self.queue.change { $0.apply(snapshot) }
        }
        link.onTransferFinished = { [weak self] id, delivered in
            // A failed transfer is retried on the next flush, not in a loop.
            self?.queue.change { $0.markPhoneTransfer(id, delivered ? .delivered : .notSent) }
        }
        link.onActivated = { [weak self] in
            self?.reconcile()
            self?.requestSnapshot()
            Task { await self?.flush() }
        }
    }

    /// The reading taken at stop decides the iCloud fallback.
    var isPhoneReachable: Bool {
        link.isReachable
    }

    func start() {
        link.activate()
    }

    /// On screen with the phone in reach: ask it for a fresh snapshot. Out
    /// of reach this does nothing; the held snapshot stays, and nothing says
    /// "syncing" (PHILOSOPHY §5).
    func requestSnapshot() {
        link.requestSnapshot()
    }

    /// Sends what each take still needs. A call that arrives while a pass
    /// is running asks for one more pass and waits for it, so a background
    /// refresh never returns before its work is done.
    func flush() async {
        if let running = flushTask {
            flushAgain = true
            await running.value
            return
        }
        let task = Task { @MainActor in
            await self.runPasses()
            self.flushTask = nil
        }
        flushTask = task
        await task.value
    }

    private func runPasses() async {
        // Re-arm before working, so a run the system cuts short still has
        // its next wake.
        scheduleRefreshIfNeeded()
        repeat {
            flushAgain = false
            var sent: UUID?
            for item in queue.state.needingPhoneSend() where item.id != heldTakeID {
                if link.send(item.take, audioURL: queue.audioURL(for: item.id)) {
                    queue.change { $0.markPhoneTransfer(item.id, .pending) }
                    sent = item.id
                }
            }
            if let sent { link.wake(sent) }
            if let cloud {
                for item in queue.state.needingCloudUpload(now: .now) where item.id != heldTakeID {
                    // Undone, or confirmed, mid-flush.
                    guard queue.state.item(item.id)?.status == .onWatch else { continue }
                    if await cloud.upload(item.take, audioURL: queue.audioURL(for: item.id)) {
                        queue.change { $0.markInICloud(item.id) }
                    }
                }
            }
        } while flushAgain
        scheduleRefreshIfNeeded()
    }

    /// A transfer the state thinks is pending but the system no longer holds
    /// (the app relaunched before `didFinish` arrived) is sent again; the
    /// phone's ledger drops the duplicate.
    private func reconcile() {
        let outstanding = link.outstandingTakeIDs
        let lost = queue.state.takes
            .filter { $0.phoneTransfer == .pending && !outstanding.contains($0.id) }
            .map(\.id)
        guard !lost.isEmpty else { return }
        queue.change { state in lost.forEach { state.markPhoneTransfer($0, .notSent) } }
    }

    /// While any take is still only on the watch, ask watchOS for a
    /// background refresh so the iCloud fallback runs without the app open.
    private func scheduleRefreshIfNeeded() {
        guard let next = queue.state.nextCloudAttempt(now: .now) else { return }
        scheduleRefresh(next)
    }
}
