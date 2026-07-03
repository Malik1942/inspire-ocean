import Foundation

/// The single stillness switch every moving part of the Ocean scene consults.
///
/// Computed once (from Calm Accessibility Mode and the system Reduce Motion
/// setting) and injected into the scene; subsystems ask this value, never the
/// environment. That keeps stillness consistent as later phases add motion:
/// one seam, no scattered checks.
enum MotionPolicy: Equatable {
    /// Drift, breathing, and ambient particles run.
    case full
    /// The water holds still: positions rest, transitions become crossfades.
    case still

    /// Derives the policy the same way the field derives `still` today:
    /// either accessibility signal quiets the water.
    static func current(calm: Bool, reduceMotion: Bool) -> MotionPolicy {
        (calm || reduceMotion) ? .still : .full
    }
}
