import Foundation
import CloudKit
import os

/// Failures only, and never user content: a take ID at most.
private let log = Logger(subsystem: "com.inspireocean.app.watchkitapp", category: "sync")

/// Uploads takes to the iCloud inbox when the phone is out of reach. Upload
/// only: the watch never fetches the Ocean or any other record.
final class CloudInbox {
    private let database: CKDatabase
    private static let zoneReadyKey = "watch.inboxZoneReady"

    /// Nil in an unsigned build: CloudKit traps without the iCloud
    /// entitlement, and the App Group container is the signed-build proof.
    static func makeIfAvailable() -> CloudInbox? {
        guard WatchInboxSchema.isSignedBuild else { return nil }
        return CloudInbox(database: CKContainer(identifier: WatchInboxSchema.containerID).privateCloudDatabase)
    }

    private init(database: CKDatabase) {
        self.database = database
    }

    /// True once the record is saved in iCloud. A second upload of the same
    /// take overwrites the first.
    func upload(_ take: WatchTake, audioURL: URL) async -> Bool {
        do {
            try await ensureZone()
            let record = WatchInboxSchema.record(for: take, audioURL: audioURL)
            let (results, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            switch results[record.recordID] {
            case .success:
                return true
            case .failure(let error as CKError) where error.code == .zoneNotFound || error.code == .userDeletedZone:
                log.error("Upload of take \(take.id.uuidString, privacy: .public) failed: the inbox zone is gone (CKError \(error.code.rawValue, privacy: .public))")
                UserDefaults.standard.set(false, forKey: Self.zoneReadyKey)
                return false
            case .failure(let error):
                log.error("Upload of take \(take.id.uuidString, privacy: .public) failed: \(Self.describe(error), privacy: .public)")
                return false
            case nil:
                log.error("Upload of take \(take.id.uuidString, privacy: .public) returned no result")
                return false
            }
        } catch {
            log.error("Upload of take \(take.id.uuidString, privacy: .public) failed: \(Self.describe(error), privacy: .public)")
            return false
        }
    }

    /// The CKError code, or an error's domain and code: never a description,
    /// which can carry a file path.
    private static func describe(_ error: Error) -> String {
        if let error = error as? CKError { return "CKError \(error.code.rawValue)" }
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }

    private func ensureZone() async throws {
        guard !UserDefaults.standard.bool(forKey: Self.zoneReadyKey) else { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: WatchInboxSchema.zoneID)], deleting: [])
        UserDefaults.standard.set(true, forKey: Self.zoneReadyKey)
    }
}
