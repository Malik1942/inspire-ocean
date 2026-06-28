import SwiftUI
import WatchKit

/// The wrist capture screen. Opens straight into a hot mic (P0-2): no tap to
/// begin, the thought is caught before it's gone. Stop is the one dominant
/// control — tapping the listening orb ends the take and the whisper is caught.
///
/// Reads as Oryne, not a default watch app: full-bleed Ocean black (OLED-kind),
/// the gray mic orb + waveform motif, monospaced timer, and "Caught" in the
/// Ocean's voice — all from the shared `OceanTheme` tokens.
struct WatchCaptureView: View {
    @State private var recorder = WatchAudioRecorder()

    @Environment(\.scenePhase) private var scenePhase
    /// Always-On Display: dim rather than hide, so capture state stays legible.
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    private enum Stage { case starting, recording, caught, idle, denied, failed }
    @State private var stage: Stage = .starting
    @State private var caughtResetTask: Task<Void, Never>?

    /// A reflexive double-press shouldn't mint an empty whisper.
    private let minimumDuration: TimeInterval = 0.6

    var body: some View {
        ZStack {
            OceanTheme.abyss.ignoresSafeArea()

            switch stage {
            case .starting:  startingView
            case .recording: recordingView
            case .caught:    caughtView
            case .idle:      idleView
            case .denied:    deniedView
            case .failed:    failedView
            }
        }
        // Auto-start on appear — opening the app is the whole gesture.
        .task {
            if stage == .starting { await begin() }
        }
        // Wrist down / interruption ends the take like a tap on stop: capture
        // what was caught, never leave a hot mic behind or lose the words.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, recorder.isRecording { finishCapture() }
        }
        .animation(.snappy, value: stage)
    }

    // MARK: Stages

    private var startingView: some View {
        VStack(spacing: 8) {
            ProgressView().tint(OceanTheme.accent)
            Text("Opening…")
                .font(.caption2).foregroundStyle(OceanTheme.mist)
        }
    }

    private var recordingView: some View {
        VStack(spacing: 10) {
            Text("Listening…")
                .font(.caption2).foregroundStyle(OceanTheme.mist)

            WatchWaveform(level: recorder.level, active: !luminanceReduced)
                .frame(height: 22)
                .opacity(luminanceReduced ? 0.4 : 1)

            Button(action: finishCapture) { micOrb(stopping: true) }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop and catch whisper")

            Text(timeString(recorder.elapsed))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(OceanTheme.foam)
                .opacity(luminanceReduced ? 0.6 : 1)
        }
        .padding(.horizontal)
    }

    private var caughtView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(OceanTheme.accent)
            Text("Caught")
                .font(.headline).foregroundStyle(OceanTheme.foam)
            // Phase 2 wires the live "N waiting to sync" count in here.
        }
    }

    private var idleView: some View {
        VStack(spacing: 10) {
            Button { Task { await begin() } } label: { micOrb(stopping: false) }
                .buttonStyle(.plain)
                .accessibilityLabel("Catch a whisper")
            Text("Tap to whisper")
                .font(.caption2).foregroundStyle(OceanTheme.mist)
        }
    }

    private var deniedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.slash.fill")
                .font(.title3).foregroundStyle(OceanTheme.mist)
            Text("Microphone is off")
                .font(.headline).foregroundStyle(OceanTheme.foam)
            Text("Turn on Microphone for Oryne in the Watch app on your iPhone to catch whispers.")
                .font(.caption2)
                .foregroundStyle(OceanTheme.mist)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    private var failedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3).foregroundStyle(OceanTheme.mist)
            Text("Couldn't start recording")
                .font(.subheadline).foregroundStyle(OceanTheme.foam)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await begin() } }
                .font(.caption.weight(.semibold))
                .tint(OceanTheme.accent)
        }
        .padding(.horizontal)
    }

    // MARK: The mic / stop orb

    private func micOrb(stopping: Bool) -> some View {
        ZStack {
            Circle().fill(OceanTheme.current)
            Circle().strokeBorder(OceanTheme.surface.opacity(0.6), lineWidth: 1)
            Image(systemName: stopping ? "stop.fill" : "mic.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(stopping ? OceanTheme.foam : OceanTheme.accent)
        }
        .frame(width: 64, height: 64) // comfortably past the 44pt minimum
    }

    // MARK: Actions

    private func begin() async {
        stage = .starting
        switch await recorder.start() {
        case .started:          stage = .recording
        case .permissionDenied: stage = .denied
        case .failed:           stage = .failed
        }
    }

    private func finishCapture() {
        guard recorder.isRecording, let result = recorder.stop() else {
            stage = .idle
            return
        }

        // Discard a reflexive blip rather than queue an empty whisper.
        if result.duration < minimumDuration {
            try? FileManager.default.removeItem(at: result.url)
            stage = .idle
            return
        }

        // Phase 2 hands (result.url, result.duration, a fresh captureID) to
        // PendingCaptureStore here; Phase 1 confirms the file is safe on disk.
        WKInterfaceDevice.current().play(.success)
        stage = .caught

        caughtResetTask?.cancel()
        caughtResetTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            await MainActor.run { if stage == .caught { stage = .idle } }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - Waveform

/// A simplified version of the phone's listening waveform, scaled to the wrist.
/// Pauses (and the view dims it) under Always-On Display to spare the battery.
private struct WatchWaveform: View {
    let level: Double
    let active: Bool

    var body: some View {
        TimelineView(.animation(paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<13, id: \.self) { i in
                    let phase = Double(i) * 0.5
                    let base = active ? (0.3 + 0.7 * abs(sin(t * 4 + phase))) : 0.2
                    let h = max(3, base * (active ? (5 + level * 22) : 5))
                    Capsule()
                        .fill(OceanTheme.accent.opacity(active ? 0.9 : 0.4))
                        .frame(width: 3, height: h)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
