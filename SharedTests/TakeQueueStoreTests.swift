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

    func test_sweep_deletesOnlyExpiredTranscribedAudio() throws {
        var state = TakeQueueState()
        let waiting = take(), clouded = take(1), confirmed = take(2), expired = take(3)
        let unlisted = UUID()
        [waiting, clouded, confirmed, expired].forEach { state.add($0, phoneReachableAtStop: true) }
        state.markInICloud(clouded.id)
        state.apply([WatchConfirmation(id: confirmed.id, title: nil), WatchConfirmation(id: expired.id, title: nil)])
        var words = WristThought(id: expired.id, title: nil, createdAt: expired.createdAt)
        words.hasTranscript = true
        state.apply(WristSnapshot(recent: [words], today: nil, todayDay: nil, deletedIDs: [], generatedAt: expired.createdAt))
        for id in [waiting.id, clouded.id, confirmed.id, expired.id, unlisted] { try writeAudio(id) }

        store.sweep(state, now: expired.createdAt.addingTimeInterval(TakeQueueState.audioRetention + 60))

        XCTAssertTrue(audioExists(waiting.id))
        XCTAssertTrue(audioExists(clouded.id), "kept for replay")
        XCTAssertTrue(audioExists(confirmed.id), "no transcript: kept")
        XCTAssertFalse(audioExists(expired.id))
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

    func test_unreadableIndex_isSetAsideNotOverwritten() throws {
        try Data("corrupt".utf8).write(to: store.indexURL)
        XCTAssertEqual(store.load(), TakeQueueState())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.indexURL.path))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let aside = try XCTUnwrap(names.first { $0.hasPrefix("queue.unreadable-") })
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(aside)), Data("corrupt".utf8))
    }

    func test_unlistedTakes_returnsPlayableRecordingsTheIndexMisses() throws {
        var state = TakeQueueState()
        let listed = take()
        state.add(listed, phoneReachableAtStop: true)
        let playable = UUID(), unplayable = UUID()
        for id in [listed.id, playable, unplayable] { try writeAudio(id) }

        let recovered = store.unlistedTakes(in: state) { url in
            url.lastPathComponent.hasPrefix(playable.uuidString) ? 5 : nil
        }

        XCTAssertEqual(recovered.map(\.id), [playable])
        XCTAssertEqual(recovered.first?.duration, 5)
    }

    func test_unlistedTakes_timesTheTakeFromTheFile() throws {
        let id = UUID()
        try writeAudio(id)
        let when = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try FileManager.default.setAttributes([.creationDate: when], ofItemAtPath: store.audioURL(for: id).path)

        let recovered = store.unlistedTakes(in: TakeQueueState()) { _ in 3 }

        let createdAt = try XCTUnwrap(recovered.first?.createdAt)
        XCTAssertEqual(createdAt.timeIntervalSinceReferenceDate, when.timeIntervalSinceReferenceDate, accuracy: 1)
    }

    func test_unreadableIndex_recordingsComeBack() throws {
        var state = TakeQueueState()
        let waiting = take()
        state.add(waiting, phoneReachableAtStop: true)
        store.save(state)
        try writeAudio(waiting.id)
        try Data("corrupt".utf8).write(to: store.indexURL)

        let loaded = store.load()
        let recovered = store.unlistedTakes(in: loaded) { _ in 2 }

        XCTAssertEqual(recovered.map(\.id), [waiting.id])
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
