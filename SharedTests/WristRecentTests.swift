import XCTest
import Foundation

final class WristRecentTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let noAudio: (UUID) -> Bool = { _ in false }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func take(_ offset: TimeInterval) -> WatchTake {
        WatchTake(id: UUID(), createdAt: t0.addingTimeInterval(offset), duration: 8)
    }

    private func thought(_ id: UUID, title: String? = nil, hasAudio: Bool = false, at date: Date? = nil) -> WristThought {
        var thought = WristThought(id: id, title: title, createdAt: date ?? t0)
        thought.reading = "A room that tells you to stay."
        thought.hasAudio = hasAudio
        thought.isVoice = true
        return thought
    }

    private func snapshot(_ recent: [WristThought] = [], today: WristThought? = nil, deleted: [UUID] = []) -> WristSnapshot {
        WristSnapshot(recent: recent, today: today, todayDay: today == nil ? nil : t0, deletedIDs: deleted, generatedAt: t0)
    }

    func test_queueTakes_areListedNewestFirst_withoutASnapshot() {
        var queue = TakeQueueState()
        let older = take(0), waiting = take(60)
        queue.add(older, phoneReachableAtStop: true)
        queue.add(waiting, phoneReachableAtStop: false)
        queue.apply([WatchConfirmation(id: older.id, title: "Lighthouse café")])

        let rows = WristRecent.rows(queue: queue, snapshot: nil, hasLocalAudio: noAudio)

        XCTAssertEqual(rows.map(\.id), [waiting.id, older.id])
        XCTAssertTrue(rows[0].isWaiting)
        XCTAssertNil(rows[0].title)
        XCTAssertEqual(rows[1].title, "Lighthouse café")
        XCTAssertFalse(rows[1].isWaiting)
        XCTAssertEqual(rows[1].duration, 8)
    }

    func test_snapshot_givesTheCurrentTitleAndReading() {
        var queue = TakeQueueState()
        let a = take(0)
        queue.add(a, phoneReachableAtStop: true)
        queue.apply([WatchConfirmation(id: a.id, title: "Lighthouse café")])

        let row = WristRecent.rows(queue: queue, snapshot: snapshot([thought(a.id, title: "The café by the lighthouse")]), hasLocalAudio: noAudio).first

        XCTAssertEqual(row?.title, "The café by the lighthouse")
        XCTAssertEqual(row?.reading, "A room that tells you to stay.")
    }

    func test_deletedTake_isNotListed() {
        var queue = TakeQueueState()
        let a = take(0)
        queue.add(a, phoneReachableAtStop: true)
        XCTAssertTrue(WristRecent.rows(queue: queue, snapshot: snapshot(deleted: [a.id]), hasLocalAudio: noAudio).isEmpty)
    }

    func test_takeOnlyTheSnapshotKnows_isListedAndPlaysFromThePhone() {
        let id = UUID()
        let rows = WristRecent.rows(queue: TakeQueueState(), snapshot: snapshot([thought(id, hasAudio: true)]), hasLocalAudio: noAudio)
        XCTAssertEqual(rows.map(\.id), [id])
        XCTAssertEqual(rows.first?.audio, .phone)
        XCTAssertNil(rows.first?.duration)
    }

    func test_audio_prefersTheWatchsOwnCopy() {
        var queue = TakeQueueState()
        let local = take(0), remote = take(1), silent = take(2)
        [local, remote, silent].forEach { queue.add($0, phoneReachableAtStop: true) }
        let snap = snapshot([thought(local.id, hasAudio: true), thought(remote.id, hasAudio: true), thought(silent.id)])

        let rows = WristRecent.rows(queue: queue, snapshot: snap) { $0 == local.id }
        let audio = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.audio) })

        XCTAssertEqual(audio[local.id], .watch)
        XCTAssertEqual(audio[remote.id], .phone)
        XCTAssertEqual(audio[silent.id], WristRow.Audio.none)
    }

    func test_hasTranscript_followsTheSnapshot_andAQueueOnlyTakeHasNone() {
        let id = UUID()
        var spoken = WristThought(id: id, title: "Lighthouse café", createdAt: t0)
        spoken.hasTranscript = true
        spoken.isVoice = true

        let fromSnapshot = WristRecent.rows(
            queue: TakeQueueState(), snapshot: snapshot([spoken]), hasLocalAudio: noAudio
        ).first
        XCTAssertEqual(fromSnapshot?.hasTranscript, true)
        XCTAssertNil(fromSnapshot?.reading)

        var queue = TakeQueueState()
        queue.add(take(0), phoneReachableAtStop: false)
        let fromQueue = WristRecent.rows(queue: queue, snapshot: nil, hasLocalAudio: noAudio).first
        XCTAssertEqual(fromQueue?.isVoice, true)
        XCTAssertEqual(fromQueue?.hasTranscript, false)
    }

    func test_today_showsOnItsDayOnly_andIsMarked() {
        let pick = thought(UUID(), title: "Warm to cool", hasAudio: true, at: t0.addingTimeInterval(-40 * 86_400))
        let snap = snapshot(today: pick)

        let row = WristRecent.today(snapshot: snap, queue: TakeQueueState(), now: t0.addingTimeInterval(60), calendar: utc, hasLocalAudio: noAudio)
        XCTAssertEqual(row?.id, pick.id)
        XCTAssertEqual(row?.isToday, true)
        XCTAssertEqual(row?.audio, .phone)

        XCTAssertNil(WristRecent.today(snapshot: snap, queue: TakeQueueState(), now: t0.addingTimeInterval(86_400), calendar: utc, hasLocalAudio: noAudio))
        XCTAssertNil(WristRecent.today(snapshot: nil, queue: TakeQueueState(), now: t0, calendar: utc, hasLocalAudio: noAudio))
    }
}
