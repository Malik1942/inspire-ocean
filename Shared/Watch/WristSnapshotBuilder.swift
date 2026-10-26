import Foundation

/// Builds the wrist snapshot from plain values, never `Node` (the watch
/// compiles this folder and has no store), so the rules are tested here.
/// The phone's `WristSnapshotPublisher` turns its thoughts into `Source`s.
enum WristSnapshotBuilder {
    /// As many wrist takes as the watch keeps confirmed.
    static let recentLimit = TakeQueueState.confirmedKept
    /// The phone summarizes a whisper this long (`CaptureSession.summaryThreshold`),
    /// so a cut mostly means its summary hasn't landed yet.
    static let readingLimit = 240

    /// One thought as the phone holds it, reduced to what the wrist needs.
    struct Source: Equatable {
        var id: UUID
        /// Already without the placeholder (`WhisperRules.name`).
        var title: String?
        /// A machine reading: a long whisper's summary, or a link's page summary.
        var summary: String?
        /// The thought's own words: its transcript, or its text.
        var words: String?
        var isVoice: Bool
        var hasAudio: Bool
        var createdAt: Date
    }

    /// `ledgerIDs`: every wrist take the phone has imported. `liveIDs`: those
    /// still in the store. `recent`: sources for the newest live takes (more
    /// than the limit is fine; anything not in the ledger is left out).
    static func build(
        ledgerIDs: Set<UUID>, liveIDs: Set<UUID>, recent: [Source], today: Source?, now: Date
    ) -> WristSnapshot {
        let newest = recent
            .filter { ledgerIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(recentLimit)
            .map(thought(from:))
        return WristSnapshot(
            recent: Array(newest),
            today: today.map(thought(from:)),
            todayDay: today == nil ? nil : now,
            deletedIDs: ledgerIDs.subtracting(liveIDs).sorted { $0.uuidString < $1.uuidString },
            generatedAt: now
        )
    }

    /// The summary when there is one; otherwise the user's own current
    /// words, cut at the limit. The user's text is never summarized here.
    static func thought(from source: Source) -> WristThought {
        let words = trimmed(source.words)
        var thought = WristThought(id: source.id, title: source.title, createdAt: source.createdAt)
        thought.isVoice = source.isVoice
        thought.hasAudio = source.hasAudio
        thought.hasTranscript = source.isVoice && words != nil
        if let summary = trimmed(source.summary) {
            thought.reading = summary
            thought.readingIsSummary = true
        } else if let words {
            let (reading, continues) = cut(words, limit: readingLimit)
            thought.reading = reading
            thought.continues = continues
        }
        return thought
    }

    /// Cuts at the last space in the second half of the limit (a word
    /// boundary), else at the limit itself (Chinese has no spaces).
    static func cut(_ text: String, limit: Int) -> (String, Bool) {
        guard text.count > limit else { return (text, false) }
        let head = text.prefix(limit)
        if let space = head.lastIndex(where: \.isWhitespace),
           head.distance(from: head.startIndex, to: space) >= limit / 2 {
            return (String(head[..<space]).trimmingCharacters(in: .whitespacesAndNewlines), true)
        }
        return (String(head).trimmingCharacters(in: .whitespacesAndNewlines), true)
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
