import SwiftUI

@main
struct OryneWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

/// Phase 0 placeholder. Its only job is to prove the watch target links the
/// shared Oryne design tokens (`OceanTheme`, moved into `Shared/DesignSystem`)
/// — full-bleed Ocean black with foam/accent foreground, no watchOS defaults.
/// Replaced by `WatchCaptureView` in Phase 1.
private struct WatchRootView: View {
    var body: some View {
        ZStack {
            OceanTheme.abyss.ignoresSafeArea()
            VStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(OceanTheme.accent)
                Text("Oryne")
                    .font(.headline)
                    .foregroundStyle(OceanTheme.foam)
            }
        }
    }
}
