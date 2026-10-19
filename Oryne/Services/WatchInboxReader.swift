import Foundation
import CloudKit

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
            guard case .success = zoneResults[zone.zoneID] else { return }

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
            guard case .success = subscriptionResults[subscription.subscriptionID] else { return }

            defaults.set(true, forKey: Self.preparedKey)
        } catch {
            // Signed out or offline: try again on the next fetch.
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
    /// came over WatchConnectivity and was never uploaded.
    func flushPendingDeletions() async {
        let queue = InboxDeletionQueue.load(from: defaults)
        guard !queue.isEmpty else { return }
        let ids = queue.ids
        let results: [CKRecord.ID: Result<Void, Error>]
        do {
            // Not atomic: one record already gone must not fail the others.
            results = try await database.modifyRecords(
                saving: [], deleting: ids.map(WatchInboxSchema.recordID(for:)), atomically: false
            ).deleteResults
        } catch {
            return   // offline or signed out: the queue keeps them
        }

        // Takes may have settled while the request was out: start from the
        // stored queue, not the one loaded above.
        var remaining = InboxDeletionQueue.load(from: defaults)
        for id in ids {
            switch results[WatchInboxSchema.recordID(for: id)] {
            case .success:
                remaining.remove(id)
            case .failure(let error):
                if (error as? CKError)?.code == .unknownItem { remaining.remove(id) }
            case nil:
                break
            }
        }
        remaining.save(to: defaults)
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
                for (_, result) in changes.modificationResultsByID {
                    switch result {
                    case .success(let modification):
                        let outcome = accept(modification.record)
                        if outcome == .accepted { arrived = true }
                        outcomes.append(outcome)
                    case .failure:
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
                return arrived
            }
        }
    }

    private func accept(_ record: CKRecord) -> InboxRecordOutcome {
        guard let take = WatchInboxSchema.take(from: record) else { return .invalid }
        // No file yet: the asset has not finished downloading.
        guard let audio = WatchInboxSchema.audioURL(in: record) else { return .failedForNow }
        do {
            try folder.accept(take, copyingAudioFrom: audio)
            return .accepted
        } catch {
            return .failedForNow
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
