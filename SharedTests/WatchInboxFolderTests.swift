import XCTest
import Foundation

final class WatchInboxFolderTests: XCTestCase {

    private var root: URL!
    private var folder: WatchInboxFolder!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchInboxFolderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        folder = WatchInboxFolder(directory: root.appendingPathComponent("WatchInbox", isDirectory: true))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func take(_ offset: TimeInterval = 0) -> WatchTake {
        WatchTake(id: UUID(), createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000 + offset), duration: 2)
    }

    private func sourceFile(_ bytes: [UInt8]) throws -> URL {
        let url = root.appendingPathComponent("source-\(UUID().uuidString).m4a")
        try Data(bytes).write(to: url)
        return url
    }

    func test_acceptMoving_takesTheFileAndListsTheTake() throws {
        let t = take()
        let source = try sourceFile([1, 2, 3])
        try folder.accept(t, movingAudioFrom: source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(folder.pending(), [t])
        XCTAssertEqual(try Data(contentsOf: folder.audioURL(for: t.id)), Data([1, 2, 3]))
    }

    func test_acceptCopying_leavesTheSource() throws {
        let t = take()
        let source = try sourceFile([4, 5])
        try folder.accept(t, copyingAudioFrom: source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(folder.pending(), [t])
    }

    func test_pending_needsBothFiles() throws {
        let audioOnly = take(), metadataOnly = take(1)
        try Data([1]).write(to: folder.audioURL(for: audioOnly.id))
        try XCTUnwrap(WatchWire.encode(metadataOnly)).write(to: folder.metadataURL(for: metadataOnly.id))
        XCTAssertEqual(folder.pending(), [])
    }

    func test_pending_isOldestFirst() throws {
        let older = take(0), newer = take(10)
        try folder.accept(newer, movingAudioFrom: try sourceFile([1]))
        try folder.accept(older, movingAudioFrom: try sourceFile([2]))
        XCTAssertEqual(folder.pending(), [older, newer])
    }

    func test_secondDelivery_replacesTheFirstCopy() throws {
        let t = take()
        try folder.accept(t, movingAudioFrom: try sourceFile([1]))
        try folder.accept(t, copyingAudioFrom: try sourceFile([9, 9]))
        XCTAssertEqual(folder.pending(), [t])
        XCTAssertEqual(try Data(contentsOf: folder.audioURL(for: t.id)), Data([9, 9]))
    }

    func test_failedSecondDelivery_keepsTheFirstCopy() throws {
        let t = take()
        try folder.accept(t, movingAudioFrom: try sourceFile([1]))
        let missing = root.appendingPathComponent("gone-\(UUID().uuidString).m4a")
        XCTAssertThrowsError(try folder.accept(t, copyingAudioFrom: missing))
        XCTAssertEqual(folder.pending(), [t])
        XCTAssertEqual(try Data(contentsOf: folder.audioURL(for: t.id)), Data([1]))
    }

    func test_failedFirstDelivery_listsNothing() throws {
        let missing = root.appendingPathComponent("gone-\(UUID().uuidString).m4a")
        XCTAssertThrowsError(try folder.accept(take(), movingAudioFrom: missing))
        XCTAssertEqual(folder.pending(), [])
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.directory.path)
        XCTAssertEqual(leftovers, [], "a failed delivery leaves nothing behind")
    }

    func test_remove_deletesBothFiles() throws {
        let t = take()
        try folder.accept(t, movingAudioFrom: try sourceFile([1]))
        folder.remove(t.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.audioURL(for: t.id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.metadataURL(for: t.id).path))
        XCTAssertEqual(folder.pending(), [])
    }

    func test_unreadableMetadata_isIgnored() throws {
        let id = UUID()
        try Data([1]).write(to: folder.audioURL(for: id))
        try Data("nope".utf8).write(to: folder.metadataURL(for: id))
        XCTAssertEqual(folder.pending(), [])
    }
}
