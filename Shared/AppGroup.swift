import Foundation

/// The App Group shared by every Oryne target — the phone app, the share
/// extension, the widgets, and the watch. Frozen pre-rebrand (Inspire Ocean):
/// renaming it would orphan the shared container every surface reads and
/// writes, so it lives in one place that all targets compile rather than as a
/// literal copied per target.
enum AppGroup {
    static let identifier = "group.com.inspireocean.shared"

    /// The shared container, or `nil` on an unsigned build (no entitlement) —
    /// callers fall back to app-local storage exactly as the phone's
    /// persistence stack does.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
