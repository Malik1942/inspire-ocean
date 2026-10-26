import Foundation
import SwiftData
import CoreData

/// Keeps the wrist's snapshot current (watch redesign spec §2): rebuilt
/// after every save to the store and every change CloudKit brings in,
/// coalesced, and sent only when it differs from the last one sent. The
/// watch also asks for one each time it comes on screen (`publish()`), which
/// is what brings Today on a day the phone app wasn't opened.
@MainActor
final class WristSnapshotPublisher {
    static let coalescing: Duration = .seconds(2)

    private let context: ModelContext
    private let defaults: UserDefaults
    private let link: WatchLink
    private var lastSent: WristSnapshot?
    private var pending: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(context: ModelContext, defaults: UserDefaults, link: WatchLink) {
        self.context = context
        self.defaults = defaults
        self.link = link
    }

    /// Listens for local saves (a new thought, an edit, a delete, a title or
    /// summary landing) and for CloudKit bringing in another device's change.
    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [ModelContext.didSave, Notification.Name.NSPersistentStoreRemoteChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        }
    }

    /// One publish for a burst of saves.
    func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.coalescing)
            guard !Task.isCancelled else { return }
            self?.publish()
        }
    }

    /// Builds the snapshot now, and sends it when it differs from the last
    /// one sent. Returned for a watch that asked.
    @discardableResult
    func publish(now: Date = .now) -> WristSnapshot {
        let snapshot = build(now: now)
        if !snapshot.hasSameContent(as: lastSent) {
            link.send(snapshot)
            lastSent = snapshot
        }
        return snapshot
    }

    func audio(for id: UUID) -> Data? {
        node(id)?.audioData
    }

    /// Today's thought was opened on the wrist: met, as an open on the phone
    /// is. The save publishes a fresh snapshot.
    func markMet(_ id: UUID) {
        guard let node = node(id) else { return }
        Resurfacing.markMet(node, context: context)
    }

    /// Only the newest wrist takes become sources: reading `audioData` loads
    /// the recording, so the rest are counted by ID alone.
    private func build(now: Date) -> WristSnapshot {
        let ids = Array(ImportLedger.load(from: defaults).entries.keys)
        let placeholders = VoiceUnderstanding.whisperPlaceholders
        let wrist = (try? context.fetch(FetchDescriptor<Node>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        let newest = wrist
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(WristSnapshotBuilder.recentLimit)
            .map { WristSnapshotBuilder.Source(node: $0, placeholders: placeholders) }
        let everything = (try? context.fetch(FetchDescriptor<Node>())) ?? []
        let today = Resurfacing.pick(from: everything, now: now)
        return WristSnapshotBuilder.build(
            ledgerIDs: Set(ids),
            liveIDs: Set(wrist.map(\.id)),
            recent: Array(newest),
            today: today.map { WristSnapshotBuilder.Source(node: $0, placeholders: placeholders) },
            now: now
        )
    }

    private func node(_ id: UUID) -> Node? {
        try? context.fetch(FetchDescriptor<Node>(predicate: #Predicate { $0.id == id })).first
    }
}
