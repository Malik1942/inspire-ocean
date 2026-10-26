import Foundation

/// One row on the wrist's Today or Recent page, and the thought it opens.
struct WristRow: Hashable, Identifiable {
    enum Audio: Hashable {
        /// The watch still holds the recording.
        case watch
        /// The phone holds it and sends it on request.
        case phone
        /// Nothing to play: no control.
        case none
    }

    var id: UUID
    /// Nil until the phone names it: the row shows the time it was caught.
    var title: String?
    var caughtAt: Date
    /// The take's length; nil for a thought the watch has no take for.
    var duration: TimeInterval?
    /// Still only on the watch: "Waiting for iPhone".
    var isWaiting: Bool
    var reading: String?
    var readingIsSummary: Bool
    var continues: Bool
    var isVoice: Bool
    var audio: Audio
    /// Opened from Today: opening it tells the phone it was met.
    var isToday: Bool
}

/// The wrist's Today and Recent rows, from the queue (what the watch caught)
/// and the phone's snapshot (what those takes are now). Pure, so the rules
/// are tested without a watch.
enum WristRecent {
    /// Every take still in the queue, whatever its state (a take on the
    /// watch or in iCloud is never hidden for want of a snapshot), and every
    /// take the snapshot lists; never one the phone deleted. Newest first.
    static func rows(queue: TakeQueueState, snapshot: WristSnapshot?, hasLocalAudio: (UUID) -> Bool) -> [WristRow] {
        let deleted = Set(snapshot?.deletedIDs ?? [])
        var rows: [WristRow] = []
        var listed: Set<UUID> = []
        for item in queue.takes where !deleted.contains(item.id) {
            rows.append(row(
                thought: snapshot?.recentThought(item.id), id: item.id, fallbackTitle: item.title,
                caughtAt: item.take.createdAt, duration: item.take.duration, isWaiting: item.status == .onWatch,
                isVoice: true, hasLocalAudio: hasLocalAudio(item.id), isToday: false
            ))
            listed.insert(item.id)
        }
        for thought in snapshot?.recent ?? [] where !listed.contains(thought.id) {
            rows.append(row(
                thought: thought, id: thought.id, fallbackTitle: nil, caughtAt: thought.createdAt,
                duration: nil, isWaiting: false, isVoice: thought.isVoice,
                hasLocalAudio: hasLocalAudio(thought.id), isToday: false
            ))
        }
        return rows.sorted { $0.caughtAt > $1.caughtAt }
    }

    /// Today's resurfaced thought, only on the day the phone picked it.
    static func today(
        snapshot: WristSnapshot?, queue: TakeQueueState, now: Date,
        calendar: Calendar = .current, hasLocalAudio: (UUID) -> Bool
    ) -> WristRow? {
        guard let thought = snapshot?.today(on: now, calendar: calendar) else { return nil }
        return row(
            thought: thought, id: thought.id, fallbackTitle: nil, caughtAt: thought.createdAt,
            duration: queue.item(thought.id)?.take.duration, isWaiting: false, isVoice: thought.isVoice,
            hasLocalAudio: hasLocalAudio(thought.id), isToday: true
        )
    }

    private static func row(
        thought: WristThought?, id: UUID, fallbackTitle: String?, caughtAt: Date, duration: TimeInterval?,
        isWaiting: Bool, isVoice: Bool, hasLocalAudio: Bool, isToday: Bool
    ) -> WristRow {
        let audio: WristRow.Audio = hasLocalAudio ? .watch : (thought?.hasAudio == true ? .phone : .none)
        return WristRow(
            id: id, title: thought?.title ?? fallbackTitle, caughtAt: caughtAt, duration: duration,
            isWaiting: isWaiting, reading: thought?.reading, readingIsSummary: thought?.readingIsSummary ?? false,
            continues: thought?.continues ?? false, isVoice: isVoice, audio: audio, isToday: isToday
        )
    }
}
