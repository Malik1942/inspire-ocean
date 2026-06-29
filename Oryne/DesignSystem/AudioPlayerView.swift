import SwiftUI
import AVFoundation
import Observation

/// One app-wide voice for stored recordings. A single player means two
/// surfaces (detail card, edit sheet) can never talk over each other, and
/// the controls stay as small as the role: audio is provenance for the
/// transcript, not an artifact of its own.
@Observable
final class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayback()

    private(set) var isPlaying = false
    private(set) var currentData: Data?

    private var player: AVAudioPlayer?

    func isPlaying(_ data: Data) -> Bool {
        isPlaying && currentData == data
    }

    func toggle(data: Data) {
        if isPlaying(data) {
            pause()
            return
        }
        if currentData != data || player == nil {
            player?.stop()
            player = try? AVAudioPlayer(data: data)
            player?.delegate = self
            currentData = data
        }
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        isPlaying = player.play()
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.stop()
        player = nil
        currentData = nil
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}

/// The single, quiet affordance for hearing the original audio. Deliberately
/// minimal — no progress, no duration, no waveform: the transcript is the
/// thought; this is just a way to check it against what was said.
struct ListenChip: View {
    let data: Data

    var body: some View {
        let playing = AudioPlayback.shared.isPlaying(data)
        Button {
            AudioPlayback.shared.toggle(data: data)
        } label: {
            Label((playing ? "Pause" : "Listen") as LocalizedStringKey, systemImage: playing ? "pause.fill" : "play.fill")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08), in: Capsule())
                .foregroundStyle(OceanTheme.mist)
        }
        .accessibilityLabel((playing ? "Pause recording" : "Listen to recording") as LocalizedStringKey)
    }
}
