import SwiftUI

// BACKUP / not currently wired. The app uses the system `.confirmationDialog`
// (the chat-bubble popover) for delete confirmation. This Liquid Glass
// alternative is kept ready to swap in: apply `.oceanConfirmationDialog(...)` in
// place of `.confirmationDialog(...)` at the call sites (ExpandedNodeView,
// LibraryView). Unused for now — it compiles but is not referenced.

/// A destructive-action confirmation in the Ocean aesthetic, presented as a
/// rounded **Liquid Glass** container (iOS 26): the translucent, refractive
/// texture of the system popover the app used to show — but centered and
/// tail-free. The scrim is kept light on purpose so the glass keeps reading as
/// translucent over the Ocean behind it, rather than flattening into an opaque
/// modal card. Falls back to `.ultraThinMaterial` on iOS 18–25.
struct OceanConfirmationOverlay: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            dialog
                .frame(maxWidth: 300)
                .padding(.horizontal, 40)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        }
    }

    private var dialog: some View {
        VStack(spacing: 20) {
            VStack(spacing: 7) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(OceanTheme.foam)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(OceanTheme.mist)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                cancelButton
                confirmButton
            }
        }
        .padding(22)
        .modifier(GlassPanel(cornerRadius: 30))
    }

    @ViewBuilder
    private var cancelButton: some View {
        let label = Text("Cancel")
            .font(.body.weight(.medium))
            .foregroundStyle(OceanTheme.foam)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
        if #available(iOS 26.0, *) {
            Button(action: onCancel) { label }
                .buttonStyle(.glass)
                .overlay(glassRim)
        } else {
            Button(action: onCancel) { label }
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(glassRim)
        }
    }

    @ViewBuilder
    private var confirmButton: some View {
        // Red text on a neutral glass pill (not a filled red button): the
        // destructive role colors the text, the glass background stays normal.
        let label = Text(confirmTitle)
            .font(.body.weight(.semibold))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
        if #available(iOS 26.0, *) {
            Button(role: .destructive, action: onConfirm) { label }
                .buttonStyle(.glass)
                .overlay(glassRim)
        } else {
            Button(action: onConfirm) { label }
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(glassRim)
        }
    }

    /// A faint hairline that lets each glass button's edge read against the
    /// glass panel behind it — soft enough to feel like the glass's own rim,
    /// not a drawn outline.
    private var glassRim: some View {
        Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
    }
}

/// The container's Liquid Glass surface (iOS 26), with an `.ultraThinMaterial`
/// fallback so the dialog still reads as glass on iOS 18–25.
private struct GlassPanel: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
    }
}

extension View {
    /// Presents `OceanConfirmationOverlay` (a Liquid Glass confirmation) when
    /// `isPresented` is true. `onConfirm` runs before the overlay dismisses so
    /// callers can still read any pending selection.
    func oceanConfirmationDialog(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        confirmTitle: String = "Delete",
        onConfirm: @escaping () -> Void
    ) -> some View {
        overlay {
            ZStack {
                if isPresented.wrappedValue {
                    OceanConfirmationOverlay(
                        title: title,
                        message: message,
                        confirmTitle: confirmTitle,
                        onConfirm: { onConfirm(); isPresented.wrappedValue = false },
                        onCancel: { isPresented.wrappedValue = false }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isPresented.wrappedValue)
        }
    }
}
