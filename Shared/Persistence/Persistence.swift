import Foundation
import SwiftData

/// Local-first SwiftData stack (iOS Build Requirements §14).
///
/// When an App Group is available (share extension / app intents) the store is
/// placed in the shared container so captures from extensions land in the same
/// Ocean. Otherwise it falls back to the app's default store.
enum Persistence {
    static let appGroupID = "group.com.inspireocean.shared"
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
        let configuration: ModelConfiguration

        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let url = groupURL.appendingPathComponent(storeName)
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: schema)
        }

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A corrupt local store should never hard-crash capture; rebuild it.
            assertionFailure("ModelContainer failed: \(error). Falling back to in-memory store.")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }
}
