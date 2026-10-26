import Foundation
import AVFoundation
import Observation

/// The watch's queue of takes: the only place `TakeQueueState` is mutated.
/// Every change saves at once and sweeps audio the state no longer needs
/// (safe on the phone, transcribed there, and past the replay window), so a
/// take is never lost to a crash and never kept longer than it needs to be. A sweep never touches a recording the index doesn't list
/// (see `TakeQueueState.audioDisposable`); a take that leaves the queue
/// (Undo, or pruned once confirmed) takes its audio with it deliberately.
@MainActor
@Observable
final class TakeQueue {
    private(set) var state: TakeQueueState
    private let store: TakeQueueStore
    #if DEBUG
    @ObservationIgnored private var isShowingDemo = false
    #endif

    init(store: TakeQueueStore = .standard) {
        self.store = store
        var state = store.load()
        // Recordings caught but missing from the index (a failed save, an
        // unreadable index) go back in the queue rather than sit stuck.
        // Launch only: nothing is being recorded yet.
        // Below the 0.6 s minimum is a reflex press, never a take.
        let recovered = store.unlistedTakes(in: state) { url in
            let length = (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
            return length >= 0.6 ? length : nil
        }
        for take in recovered {
            state.add(take, phoneReachableAtStop: false)
        }
        self.state = state
        if !recovered.isEmpty { store.save(state) }
        store.sweep(state)
    }

    func audioURL(for id: UUID) -> URL {
        store.audioURL(for: id)
    }

    /// Whether the watch still holds this take's recording.
    func hasAudio(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: store.audioURL(for: id).path)
    }

    func change(_ mutate: (inout TakeQueueState) -> Void) {
        let before = state
        mutate(&state)
        #if DEBUG
        // A screenshot demo never touches the real queue on disk.
        if isShowingDemo { return }
        #endif
        store.save(state)
        // A take leaves the index only by Undo or by being pruned once
        // confirmed (even when confirmed and pruned in the same change):
        // either way its audio goes now, since the sweep keeps anything the
        // index doesn't list.
        for id in state.idsRemoved(since: before) {
            store.deleteAudio(id)
        }
        store.sweep(state)
    }

    /// Deletes a recording that was never queued (a reflex press, a failed
    /// or empty take). Queued takes lose their audio through `change`.
    func deleteAudio(_ id: UUID) {
        store.deleteAudio(id)
    }

    #if DEBUG
    /// Screenshot seam: show a queue without touching disk.
    func showDemo(_ demo: TakeQueueState) {
        isShowingDemo = true
        state = demo
    }
    #endif
}
