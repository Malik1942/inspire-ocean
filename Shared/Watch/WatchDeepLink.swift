import Foundation

/// `oryne://watch/catch`: the complication's way into a hot mic. The phone's
/// `AppState.handleDeepLink` ignores the `watch` host.
enum WatchDeepLink {
    static let catchURL = URL(string: "oryne://watch/catch")!

    static func isCatch(_ url: URL) -> Bool {
        url.scheme == "oryne" && url.host == "watch" && url.path == "/catch"
    }
}
