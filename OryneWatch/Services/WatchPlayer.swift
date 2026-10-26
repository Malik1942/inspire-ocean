import Foundation
import AVFoundation
import Observation

/// Replays one recording at a time on the wrist: a take's own file, or
/// audio fetched from the phone. Playback is for checking the words
/// (PHILOSOPHY §2): play, pause, and nothing to manage. Capture always wins:
/// a recording stops it first (`WatchCaptureModel.begin`).
@MainActor
@Observable
final class WatchPlayer {
    enum State: Equatable {
        case idle
        case playing
        case paused
    }

    private(set) var state: State = .idle
    /// The thought being played or paused.
    private(set) var currentID: UUID?
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// Resumes `id` when it is the paused one, else plays `url` from the
    /// start. False when the file doesn't play.
    @discardableResult
    func play(_ url: URL, id: UUID) -> Bool {
        if currentID == id, state == .paused, let player {
            player.play()
            state = .playing
            startTicking()
            return true
        }
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            self.player = player
            guard player.play() else {
                stop()
                return false
            }
            currentID = id
            duration = player.duration
            elapsed = 0
            state = .playing
            startTicking()
            return true
        } catch {
            stop()
            return false
        }
    }

    func pause() {
        guard state == .playing else { return }
        player?.pause()
        ticker?.cancel()
        state = .paused
    }

    /// Releases the audio session only when this player held it, so a stop
    /// arriving after a recording began (the thought closing as Capture
    /// returns) never takes the session from the recorder.
    func stop() {
        let held = player != nil
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        currentID = nil
        elapsed = 0
        duration = 0
        state = .idle
        if held {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Reads the position for the toolbar's time, and ends playback when the
    /// file runs out.
    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let player = self.player else { return }
                if player.isPlaying {
                    self.elapsed = player.currentTime
                } else if self.state == .playing {
                    self.stop()
                    return
                }
            }
        }
    }
}
