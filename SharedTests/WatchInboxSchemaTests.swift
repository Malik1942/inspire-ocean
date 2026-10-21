import XCTest
import CloudKit

final class WatchInboxSchemaTests: XCTestCase {

    func test_frozenIdentifiers_matchPersistence() {
        XCTAssertEqual(WatchInboxSchema.containerID, Persistence.cloudKitContainerID)
        XCTAssertEqual(WatchInboxSchema.appGroupID, Persistence.appGroupID)
    }

    func test_inboxZone_isNotTheSwiftDataMirrorZone() {
        XCTAssertNotEqual(WatchInboxSchema.zoneName, "com.apple.coredata.cloudkit.zone")
    }

    func test_recordRoundTrip_keepsTakeAndAudio() throws {
        let audio = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data([1, 2, 3]).write(to: audio)
        defer { try? FileManager.default.removeItem(at: audio) }
        let take = WatchTake(id: UUID(), createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000), duration: 4.25)

        let record = WatchInboxSchema.record(for: take, audioURL: audio)

        XCTAssertEqual(record.recordType, WatchInboxSchema.recordType)
        XCTAssertEqual(record.recordID.recordName, take.id.uuidString)
        XCTAssertEqual(record.recordID.zoneID.zoneName, WatchInboxSchema.zoneName)
        XCTAssertEqual(WatchInboxSchema.take(from: record), take)
        XCTAssertEqual(WatchInboxSchema.audioURL(in: record), audio)
    }

    func test_takeFromForeignRecordType_isNil() {
        let record = CKRecord(recordType: "Something", recordID: WatchInboxSchema.recordID(for: UUID()))
        record[WatchInboxSchema.Field.createdAt] = Date()
        record[WatchInboxSchema.Field.duration] = 1.0
        XCTAssertNil(WatchInboxSchema.take(from: record))
    }

    func test_takeFromRecordWithBadName_isNil() {
        let id = CKRecord.ID(recordName: "not-a-uuid", zoneID: WatchInboxSchema.zoneID)
        let record = CKRecord(recordType: WatchInboxSchema.recordType, recordID: id)
        record[WatchInboxSchema.Field.createdAt] = Date()
        record[WatchInboxSchema.Field.duration] = 1.0
        XCTAssertNil(WatchInboxSchema.take(from: record))
    }

    // MARK: - Which records the phone may copy

    private func takeRecord(audio: URL?) -> (WatchTake, CKRecord) {
        let take = WatchTake(id: UUID(), createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000), duration: 3)
        let record = CKRecord(recordType: WatchInboxSchema.recordType, recordID: WatchInboxSchema.recordID(for: take.id))
        record[WatchInboxSchema.Field.createdAt] = take.createdAt
        record[WatchInboxSchema.Field.duration] = take.duration
        record[WatchInboxSchema.Field.version] = Int64(take.version)
        if let audio { record[WatchInboxSchema.Field.audio] = CKAsset(fileURL: audio) }
        return (take, record)
    }

    func test_check_takeWithDownloadedAudio_isReady() {
        let audio = URL(fileURLWithPath: "/tmp/take.m4a")
        let (take, record) = takeRecord(audio: audio)

        XCTAssertEqual(WatchInboxSchema.check(record), .ready(take, audio: audio))
    }

    func test_check_foreignRecordType_isNotATake() {
        let record = CKRecord(recordType: "Something", recordID: WatchInboxSchema.recordID(for: UUID()))
        record[WatchInboxSchema.Field.createdAt] = Date()
        record[WatchInboxSchema.Field.duration] = 1.0
        record[WatchInboxSchema.Field.audio] = CKAsset(fileURL: URL(fileURLWithPath: "/tmp/take.m4a"))

        XCTAssertEqual(WatchInboxSchema.check(record), .invalid(.notATake))
    }

    func test_check_takeMissingItsFields_isNotATake() {
        let record = CKRecord(recordType: WatchInboxSchema.recordType, recordID: WatchInboxSchema.recordID(for: UUID()))
        record[WatchInboxSchema.Field.audio] = CKAsset(fileURL: URL(fileURLWithPath: "/tmp/take.m4a"))

        XCTAssertEqual(WatchInboxSchema.check(record), .invalid(.notATake))
    }

    /// The watch always writes an audio asset: a take without one would
    /// otherwise hold the change token forever.
    func test_check_takeWithoutAnAudioAsset_isInvalid() {
        let (_, record) = takeRecord(audio: nil)

        XCTAssertEqual(WatchInboxSchema.check(record), .invalid(.noAudio))
    }

    func test_check_audioNotYetDownloaded_isReadAgainLater() {
        let take = WatchTake(id: UUID(), createdAt: Date(), duration: 1)

        XCTAssertEqual(InboxRecordCheck(take: take, hasAudio: true, downloadedAudio: nil), .notDownloaded)
    }

    func test_check_notATake_winsOverMissingAudio() {
        XCTAssertEqual(InboxRecordCheck(take: nil, hasAudio: false, downloadedAudio: nil), .invalid(.notATake))
    }
}
