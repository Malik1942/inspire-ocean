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

    /// The wrist went down: playback stops; the fetched copy stays for this visit.
    func sceneWentInactive() {
        if isPlayerOnThis { player.stop() }
    }

    /// Leaving the thought: playback stops and fetched audio goes.
    func leave() {
        if isPlayerOnThis { player.stop() }
        if fetched != nil {
            PlaybackCache.remove(row.id)
            fetched = nil
        }
    }

    private func playFromPhone() async {
        if let fetched {
            if !player.play(fetched, id: row.id) { audio = .failed }
            return
        }
        guard audio != .fetching else { return }
        audio = .fetching
        switch await link.fetchAudio(row.id) {
        case .file(let url):
            fetched = url
            audio = .ready
            if !player.play(url, id: row.id) { audio = .failed }
        case .phoneAway:
            audio = .phoneAway
        case .failed:
            audio = .failed
        }
    }
}
