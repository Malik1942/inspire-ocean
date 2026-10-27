import XCTest
import Foundation

/// Unit tests for `TakeSync`, the watch's sender, over fakes of the phone
/// link and the iCloud inbox and a real `TakeQueue` in a temporary folder.
/// The watch files are compiled into this bundle (see project.yml); no
/// app-module import.
final class TakeSyncTests: XCTestCase {

    // MARK: - Fixture

    @MainActor
    private final class Fixture {
        let queue: TakeQueue
        let library: WristLibrary
        let link = FakePhoneLink()
        let cloud = FakeCloudInbox()
        var scheduled: [Date] = []
        private(set) var sync: TakeSync!

        init(directory: URL) {
            queue = TakeQueue(store: TakeQueueStore(directory: directory))
            library = WristLibrary(store: WristSnapshotStore(url: directory.appendingPathComponent("wrist.json")))
            sync = TakeSync(queue: queue, link: link, cloud: cloud, library: library) { [unowned self] date in
                self.scheduled.append(date)
            }
        }

        /// A take caught a minute ago: out of the phone's reach goes to iCloud
        /// at once; in reach goes over WatchConnectivity only, for now.
        @discardableResult
        func catchTake(reachable: Bool) -> UUID {
            let take = WatchTake(id: UUID(), createdAt: Date().addingTimeInterval(-60), duration: 3)
            queue.change { $0.add(take, phoneReachableAtStop: reachable) }
            return take.id
        }

        func item(_ id: UUID) -> QueuedTake? {
            queue.state.item(id)
        }
    }

    @MainActor
    private final class FakePhoneLink: PhoneLinking {
        var onConfirmations: (@MainActor ([WatchConfirmation]) -> Void)?
        var onTransferFinished: (@MainActor (_ id: UUID, _ delivered: Bool) -> Void)?
        var onActivated: (@MainActor () -> Void)?
        var onSnapshot: (@MainActor (WristSnapshot) -> Void)?
        private(set) var snapshotRequests = 0
        var isActivated = true
        var isReachable = false
        var outstandingTakeIDs: Set<UUID> = []
        private(set) var sent: [UUID] = []

        func activate() {}

        func send(_ take: WatchTake, audioURL: URL) -> Bool {
            guard isActivated else { return false }
            sent.append(take.id)
            return true
        }

        func wake(_ id: UUID) {}

        func requestSnapshot() {
            snapshotRequests += 1
        }
    }

    @MainActor
    private final class FakeCloudInbox: CloudInboxUploading {
        /// While true, an upload waits until `finishHeld` answers it.
        var holdsUploads = false
        private(set) var started: [UUID] = []
        private var held: [CheckedContinuation<Bool, Never>] = []

        var heldCount: Int { held.count }

        func upload(_ take: WatchTake, audioURL: URL) async -> Bool {
            started.append(take.id)
            guard holdsUploads else { return true }
            return await withCheckedContinuation { held.append($0) }
        }

        /// Answers every held upload, and lets later ones through at once.
        func finishHeld(_ saved: Bool = true) {
            holdsUploads = false
            let waiting = held
            held = []
            waiting.forEach { $0.resume(returning: saved) }
        }
    }

    @MainActor
    private final class Flag {
        var isSet = false
    }

