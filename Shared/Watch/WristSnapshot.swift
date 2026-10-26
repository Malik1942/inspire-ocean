import Foundation

/// One thought as the wrist shows it: a name and a short reading, never the
/// full words of a long thought (the phone keeps those). Built on the phone
/// by `WristSnapshotBuilder`.
struct WristThought: Codable, Hashable, Identifiable {
    var id: UUID
    /// Nil while the thought has no name (untitled, or only the placeholder).
    var title: String?
    /// The summary, or the thought's own words cut at the reading limit; nil
    /// when it has no words.
    var reading: String?
    /// The reading is a machine summary: the wrist labels it "Summary", as
    /// the phone does (PHILOSOPHY §3).
    var readingIsSummary: Bool = false
    /// The user's own words were cut at the limit: "Continues on iPhone".
    var continues: Bool = false
    /// A voice thought with a transcript: the watch's copy of its audio
    /// expires as the phone's does.
    var hasTranscript: Bool = false
    /// The phone still holds a recording it can send on request.
    var hasAudio: Bool = false
    var isVoice: Bool = false
    var createdAt: Date
}

/// What the phone tells the wrist about its thoughts: the recent wrist takes
/// as they are now, today's resurfaced thought, and which wrist takes the
/// user deleted. Sent whole each time; the newer one wins.
struct WristSnapshot: Codable, Equatable {
    static let currentVersion = 1

    /// The newest live wrist takes, newest first.
    var recent: [WristThought]
    var today: WristThought?
    /// The day `today` was picked: the wrist shows it on that day only.
    var todayDay: Date?
    /// Wrist takes the phone imported that no longer exist.
    var deletedIDs: [UUID]
    /// A reply and a context update can cross; the newer one wins.
    var generatedAt: Date
    var version: Int = WristSnapshot.currentVersion

    func isNewer(than held: WristSnapshot?) -> Bool {
        guard let held else { return true }
        return generatedAt > held.generatedAt
    }

    /// The same thoughts, whenever each was built: the phone skips a repeat.
    func hasSameContent(as other: WristSnapshot?) -> Bool {
        guard var other else { return false }
        other.generatedAt = generatedAt
        return other == self
    }

    /// Today's thought, only on the day it was picked.
    func today(on now: Date, calendar: Calendar = .current) -> WristThought? {
        guard let today, let todayDay, calendar.isDate(todayDay, inSameDayAs: now) else { return nil }
        return today
    }

    func recentThought(_ id: UUID) -> WristThought? {
        recent.first { $0.id == id }
    }
}

extension WatchWire {
    /// Application context and snapshot replies: the encoded `WristSnapshot`.
    static let wristKey = "wrist"
    /// Watch to phone, with a reply: send a fresh snapshot.
    static let snapshotRequestKey = "snapshotRequest"
    /// Watch to phone, with a reply: send this thought's audio.
    static let audioRequestKey = "audioRequest"
    /// The reply to an audio request: whether a file is on its way.
    static let audioOKKey = "ok"
    /// `transferFile` metadata on fetched audio: the thought's ID.
    static let audioForKey = "audioFor"
    /// Watch to phone user info: today's thought was opened on the wrist.
    static let metKey = "met"

    static func encode(_ snapshot: WristSnapshot) -> Data? {
        try? JSONEncoder().encode(snapshot)
    }

    static func decodeSnapshot(_ data: Data) -> WristSnapshot? {
        try? JSONDecoder().decode(WristSnapshot.self, from: data)
    }

    /// The whole application context. An update replaces the dictionary, so
    /// the confirmations and the snapshot always travel together.
    static func context(for confirmations: [WatchConfirmation], snapshot: WristSnapshot?) -> [String: Any] {
        var context = self.context(for: confirmations)
        if let snapshot, let data = encode(snapshot) { context[wristKey] = data }
        return context
    }

    static func snapshot(from dictionary: [String: Any]) -> WristSnapshot? {
        guard let data = dictionary[wristKey] as? Data else { return nil }
        return decodeSnapshot(data)
    }
}
