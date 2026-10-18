import SwiftUI

/// The capture bar that rides above the tab bar on Ocean and Library: a
/// field to tap and the capture disc to hold, like a message composer. On
/// iOS 26 it lives in the tab bar's bottom accessory (system glass); earlier
/// systems get the same bar floating in its own glass.
struct CaptureBar: View {
    @Environment(CaptureControl.self) private var control

    /// The system draws the glass around the bar (tab bar accessory), so the
    /// bar brings no background of its own.
    var inAccessory: Bool
    /// Collapsed into the tab bar while scrolling: just the disc and a word.
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                control.tap()
            } label: {
                HStack(spacing: 8) {
                    if compact {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OceanTheme.accent)
                    }
                    Text(compact ? "Capture" : "What are you noticing?")
                        .font(compact ? .subheadline.weight(.medium) : .body)
                        .foregroundStyle(compact ? OceanTheme.foam : OceanTheme.hint)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Capture a thought")
            .accessibilityHint("Opens the keyboard. The button beside it whispers.")

            CaptureHoldButton(size: compact ? 34 : 42)
        }
        .padding(.leading, compact ? 14 : 18)
        .padding(.trailing, compact ? 6 : 7)
        .padding(.vertical, compact ? 4 : 6)
        .frame(maxWidth: .infinity)
        .background {
            if !inAccessory {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
            }
        }
    }
}

/// The iOS 26 accessory form: follows the tab bar's placement, so the bar
/// collapses to a compact form when the tab bar minimizes on scroll.
@available(iOS 26.0, *)
struct CaptureAccessoryBar: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        CaptureBar(inAccessory: true, compact: placement == .inline)
    }
}

/// Places the capture bar for the running system: the tab bar accessory on
/// iOS 26, a floating bar above the tab bar before that. Hidden on Ask,
/// which has its own input bar.
struct CaptureBarPlacement: ViewModifier {
    let show: Bool
    let control: CaptureControl

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content
                // Disabled, not emptied, on Ask: an empty accessory still
                // draws its capsule.
                .tabViewBottomAccessory(isEnabled: show) {
                    CaptureAccessoryBar()
                        .environment(control)
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else if #available(iOS 26.0, *) {
            // 26.0 has no way to disable the accessory per tab, so the bar
            // stays on Ask too, above Ask's own input.
            content
                .tabViewBottomAccessory {
                    CaptureAccessoryBar()
                        .environment(control)
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content.overlay(alignment: .bottom) {
                if show {
                    CaptureBar(inAccessory: false)
                        .environment(control)
                        .padding(.horizontal, 16)
                        .padding(.bottom, FastCaptureLayout.tabBarClearance)
                        .ignoresSafeArea(.keyboard)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
}
