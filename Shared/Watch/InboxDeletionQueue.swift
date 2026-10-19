import Foundation

/// iCloud inbox records waiting to be deleted once their take has settled on
/// the phone. Persisted, so a delete that fails offline, or that comes due
/// before the reader exists, is retried rather than leaving the audio in the
/// user's iCloud.
struct InboxDeletionQueue: Equatable {
    static let defaultsKey = "watch.inboxPendingDeletions"

    /// CloudKit refuses more than 400 items in one modify; stay well under.
    static let maxPerModify = 200

    /// Oldest first, no duplicates.
    private(set) var ids: [UUID] = []

    var isEmpty: Bool { ids.isEmpty }

    /// The queue in modify-sized batches, oldest first.
    func batches() -> [[UUID]] {
        stride(from: 0, to: ids.count, by: Self.maxPerModify).map {
            Array(ids[$0..<min($0 + Self.maxPerModify, ids.count)])
        }
    }

    mutating func add(_ id: UUID) {
        guard !ids.contains(id) else { return }
        ids.append(id)
    }

    mutating func remove(_ id: UUID) {
        ids.removeAll { $0 == id }
    }

    static func load(from defaults: UserDefaults) -> InboxDeletionQueue {
        let strings = defaults.stringArray(forKey: defaultsKey) ?? []
        var queue = InboxDeletionQueue()
        strings.compactMap(UUID.init(uuidString:)).forEach { queue.add($0) }
        return queue
    }

    func save(to defaults: UserDefaults) {
        defaults.set(ids.map(\.uuidString), forKey: Self.defaultsKey)
    }
}
