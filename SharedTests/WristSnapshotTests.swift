import XCTest
import Foundation

final class WristSnapshotTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let thoughtID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let deletedID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func snapshot(builtAfter offset: TimeInterval = 0, title: String = "Lighthouse café") -> WristSnapshot {
        var thought = WristThought(id: thoughtID, title: title, createdAt: t0)
        thought.reading = "A room that tells you to stay."
        thought.readingIsSummary = true
        return WristSnapshot(
            recent: [thought], today: thought, todayDay: t0,
            deletedIDs: [deletedID], generatedAt: t0.addingTimeInterval(offset)
        )
    }

    func test_context_carriesConfirmationsAndTheSnapshotTogether() {
        let confirmations = [WatchConfirmation(id: thoughtID, title: "Lighthouse café")]
        let context = WatchWire.context(for: confirmations, snapshot: snapshot())
        XCTAssertEqual(WatchWire.confirmations(fromContext: context), confirmations)
        XCTAssertEqual(WatchWire.snapshot(from: context), snapshot())
    }

    func test_contextWithoutASnapshot_carriesNone() {
        let context = WatchWire.context(for: [], snapshot: nil)
        XCTAssertNil(WatchWire.snapshot(from: context))
    }

    func test_isNewer_comparesWhenEachWasBuilt() {
        XCTAssertTrue(snapshot().isNewer(than: nil))
        XCTAssertTrue(snapshot(builtAfter: 5).isNewer(than: snapshot()))
        XCTAssertFalse(snapshot().isNewer(than: snapshot(builtAfter: 5)))
        XCTAssertFalse(snapshot().isNewer(than: snapshot()), "the same snapshot again changes nothing")
    }

    func test_hasSameContent_ignoresWhenItWasBuilt() {
        XCTAssertTrue(snapshot(builtAfter: 60).hasSameContent(as: snapshot()))
        XCTAssertFalse(snapshot(title: "Renamed").hasSameContent(as: snapshot()))
        XCTAssertFalse(snapshot().hasSameContent(as: nil))
    }

    func test_today_showsOnlyOnTheDayItWasPicked() {
        XCTAssertEqual(snapshot().today(on: t0.addingTimeInterval(60), calendar: utc)?.id, thoughtID)
        XCTAssertNil(snapshot().today(on: t0.addingTimeInterval(86_400), calendar: utc))
    }

    func test_recentThought_findsByID() {
        XCTAssertEqual(snapshot().recentThought(thoughtID)?.title, "Lighthouse café")
        XCTAssertNil(snapshot().recentThought(deletedID))
    }
}
