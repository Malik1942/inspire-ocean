import Foundation

/// Ambient rediscovery (PRD §12): one forgotten fragment resurfaces per day.
///
/// The pick is deterministic for a given day, so the Ocean Field, the Home
/// Screen widget, and any other surface all agree on which fragment is
/// resurfacing today.
enum Resurfacing {
    /// Minimum age before a fragment is eligible to resurface.
    static let minimumAge: TimeInterval = 60 * 60 * 24 * 2

    /// Today's resurfacing fragment, or nil when the Ocean is too young.
    static func pick(from nodes: [Node], now: Date = .now) -> Node? {
        guard nodes.count > 3 else { return nil }
        let older = nodes
            .filter { now.timeIntervalSince($0.createdAt) > minimumAge }
            .sorted { $0.createdAt < $1.createdAt }
        guard !older.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: now) ?? 0
        return older[day % older.count]
    }
}
