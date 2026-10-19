import Foundation

/// The watch's on-disk queue: `queue.json` (the encoded `TakeQueueState`)
/// and one `<id>.m4a` per take, in the watch app's own Application Support.
/// Watch and phone never share a container; the phone gets takes only
/// through WatchConnectivity or the iCloud inbox.
struct TakeQueueStore {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static var standard: TakeQueueStore {
        TakeQueueStore(directory: URL.applicationSupportDirectory.appendingPathComponent("Takes", isDirectory: true))
    }

    var indexURL: URL {
        directory.appendingPathComponent("queue.json")
    }

    func audioURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).m4a")
    }

    func load() -> TakeQueueState {
        guard let data = try? Data(contentsOf: indexURL),
              let state = try? JSONDecoder().decode(TakeQueueState.self, from: data)
        else { return TakeQueueState() }
        return state
    }

    func save(_ state: TakeQueueState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    /// Deletes audio the state says is safe elsewhere. A recording the index
    /// doesn't list (one being recorded, an unreadable index, a crash
    /// mid-recording) is kept: `audioDisposable` never guesses about it.
    func sweep(_ state: TakeQueueState) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        for file in files where file.pathExtension == "m4a" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  state.audioDisposable(id)
            else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    func deleteAudio(_ id: UUID) {
        try? FileManager.default.removeItem(at: audioURL(for: id))
    }
}
