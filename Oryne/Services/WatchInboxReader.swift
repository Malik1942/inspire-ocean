import Foundation
import CloudKit
import os

/// Failures only, and never user content: a take ID at most.
private let log = Logger(subsystem: "com.inspireocean.app", category: "watch")

/// Reads the iCloud inbox the watch falls back to: a zone subscription for
/// silent pushes, plus a zone-changes fetch at launch and on foreground
/// (pushes are not guaranteed). Each take's audio is copied into the inbox
/// folder for the importer; a record is deleted (from a persisted queue, so
/// a failed delete is retried) once the importer has settled its take. Runs
/// only on the paired iPhone, and only in a signed build (CloudKit traps
/// without the entitlement).
@MainActor
final class WatchInboxReader {
    private let database = CKContainer(identifier: WatchInboxSchema.containerID).privateCloudDatabase
    private let folder: WatchInboxFolder
    private let defaults: UserDefaults
    private var isFetching = false
    private var fetchAgain = false
    private var isFlushing = false
    private var flushAgain = false

    /// CloudKit refuses more than 400 items in one modify; stay well under.
    private static let deletionChunkSize = 200

    private static let tokenKey = "watch.inboxChangeToken"
    private static let preparedKey = "watch.inboxPrepared"

    init(folder: WatchInboxFolder, defaults: UserDefaults) {
        self.folder = folder
        self.defaults = defaults
    }

    /// Whether a remote notification is this inbox's subscription firing.
    nonisolated static func isInboxPush(_ userInfo: [AnyHashable: Any]) -> Bool {
        CKNotification(fromRemoteNotificationDictionary: userInfo)?.subscriptionID == WatchInboxSchema.subscriptionID
    }

    /// Creates the zone and the silent-push subscription, once. The prepared
    /// flag is set only when CloudKit reports both saved: a call can return
    /// without throwing yet fail per item.
    func prepare() async {
        guard !defaults.bool(forKey: Self.preparedKey) else { return }
        do {
            let zone = CKRecordZone(zoneID: WatchInboxSchema.zoneID)
            let zoneResults = try await database.modifyRecordZones(saving: [zone], deleting: []).saveResults
            guard case .success = zoneResults[zone.zoneID] else {
                log.error("prepare: the inbox zone wasn't saved: \(Self.describe(result: zoneResults[zone.zoneID]), privacy: .public)")
                return
            }

            let subscription = CKRecordZoneSubscription(
                zoneID: WatchInboxSchema.zoneID,
                subscriptionID: WatchInboxSchema.subscriptionID
            )
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            let subscriptionResults = try await database
                .modifySubscriptions(saving: [subscription], deleting: [])
                .saveResults
            guard case .success = subscriptionResults[subscription.subscriptionID] else {
                log.error("prepare: the inbox subscription wasn't saved: \(Self.describe(result: subscriptionResults[subscription.subscriptionID]), privacy: .public)")
                return
            }

            defaults.set(true, forKey: Self.preparedKey)
        } catch {
            // Signed out or offline: try again on the next fetch.
            log.error("prepare failed: \(Self.describe(error), privacy: .public)")
        }
    }

    /// Copies every new take in the zone into the inbox folder. True when at
    /// least one arrived. Single flight: a push that lands mid-fetch gets one
    /// more pass.
    func fetch() async -> Bool {
        if isFetching {
            fetchAgain = true
            return false
        }
        isFetching = true
        defer { isFetching = false }

        var arrived = false
        repeat {
            fetchAgain = false
            await prepare()
            await flushPendingDeletions()
            if await fetchChanges() { arrived = true }
        } while fetchAgain
        return arrived
    }

    /// Deletes the iCloud records of takes that have settled on the phone.
    /// The queue is persisted, so a delete that fails offline is tried again
    /// on the next fetch. A record that is already gone is done: that take
    /// came over WatchConnectivity and was never uploaded. Single flight: a
    /// take that settles mid-flush (a batch import settles many) gets one
    /// more pass instead of a request of its own.
    func flushPendingDeletions() async {
        if isFlushing {
            flushAgain = true
            return
        }
        isFlushing = true
        defer { isFlushing = false }

        repeat {
            flushAgain = false
            await flushOnce()
        } while flushAgain
    }

