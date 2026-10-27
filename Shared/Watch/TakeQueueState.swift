import Foundation

/// Where a wrist take stands on its way to the Ocean.
enum TakeStatus: String, Codable {
    /// Not yet in iCloud or confirmed: the watch holds the only copy it can count on.
    case onWatch
    /// Safe in the iCloud inbox; the phone hasn't confirmed it yet.
    case inICloud
    /// The phone says it's in the Ocean.
    case confirmed
}

/// The WatchConnectivity handoff for one take.
enum PhoneTransfer: String, Codable {
    /// Not handed to WatchConnectivity (never, or a failed attempt).
    case notSent
    /// Queued with the system, which still reads the file.
    case pending
    /// The system reports the file reached the phone.
    case delivered
}

struct QueuedTake: Codable, Equatable, Identifiable {
    var take: WatchTake
    var status: TakeStatus = .onWatch
    var phoneTransfer: PhoneTransfer = .notSent
    /// Whether the phone was reachable when the take was caught. A take
    /// caught out of reach goes to the iCloud inbox at once.
    var phoneReachableAtStop: Bool
    var title: String? = nil
    /// The phone has a transcript for it, so its audio here may expire as
    /// the phone's does.
    var hasTranscript: Bool = false

    var id: UUID { take.id }
}

extension QueuedTake {
    private enum CodingKeys: String, CodingKey {
        case take, status, phoneTransfer, phoneReachableAtStop, title, hasTranscript
    }

    /// Fields added after an index was written decode to their defaults, so
    /// an index from an earlier version still loads (and its takes stay).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        take = try container.decode(WatchTake.self, forKey: .take)
        status = try container.decodeIfPresent(TakeStatus.self, forKey: .status) ?? .onWatch
        phoneTransfer = try container.decodeIfPresent(PhoneTransfer.self, forKey: .phoneTransfer) ?? .notSent
        phoneReachableAtStop = try container.decode(Bool.self, forKey: .phoneReachableAtStop)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        hasTranscript = try container.decodeIfPresent(Bool.self, forKey: .hasTranscript) ?? false
    }
}

/// The watch's queue of takes as pure state. Every rule about what to send,
/// what to keep, and what is safe to delete lives here so it can be tested
/// without a watch; `TakeQueue` on the watch persists it and acts on it.
struct TakeQueueState: Codable, Equatable {
    /// Confirmed takes kept for the status line and the last title.
    static let confirmedKept = 20
    /// How long a take may wait for the phone before also going to iCloud.
    static let cloudFallbackDelay: TimeInterval = 120

    /// How long to wait before trying the iCloud fallback again for a take
    /// whose upload already failed.
    static let cloudRetryInterval: TimeInterval = 15 * 60

    /// How long the watch keeps a transcribed take's audio: the phone's own
    /// retention (`OryneApp.expireConfirmedAudio`), so the wrist's copy
    /// never outlives the phone's.
    static let audioRetention: TimeInterval = 30 * 24 * 60 * 60

    /// Oldest first.
    private(set) var takes: [QueuedTake]

    init(takes: [QueuedTake] = []) {
        self.takes = takes
    }

    func item(_ id: UUID) -> QueuedTake? {
        takes.first { $0.id == id }
    }

    mutating func add(_ take: WatchTake, phoneReachableAtStop: Bool) {
        guard item(take.id) == nil else { return }
        takes.append(QueuedTake(take: take, phoneReachableAtStop: phoneReachableAtStop))
    }

    /// Undo: gone from the queue as if never caught.
    mutating func remove(_ id: UUID) {
        takes.removeAll { $0.id == id }
    }

    mutating func markPhoneTransfer(_ id: UUID, _ transfer: PhoneTransfer) {
        update(id) { $0.phoneTransfer = transfer }
    }

    /// Only a take that exists solely on the watch moves to iCloud; a
    /// confirmed take stays confirmed.
    mutating func markInICloud(_ id: UUID) {
        update(id) { if $0.status == .onWatch { $0.status = .inICloud } }
    }

    /// Applies the phone's recent list. Unknown IDs are ignored; a missing
    /// title never erases one the watch already has.
    mutating func apply(_ confirmations: [WatchConfirmation]) {
        for confirmation in confirmations {
            update(confirmation.id) {
                $0.status = .confirmed
                if let title = confirmation.title { $0.title = title }
            }
        }
        prune()
    }

