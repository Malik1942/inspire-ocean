import XCTest
import Foundation

final class TakeQueueStoreTests: XCTestCase {

    private var directory: URL!
    private var store: TakeQueueStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TakeQueueStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = TakeQueueStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func take(_ offset: TimeInterval = 0) -> WatchTake {
        WatchTake(id: UUID(), createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000 + offset), duration: 2)
    }

    private func writeAudio(_ id: UUID) throws {
        try Data([1]).write(to: store.audioURL(for: id))
    }

    private func audioExists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: store.audioURL(for: id).path)
    }

    func test_loadFromAnEmptyFolder_isEmpty() {
        XCTAssertEqual(store.load(), TakeQueueState())
    }

    func test_saveThenLoad_roundTrips() {
        var state = TakeQueueState()
        state.add(take(), phoneReachableAtStop: false)
        store.save(state)
        XCTAssertEqual(store.load(), state)
    }

    func test_garbageIndex_loadsEmpty() throws {
        try Data("nope".utf8).write(to: store.indexURL)
        XCTAssertEqual(store.load(), TakeQueueState())
    }

    func test_sweep_deletesOnlyAudioSafeElsewhere() throws {
        var state = TakeQueueState()
        let waiting = take(), clouded = take(1), confirmed = take(2)
        let unlisted = UUID()
        [waiting, clouded, confirmed].forEach { state.add($0, phoneReachableAtStop: true) }
        state.markInICloud(clouded.id)
        state.apply([WatchConfirmation(id: confirmed.id, title: nil)])
        for id in [waiting.id, clouded.id, confirmed.id, unlisted] { try writeAudio(id) }

        store.sweep(state)

        XCTAssertTrue(audioExists(waiting.id))
        XCTAssertFalse(audioExists(clouded.id))
        XCTAssertFalse(audioExists(confirmed.id))
        XCTAssertTrue(audioExists(unlisted), "a recording the index doesn't list is never guessed away")
    }

    func test_unreadableIndex_neverCostsAWaitingTake() throws {
        let waiting = take()
        var state = TakeQueueState()
        state.add(waiting, phoneReachableAtStop: true)
        store.save(state)
        try writeAudio(waiting.id)
        try Data("corrupt".utf8).write(to: store.indexURL)

        store.sweep(store.load())

        XCTAssertTrue(audioExists(waiting.id))
    }

    func test_deleteAudio_removesTheFile() throws {
        let id = UUID()
        try writeAudio(id)
        store.deleteAudio(id)
        XCTAssertFalse(audioExists(id))
    }

    func test_sweep_neverTouchesTheIndex() {
        let state = TakeQueueState()
        store.save(state)
        store.sweep(state)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.indexURL.path))
    }
}
