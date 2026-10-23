import SwiftUI

/// The capture disc: a flat matte circle, 44 pt, with the waveform glyph.
/// Tap to start a whisper and tap its Stop to keep it, as in Voice Memos
/// and every AI app's dictation; or hold to whisper and lift to keep it.
/// While a take is live the glyph itself carries the state: bars that move
/// with the microphone under a finger, a Stop square for a tapped take. No
/// glow, no ring, no highlight (Philosophy §4). Every instance drives the
/// shared `CaptureControl`, so the bar's disc and the overlay's disc are
/// one control.
///
/// In the open composer the disc is the card's one trailing action: it
/// whispers while the field is empty, and once there are words it is the
/// send, in place. Only the glyph (replaced, not moved) and the tint change.
/// A send that waits for pictures still loading shows the loading tiles'
/// spinner in the arrow's place until they are in.
struct CaptureHoldButton: View {
    @Environment(CaptureControl.self) private var control
    @Environment(\.calmAccessibility) private var calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size: CGFloat = 44
    /// The disc in the open composer, where VoiceOver calls it Whisper.
    var inComposer = false
    /// The composer's release, once there is something to release: a tap
    /// sends, and the disc wears the send's tint and arrow. No hold then.
    var send: (() -> Void)? = nil
    /// The send was tapped while pictures are still loading: it goes once
    /// they are in.
    var waiting = false

    @State private var pressBegan: Date?
    @State private var holdTask: Task<Void, Never>?
    @State private var tapOnLockedTake = false
    @State private var isPressed = false

    private var tapToToggle: Bool { calm || control.tapToToggle }
    private var listening: Bool { control.isListening }
    private var locked: Bool { control.touch == .locked }
    private var stilled: Bool { reduceMotion || calm }
    private var sends: Bool { send != nil && !listening }
    private var waits: Bool { sends && waiting }

    var body: some View {
        ZStack {
            // Glass, like every control; a lighter tint while listening,
            // and the send's own (OceanPrimaryIconButtonStyle) when ready.
            Color.clear
                .frame(width: size, height: size)
                .oceanGlass(in: Circle(), tint: listening || sends ? Color.white.opacity(0.18) : nil, interactive: false)
                .opacity(isPressed ? 0.75 : 1)

            glyph
        }
        .frame(width: size, height: size)
        // One body: without it the glyph (a symbol with a content
        // transition) jumps ahead of its glass while the card folds.
        .geometryGroup()
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.15), value: listening)
        .animation(.easeOut(duration: 0.15), value: sends)
        .animation(.easeOut(duration: 0.15), value: waits)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .gesture(pressGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(waits ? Text("Waiting for images") : Text(verbatim: ""))
        .accessibilityHint(sends ? Text(verbatim: "") : tapToToggle ? Text("Tap to start or stop a whisper.") : Text("Tap to start or stop a whisper. Or hold, and let go to end it."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if let send, !listening { send() } else if listening { control.stop() } else { control.touch = .locked }
        }
        // VoiceOver hears the wait as it begins, as the eye sees the spinner.
        .onChange(of: waits) { _, waits in
            if waits { AccessibilityNotification.Announcement(String(localized: "Waiting for images")).post() }
        }
    }

    private var accessibilityName: Text {
        if listening { return Text("Stop whisper") }
        if sends { return Text("Release into the Ocean") }
        return inComposer ? Text("Whisper") : Text("Capture")
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
        } else if waits {
            // The loading tiles' own spinner: the send waits on them.
            ProgressView()
                .tint(OceanTheme.foam)
                .transition(.opacity)
        } else {
            // One image for both, so the waveform is replaced by the
            // arrow where it stands. The arrow is the send's: 17 semibold.
            Image(systemName: sends ? "arrow.up" : "waveform")
                .font(.system(size: sends ? 17 : size * 0.4, weight: sends ? .semibold : .regular))
                .foregroundStyle(sends ? OceanTheme.foam : OceanTheme.accent)
                .contentTransition(.symbolEffect(.replace))
                .transition(.opacity)
        }
    }

    // MARK: Gesture

    /// One DragGesture carries tap, hold and stop, so a press can still
    /// become a hold after it begins.
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { _ in
                if pressBegan == nil { begin() }
            }
            .onEnded { value in
                // The send, like a button, lets go without firing when the
                // finger slides well off the disc first.
                let reach = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: -16, dy: -16)
                end(inside: reach.contains(value.location))
            }
    }

    private func begin() {
        pressBegan = .now
        isPressed = true
        tapOnLockedTake = listening && (locked || tapToToggle)
        holdTask?.cancel()
        guard !sends, !tapToToggle, !tapOnLockedTake else { return }
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: CaptureControl.holdThreshold)
            guard !Task.isCancelled, pressBegan != nil else { return }
            control.touch = .held(since: .now)
            CaptureFeedback.touch(.soft)
        }
    }

    private func end(inside: Bool) {
        holdTask?.cancel()
        holdTask = nil
        isPressed = false
        defer {
            pressBegan = nil
            tapOnLockedTake = false
        }
        if tapOnLockedTake {
            control.stop()               // a tapped take's Stop: keep it
            return
        }
        if let send, sends {
            // A tap sends. A press long enough to be a hold, the disc's
            // other habit, lets go without sending.
            let tapped = pressBegan.map { Date.now.timeIntervalSince($0) < 0.5 } ?? false
            if inside, tapped { send() }
            return
        }
        switch control.touch {
        case .held:
            control.touch = .up          // lift = catch
        case .locked:
            break                        // a take already starting
        case .up:
            // A tap starts a take that runs until Stop.
            control.touch = .locked
            CaptureFeedback.touch(.soft)
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
