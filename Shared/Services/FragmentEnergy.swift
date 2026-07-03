import Foundation

/// The liveliness of a fragment in the Ocean, derived purely from recency.
///
/// Energy is a function of time, never stored: persisting it would go stale
/// within hours and churn CloudKit sync for no reason. The same inputs give
/// the same answer on every surface, which keeps the app and the widgets in
/// agreement (the same reasoning behind `Resurfacing.pick` and the layout's
/// prominence).
///
/// The scene maps energy to buoyancy, glow warmth, and drift amplitude and
/// speed: a thought captured today floats higher and glows warmer than one
/// from a month ago, and an old thought never goes fully still.
enum FragmentEnergy {

    /// Days for a fragment's energy to halve.
    static let halfLifeDays: Double = 7

    /// Old fragments keep breathing faintly; the water is never dead.
    static let floor: Double = 0.15

    /// Energy in 0...1 for a fragment captured at `createdAt`.
    static func energy(createdAt: Date, now: Date = .now) -> Double {
        let ageDays = max(0, now.timeIntervalSince(createdAt)) / 86_400
        let decayed = exp(-log(2.0) * ageDays / halfLifeDays)
        return min(1, max(floor, decayed))
    }
}
