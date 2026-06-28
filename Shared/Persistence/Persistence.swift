import Foundation
import SwiftData

/// Local-first SwiftData stack (iOS Build Requirements §14).
///
/// When an App Group is available (share extension / app intents) the store is
/// placed in the shared container so captures from extensions land in the same
/// Ocean. Otherwise it falls back to the app's default store.
enum Persistence {
    // Frozen pre-rebrand (Inspire Ocean) identifiers: renaming the App Group,
    // store file, or CloudKit container would orphan every existing user's data.
    // The App Group lives in `AppGroup` so the watch (which doesn't compile this
    // file) shares one definition rather than a copied literal.
    static let appGroupID = AppGroup.identifier
    static let cloudKitContainerID = "iCloud.com.inspireocean.app"
    private static let storeName = "InspireOcean.store"

    static let schema = Schema([
        Node.self,
        Conversation.self,
        ChatMessage.self
    ])

    /// Process-wide container shared by the app and its App Intents, so a Siri
    /// capture lands in the same Ocean the app reads from.
    static let shared: ModelContainer = makeContainer()

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        if inMemory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [config])
        }

        // The shared App Group container is available only in a properly signed
        // build (a Development Team set in Xcode). Its presence is also our gate
        // for CloudKit: both entitlements ship together, and CloudKit can't be
        // attempted without the iCloud entitlement. Crucially, attempting it
        // anyway does NOT fail gracefully — NSPersistentCloudKitContainer traps
        // on a background queue *after* the ModelContainer has initialized, so a
        // `try?` around the init can't catch it (it crashed the unsigned sim).
        let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        // The store lives in the App Group container (so share-extension and
        // App-Intent captures land in the same Ocean), else app-local storage.
        let url = (groupURL ?? URL.applicationSupportDirectory)
            .appendingPathComponent(storeName)

        // Signed build → mirror the same store file to the user's private
        // CloudKit database. iCloud scopes it to the Apple ID already signed in
        // on the device — no in-app sign-in. Existing local data uploads on
        // first launch; with no iCloud account, CloudKit degrades to local
        // without crashing (the entitlement is valid, only the account is absent).
        //
        // Gate on BOTH the App Group (proves a signed build) AND the host
        // carrying the iCloud entitlement. The widget shares the App Group but
        // deliberately has no iCloud entitlement — it reads the mirror the app
        // keeps synced, since running CloudKit in a widget is needless and risks
        // its tight memory/time budget. Letting it reach the CloudKit setup
        // would trap on a background queue, uncatchable by `try?`.
        if groupURL != nil, hostCarriesICloudEntitlement {
            let cloudConfig = ModelConfiguration(
                schema: schema,
                url: url,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
            if let container = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
                return container
            }
        }

        // Fallback 1: local-only — unsigned simulator/CLI build (no entitlement),
        // or the CloudKit store failed to open. Identical to pre-CloudKit behavior.
        let localConfig = ModelConfiguration(schema: schema, url: url)
        if let container = try? ModelContainer(for: schema, configurations: [localConfig]) {
            return container
        }

        // Fallback 2: a corrupt store should never hard-crash capture.
        assertionFailure("ModelContainer failed twice; falling back to in-memory store.")
        let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [fallback])
    }

    /// Whether the running process is one that ships the iCloud entitlement and
    /// may therefore open a CloudKit-backed store. Only the app and the share
    /// extension do; the widget extension shares the App Group but not iCloud.
    /// Bundle ids are frozen pre-rebrand identifiers (see `appGroupID`).
    private static var hostCarriesICloudEntitlement: Bool {
        switch Bundle.main.bundleIdentifier {
        case "com.inspireocean.app", "com.inspireocean.app.share":
            return true
        default:
            return false
        }
    }
}
