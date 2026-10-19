import Foundation

/// One wrist take on its way from the watch to the Ocean.
///
/// The watch mints `id` when recording starts. It becomes the thought's
/// `Node.id`, the iCloud inbox record's name, and the key every dedupe check
/// uses, whichever path delivers the take.
struct WatchTake: Codable, Equatable, Identifiable {
    static let currentVersion = 1

    var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var version: Int = WatchTake.currentVersion
}

/// The phone's word back to the watch: this take is in the Ocean, with the
/// title it was given once understood (nil until then, or when the recording
/// held no words to name it by).
struct WatchConfirmation: Codable, Equatable {
    var id: UUID
    var title: String?
}

/// WatchConnectivity payload keys and codecs: one definition for both ends.
/// Payloads travel as JSON `Data`, which is property-list safe.
enum WatchWire {
    /// `transferFile` metadata: the encoded `WatchTake`.
    static let takeKey = "take"
    /// `sendMessage` ping that wakes the phone app so a queued file lands now.
    static let wakeKey = "wake"
    /// Application context: the encoded recent `[WatchConfirmation]`.
    static let recentKey = "recent"

    static func encode(_ take: WatchTake) -> Data? {
        try? JSONEncoder().encode(take)
    }

    static func decodeTake(_ data: Data) -> WatchTake? {
        try? JSONDecoder().decode(WatchTake.self, from: data)
    }

    static func metadata(for take: WatchTake) -> [String: Any] {
        guard let data = encode(take) else { return [:] }
        return [takeKey: data]
    }

    static func take(fromMetadata metadata: [String: Any]?) -> WatchTake? {
        guard let data = metadata?[takeKey] as? Data else { return nil }
        return decodeTake(data)
    }

    static func context(for confirmations: [WatchConfirmation]) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(confirmations) else { return [:] }
        return [recentKey: data]
    }

    static func confirmations(fromContext context: [String: Any]) -> [WatchConfirmation] {
        guard let data = context[recentKey] as? Data,
              let list = try? JSONDecoder().decode([WatchConfirmation].self, from: data)
        else { return [] }
        return list
    }
}
