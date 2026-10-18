import SwiftUI

/// The capture button: a lifted glass disc that breathes with the microphone
/// while a take is live. Tap to type, hold to whisper, slide up to lock, tap
/// again to stop. Every instance drives the shared `CaptureControl`, so the
/// floating button over the tabs and the overlay's own button are the same
/// control in two places.
struct CaptureHoldButton: View {
    @Environment(CaptureControl.self) private var control
    @Environment(\.calmAccessibility) private var calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size: CGFloat = 64

    @State private var pressBegan: Date?
    @State private var holdTask: Task<Void, Never>?
    @State private var lockedThisTouch = false
    @State private var tapOnLockedTake = false
    @State private var isPressed = false

    private var tapToToggle: Bool { calm || control.tapToToggle }

    private var listening: Bool { control.isListening }
    private var locked: Bool { control.touch == .locked }

    /// Reduce Motion and Calm Accessibility Mode still the breath: the disc
    /// still lifts when a take is live, it just doesn't move with the voice.
    private var stilled: Bool { reduceMotion || calm }

    /// The finger is down past the tap threshold and the take isn't locked
    /// yet: the moment the slide-up hint is useful.
    private var holding: Bool {
        if case .held = control.touch { return listening && !tapToToggle }
        return false
    }

    /// The microphone level the body follows, 0 when stilled.
    private var breath: CGFloat { stilled || !listening ? 0 : CGFloat(min(max(control.level, 0), 1)) }

    var body: some View {
        ZStack {
            disc

            glyph
                .font(.system(size: locked && listening ? size * 0.28 : size * 0.36, weight: .medium))
                .foregroundStyle(listening ? OceanTheme.foam : OceanTheme.accent)
                .contentTransition(stilled ? .opacity : .symbolEffect(.replace.downUp))
                .scaleEffect(discScale)
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: locked)
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: listening)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .top) { lockHint }
        .animation(.easeOut(duration: 0.24), value: holding)
        .contentShape(Circle())
        .gesture(pressGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(tapToToggle ? Text("Tap to start or stop a whisper.") : Text("Tap to type. Hold to whisper. Slide up to keep listening."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if listening { control.stop() } else { control.touch = .locked }
        }
    }

    // MARK: Body

    /// Pressed, the disc sinks a little into the water; listening, it rises
    /// and swells with the voice. Presence is the body and its shadow, never
    /// a ring or a glow around it (Philosophy §4).
    private var discScale: CGFloat {
        if listening { return 1.06 + breath * 0.10 }
        return isPressed ? 0.93 : 1
    }

    /// How far the body floats above the water. The depth shadow carries it:
    /// tight and close when pressed, longer and softer while a take lifts it.
    private var lift: CGFloat {
        if listening { return 1 + breath * 0.8 }
        return isPressed ? 0.35 : 0.75
    }

    private var disc: some View {
        Circle()
            .fill(.ultraThinMaterial)
            // Top-lit body tone, the same light the field's bodies take.
            .overlay(
                Circle().fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(listening ? 0.17 : 0.11),
                            Color.white.opacity(listening ? 0.05 : 0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            // A lit upper edge that fades out by the middle: glass catching
            // light, not a rim drawn around it.
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(listening ? 0.20 : 0.14), Color.white.opacity(0)],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 0.6
                )
            )
            // Contact shadow, then the depth shadow that carries the lift.
            .shadow(color: .black.opacity(0.30), radius: 1.5, y: 1)
            .shadow(color: .black.opacity(0.30 + 0.16 * lift), radius: 4 + 14 * lift, y: 2 + 9 * lift)
            .scaleEffect(discScale)
            .animation(stilled ? nil : .interactiveSpring(response: 0.18, dampingFraction: 0.9), value: control.level)
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: listening)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isPressed)
    }

    /// While a hold is live and not yet locked: a quiet lock and chevron
    /// above the disc say where the finger can go. Words carry it for
    /// VoiceOver (the hint), so this is never the only path.
    @ViewBuilder
    private var lockHint: some View {
        if holding {
            VStack(spacing: 1) {
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.17, weight: .semibold))
                Image(systemName: "chevron.compact.up")
                    .font(.system(size: size * 0.20, weight: .semibold))
            }
            .foregroundStyle(OceanTheme.mist)
            .offset(y: -(size * 0.62))
            .transition(stilled ? .opacity : .opacity.combined(with: .offset(y: 8)))
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var glyph: some View {
        if locked && listening {
            Image(systemName: "stop.fill")
        } else {
            Image(systemName: "waveform")
        }
    }

    private var accessibilityLabel: Text {
        if listening { return Text("Stop whisper") }
        return Text("Capture")
    }

    // MARK: Gesture

    /// One DragGesture carries tap, hold, lock and stop so the finger never
    /// has to leave the disc to change its mind.
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if pressBegan == nil { begin() }
                guard !tapToToggle, !tapOnLockedTake, !lockedThisTouch else { return }
                if case .held = control.touch, value.translation.height < -CaptureControl.lockDistance {
                    lockedThisTouch = true
                    control.touch = .locked
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
            }
            .onEnded { _ in end() }
    }

    private func begin() {
        pressBegan = .now
        isPressed = true
        tapOnLockedTake = listening && (locked || tapToToggle)
        lockedThisTouch = false
        holdTask?.cancel()
        guard !tapToToggle, !tapOnLockedTake else { return }
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: CaptureControl.holdThreshold)
            guard !Task.isCancelled, pressBegan != nil else { return }
            control.touch = .held(since: .now)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    private func end() {
        holdTask?.cancel()
        holdTask = nil
        isPressed = false
        defer {
            pressBegan = nil
            lockedThisTouch = false
            tapOnLockedTake = false
        }
        if tapOnLockedTake {
            control.stop()
            return
        }
        if tapToToggle {
            // Tap starts a locked take; the next tap (above) stops it.
            control.touch = .locked
            return
        }
        switch control.touch {
        case .held:
            // Lift = catch. The overlay stops the take on this change.
            control.touch = .up
        case .locked:
            // Slid up: the take keeps running until Stop.
            break
        case .up:
            control.tap()
        }
    }
}
