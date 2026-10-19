import Foundation

/// The phone's record of every wrist take it has imported: the one source of
/// truth for "seen before", whichever path delivered the take. Asking the
/// store whether a Node with the ID exists is not enough: a thought the user
/// deleted must not come back when a late copy arrives over the other path.
///
/// Phone-local (App Group defaults), never synced: it is bookkeeping, not
/// the user's water.
struct ImportLedger: Codable, Equatable {
    enum State: String, Codable {
        /// In the store as a voice thought; understanding hasn't finished.
        case imported
        /// The understanding pass ran. The title may still be nil when the
        /// recording held no words.
        case understood
    }

    struct Entry: Codable, Equatable {
        var state: State
        var importedAt: Date
        var title: String?
    }

    static let retention: TimeInterval = 90 * 24 * 60 * 60
    /// Enough to confirm a large batch caught away from the phone; a few KB of context.
    static let confirmationLimit = 200
    static let defaultsKey = "watch.importLedger"

    private(set) var entries: [UUID: Entry] = [:]

    func hasSeen(_ id: UUID) -> Bool {
        entries[id] != nil
    }

    mutating func markImported(_ id: UUID, at date: Date) {
        guard entries[id] == nil else { return }
        entries[id] = Entry(state: .imported, importedAt: date, title: nil)
    }

    mutating func markUnderstood(_ id: UUID, title: String?) {
        guard entries[id] != nil else { return }
        entries[id]?.state = .understood
        entries[id]?.title = title
    }

    /// Imported takes still waiting for understanding, oldest first.
    var awaitingUnderstanding: [UUID] {
        entries
            .filter { $0.value.state == .imported }
            .sorted { $0.value.importedAt < $1.value.importedAt }
            .map(\.key)
    }

    /// What the watch is told: the newest imports, newest first.
    func recentConfirmations() -> [WatchConfirmation] {
        entries
            .sorted { $0.value.importedAt > $1.value.importedAt }
            .prefix(Self.confirmationLimit)
            .map { WatchConfirmation(id: $0.key, title: $0.value.title) }
    }

    /// Forgets settled entries older than the retention window. An entry
    /// still awaiting understanding is kept however old it is.
    mutating func prune(now: Date) {
        entries = entries.filter {
            $0.value.state == .imported || now.timeIntervalSince($0.value.importedAt) < Self.retention
        }
    }

    static func load(from defaults: UserDefaults) -> ImportLedger {
        guard let data = defaults.data(forKey: defaultsKey),
              let ledger = try? JSONDecoder().decode(ImportLedger.self, from: data)
        else { return ImportLedger() }
        return ledger
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
