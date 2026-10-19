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
}
