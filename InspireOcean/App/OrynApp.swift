import SwiftUI
import SwiftData

@main
struct OrynApp: App {
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
                }
        }
        .modelContainer(container)
    }
}
