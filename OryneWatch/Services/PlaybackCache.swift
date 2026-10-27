import Foundation

/// Audio fetched from the phone for one listen. Never part of the take
/// queue: cleared when the thought closes and at launch.
enum PlaybackCache {
    static var folder: URL {
        URL.cachesDirectory.appendingPathComponent("Playback", isDirectory: true)
    }

    static func url(for id: UUID) -> URL {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(id.uuidString).m4a")
    }

    static func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(id.uuidString).m4a"))
    }

    static func clear() {
        try? FileManager.default.removeItem(at: folder)
    }
}
