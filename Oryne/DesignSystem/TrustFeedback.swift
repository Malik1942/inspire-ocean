import SwiftUI
import Observation

// MARK: - BreathingDots

/// Three soft dots breathing in sequence — the Ocean working.
///
/// This is the app's single "something is happening" mark, shared by the Ask
/// reading beat and the capture moment so waiting looks the same everywhere:
/// alive, unhurried, never a spinner. When motion is reduced (system setting
/// or Calm Accessibility Mode) the dots hold still at half-light instead of
/// disappearing — the state stays visible, only the motion rests.
struct BreathingDots: View {
    var size: CGFloat = 5
    var tint: Color = OceanTheme.mist

    @Environment(\.calmAccessibility) private var calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    private var still: Bool { calm || reduceMotion }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(tint)
                    .frame(width: size, height: size)
                    .opacity(still ? 0.55 : (breathing ? 0.85 : 0.3))
                    .scaleEffect(still ? 1 : (breathing ? 1.0 : 0.72))
                    .animation(
                        still ? nil : .easeInOut(duration: 0.65)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.18),
                        value: breathing
                    )
            }
        }
        .onAppear { breathing = true }
        .accessibilityHidden(true)
    }
}

// MARK: - UndoCurrent

/// The takeback current: one recent action at a time can be undone for a few
/// seconds, then the water settles and the action becomes final.
///
/// Lightweight by design — no undo stack, no manager, no persistence. Each
/// offer carries its own `undo` closure and an optional `onExpire` that runs
/// when the window closes (e.g. the actual delete behind a grace-period
/// delete). Posting a new offer settles the previous one immediately, so two
/// destructive actions can never share a window. If the app dies mid-window,
/// `onExpire` never runs — every grace pattern here fails toward keeping the
/// user's data, never toward losing it.
@MainActor
@Observable
final class UndoCurrent {
    struct Offer: Identifiable {
        let id = UUID()
        let label: String
        let undo: () -> Void
        let onExpire: (() -> Void)?
    }

    private(set) var offer: Offer?
    private var expireTask: Task<Void, Never>?

    func post(
        _ label: String,
        for duration: Duration = .seconds(6),
        onExpire: (() -> Void)? = nil,
        undo: @escaping () -> Void
    ) {
        settle()
        let next = Offer(label: label, undo: undo, onExpire: onExpire)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            offer = next
        }
        expireTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, self.offer?.id == next.id else { return }
            withAnimation(.easeOut(duration: 0.45)) { self.offer = nil }
            next.onExpire?()
        }
    }

    func performUndo() {
        expireTask?.cancel()
        expireTask = nil
        let current = offer
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            offer = nil
        }
        current?.undo()
    }

    /// Finalize the current offer now (its expiry action runs immediately).
    func settle() {
        expireTask?.cancel()
        expireTask = nil
        let current = offer
        offer = nil
        current?.onExpire?()
    }
}

/// The floating takeback capsule — quiet label, one word of action. Rendered
/// once, at the root, just above the tab bar.
struct UndoDriftView: View {
    let offer: UndoCurrent.Offer
    var onUndo: () -> Void

    @Environment(\.calmAccessibility) private var calm

    var body: some View {
        HStack(spacing: 14) {
            Text(offer.label)
                .font(.subheadline)
                .foregroundStyle(OceanTheme.foam)
                .lineLimit(1)

            Button(action: onUndo) {
                Text("Undo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OceanTheme.accent)
                    .padding(.vertical, calm ? 10 : 4)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, calm ? 14 : 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
    }
}
