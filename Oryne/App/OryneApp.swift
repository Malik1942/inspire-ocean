import SwiftUI
import SwiftData

@main
struct OryneApp: App {
    let container = Persistence.shared

    /// The cloud seam (§14) activates itself when an `ANTHROPIC_API_KEY` is
    /// present in the environment (or `AnthropicAPIKey` in Info.plist via a
    /// local xcconfig — never commit a key). Without one, this behaves exactly
    /// like the on-device V1: retrieval, themes, and transcription never leave
    /// the device either way.
    private let ai: any OceanAIService = CloudOceanAIService(configuration: .fromEnvironment())

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.oceanAI, ai)
                .tint(OceanTheme.accent)
                .preferredColorScheme(.dark)
                .task {
                    SeedData.seedIfNeeded(container.mainContext)
                    Self.migrateLegacyAudio(context: container.mainContext)
                }
        }
        .modelContainer(container)
    }

    /// One-time: fold pre-CloudKit voice recordings — loose `.m4a` files named
    /// by the legacy `audioFileName` — into `audioData` so they sync like images
    /// do. Runs at launch before CloudKit cements the legacy nodes in their
    /// file-dangling form. Idempotent: a migrated node clears `audioFileName`, so
    /// it no longer matches the fetch on the next launch.
    @MainActor
    static func migrateLegacyAudio(context: ModelContext) {
        let descriptor = FetchDescriptor<Node>(
            predicate: #Predicate { $0.audioFileName != nil }
        )
        guard let nodes = try? context.fetch(descriptor), !nodes.isEmpty else { return }

        for node in nodes {
            guard let name = node.audioFileName else { continue }
            let url = AudioRecorder.url(for: name)
            if node.audioData == nil, let data = try? Data(contentsOf: url) {
                node.audioData = data
                try? FileManager.default.removeItem(at: url)
            }
            // Clear the legacy pointer even if the file was already gone, so the
            // node stops matching and the migration converges.
            node.audioFileName = nil
        }
        try? context.save()
    }
}
