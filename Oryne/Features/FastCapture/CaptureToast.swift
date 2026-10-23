import SwiftUI

/// The one thing a capture says back: the thought is in, and the way back is
/// right there. `OceanToast`, centered above the capture bar, held for the
/// whole undo window. Nothing else rides with it: no interpreted title, no
/// nearby hint (Malik, 2026-10-18).
struct CaptureToast: View {
    var onUndo: () -> Void

    var body: some View {
        OceanToast(
            message: String(localized: "Carried into the sea"),
            actionTitle: "Undo",
            actionAccessibilityLabel: "Undo capture",
            action: onUndo
        )
    }
}
