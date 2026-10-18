import SwiftUI

/// The capture bar above the tab bar on Ocean and Library, like a message
/// composer: a field to tap and the disc to hold. Its geometry is fixed so
/// the disc sits concentric with the capsule's end (FastCaptureLayout).
struct CaptureBar: View {
    @Environment(CaptureControl.self) private var control

    var body: some View {
        HStack(spacing: 12) {
            Button {
                control.tap()
            } label: {
                HStack {
                    Text("What are you noticing?")
                        .font(.body)
                        .foregroundStyle(OceanTheme.hint)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Capture a thought")
            .accessibilityHint("Opens the keyboard. The button beside it whispers.")

            CaptureHoldButton(size: FastCaptureLayout.buttonSize)
        }
        .padding(.leading, FastCaptureLayout.barHeight / 2 - 8)
        .padding(.trailing, FastCaptureLayout.discInset)
        .frame(height: FastCaptureLayout.barHeight)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        )
    }
}

/// Places the bar above the tab bar. Hidden on Ask, which has its own input.
struct CaptureBarPlacement: ViewModifier {
    let show: Bool
    let control: CaptureControl

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if show {
                CaptureBar()
                    .environment(control)
                    .padding(.horizontal, 16)
                    .padding(.bottom, FastCaptureLayout.tabBarClearance)
                    .ignoresSafeArea(.keyboard)
                    .transition(.opacity)
            }
        }
    }
}
