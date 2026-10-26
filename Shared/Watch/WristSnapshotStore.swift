import Foundation

/// The phone's latest wrist snapshot on the watch's own disk, so Today and
/// Recent show at launch before the phone answers. One JSON file in the
/// watch app's Application Support.
struct WristSnapshotStore {
    let url: URL

    init(url: URL) {
        self.url = url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    static var standard: WristSnapshotStore {
        WristSnapshotStore(url: URL.applicationSupportDirectory
            .appendingPathComponent("Wrist", isDirectory: true)
            .appendingPathComponent("snapshot.json"))
    }

    /// Nil before the first snapshot, or when the file can't be read: the
    /// pages then show the queue alone until the phone sends another.
    func load() -> WristSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return WatchWire.decodeSnapshot(data)
    }

    func save(_ snapshot: WristSnapshot) {
        guard let data = WatchWire.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
