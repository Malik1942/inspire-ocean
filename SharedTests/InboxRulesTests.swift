import XCTest

final class InboxRulesTests: XCTestCase {

    // MARK: - InboxTokenPolicy

    func test_token_mayBeSaved_whenNothingFetched() {
        XCTAssertTrue(InboxTokenPolicy.maySaveToken(after: []))
    }

    func test_token_mayBeSaved_whenEveryRecordWasAccepted() {
        XCTAssertTrue(InboxTokenPolicy.maySaveToken(after: [.accepted]))
    }

    func test_token_mayBeSaved_whenOnlyInvalidRecordsFailed() {
        XCTAssertTrue(InboxTokenPolicy.maySaveToken(after: [.accepted, .invalid]))
    }

    func test_token_isHeldBack_whenARecordFailedForNow() {
        XCTAssertFalse(InboxTokenPolicy.maySaveToken(after: [.failedForNow]))
    }

    func test_token_isHeldBack_whenAnyRecordFailedForNow_amongOthers() {
        XCTAssertFalse(InboxTokenPolicy.maySaveToken(after: [.accepted, .failedForNow, .invalid]))
    }

    // MARK: - InboxDeletionQueue

    func test_queue_addKeepsOrderAndIgnoresDuplicates() {
        let a = UUID(), b = UUID()
        var queue = InboxDeletionQueue()
        XCTAssertTrue(queue.isEmpty)

        queue.add(a)
        queue.add(b)
        queue.add(a)

        XCTAssertEqual(queue.ids, [a, b])
        XCTAssertFalse(queue.isEmpty)
    }

    func test_queue_removeDropsOne() {
        let a = UUID(), b = UUID()
        var queue = InboxDeletionQueue()
        queue.add(a)
        queue.add(b)

        queue.remove(a)

        XCTAssertEqual(queue.ids, [b])
    }

    func test_queue_roundTripsThroughDefaults() throws {
        let suite = "InboxRulesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = UUID(), b = UUID()
        var queue = InboxDeletionQueue()
        queue.add(a)
        queue.add(b)

        queue.save(to: defaults)

        XCTAssertEqual(InboxDeletionQueue.load(from: defaults), queue)
    }

    func test_queue_loadOfGarbageIsEmpty() throws {
        let suite = "InboxRulesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["nope"], forKey: InboxDeletionQueue.defaultsKey)

        XCTAssertTrue(InboxDeletionQueue.load(from: defaults).isEmpty)
    }
}
