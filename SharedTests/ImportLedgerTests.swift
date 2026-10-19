import XCTest
import Foundation

/// The ledger is the phone's only "seen before" check, whichever path
/// delivered a take (spec §2, import exactly once).
final class ImportLedgerTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    func test_newTake_isUnseenUntilImported() {
        var ledger = ImportLedger()
        let id = UUID()
        XCTAssertFalse(ledger.hasSeen(id))
        ledger.markImported(id, at: t0)
        XCTAssertTrue(ledger.hasSeen(id))
    }

    func test_secondCopy_fromEitherPath_isSeenAndKeepsTheFirstImport() {
        // WatchConnectivity first or iCloud first: only the ID matters.
        var ledger = ImportLedger()
        let id = UUID()
        ledger.markImported(id, at: t0)
        ledger.markImported(id, at: t0.addingTimeInterval(60))
        XCTAssertTrue(ledger.hasSeen(id))
        XCTAssertEqual(ledger.entries[id]?.importedAt, t0)
        XCTAssertEqual(ledger.entries.count, 1)
    }

    func test_deletedThought_lateCopy_staysSeen() {
        // The ledger never asks the store, so deleting the thought leaves
        // its entry, and a late copy over the other path is still refused.
        var ledger = ImportLedger()
        let id = UUID()
        ledger.markImported(id, at: t0)
        ledger.markUnderstood(id, title: "Lighthouse café")
        ledger.prune(now: t0.addingTimeInterval(89 * day))
        XCTAssertTrue(ledger.hasSeen(id))
    }

    func test_awaitingUnderstanding_isOldestFirstAndExcludesUnderstood() {
        var ledger = ImportLedger()
        let a = UUID(), b = UUID(), c = UUID()
        ledger.markImported(b, at: t0.addingTimeInterval(10))
        ledger.markImported(a, at: t0)
        ledger.markImported(c, at: t0.addingTimeInterval(20))
        ledger.markUnderstood(c, title: nil)
        XCTAssertEqual(ledger.awaitingUnderstanding, [a, b])
    }

    func test_markUnderstood_unknownID_isIgnored() {
        var ledger = ImportLedger()
        ledger.markUnderstood(UUID(), title: "Stray")
        XCTAssertTrue(ledger.entries.isEmpty)
    }

    func test_recentConfirmations_newestFirstCappedWithTitles() {
        var ledger = ImportLedger()
        let limit = ImportLedger.confirmationLimit
        let ids = (0..<(limit + 5)).map { _ in UUID() }
        for (i, id) in ids.enumerated() {
            ledger.markImported(id, at: t0.addingTimeInterval(Double(i)))
        }
        ledger.markUnderstood(ids[limit + 4], title: "Newest")

        let recent = ledger.recentConfirmations()

        XCTAssertEqual(limit, 200)
        XCTAssertEqual(recent.count, limit)
        XCTAssertEqual(recent.first, WatchConfirmation(id: ids[limit + 4], title: "Newest"))
        XCTAssertEqual(recent.last?.id, ids[5])
        XCTAssertNil(recent[1].title)
    }

    func test_prune_dropsOldSettledKeepsOldPendingAndRecent() {
        var ledger = ImportLedger()
        let old = UUID(), oldPending = UUID(), recent = UUID()
        ledger.markImported(old, at: t0)
        ledger.markUnderstood(old, title: nil)
        ledger.markImported(oldPending, at: t0)
        ledger.markImported(recent, at: t0.addingTimeInterval(80 * day))
        ledger.markUnderstood(recent, title: nil)

        ledger.prune(now: t0.addingTimeInterval(91 * day))

        XCTAssertFalse(ledger.hasSeen(old))
        XCTAssertTrue(ledger.hasSeen(oldPending), "a take still awaiting understanding is never forgotten")
        XCTAssertTrue(ledger.hasSeen(recent))
    }

    func test_saveThenLoad_roundTrips() throws {
        let suite = "ImportLedgerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var ledger = ImportLedger()
        let id = UUID()
        ledger.markImported(id, at: t0)
        ledger.markUnderstood(id, title: "Lighthouse café")

        ledger.save(to: defaults)

        XCTAssertEqual(ImportLedger.load(from: defaults), ledger)
    }

    func test_load_withNothingOrGarbage_isEmpty() throws {
        let suite = "ImportLedgerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ImportLedger.load(from: defaults), ImportLedger())
        defaults.set(Data("nope".utf8), forKey: ImportLedger.defaultsKey)
        XCTAssertEqual(ImportLedger.load(from: defaults), ImportLedger())
    }
}
