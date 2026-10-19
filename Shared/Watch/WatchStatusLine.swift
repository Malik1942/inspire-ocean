import Foundation

/// The one status line under the record disc, derived from the queue so it
/// can never claim more than is true (PHILOSOPHY §3: nothing untrue, by words
/// or by omission). The watch view turns each case into localized words.
enum WatchStatusLine: Equatable {
    /// Nothing ever caught: no line at all.
    case empty
    /// Takes not yet in iCloud or confirmed (the watch holds the only copy it can count on).
    case waiting(count: Int)
    /// Nothing is only on the watch, but not everything is confirmed.
    case onItsWay
    /// The phone has confirmed every take.
    case inOcean

    static func derive(from state: TakeQueueState) -> WatchStatusLine {
        let onWatch = state.takes.filter { $0.status == .onWatch }.count
        if onWatch > 0 { return .waiting(count: onWatch) }
        if state.takes.contains(where: { $0.status == .inICloud }) { return .onItsWay }
        if state.takes.contains(where: { $0.status == .confirmed }) { return .inOcean }
        return .empty
    }

    /// The title of the newest confirmed take, once the phone has named it.
    /// Nil while that take is unnamed: an older title would describe the
    /// wrong thought.
    static func lastTitle(from state: TakeQueueState) -> String? {
        state.takes
            .filter { $0.status == .confirmed }
            .max { $0.take.createdAt < $1.take.createdAt }?
            .title
    }
}
