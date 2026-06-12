import SwiftUI
import AVFoundation
import Observation

/// Plays a voice drift straight from its bytes (`Node.audioData` or a fresh
/// recording) — listening only; the audio itself is never altered.
@Observable
final class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    private(set) var progress: Double = 0   // 0...1
    private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(data: Data) {
        if isPlaying { pause() } else { play(data: data) }
    }

    func play(data: Data) {
        if player == nil {
            guard let p = try? AVAudioPlayer(data: data) else { return }
            p.delegate = self
            player = p
            duration = p.duration
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        isPlaying = player?.play() == true
        if isPlaying { startTimer() }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
        stopTimer()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        progress = 0
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let player = self.player, player.duration > 0 else { return }
            self.progress = player.currentTime / player.duration
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

/// A quiet play/pause row: control, hairline progress, duration.
struct AudioPlayerView: View {
    let data: Data

    @State private var playback = AudioPlayback()

    var body: some View {
        HStack(spacing: 12) {
            Button { playback.toggle(data: data) } label: {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(OceanTheme.accent)
            }
            .accessibilityLabel(playback.isPlaying ? "Pause recording" : "Play recording")

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(OceanTheme.accent.opacity(0.8))
                        .frame(width: max(0, geo.size.width * playback.progress))
                }
            }
            .frame(height: 3)

            Text(timeString(playback.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(OceanTheme.mist)
        }
        .onDisappear { playback.stop() }
        .onChange(of: data) { playback.stop() }
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%01d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