    @MainActor
    private func makeFixture() -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TakeSyncTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return Fixture(directory: directory)
    }

    /// Lets other main-actor work run until `condition` holds (or gives up).
    @MainActor
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() {
            await Task.yield()
        }
    }

    // MARK: - The Undo hold

    @MainActor
    func test_heldTake_isNeitherSentNorUploaded() async {
        let f = makeFixture()
        let id = f.catchTake(reachable: false)
        f.sync.heldTakeID = id

        await f.sync.flush()

        XCTAssertEqual(f.link.sent, [])
        XCTAssertEqual(f.cloud.started, [])
        XCTAssertEqual(f.item(id)?.status, .onWatch)
        XCTAssertEqual(f.item(id)?.phoneTransfer, .notSent)
    }

    @MainActor
    func test_takeReleasedFromTheHold_goesOnTheNextFlush() async {
        let f = makeFixture()
        let id = f.catchTake(reachable: false)
        f.sync.heldTakeID = id
        await f.sync.flush()

        f.sync.heldTakeID = nil
        await f.sync.flush()

        XCTAssertEqual(f.link.sent, [id])
        XCTAssertEqual(f.cloud.started, [id])
        XCTAssertEqual(f.item(id)?.phoneTransfer, .pending)
        XCTAssertEqual(f.item(id)?.status, .inICloud)
    }

    // MARK: - Changes while an upload is out

    /// The held take is in the pass's list when it starts; Undo lands while
    /// another take uploads. The undone take must never reach iCloud, or the
    /// phone would import a take the user took back.
    @MainActor
    func test_takeUndoneMidUpload_isNeverUploaded() async {
        let f = makeFixture()
        let first = f.catchTake(reachable: false)
        let undone = f.catchTake(reachable: false)
        f.sync.heldTakeID = undone
        f.cloud.holdsUploads = true

        let flushing = Task { await f.sync.flush() }
        await settle { f.cloud.heldCount == 1 }
        XCTAssertEqual(f.cloud.started, [first])

        f.sync.heldTakeID = nil                 // Undo, as WatchCaptureModel.undo does it
        f.queue.change { $0.remove(undone) }
        f.cloud.finishHeld()
        await flushing.value

        XCTAssertEqual(f.cloud.started, [first])
        XCTAssertFalse(f.link.sent.contains(undone))
        XCTAssertNil(f.item(undone))
        XCTAssertEqual(f.item(first)?.status, .inICloud)
    }

    @MainActor
    func test_takeConfirmedMidUpload_isNotUploaded() async {
        let f = makeFixture()
        let first = f.catchTake(reachable: false)
        let confirmed = f.catchTake(reachable: false)
        f.cloud.holdsUploads = true

        let flushing = Task { await f.sync.flush() }
        await settle { f.cloud.heldCount == 1 }
        f.link.onConfirmations?([WatchConfirmation(id: confirmed, title: "Lighthouse café")])
        f.cloud.finishHeld()
        await flushing.value

        XCTAssertEqual(f.cloud.started, [first])
        XCTAssertEqual(f.item(confirmed)?.status, .confirmed)
        XCTAssertEqual(f.item(confirmed)?.title, "Lighthouse café")
    }

    /// The phone confirms a take while its own upload is still out; the
    /// upload's success must not move it back to "in iCloud".
    @MainActor
    func test_takeConfirmedWhileItsUploadIsOut_staysConfirmed() async {
        let f = makeFixture()
        let id = f.catchTake(reachable: false)
        f.cloud.holdsUploads = true

        let flushing = Task { await f.sync.flush() }
        await settle { f.cloud.heldCount == 1 }
        f.link.onConfirmations?([WatchConfirmation(id: id, title: nil)])
        f.cloud.finishHeld()
        await flushing.value

        XCTAssertEqual(f.item(id)?.status, .confirmed)
    }

    // MARK: - Reconcile on activation

    /// The app relaunched before the system said the transfer finished, and
    /// the system no longer holds it: the take is sent again.
    @MainActor
    func test_activation_resendsAPendingTransferTheSystemLost() async {
        let f = makeFixture()
        let id = f.catchTake(reachable: true)
        f.queue.change { $0.markPhoneTransfer(id, .pending) }
        f.link.outstandingTakeIDs = []

        f.link.onActivated?()
        await f.sync.flush()

        XCTAssertEqual(f.link.sent, [id])
        XCTAssertEqual(f.item(id)?.phoneTransfer, .pending)
    }

    @MainActor
    func test_activation_keepsAPendingTransferTheSystemStillHolds() async {
        let f = makeFixture()
        let id = f.catchTake(reachable: true)
        f.queue.change { $0.markPhoneTransfer(id, .pending) }
        f.link.outstandingTakeIDs = [id]

        f.link.onActivated?()
        await f.sync.flush()

        XCTAssertEqual(f.link.sent, [])
        XCTAssertEqual(f.item(id)?.phoneTransfer, .pending)
    }

    // MARK: - Single flight

    /// A flush that arrives mid-pass starts no pass of its own: it asks for
    /// one more and returns only once that pass has run.
    @MainActor
    func test_flushArrivingMidPass_runsOneMorePass_andWaitsForIt() async {
        let f = makeFixture()
        let first = f.catchTake(reachable: false)
        f.cloud.holdsUploads = true

        let running = Task { await f.sync.flush() }
        await settle { f.cloud.heldCount == 1 }
        let later = f.catchTake(reachable: true)
        let secondReturned = Flag()
        let second = Task {
            await f.sync.flush()
            secondReturned.isSet = true
        }
        await settle { secondReturned.isSet }

        XCTAssertFalse(secondReturned.isSet, "returned before its pass ran")
        XCTAssertEqual(f.link.sent, [first], "a second pass ran alongside the first")

        f.cloud.finishHeld()
        await second.value
        await running.value

        XCTAssertEqual(f.link.sent, [first, later])
        XCTAssertEqual(f.cloud.started, [first])
        XCTAssertEqual(f.item(later)?.phoneTransfer, .pending)
    }

    // MARK: - The wrist snapshot

    @MainActor
    func test_snapshot_dropsATakeDeletedOnThePhone_withItsAudio() throws {
        let f = makeFixture()
        let id = f.catchTake(reachable: true)
        try Data([1]).write(to: f.queue.audioURL(for: id))
        f.link.onConfirmations?([WatchConfirmation(id: id, title: "Lighthouse café")])
        let snapshot = WristSnapshot(recent: [], today: nil, todayDay: nil, deletedIDs: [id], generatedAt: Date())

        f.link.onSnapshot?(snapshot)

        XCTAssertNil(f.item(id))
        XCTAssertFalse(f.queue.hasAudio(id))
        XCTAssertEqual(f.library.snapshot, snapshot)
    }

    @MainActor
    func test_olderSnapshot_changesNothing() {
        let f = makeFixture()
        let id = f.catchTake(reachable: true)
        f.link.onConfirmations?([WatchConfirmation(id: id, title: nil)])
        let now = Date()
        let newer = WristSnapshot(recent: [], today: nil, todayDay: nil, deletedIDs: [], generatedAt: now)
        let older = WristSnapshot(recent: [], today: nil, todayDay: nil, deletedIDs: [id], generatedAt: now.addingTimeInterval(-5))

        f.link.onSnapshot?(newer)
        f.link.onSnapshot?(older)

        XCTAssertNotNil(f.item(id), "a crossed, older snapshot deletes nothing")
        XCTAssertEqual(f.library.snapshot, newer)
    }

    @MainActor
    func test_activation_asksForAFreshSnapshot() async {
        let f = makeFixture()
        f.link.onActivated?()
        await f.sync.flush()
        XCTAssertEqual(f.link.snapshotRequests, 1)
    }

    @MainActor
    func test_requestSnapshot_asksTheLink() {
        let f = makeFixture()
        f.sync.requestSnapshot()
        XCTAssertEqual(f.link.snapshotRequests, 1)
    }

    // MARK: - Background refresh

    @MainActor
    func test_flush_asksForARefresh_whileATakeIsOnlyOnTheWatch() async {
        let f = makeFixture()
        f.catchTake(reachable: true)

        await f.sync.flush()

        XCTAssertFalse(f.scheduled.isEmpty)
    }

    @MainActor
    func test_flush_asksForNoRefresh_whenNothingWaits() async {
        let f = makeFixture()

        await f.sync.flush()

        XCTAssertEqual(f.scheduled, [])
    }
}
