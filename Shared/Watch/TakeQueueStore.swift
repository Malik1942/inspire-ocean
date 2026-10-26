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

    /// Loads the queue. An index that exists but can't be read is moved
    /// aside (kept for diagnosis), so the next save can't overwrite the only
    /// record of it; its recordings come back through `unlistedTakes`.
    func load() -> TakeQueueState {
        guard let data = try? Data(contentsOf: indexURL) else { return TakeQueueState() }
        if let state = try? JSONDecoder().decode(TakeQueueState.self, from: data) { return state }
        let aside = directory.appendingPathComponent("queue.unreadable-\(UUID().uuidString).json")
        try? FileManager.default.moveItem(at: indexURL, to: aside)
        return TakeQueueState()
    }

    func save(_ state: TakeQueueState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    /// Deletes audio the state says the wrist no longer needs. A recording
    /// the index doesn't list (one being recorded, an unreadable index, a
    /// crash mid-recording) is kept: `audioDisposable` never guesses about it.
    func sweep(_ state: TakeQueueState, now: Date = .now) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        for file in files where file.pathExtension == "m4a" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  state.audioDisposable(id, now: now)
            else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Recordings on disk the index doesn't list, as takes ready to queue
    /// again: each take's time from the file's creation date (recording
    /// start), its length from `duration`, which returns nil for a recording
    /// that doesn't play back (a crash mid-recording leaves one; it stays
    /// ignored). Call at launch only, when nothing is being recorded.
    /// Oldest first.
    func unlistedTakes(in state: TakeQueueState, duration: (URL) -> TimeInterval?) -> [WatchTake] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        return files
            .filter { $0.pathExtension == "m4a" }
            .compactMap { file -> WatchTake? in
                guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                      state.item(id) == nil,
                      let length = duration(file), length > 0
                else { return nil }
                let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                return WatchTake(id: id, createdAt: created, duration: length)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func deleteAudio(_ id: UUID) {
        try? FileManager.default.removeItem(at: audioURL(for: id))
    }
}
