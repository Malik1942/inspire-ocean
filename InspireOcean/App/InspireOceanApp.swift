import SwiftUI
import SwiftData

@main
struct InspireOceanApp: App {
    let container = Persistence.shared

    /// V1 runs on-device. To move Ocean to the cloud (§14), swap this for
    /// `CloudOceanAIService(configuration: …)` — nothing else changes.
    private let ai: any OceanAIService = LocalOceanAIService()

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
