import SwiftUI

/// The capture disc: a flat matte circle, 44 pt, with the waveform glyph.
/// Tap to type, hold to whisper, slide up to lock, tap the locked disc to
/// stop. While a take is live the glyph itself carries the state: bars that
/// move with the microphone, then a Stop square once locked. No glow, no
/// ring, no highlight (Philosophy §4). Every instance drives the shared
/// `CaptureControl`, so the bar's disc and the overlay's disc are one control.
struct CaptureHoldButton: View {
    @Environment(CaptureControl.self) private var control
    @Environment(\.calmAccessibility) private var calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size: CGFloat = 44

    @State private var pressBegan: Date?
    @State private var holdTask: Task<Void, Never>?
    @State private var lockedThisTouch = false
    @State private var tapOnLockedTake = false
    @State private var isPressed = false

    private var tapToToggle: Bool { calm || control.tapToToggle }
    private var listening: Bool { control.isListening }
    private var locked: Bool { control.touch == .locked }
    private var stilled: Bool { reduceMotion || calm }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(listening ? 0.16 : 0.10))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                .opacity(isPressed ? 0.75 : 1)

            glyph
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.15), value: listening)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .gesture(pressGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(listening ? Text("Stop whisper") : Text("Capture"))
        .accessibilityHint(tapToToggle ? Text("Tap to start or stop a whisper.") : Text("Tap to type. Hold to whisper. Slide up to keep listening."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if listening { control.stop() } else { control.touch = .locked }
        }
    }

    @ViewBuilder
    private var glyph: some View {
        if listening && locked {
            Image(systemName: "stop.fill")
                .font(.system(size: size * 0.32, weight: .medium))
                .foregroundStyle(OceanTheme.foam)
                .transition(.opacity)
        } else if listening {
            LevelBars(level: stilled ? 0.5 : control.level, size: size)
                .transition(.opacity)
        } else {
            Image(systemName: "waveform")
                .font(.system(size: size * 0.4, weight: .regular))
                .foregroundStyle(OceanTheme.accent)
                .transition(.opacity)
        }
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
            control.touch = .locked
            return
        }
        switch control.touch {
        case .held:
            control.touch = .up          // lift = catch
        case .locked:
            break                        // slid up: runs until Stop
        case .up:
            control.tap()
        }
    }
}

/// Five bars that follow the microphone level: the recording glyph people
/// already know. Information in the glyph, not in the material.
private struct LevelBars: View {
    let level: Double
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.06) {
            ForEach(0..<5, id: \.self) { i in
                let weight: [Double] = [0.45, 0.8, 1.0, 0.8, 0.45]
                let h = size * (0.16 + 0.26 * min(max(level, 0), 1) * weight[i])
                Capsule()
                    .fill(OceanTheme.foam)
                    .frame(width: size * 0.07, height: max(size * 0.12, h))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
