import Foundation
import Observation

/// One thought on the wrist: its reading, and its recording from the watch
/// or fetched from the phone. A notice about the audio stays until tapped
/// (PHILOSOPHY §5: failure never fades on its own).
@MainActor
@Observable
final class WatchThoughtModel {
    enum Audio: Equatable {
        /// Nothing to play: no control.
        case none
        case ready
        case fetching
        case phoneAway
        case failed
    }

    let row: WristRow
    let player: WatchPlayer
    private(set) var audio: Audio
    @ObservationIgnored private let queue: TakeQueue
    @ObservationIgnored private let link: PhoneLink
    @ObservationIgnored private var fetched: URL?
    @ObservationIgnored private var metSent = false
    /// False while the wrist is down. A file that arrives then is kept and
    /// is not started.
    @ObservationIgnored private var sceneActive = true

    init(row: WristRow, queue: TakeQueue, player: WatchPlayer, link: PhoneLink) {
        self.row = row
        self.queue = queue
        self.player = player
        self.link = link
        audio = row.audio == .none ? .none : .ready
        #if DEBUG
        // Screenshot seam: `ORYNE_WATCH_AUDIO=fetching|phoneAway|fetchFailed`.
        switch ProcessInfo.processInfo.environment["ORYNE_WATCH_AUDIO"] {
        case "fetching": audio = .fetching
        case "phoneAway": audio = .phoneAway
        case "fetchFailed": audio = .failed
        default: break
        }
        #endif
    }

    var isPlaying: Bool {
        player.currentID == row.id && player.state == .playing
    }

    var isPlayerOnThis: Bool {
        player.currentID == row.id
    }

    /// Opening Today's thought tells the phone it was met, once.
    func appeared() {
        guard row.isToday, !metSent else { return }
        metSent = true
        link.sendMet(row.id)
    }

    func togglePlay() async {
        if isPlaying {
            player.pause()
            return
        }
        switch row.audio {
        case .none:
            return
        case .watch:
            if !player.play(queue.audioURL(for: row.id), id: row.id) { audio = .failed }
        case .phone:
            await playFromPhone()
        }
    }

    func dismissNotice() {
        if audio == .phoneAway || audio == .failed { audio = .ready }
    }

    /// The wrist went down: playback stops. The fetched copy stays, and a
    /// file that arrives now is kept for a later tap rather than started.
    func sceneWentInactive() {
        sceneActive = false
        if isPlayerOnThis { player.stop() }
    }

    /// The wrist is up again. Playback does not resume on its own.
    func sceneBecameActive() {
        sceneActive = true
    }

    /// Leaving retires any in-flight fetch, even when this thought is not
    /// the one playing, and drops audio this visit already holds.
    func leave() {
        player.invalidate()
        if fetched != nil {
            PlaybackCache.remove(row.id)
            fetched = nil
        }
    }

    private func playFromPhone() async {
        if let fetched {
            guard sceneActive else { return }
            if !player.play(fetched, id: row.id) { audio = .failed }
            return
        }
        guard audio != .fetching else { return }
        audio = .fetching
        let generation = player.generation
        switch await link.fetchAudio(row.id) {
        case .file(let url):
            // Left, or a capture started, while this was on its way.
            if player.generation != generation {
                PlaybackCache.remove(row.id)
                return
            }
            fetched = url
            audio = .ready
            guard sceneActive else { return }
            if !player.play(url, id: row.id) { audio = .failed }
        case .phoneAway:
            audio = .phoneAway
        case .failed:
            audio = .failed
        }
    }
}
