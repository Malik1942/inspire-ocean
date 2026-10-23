import XCTest
import Foundation

/// Unit tests for `CapturePictureSlots`: the composer's pictures in pick
/// order, the places held for those still loading, the room left, and the
/// send that waits for them.
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class CapturePictureSlotsTests: XCTestCase {

    private struct Pic: Identifiable {
        let id = UUID()
        let name: String
    }

    /// The card left to right: a picture's name, or "…" for a place still
    /// loading.
    private func card(_ slots: CapturePictureSlots<Pic>) -> [String] {
        slots.slots.map { slot in
            if case .picture(let picture) = slot { return picture.name }
            return "…"
        }
    }

    private func pics(_ names: String...) -> [Pic] {
        names.map { Pic(name: $0) }
    }

    // MARK: Pick order

    func testPicturesLandInTheOrderPicked() throws {
        var slots = CapturePictureSlots<Pic>(limit: 10)
        let load = try XCTUnwrap(slots.reserve(3))
        slots.fill(load.id, with: pics("a", "b", "c"))
        XCTAssertEqual(card(slots), ["a", "b", "c"])
    }

    func testAFastLoadLandsBehindASlowerEarlierPick() throws {
        var slots = CapturePictureSlots<Pic>(limit: 10)
        let slow = try XCTUnwrap(slots.reserve(1))
        let fast = try XCTUnwrap(slots.reserve(1))
        slots.fill(fast.id, with: pics("fast"))
        XCTAssertEqual(card(slots), ["…", "fast"])
        slots.fill(slow.id, with: pics("slow"))
        XCTAssertEqual(card(slots), ["slow", "fast"])
    }

    func testLoadsLandingOutOfOrderKeepEachLoadsPlaces() throws {
        var slots = CapturePictureSlots<Pic>(limit: 10)
        let first = try XCTUnwrap(slots.reserve(2))
        let second = try XCTUnwrap(slots.reserve(1))
        slots.fill(second.id, with: pics("c"))
        slots.fill(first.id, with: pics("a", "b"))
        XCTAssertEqual(card(slots), ["a", "b", "c"])
    }

    func testAPictureThatCannotBeReadGivesUpItsPlace() throws {
        var slots = CapturePictureSlots<Pic>(limit: 10)
        let load = try XCTUnwrap(slots.reserve(3))
        slots.fill(load.id, with: pics("a", "b"))
        XCTAssertEqual(card(slots), ["a", "b"])
        XCTAssertEqual(slots.room, 8)
    }

    func testPicturesBeyondALoadsPlacesAreLeftOut() throws {
        var slots = CapturePictureSlots<Pic>(limit: 10)
        let load = try XCTUnwrap(slots.reserve(1))
        slots.fill(load.id, with: pics("a", "b"))
        XCTAssertEqual(card(slots), ["a"])
    }

    func testTheScreenshotTakesTheFrontPlace() throws {
        var slots = CapturePictureSlots<Pic>(limit: 10, pictures: pics("x"))
        let shot = try XCTUnwrap(slots.reserve(1, atFront: true))
        XCTAssertEqual(card(slots), ["…", "x"])
        slots.fill(shot.id, with: pics("shot"))
        XCTAssertEqual(card(slots), ["shot", "x"])
    }

    // MARK: Room

    func testRoomCountsPicturesAndPlacesStillLoading() {
        var slots = CapturePictureSlots<Pic>(limit: 10, pictures: pics("a", "b", "c"))
        _ = slots.reserve(2)
        XCTAssertEqual(slots.room, 5)
    }

    func testAPickTakesOnlyTheRoomLeft() {
        var slots = CapturePictureSlots<Pic>(limit: 10, pictures: pics("1", "2", "3", "4", "5", "6", "7", "8"))
        let load = slots.reserve(5)
        XCTAssertEqual(load?.count, 2)
        XCTAssertEqual(slots.loadingCount, 2)
        XCTAssertEqual(slots.room, 0)
    }

    func testAFullCardHoldsNoPlace() {
        var slots = CapturePictureSlots<Pic>(limit: 2, pictures: pics("a", "b"))
        XCTAssertNil(slots.reserve(1))
        XCTAssertEqual(card(slots), ["a", "b"])
    }

    func testNothingPickedHoldsNoPlace() {
        var slots = CapturePictureSlots<Pic>(limit: 10)
        XCTAssertNil(slots.reserve(0))
        XCTAssertFalse(slots.isLoading)
    }

    func testRemovingAPictureFreesItsPlace() {
        let kept = pics("x", "y")
        var slots = CapturePictureSlots<Pic>(limit: 10, pictures: kept)
        slots.remove(kept[0].id)
        XCTAssertEqual(card(slots), ["y"])
        XCTAssertEqual(slots.room, 9)
    }

    // MARK: Loading

    func testLoadingCountsPlacesNotYetFilled() throws {
        var slots = CapturePictureSlots<Pic>(limit: 10, pictures: pics("x"))
        let load = try XCTUnwrap(slots.reserve(2))
        XCTAssertTrue(slots.isLoading)
        XCTAssertEqual(slots.loadingCount, 2)
        slots.fill(load.id, with: pics("a", "b"))
        XCTAssertFalse(slots.isLoading)
        XCTAssertEqual(slots.pictures.map(\.name), ["x", "a", "b"])
    }

    func testCancellingLetsGoOfEveryPlaceStillLoading() throws {
        var slots = CapturePictureSlots<Pic>(limit: 10, pictures: pics("x"))
        let first = try XCTUnwrap(slots.reserve(1))
        let second = try XCTUnwrap(slots.reserve(2))
        slots.fill(first.id, with: pics("a"))
        _ = slots.cancelLoading()
        XCTAssertEqual(card(slots), ["x", "a"])
        XCTAssertEqual(slots.room, 8)
        // The load let go lands on nothing.
        slots.fill(second.id, with: pics("b", "c"))
        XCTAssertEqual(card(slots), ["x", "a"])
    }

    // MARK: The send

    func testASendWithNothingLoadingGoesAtOnce() {
        var slots = CapturePictureSlots<Pic>(limit: 10, pictures: pics("x"))
        XCTAssertTrue(slots.requestSend())
        XCTAssertFalse(slots.sendWaiting)
    }

    func testASendWaitsForPicturesStillLoading() {
        var slots = CapturePictureSlots<Pic>(limit: 10)
        _ = slots.reserve(1)
        XCTAssertFalse(slots.requestSend())
        XCTAssertTrue(slots.sendWaiting)
    }

    func testTheWaitingSendGoesWhenTheLastPictureLands() throws {
        var slots = CapturePictureSlots<Pic>(limit: 10)
        let first = try XCTUnwrap(slots.reserve(1))
        let second = try XCTUnwrap(slots.reserve(1))
        XCTAssertFalse(slots.requestSend())
        XCTAssertFalse(slots.fill(first.id, with: pics("a")))
        XCTAssertTrue(slots.sendWaiting)
        XCTAssertTrue(slots.fill(second.id, with: pics("b")))
        XCTAssertFalse(slots.sendWaiting)
    }

    func testALoadWithNoSendWaitingSendsNothing() throws {
        var slots = CapturePictureSlots<Pic>(limit: 10)
        let load = try XCTUnwrap(slots.reserve(1))
        XCTAssertFalse(slots.fill(load.id, with: pics("a")))
    }

    func testAPictureThatCannotBeReadStillEndsTheWait() throws {
        var slots = CapturePictureSlots<Pic>(limit: 10, pictures: pics("x"))
        let load = try XCTUnwrap(slots.reserve(1))
        XCTAssertFalse(slots.requestSend())
        XCTAssertTrue(slots.fill(load.id, with: []))
        XCTAssertEqual(card(slots), ["x"])
    }

    func testALaterLoadNeverSendsOnItsOwn() throws {
        var slots = CapturePictureSlots<Pic>(limit: 10)
        let first = try XCTUnwrap(slots.reserve(1))
        XCTAssertFalse(slots.requestSend())
        // The wait is over once nothing loads, whether or not the send went.
        XCTAssertTrue(slots.fill(first.id, with: pics("a")))
        let undo = try XCTUnwrap(slots.reserve(1))
        XCTAssertFalse(slots.fill(undo.id, with: pics("b")))
    }

    func testCancellingSendsAWaitingSendWithWhatLanded() {
        var slots = CapturePictureSlots<Pic>(limit: 10, pictures: pics("x"))
        _ = slots.reserve(2)
        XCTAssertFalse(slots.requestSend())
        XCTAssertTrue(slots.cancelLoading())
        XCTAssertFalse(slots.sendWaiting)
        XCTAssertEqual(card(slots), ["x"])
    }

    func testCancellingWithNoSendWaitingSendsNothing() {
        var slots = CapturePictureSlots<Pic>(limit: 10)
        _ = slots.reserve(1)
        XCTAssertFalse(slots.cancelLoading())
    }

    func testAWaitCalledOffNeverSendsLater() throws {
        var slots = CapturePictureSlots<Pic>(limit: 10)
        let load = try XCTUnwrap(slots.reserve(1))
        XCTAssertFalse(slots.requestSend())
        slots.callOffSend()
        XCTAssertFalse(slots.sendWaiting)
        XCTAssertFalse(slots.fill(load.id, with: pics("a")))
        XCTAssertEqual(card(slots), ["a"])
    }

    // MARK: Starting over

    func testStartingOverDropsLoadsAndTheWait() throws {
        var slots = CapturePictureSlots<Pic>(limit: 10)
        let load = try XCTUnwrap(slots.reserve(2))
        XCTAssertFalse(slots.requestSend())
        slots.replace(with: pics("z"))
        XCTAssertEqual(card(slots), ["z"])
        XCTAssertFalse(slots.sendWaiting)
        XCTAssertFalse(slots.fill(load.id, with: pics("a", "b")))
        XCTAssertEqual(card(slots), ["z"])
    }
}
