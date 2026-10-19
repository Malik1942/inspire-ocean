import Foundation
import CloudKit

/// Reads the iCloud inbox the watch falls back to: a zone subscription for
/// silent pushes, plus a zone-changes fetch at launch and on foreground
/// (pushes are not guaranteed). Each take's audio is copied into the inbox
/// folder for the importer; a record is deleted once the importer has
/// settled its take. Runs only on the paired iPhone, and only in a signed
/// build (CloudKit traps without the entitlement).
@MainActor
final class WatchInboxReader {
    private let database = CKContainer(identifier: WatchInboxSchema.containerID).privateCloudDatabase
    private let folder: WatchInboxFolder
    private let defaults: UserDefaults
    private var isFetching = false

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

    /// Creates the zone and the silent-push subscription, once.
    func prepare() async {
        guard !defaults.bool(forKey: Self.preparedKey) else { return }
        do {
            _ = try await database.modifyRecordZones(
                saving: [CKRecordZone(zoneID: WatchInboxSchema.zoneID)], deleting: []
            )
            let subscription = CKRecordZoneSubscription(
                zoneID: WatchInboxSchema.zoneID,
                subscriptionID: WatchInboxSchema.subscriptionID
            )
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
            defaults.set(true, forKey: Self.preparedKey)
        } catch {
            // Signed out or offline: try again on the next fetch.
        }
    }

    /// Copies every new take in the zone into the inbox folder. True when at
    /// least one arrived.
    func fetch() async -> Bool {
        guard !isFetching else { return false }
        isFetching = true
        defer { isFetching = false }
        await prepare()

        var token = loadToken()
        var arrived = false
        do {
            while true {
                let changes = try await database.recordZoneChanges(inZoneWith: WatchInboxSchema.zoneID, since: token)
                for (_, result) in changes.modificationResultsByID {
                    guard case .success(let modification) = result else { continue }
                    if accept(modification.record) { arrived = true }
                }
                token = changes.changeToken
                saveToken(token)
                if !changes.moreComing { break }
            }
        } catch let error as CKError where error.code == .changeTokenExpired {
            saveToken(nil)   // the next fetch starts over
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            defaults.set(false, forKey: Self.preparedKey)
        } catch {
            // Offline or signed out: the next launch, foreground, or push retries.
        }
        return arrived
    }

    /// Deletes a settled take's record. An unknown record is fine: that take
    /// came over WatchConnectivity and was never uploaded.
    func deleteRecord(_ id: UUID) async {
        _ = try? await database.modifyRecords(saving: [], deleting: [WatchInboxSchema.recordID(for: id)])
    }

    private func accept(_ record: CKRecord) -> Bool {
        guard let take = WatchInboxSchema.take(from: record),
              let audio = WatchInboxSchema.audioURL(in: record)
        else { return false }
        return (try? folder.accept(take, copyingAudioFrom: audio)) != nil
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
