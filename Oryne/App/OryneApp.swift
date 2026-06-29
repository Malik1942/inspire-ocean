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
                    Self.migrateLegacyImages(context: container.mainContext)
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

    /// One-time: fold the legacy single `imageData` into the `images`
    /// relationship (as the first image) so old nodes display under the
    /// multi-image model. Mirrors `migrateLegacyAudio`. Idempotent: a migrated
    /// node clears `imageData`, so it no longer matches on the next launch; and
    /// `Node.imageDatas` falls back to `imageData` for the window before this
    /// runs (or a legacy node arriving late over CloudKit), so no image blanks.
    ///
    /// `imageData` is `.externalStorage`, which can't be filtered in a predicate,
    /// so we fetch and filter in memory (as `expireConfirmedAudio` does for
    /// `audioData`). The store is small; this is cheap.
    @MainActor
    static func migrateLegacyImages(context: ModelContext) {
        guard let nodes = try? context.fetch(FetchDescriptor<Node>()) else { return }
        var migrated = false
        for node in nodes where node.imageData != nil {
            if node.images?.isEmpty ?? true {
                node.images = [NodeImage(data: node.imageData, sortIndex: 0)]
            }
            node.imageData = nil   // converge: stop matching on the next launch
            migrated = true
        }
        if migrated { try? context.save() }
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
