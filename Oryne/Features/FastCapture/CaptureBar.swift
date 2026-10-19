import SwiftUI

/// The capture bar above the tab bar on Tide and Library, like a message
/// composer: a field to tap and the disc to hold. Its geometry is fixed so
/// the disc sits concentric with the capsule's end (FastCaptureLayout).
///
/// Folded, it is only the disc in a 56 pt circle at the same spot: the
/// capsule's leading edge slides in to meet it and the words fade first,
/// so they are clipped, never squashed. The disc itself never moves, and
/// it still taps to type and holds to whisper.
struct CaptureBar: View {
    @Environment(CaptureControl.self) private var control
    var folded = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                control.tap()
            } label: {
                Text("What are you noticing?")
                    .font(.body)
                    .foregroundStyle(OceanTheme.hint)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.leading, FastCaptureLayout.fieldLeading)
                    // minWidth 0: the words keep their width and overflow
                    // into the clip instead of widening the bar.
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(folded ? 0 : 1)
            .animation(folded ? .easeOut(duration: 0.1) : .easeOut(duration: 0.2).delay(0.3), value: folded)
            .allowsHitTesting(!folded)
            .accessibilityHidden(folded)
            .accessibilityLabel("Capture a thought")
            .accessibilityHint("Opens the keyboard. The button beside it whispers.")

            CaptureHoldButton(size: FastCaptureLayout.buttonSize)
                .padding(.trailing, FastCaptureLayout.discInset)
        }
        .frame(maxWidth: folded ? FastCaptureLayout.barHeight : .infinity, alignment: .trailing)
        .frame(height: FastCaptureLayout.barHeight)
        // Words out first, then the fold; unfolding, the words return only
        // once the capsule is wide again. They never slide with the edge.
        .animation(folded ? .smooth(duration: 0.4).delay(0.1) : .smooth(duration: 0.4), value: folded)
        // The words never spill past the folding edge; the surface and its
        // shadow sit outside the clip.
        .clipShape(Capsule())
        .background(OceanBarBackground())
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// The one container every capture state wears: the bar's Liquid Glass
/// capsule, at the bar's frame. Typing and listening in the overlay draw
/// in it too, so the bar never changes shape or material. Taller content
/// (wrapped words, a screenshot) grows it into a rounded rectangle with
/// the same end radius, which at one line is exactly the capsule.
struct CaptureCapsule<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(FastCaptureLayout.discInset)
            .frame(maxWidth: .infinity, minHeight: FastCaptureLayout.barHeight, alignment: .leading)
            .background(OceanBarBackground(cornerRadius: FastCaptureLayout.endRadius))
    }
}

/// Places the bar above the tab bar. Hidden on Ask, which has its own input.
struct CaptureBarPlacement: ViewModifier {
    let show: Bool
    /// A hold that began on the bar's disc: the overlay's identical capsule
    /// is drawn in the same frame, so the bar goes invisible but keeps the
    /// finger until it lifts or locks.
    var keepsTouch = false
    var folded = false
    let control: CaptureControl

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            CaptureBar(folded: folded)
                .environment(control)
                .padding(.horizontal, OceanSpacing.gutter)
                .padding(.bottom, FastCaptureLayout.tabBarClearance)
                .ignoresSafeArea(.keyboard)
                .opacity(show ? 1 : 0)
                .allowsHitTesting(show || keepsTouch)
                .animation(.easeOut(duration: 0.18), value: show)
        }
    }
}

/// The surface every floating bar wears: the capture bar, Ask's bar, the
/// capture toast. Dense enough to read over anything: material under a deep
/// tint, one soft shadow. A capsule, or a rounded rectangle with the same
/// end radius once a bar grows past one line.
struct OceanBarBackground: View {
    /// nil draws a capsule.
    var cornerRadius: CGFloat? = nil

    var body: some View {
        if let cornerRadius {
            // Circular corners: at half the height this is exactly the
            // capsule, so a bar growing past one line keeps its ends.
            surface(RoundedRectangle(cornerRadius: cornerRadius, style: .circular))
        } else {
            surface(Capsule())
        }
    }

    /// Liquid Glass, like the tab bar under it; the old dense material
    /// before iOS 26.
    @ViewBuilder
    private func surface<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape
                .fill(.regularMaterial)
                .overlay(shape.fill(OceanTheme.deep.opacity(0.55)))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        }
    }
}

/// The shore under the capture bar: content dims as it runs beneath the
/// bar and the tab bar. Lives inside each tab's content so it sits under
/// the tab bar, never over it.
struct ShoreGradient: View {
    var body: some View {
        VStack {
            Spacer()
            LinearGradient(
                stops: [
                    .init(color: OceanTheme.abyss.opacity(0), location: 0),
                    .init(color: OceanTheme.abyss.opacity(0.7), location: 0.5),
                    .init(color: OceanTheme.abyss.opacity(0.92), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 200)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
