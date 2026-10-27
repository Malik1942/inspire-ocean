import Foundation
import Observation

/// The phone's latest word on the wrist's thoughts, as the Today and Recent
/// pages read it. Kept on disk so the pages render at launch. A snapshot
/// older than the one held (a reply and a context update crossing) changes
/// nothing.
///
/// No watch API in here: SharedTests compiles this file (see project.yml).
@MainActor
@Observable
final class WristLibrary {
    private(set) var snapshot: WristSnapshot?
    @ObservationIgnored private let store: WristSnapshotStore
    #if DEBUG
    @ObservationIgnored private var isShowingDemo = false
    #endif

    init(store: WristSnapshotStore = .standard) {
        self.store = store
        snapshot = store.load()
    }

    /// True when the snapshot was newer and is now the one held.
    @discardableResult
    func receive(_ incoming: WristSnapshot) -> Bool {
        guard incoming.isNewer(than: snapshot) else { return false }
        snapshot = incoming
        #if DEBUG
        // A screenshot demo never touches the real snapshot on disk.
        if isShowingDemo { return true }
        #endif
        store.save(incoming)
        return true
    }

    #if DEBUG
    /// Screenshot seam: show a snapshot without touching disk.
    func showDemo(_ demo: WristSnapshot) {
        isShowingDemo = true
        snapshot = demo
    }
    #endif
}
