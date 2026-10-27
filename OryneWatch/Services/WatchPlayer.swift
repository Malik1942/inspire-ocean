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
    /// Bumped by `invalidate`. A phone fetch keeps the value it saw and plays
    /// only if it still matches, so leaving or starting a capture cannot
    /// start audio after the fact.
    private(set) var generation = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// True after `setActive(true)` succeeds, until `stop` has attempted to
    /// deactivate. Covers the gap before `player` is assigned, so a throw
    /// from `AVAudioPlayer(contentsOf:)` still releases the session.
    @ObservationIgnored private var sessionHeld = false

    /// Resumes `id` when it is the paused one, else plays `url` from the
    /// start. False when the file doesn't play.
    @discardableResult
    func play(_ url: URL, id: UUID) -> Bool {
        if currentID == id, state == .paused, let player {
            guard player.play() else {
                stop()
                return false
            }
            state = .playing
            startTicking()
            return true
        }
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            sessionHeld = true
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

    /// Ends playback and retires the current generation. A fetch that started
    /// before this must not start playback when it returns. `stop` itself
    /// does not retire the generation: a file that arrives while the wrist
    /// is down is kept for a later tap.
    func invalidate() {
        generation += 1
        stop()
    }

    /// Releases the audio session only when this player held it, so a stop
    /// arriving after a recording began (the thought closing as Capture
    /// returns) never takes the session from the recorder.
    func stop() {
        let held = player != nil || sessionHeld
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
        sessionHeld = false
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
