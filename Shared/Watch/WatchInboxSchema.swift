import Foundation
import CloudKit

/// The iCloud inbox a wrist take falls back to when the phone is out of
/// reach: a dedicated zone in the user's private database, apart from the
/// zone the SwiftData mirror owns, so the two never touch.
///
/// The watch compiles only `Shared/Watch`, so the frozen identifiers are
/// restated here; `WatchInboxSchemaTests` holds them equal to `Persistence`.
enum WatchInboxSchema {
    static let containerID = "iCloud.com.inspireocean.app"
    static let appGroupID = "group.com.inspireocean.shared"
    static let zoneName = "WatchInbox"
    static let recordType = "WatchTake"
    static let subscriptionID = "watch-inbox"

    enum Field {
        static let createdAt = "createdAt"
        static let duration = "duration"
        static let version = "version"
        static let audio = "audio"
    }

    static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    static func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    /// Whether this process is a signed build carrying the App Group, which
    /// ships together with the iCloud entitlement. CloudKit traps (on a
    /// background queue, uncatchably) without the entitlement, so every
    /// CloudKit path checks this first: the same gate `Persistence` uses.
    static var isSignedBuild: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    static func record(for take: WatchTake, audioURL: URL) -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: recordID(for: take.id))
        record[Field.createdAt] = take.createdAt
        record[Field.duration] = take.duration
        record[Field.version] = Int64(take.version)
        record[Field.audio] = CKAsset(fileURL: audioURL)
        return record
    }

    static func take(from record: CKRecord) -> WatchTake? {
        guard record.recordType == recordType,
              let id = UUID(uuidString: record.recordID.recordName),
              let createdAt = record[Field.createdAt] as? Date,
              let duration = record[Field.duration] as? Double
        else { return nil }
        let version = (record[Field.version] as? Int64).map(Int.init) ?? WatchTake.currentVersion
        return WatchTake(id: id, createdAt: createdAt, duration: duration, version: version)
    }

    static func audioURL(in record: CKRecord) -> URL? {
        (record[Field.audio] as? CKAsset)?.fileURL
    }
}
