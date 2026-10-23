import SwiftUI

/// The way back after a thought is deleted or archived: what happened, and
/// Undo. The capture toast's twin (`CaptureToast`): a capsule in the bar's
/// own material, floating over the page for the whole undo window.
struct UndoToast: View {
    /// Already localized: VoiceOver announces the same words.
    let message: String
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(message)
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
        }
        .padding(.leading, 22)
        .padding(.trailing, 12)
        .frame(height: 48)
        .background(OceanBarBackground())
        .accessibilityElement(children: .contain)
    }
}
