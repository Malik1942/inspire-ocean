import XCTest
import Foundation

/// Every row of the spec's status table, plus the last-title rule.
final class WatchStatusLineTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func take(_ offset: TimeInterval) -> WatchTake {
        WatchTake(id: UUID(), createdAt: t0.addingTimeInterval(offset), duration: 3)
    }

    func test_nothingEverCaught_hasNoLine() {
        XCTAssertEqual(WatchStatusLine.derive(from: TakeQueueState()), .empty)
    }

    func test_anyTakeOnlyOnTheWatch_countsThoseTakes() {
        var state = TakeQueueState()
        let a = take(0), b = take(1), clouded = take(2), confirmed = take(3)
        [a, b, clouded, confirmed].forEach { state.add($0, phoneReachableAtStop: true) }
        state.markInICloud(clouded.id)
        state.apply([WatchConfirmation(id: confirmed.id, title: nil)])
        XCTAssertEqual(WatchStatusLine.derive(from: state), .waiting(count: 2))
    }

    func test_noneOnTheWatch_someInICloud_isOnItsWay() {
        var state = TakeQueueState()
        let clouded = take(0), confirmed = take(1)
        [clouded, confirmed].forEach { state.add($0, phoneReachableAtStop: false) }
        state.markInICloud(clouded.id)
        state.apply([WatchConfirmation(id: confirmed.id, title: nil)])
        XCTAssertEqual(WatchStatusLine.derive(from: state), .onItsWay)
    }

    func test_everythingConfirmed_isInOcean() {
        var state = TakeQueueState()
        let a = take(0)
        state.add(a, phoneReachableAtStop: true)
        state.apply([WatchConfirmation(id: a.id, title: nil)])
        XCTAssertEqual(WatchStatusLine.derive(from: state), .inOcean)
    }

    func test_lastTitle_isTheNewestConfirmedTakesTitle() {
        var state = TakeQueueState()
        let older = take(0), newer = take(10)
        [older, newer].forEach { state.add($0, phoneReachableAtStop: true) }
        state.apply([
            WatchConfirmation(id: older.id, title: "Old idea"),
            WatchConfirmation(id: newer.id, title: "Lighthouse café"),
        ])
        XCTAssertEqual(WatchStatusLine.lastTitle(from: state), "Lighthouse café")
    }

    func test_lastTitle_isNilWhileTheNewestConfirmedIsUnnamed() {
        var state = TakeQueueState()
        let older = take(0), newer = take(10)
        [older, newer].forEach { state.add($0, phoneReachableAtStop: true) }
        state.apply([
            WatchConfirmation(id: older.id, title: "Old idea"),
            WatchConfirmation(id: newer.id, title: nil),
        ])
        XCTAssertNil(WatchStatusLine.lastTitle(from: state), "an older title would describe the wrong thought")
    }

    func test_lastTitle_ignoresUnconfirmedTakes() {
        var state = TakeQueueState()
        let named = take(0), waiting = take(10)
        [named, waiting].forEach { state.add($0, phoneReachableAtStop: true) }
        state.apply([WatchConfirmation(id: named.id, title: "Lighthouse café")])
        XCTAssertEqual(WatchStatusLine.lastTitle(from: state), "Lighthouse café")
    }
}
