import Foundation
import SwiftData

/// Ambient rediscovery (PRD §12): one forgotten fragment resurfaces per day.
///
/// The pick is made once a day and held (`Hold`, in the App Group defaults),
/// so the Ocean Field, the Home Screen widget, and any other surface all
/// agree on which fragment is resurfacing today, all day.
///
/// The rhythm (v2) keeps rediscovery feeling like memory, not rotation:
/// - **Forgottenness carries most of the weight.** How long since the thought
///   was last met — created or resurfaced — so what rises genuinely comes
///   from the deep, not from a round-robin.
/// - **Echoes.** A thought that shares a current with what the user captured
///   most recently gets a gentle lift — the Ocean brings back what feels
///   connected to what they're exploring now (the promise onboarding makes).
/// - **Rest.** A fragment that actually got met (opened) rests for a couple
///   of weeks before it can rise again, so one loud memory can't loop.
/// - **Daily shimmer.** A small deterministic per-day variation keeps the
///   pick from being a pure ranking, without ever letting the app and the
///   widget disagree.
enum Resurfacing {
    /// Minimum age before a fragment is eligible to resurface.
    static let minimumAge: TimeInterval = 60 * 60 * 24 * 2

    /// How long a met fragment rests before it may rise again.
    static let restAfterMeeting: TimeInterval = 60 * 60 * 24 * 14

    /// The Home Screen widget's kind. The app reloads the widget by it when
    /// today's pick changes; placed widgets are keyed by it, so it never
    /// changes.
    static let widgetKind = "com.inspireocean.app.widgets.resurfacing"

    /// "Let it rest": the thought the user sent back down today. It is
    /// excluded from today's pick (and marked met), so another rises; the
    /// widget reads the same key, so every surface agrees. One per day.
    enum Rest {
        static let idKey = "resurfacing.restedID"
        static let dayKey = "resurfacing.restedDay"

        static func restedID(now: Date = .now, defaults: UserDefaults = FastCapturePreferences.defaults) -> UUID? {
            guard let raw = defaults.string(forKey: idKey), let id = UUID(uuidString: raw),
                  let day = defaults.object(forKey: dayKey) as? Date,
                  Calendar.current.isDate(day, inSameDayAs: now)
            else { return nil }
            return id
        }

        static var restedToday: Bool { restedID() != nil }

        static func rest(_ id: UUID, now: Date = .now, defaults: UserDefaults = FastCapturePreferences.defaults) {
            defaults.set(id.uuidString, forKey: idKey)
            defaults.set(now, forKey: dayKey)
        }
    }

    /// Today's pick holds all day. The scoring reads what moves during a day
    /// (the five newest thoughts, their themes, the clock), so a capture,
    /// archive or delete elsewhere would otherwise re-pick. Each thought that
    /// rises today is kept in order, and the first one still live is today's;
    /// only when none is does the scoring choose again. An undo that brings
    /// an earlier one back brings it back here too.
    private enum Hold {
        static let idsKey = "resurfacing.heldIDs"
        static let dayKey = "resurfacing.heldDay"

        static func heldIDs(now: Date, defaults: UserDefaults) -> [UUID] {
            guard let day = defaults.object(forKey: dayKey) as? Date,
                  Calendar.current.isDate(day, inSameDayAs: now)
            else { return [] }
            return (defaults.stringArray(forKey: idsKey) ?? []).compactMap(UUID.init(uuidString:))
        }

        static func hold(_ id: UUID, now: Date, defaults: UserDefaults) {
            defaults.set((heldIDs(now: now, defaults: defaults) + [id]).map(\.uuidString), forKey: idsKey)
            defaults.set(now, forKey: dayKey)
        }
    }

    /// Today's resurfacing fragment, or nil when the Ocean is too young.
    static func pick(from nodes: [Node], now: Date = .now,
                     defaults: UserDefaults = FastCapturePreferences.defaults) -> Node? {
        // Seeded starter content never resurfaces as if it were a rediscovered
        // thought: the moment only means something when it is the user's own.
        let restedToday = Rest.restedID(now: now, defaults: defaults)
        let live = nodes.filter { !$0.isArchived && !$0.isExample && $0.id != restedToday }
        guard live.count > 3 else { return nil }

        // A thought already chosen today holds while it is live (`Hold`).
        for id in Hold.heldIDs(now: now, defaults: defaults) {
            if let held = live.first(where: { $0.id == id }) { return held }
        }

        let calendar = Calendar.current
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0

        let aged = live.filter { now.timeIntervalSince($0.createdAt) > minimumAge }
        guard !aged.isEmpty else { return nil }

        // Fragments met recently rest — unless everything is resting, in
        // which case the deep past is still better than silence.
        let rested = aged.filter { node in
            guard let met = node.lastResurfacedAt else { return true }
            return calendar.isDate(met, inSameDayAs: now)
                || now.timeIntervalSince(met) > restAfterMeeting
        }
        let pool = rested.isEmpty ? aged : rested

        // The themes of the five newest captures — what the user is
        // exploring now. Sharing one is an echo worth surfacing.
        let recentThemes = Set(
            live.sorted { $0.createdAt > $1.createdAt }
                .prefix(5)
                .flatMap(\.themes)
        )

        func score(_ node: Node) -> Double {
            // Idle time ignores a same-day meeting, so opening today's pick
            // never changes today's pick out from under the widget.
            let lastMet = node.lastResurfacedAt.flatMap {
                calendar.isDate($0, inSameDayAs: now) ? nil : $0
            }
            let lastTouch = max(lastMet ?? .distantPast, node.createdAt)
            let idleDays = min(now.timeIntervalSince(lastTouch) / 86_400, 120)

            var s = (idleDays / 120) * 0.55
            if !recentThemes.isEmpty, !recentThemes.isDisjoint(with: node.themes) {
                s += 0.25
            }
            // Deterministic per-day shimmer: same inputs, same pick, in the
            // field and in the widget.
            s += Double(NodeComposer.stableHash("\(day)·\(node.id.uuidString)") % 1000) / 1000 * 0.20
            return s
        }

        guard let picked = pool.max(by: { score($0) < score($1) }) else { return nil }
        Hold.hold(picked.id, now: now, defaults: defaults)
        return picked
    }

    /// The resurfaced fragment was actually met — rest it for a while so the
    /// rhythm keeps moving through the Ocean instead of looping one memory.
    /// Safe to call repeatedly; today's pick stays stable either way.
    @MainActor
    static func markMet(_ node: Node, context: ModelContext) {
        node.lastResurfacedAt = .now
        try? context.save()
    }
}
