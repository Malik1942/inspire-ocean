import Foundation
import Observation

/// The names of the currents, kept in memory for every view that shows one
/// (a thought's meta line, Tide's tiles, the Currents page, export) so none
/// of them needs its own fetch. `RootTabView` feeds it from a live query of
/// `Current` rows; everything else reads `name(for:)`.
@Observable
final class CurrentDirectory {
    static let shared = CurrentDirectory()

    struct Entry: Equatable {
        let key: String
        let labelEN: String?
        let labelZH: String?
        let pinnedName: String?
    }

    private(set) var entries: [String: Entry] = [:]

    /// The app's language, which iOS sets per app (Settings › Oryne ›
    /// Language), so a Chinese user reads 光与色彩 where an English one reads
    /// Light and Color.
    var prefersChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
    }

    func update(_ currents: [Current]) {
        var fresh: [String: Entry] = [:]
        for current in currents {
            fresh[current.key] = Entry(key: current.key, labelEN: current.labelEN, labelZH: current.labelZH, pinnedName: current.pinnedName)
        }
        if fresh != entries { entries = fresh }
    }

    /// What the user reads for a key: their name, their language's label,
    /// the other language's, or the key made readable.
    func name(for key: String) -> String {
        guard let entry = entries[key] else { return CurrentKey.humanized(key) }
        return CurrentKey.name(pinnedName: entry.pinnedName, labelEN: entry.labelEN, labelZH: entry.labelZH, key: key, preferringChinese: prefersChinese)
    }

    /// Every known key with its name, for the snap's candidate list.
    var names: [String: String] {
        entries.mapValues { CurrentKey.name(pinnedName: $0.pinnedName, labelEN: $0.labelEN, labelZH: $0.labelZH, key: $0.key, preferringChinese: prefersChinese) }
    }
}