    private func flushOnce() async {
        let ids = InboxDeletionQueue.load(from: defaults).ids
        for start in stride(from: 0, to: ids.count, by: Self.deletionChunkSize) {
            let chunk = Array(ids[start..<min(start + Self.deletionChunkSize, ids.count)])
            let results: [CKRecord.ID: Result<Void, Error>]
            do {
                // Not atomic: one record already gone must not fail the others.
                results = try await database.modifyRecords(
                    saving: [], deleting: chunk.map(WatchInboxSchema.recordID(for:)), atomically: false
                ).deleteResults
            } catch {
                // Offline or signed out: the queue keeps them for the next trigger.
                log.error("Deletion flush failed (\(chunk.count, privacy: .public) records): \(Self.describe(error), privacy: .public)")
                return
            }

            // Takes may have settled while the request was out: start from the
            // stored queue, not the one loaded above.
            var remaining = InboxDeletionQueue.load(from: defaults)
            for id in chunk {
                switch results[WatchInboxSchema.recordID(for: id)] {
                case .success:
                    remaining.remove(id)
                case .failure(let error):
                    if (error as? CKError)?.code == .unknownItem {
                        remaining.remove(id)
                    } else {
                        log.error("Couldn't delete the inbox record of take \(id.uuidString, privacy: .public): \(Self.describe(error), privacy: .public)")
                    }
                case nil:
                    break
                }
            }
            remaining.save(to: defaults)
        }
    }

    /// Reads the zone's changes since the saved token. True when at least
    /// one take arrived.
    private func fetchChanges() async -> Bool {
        var token = loadToken()
        var arrived = false
        // The saved token only moves while every record so far was handled: a
        // take that failed to copy is read again next time, never skipped.
        var clean = true
        var startedOver = false

        while true {
            do {
                let changes = try await database.recordZoneChanges(inZoneWith: WatchInboxSchema.zoneID, since: token)
                var outcomes: [InboxRecordOutcome] = []
                for (recordID, result) in changes.modificationResultsByID {
                    switch result {
                    case .success(let modification):
                        let outcome = accept(modification.record)
                        if outcome == .accepted { arrived = true }
                        outcomes.append(outcome)
                    case .failure(let error):
                        log.error("Inbox record \(recordID.recordName, privacy: .public) couldn't be read: \(Self.describe(error), privacy: .public)")
                        outcomes.append(.failedForNow)
                    }
                }
                clean = clean && InboxTokenPolicy.maySaveToken(after: outcomes)
                token = changes.changeToken
                if clean { saveToken(token) }
                if !changes.moreComing { return arrived }
            } catch let error as CKError where error.code == .changeTokenExpired {
                saveToken(nil)
                guard !startedOver else { return arrived }
                startedOver = true   // read the whole zone again, once
                token = nil
                clean = true
            } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
                saveToken(nil)
                defaults.set(false, forKey: Self.preparedKey)
                return arrived
            } catch {
                // Offline or signed out: the next launch, foreground, or push retries.
                log.error("Inbox fetch failed: \(Self.describe(error), privacy: .public)")
                return arrived
            }
        }
    }

    private func accept(_ record: CKRecord) -> InboxRecordOutcome {
        guard let take = WatchInboxSchema.take(from: record) else { return .invalid }
        // The watch always writes an audio asset: a record without one is
        // malformed, and must not hold the token forever.
        guard record[WatchInboxSchema.Field.audio] is CKAsset else { return .invalid }
        // No file yet: the asset has not finished downloading.
        guard let audio = WatchInboxSchema.audioURL(in: record) else { return .failedForNow }
        do {
            try folder.accept(take, copyingAudioFrom: audio)
            return .accepted
        } catch {
            log.error("Couldn't copy take \(take.id.uuidString, privacy: .public) from the inbox: \(Self.describe(error), privacy: .public)")
            return .failedForNow
        }
    }

    /// An error's domain and code only: descriptions can carry file paths.
    private static func describe(_ error: Error) -> String {
        if let error = error as? CKError { return "CKError \(error.code.rawValue)" }
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }

    private static func describe<T>(result: Result<T, Error>?) -> String {
        switch result {
        case .failure(let error): return describe(error)
        case .success: return "success"
        case nil: return "no result"
        }
    }

    private func loadToken() -> CKServerChangeToken? {
        guard let data = defaults.data(forKey: Self.tokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveToken(_ token: CKServerChangeToken?) {
        guard let token,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        else {
            defaults.removeObject(forKey: Self.tokenKey)
            return
        }
        defaults.set(data, forKey: Self.tokenKey)
    }
}
