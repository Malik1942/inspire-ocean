import XCTest
import Foundation

final class TakeQueueStateTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func take(_ offset: TimeInterval = 0) -> WatchTake {
        WatchTake(id: UUID(), createdAt: t0.addingTimeInterval(offset), duration: 3)
    }

    func test_add_queuesOnWatchAndIgnoresDuplicates() {
        var state = TakeQueueState()
        let a = take()
        state.add(a, phoneReachableAtStop: true)
        state.add(a, phoneReachableAtStop: false)
        XCTAssertEqual(state.takes.count, 1)
        XCTAssertEqual(state.item(a.id)?.status, .onWatch)
        XCTAssertEqual(state.item(a.id)?.phoneTransfer, .notSent)
        XCTAssertEqual(state.item(a.id)?.phoneReachableAtStop, true)
    }

    func test_remove_dropsTheTake() {
        var state = TakeQueueState()
        let a = take()
        state.add(a, phoneReachableAtStop: true)
        state.remove(a.id)
        XCTAssertTrue(state.takes.isEmpty)
    }

    func test_needingPhoneSend_onlyOnWatchAndNotHandedOver() {
        var state = TakeQueueState()
        let fresh = take(), handed = take(1), clouded = take(2)
        [fresh, handed, clouded].forEach { state.add($0, phoneReachableAtStop: true) }
        state.markPhoneTransfer(handed.id, .pending)
        state.markInICloud(clouded.id)
        XCTAssertEqual(state.needingPhoneSend().map(\.id), [fresh.id])
    }

    func test_failedTransfer_isSentAgain() {
        var state = TakeQueueState()
        let a = take()
        state.add(a, phoneReachableAtStop: true)
        state.markPhoneTransfer(a.id, .pending)
        state.markPhoneTransfer(a.id, .notSent)
        XCTAssertEqual(state.needingPhoneSend().map(\.id), [a.id])
    }

    func test_needingCloudUpload_unreachableAtStop_goesAtOnce() {
        var state = TakeQueueState()
        let a = take()
        state.add(a, phoneReachableAtStop: false)
        XCTAssertEqual(state.needingCloudUpload(now: t0).map(\.id), [a.id])
    }

    func test_needingCloudUpload_reachableAtStop_waitsForTheDelay() {
        var state = TakeQueueState()
        let a = take()
        state.add(a, phoneReachableAtStop: true)
        XCTAssertTrue(state.needingCloudUpload(now: t0.addingTimeInterval(119)).isEmpty)
        XCTAssertEqual(state.needingCloudUpload(now: t0.addingTimeInterval(120)).map(\.id), [a.id])
    }

    func test_needingCloudUpload_skipsTakesOffTheWatch() {
        var state = TakeQueueState()
        let a = take(), b = take(1)
        state.add(a, phoneReachableAtStop: false)
        state.add(b, phoneReachableAtStop: false)
        state.markInICloud(a.id)
        state.apply([WatchConfirmation(id: b.id, title: nil)])
        XCTAssertTrue(state.needingCloudUpload(now: t0.addingTimeInterval(999)).isEmpty)
    }

    func test_markInICloud_neverDowngradesConfirmed() {
        var state = TakeQueueState()
        let a = take()
        state.add(a, phoneReachableAtStop: true)
        state.apply([WatchConfirmation(id: a.id, title: nil)])
        state.markInICloud(a.id)
        XCTAssertEqual(state.item(a.id)?.status, .confirmed)
    }

    func test_apply_confirmsKeepsTitleAndIgnoresUnknown() {
        var state = TakeQueueState()
        let a = take()
        state.add(a, phoneReachableAtStop: true)
        state.apply([
            WatchConfirmation(id: a.id, title: "Lighthouse café"),
            WatchConfirmation(id: UUID(), title: "Not ours"),
        ])
        state.apply([WatchConfirmation(id: a.id, title: nil)])
        XCTAssertEqual(state.takes.count, 1)
        XCTAssertEqual(state.item(a.id)?.status, .confirmed)
        XCTAssertEqual(state.item(a.id)?.title, "Lighthouse café")
    }

    func test_audioDisposable_followsWhereTheTakeIsSafe() {
        var state = TakeQueueState()
        let onWatch = take(), cloudWhileSending = take(1), cloudDone = take(2), confirmed = take(3)
        [onWatch, cloudWhileSending, cloudDone, confirmed].forEach { state.add($0, phoneReachableAtStop: true) }
        state.markPhoneTransfer(cloudWhileSending.id, .pending)
        state.markInICloud(cloudWhileSending.id)
        state.markInICloud(cloudDone.id)
        state.apply([WatchConfirmation(id: confirmed.id, title: nil)])

        XCTAssertFalse(state.audioDisposable(onWatch.id))
        XCTAssertFalse(state.audioDisposable(cloudWhileSending.id), "a pending transfer still reads the file")
        XCTAssertTrue(state.audioDisposable(cloudDone.id))
        XCTAssertTrue(state.audioDisposable(confirmed.id))
        XCTAssertTrue(state.audioDisposable(UUID()), "an unknown take has nothing worth keeping")
    }

    func test_prune_keepsNewestConfirmedAndEveryUnconfirmed() {
        var state = TakeQueueState()
        let waiting = take(-100)
        let confirmed = (0..<25).map { take(TimeInterval($0)) }
        state.add(waiting, phoneReachableAtStop: true)
        confirmed.forEach { state.add($0, phoneReachableAtStop: true) }
        state.apply(confirmed.map { WatchConfirmation(id: $0.id, title: nil) })

        XCTAssertEqual(state.takes.filter { $0.status == .confirmed }.count, TakeQueueState.confirmedKept)
        XCTAssertNotNil(state.item(waiting.id))
        XCTAssertNil(state.item(confirmed[0].id))
        XCTAssertNil(state.item(confirmed[4].id))
        XCTAssertNotNil(state.item(confirmed[5].id))
        XCTAssertNotNil(state.item(confirmed[24].id))
    }

    func test_codableRoundTrip() throws {
        var state = TakeQueueState()
        let a = take(), b = take(1)
        state.add(a, phoneReachableAtStop: false)
        state.add(b, phoneReachableAtStop: true)
        state.markPhoneTransfer(b.id, .delivered)
        state.apply([WatchConfirmation(id: b.id, title: "Lighthouse café")])
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(TakeQueueState.self, from: data), state)
    }
}
