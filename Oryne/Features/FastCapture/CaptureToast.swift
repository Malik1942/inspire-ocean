import SwiftUI

/// The one thing a capture says back: the thought is in, and the way back is
/// right there. `OceanToast`, centered above the capture bar, held for the
/// whole undo window. Nothing else rides with it: no interpreted title, no
/// nearby hint (Malik, 2026-10-18).
///
/// Its mark is the ring (design/identity-2.1.md, R3): it arrives in the warm
/// ink of the voice that made it and cools to the ring's own color as the
/// thought settles into the water. Calm and Reduce Motion: it arrives cool.
struct CaptureToast: View {
    var onUndo: () -> Void

    @Environment(\.calmAccessibility) private var calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    var body: some View {
        OceanToast(
            message: String(localized: "Carried into the sea"),
            actionTitle: "Undo",
            actionAccessibilityLabel: "Undo capture",
            ring: settled || calm || reduceMotion ? OceanTheme.ring : OceanTheme.warm,
            action: onUndo
        )
        .onAppear {
            withAnimation(OceanMotion.lift.delay(0.12)) { settled = true } // art-directed: after the toast lands
        }
    }
}