    /// Applies the phone's snapshot: current titles and transcripts for the
    /// takes it lists, and takes the user deleted leave the queue (their
    /// audio with them). Only a confirmed take can leave this way: the phone
    /// can't have deleted a take it never confirmed. A missing title never
    /// erases one the watch already has.
    mutating func apply(_ snapshot: WristSnapshot) {
        for thought in snapshot.recent {
            update(thought.id) {
                $0.hasTranscript = thought.hasTranscript
                if let title = thought.title { $0.title = title }
            }
        }
        let deleted = Set(snapshot.deletedIDs)
        takes.removeAll { $0.status == .confirmed && deleted.contains($0.id) }
    }

    /// Takes to hand to WatchConnectivity: only on the watch and not yet
    /// handed over. (A take in iCloud reaches the phone from there.)
    func needingPhoneSend() -> [QueuedTake] {
        takes.filter { $0.status == .onWatch && $0.phoneTransfer == .notSent }
    }

    /// Takes to upload to the iCloud inbox: still only on the watch, and
    /// either caught out of the phone's reach or waiting too long. The wait
    /// is timed from when the take ended (`createdAt` is when recording
    /// began), so a long take isn't uploaded the moment it's caught.
    func needingCloudUpload(now: Date) -> [QueuedTake] {
        takes.filter {
            let stoppedAt = $0.take.createdAt.addingTimeInterval($0.take.duration)
            return $0.status == .onWatch
                && (!$0.phoneReachableAtStop
                    || now.timeIntervalSince(stoppedAt) >= Self.cloudFallbackDelay)
        }
    }

    /// When the watch should next wake to try the iCloud fallback: when the
    /// earliest waiting take becomes eligible, or `cloudRetryInterval` from
    /// now for takes already eligible (their upload failed), whichever is
    /// sooner. Nil when nothing waits on the watch.
    func nextCloudAttempt(now: Date) -> Date? {
        let waiting = takes.filter { $0.status == .onWatch }
        guard !waiting.isEmpty else { return nil }
        let retry = now.addingTimeInterval(Self.cloudRetryInterval)
        let upcoming = waiting.compactMap { item -> Date? in
            guard item.phoneReachableAtStop else { return nil }
            let eligible = item.take.createdAt.addingTimeInterval(item.take.duration + Self.cloudFallbackDelay)
            return eligible > now ? eligible : nil
        }
        return min(upcoming.min() ?? retry, retry)
    }

    /// Takes that were in `before` and are gone now (Undo, or pruned once
    /// confirmed): their audio leaves with them.
    func idsRemoved(since before: TakeQueueState) -> [UUID] {
        before.takes.map(\.id).filter { item($0) == nil }
    }

    /// Whether the watch may delete this take's audio while the take stays
    /// in the queue. It keeps every recording the wrist can replay; only a
    /// confirmed take with a transcript expires, after `audioRetention`, as
    /// the phone's copy does. A take leaving the queue (Undo, pruning, deleted
    /// on the phone) takes its audio through `TakeQueue.change`. A recording
    /// the queue can't account for (an unreadable index, a crash mid-recording)
    /// is never deleted: guessing wrong loses a caught take.
    func audioDisposable(_ id: UUID, now: Date = .now) -> Bool {
        guard let item = item(id), item.status == .confirmed, item.hasTranscript else { return false }
        return now.timeIntervalSince(item.take.createdAt) > Self.audioRetention
    }

    /// Keeps every unconfirmed take and the newest `confirmedKept` confirmed.
    mutating func prune() {
        let confirmed = takes.filter { $0.status == .confirmed }
        guard confirmed.count > Self.confirmedKept else { return }
        let keep = Set(
            confirmed
                .sorted { $0.take.createdAt > $1.take.createdAt }
                .prefix(Self.confirmedKept)
                .map(\.id)
        )
        takes.removeAll { $0.status == .confirmed && !keep.contains($0.id) }
    }

    private mutating func update(_ id: UUID, _ change: (inout QueuedTake) -> Void) {
        guard let index = takes.firstIndex(where: { $0.id == id }) else { return }
        change(&takes[index])
    }
}
