import SwiftUI

/// One-time ambient guidance: a whisper that appears the first time a
/// behavior occurs, then never again. No onboarding screens, no carousels —
/// a caption that breathes in where the behavior happened and fades out.
enum TrustHint: String {
    /// First time the edit sheet opens — the ownership promise.
    case ownership = "hint.ownership"
    /// First time themes are edited — why themes matter spatially.
    case semanticDrift = "hint.semanticDrift"

    var message: String {
        switch self {
        case .ownership:
            return "Edited fields stay yours. Oryne won't overwrite them."
        case .semanticDrift:
            return "Themes shape where thoughts drift in the Ocean."
        }
    }

    var shouldShow: Bool { !UserDefaults.standard.bool(forKey: rawValue) }
    func markShown() { UserDefaults.standard.set(true, forKey: rawValue) }
}

/// Renders a trust hint once, ambiently: fades in on first encounter, lingers
/// long enough to be read, fades away, and never appears again.
struct AmbientHint: View {
    let hint: TrustHint

    @State private var visible = false

    var body: some View {
        ZStack(alignment: .leading) {
            if visible {
                Text(hint.message)
                    .font(.caption2)
                    .foregroundStyle(OceanTheme.mist)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .transition(.opacity)
            }
        }
        .task {
            guard hint.shouldShow else { return }
            hint.markShown()
            withAnimation(.easeIn(duration: 0.5)) { visible = true }
            try? await Task.sleep(for: .seconds(6))
            withAnimation(.easeOut(duration: 1.0)) { visible = false }
        }
    }
}
