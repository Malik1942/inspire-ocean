import XCTest
import Foundation

final class WristLibraryTests: XCTestCase {

    private var directory: URL!
    private var store: WristSnapshotStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WristLibraryTests-\(UUID().uuidString)", isDirectory: true)
        store = WristSnapshotStore(url: directory.appendingPathComponent("snapshot.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func snapshot(builtAt seconds: TimeInterval, deleted: [UUID] = []) -> WristSnapshot {
        WristSnapshot(recent: [], today: nil, todayDay: nil, deletedIDs: deleted,
                      generatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds))
    }

    func test_store_loadsNothingBeforeTheFirstSave() {
        XCTAssertNil(store.load())
    }

    func test_store_roundTrips() {
        let snap = snapshot(builtAt: 0, deleted: [UUID()])
        store.save(snap)
        XCTAssertEqual(store.load(), snap)
    }

    func test_store_unreadableFileLoadsNothing() throws {
        try Data("nope".utf8).write(to: store.url)
        XCTAssertNil(store.load())
    }

    @MainActor
    func test_library_keepsTheNewerSnapshot_acrossLaunches() {
        let library = WristLibrary(store: store)
        XCTAssertTrue(library.receive(snapshot(builtAt: 10)))
        XCTAssertEqual(WristLibrary(store: store).snapshot, snapshot(builtAt: 10))
    }

    @MainActor
    func test_library_ignoresAnOlderSnapshot() {
        let library = WristLibrary(store: store)
        library.receive(snapshot(builtAt: 10))
        XCTAssertFalse(library.receive(snapshot(builtAt: 5, deleted: [UUID()])))
        XCTAssertEqual(library.snapshot, snapshot(builtAt: 10))
        XCTAssertEqual(store.load(), snapshot(builtAt: 10))
    }
}
