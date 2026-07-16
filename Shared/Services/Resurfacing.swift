import Foundation
import SwiftData

/// Ambient rediscovery (PRD §12): one forgotten fragment resurfaces per day.
///
/// The pick is deterministic for a given day, so the Ocean Field, the Home
/// Screen widget, and any other surface all agree on which fragment is
/// resurfacing today.
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

    /// Today's resurfacing fragment, or nil when the Ocean is too young.
    static func pick(from nodes: [Node], now: Date = .now) -> Node? {
        // Seeded starter content never resurfaces as if it were a rediscovered
        // thought: the moment only means something when it is the user's own.
        let live = nodes.filter { !$0.isArchived && !$0.isExample }
        guard live.count > 3 else { return nil }

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
            // Deterministic per-day shimmer: same inputs, same pick — in the
            // field, in the widget, all day.
            s += Double(NodeComposer.stableHash("\(day)·\(node.id.uuidString)") % 1000) / 1000 * 0.20
            return s
        }

        return pool.max { score($0) < score($1) }
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
