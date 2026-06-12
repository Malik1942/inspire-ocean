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
                    Self.expireConfirmedAudio(context: container.mainContext)
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

    /// Audio is a temporary substrate for understanding, not a long-term
    /// asset: once a thought has a transcript, the original recording quietly
    /// expires after a retention window — Oryne keeps thoughts, not files.
    /// Thoughts with no transcript keep their audio; it's the only source of
    /// the words that's left.
    @MainActor
    static func expireConfirmedAudio(context: ModelContext, retentionDays: Int = 30) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now) ?? .now
        let descriptor = FetchDescriptor<Node>(
            predicate: #Predicate { $0.transcription != nil && $0.createdAt < cutoff }
        )
        guard let nodes = try? context.fetch(descriptor) else { return }

        var expired = false
        for node in nodes where node.audioData != nil && !(node.transcription ?? "").isEmpty {
            node.audioData = nil
            expired = true
        }
        if expired { try? context.save() }
    }
}
