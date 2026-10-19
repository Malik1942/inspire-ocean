import SwiftUI

/// The one thing a capture says back: the thought is in, and the way back is
/// right there. A capsule centered above the capture bar, in the bar's own
/// material, held for the whole undo window. Nothing else rides with it: no
/// interpreted title, no nearby hint (Malik, 2026-10-18).
struct CaptureToast: View {
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text("Carried into the sea")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(OceanTheme.foam)
                .lineLimit(1)
            Button(action: onUndo) {
                Text("Undo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OceanTheme.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo capture")
        }
        .padding(.leading, 22)
        .padding(.trailing, 12)
        .frame(height: 48)
        .background(OceanBarBackground())
        .accessibilityElement(children: .contain)
    }
}
