#if DEBUG
import CoreData
import Foundation
import SwiftData

/// Debug only: writes every record type and field the SwiftData models mirror
/// into the CloudKit Development schema, so it can be deployed to Production
/// whole. CloudKit adds a Development field only when a build saves a value
/// for it, so a schema grown by use misses the fields nobody has filled yet,
/// and Production refuses any field it lacks.
///
/// Run once from a Debug build on a device signed in to iCloud, with
/// `OCEAN_INIT_CLOUDKIT_SCHEMA=1`. It runs before the app opens its store,
/// works on a throwaway store, never the user's Ocean, and exits when done.
enum CloudKitSchema {
    static func initializeAndExit() -> Never {
        do {
            try initialize()
            report("done")
            exit(0)
        } catch {
            report("failed: \(error)")
            exit(1)
        }
    }

    private static func initialize() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudKitSchema.store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: Persistence.cloudKitContainerID
        )
        description.shouldAddStoreAsynchronously = false

        guard let model = NSManagedObjectModel.makeManagedObjectModel(
            for: [Node.self, NodeImage.self, Conversation.self, ChatMessage.self, Current.self]
        ) else {
            throw CocoaError(.coreData)
        }
        let container = NSPersistentCloudKitContainer(name: "CloudKitSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        try container.initializeCloudKitSchema()

        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    private static func report(_ outcome: String) {
        print("OCEAN_INIT_CLOUDKIT_SCHEMA: \(outcome)")
        fflush(stdout)
    }
}
#endif
