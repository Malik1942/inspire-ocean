import Foundation

/// The phone's staging folder for wrist takes: `<id>.m4a` beside `<id>.json`
/// (the encoded `WatchTake`). Both delivery paths write here first and the
/// importer drains it, so a take survives a crash or a refused save between
/// arrival and import. The metadata is written last: a take is listed only
/// once its audio is in place.
struct WatchInboxFolder {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// `WatchInbox/` in the App Group container, or app-local storage on a
    /// build without the App Group (mirroring `Persistence`).
    static var standard: WatchInboxFolder {
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WatchInboxSchema.appGroupID)
            ?? URL.applicationSupportDirectory
        return WatchInboxFolder(directory: base.appendingPathComponent("WatchInbox", isDirectory: true))
    }

    func audioURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).m4a")
    }

    func metadataURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    /// Takes ownership of a WatchConnectivity file. Synchronous on purpose:
    /// the system deletes the delivered file as soon as the delegate returns.
    func accept(_ take: WatchTake, movingAudioFrom source: URL) throws {
        try place(take) { try FileManager.default.moveItem(at: source, to: $0) }
    }

    /// Copies a CloudKit asset, whose file CloudKit owns and may remove.
    func accept(_ take: WatchTake, copyingAudioFrom source: URL) throws {
        try place(take) { try FileManager.default.copyItem(at: source, to: $0) }
    }

    /// Complete takes waiting for import, oldest first.
    func pending() -> [WatchTake] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap(WatchWire.decodeTake) }
            .filter { FileManager.default.fileExists(atPath: audioURL(for: $0.id).path) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: metadataURL(for: id))
        try? FileManager.default.removeItem(at: audioURL(for: id))
    }

    private func place(_ take: WatchTake, audio write: (URL) throws -> Void) throws {
        let audio = audioURL(for: take.id)
        // Stage beside the destination, then swap it in: a failed second
        // delivery of the same take must never remove a good first copy.
        let staged = directory.appendingPathComponent("\(take.id.uuidString).incoming-\(UUID().uuidString)")
        try write(staged)
        do {
            if FileManager.default.fileExists(atPath: audio.path) {
                _ = try FileManager.default.replaceItemAt(audio, withItemAt: staged)
            } else {
                try FileManager.default.moveItem(at: staged, to: audio)
            }
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
        guard let data = WatchWire.encode(take) else { throw CocoaError(.coderInvalidValue) }
        try data.write(to: metadataURL(for: take.id), options: .atomic)
    }
}
