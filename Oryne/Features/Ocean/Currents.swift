import Foundation

/// What the app still asks about currents now that the spatial field has
/// left the phone: which current a thought belongs to and how a concept key
/// reads. The name stays so callers do not move.
enum OceanLayoutEngine {
    /// Stream key for thoughts without themes.
    static let adriftKey = "adrift"

    /// A current's name for its key: the user's, else a label in their
    /// language, else the key made readable (`CurrentDirectory`).
    static func displayLabel(for key: String) -> String {
        CurrentDirectory.shared.name(for: key)
    }

    /// The current a node belongs to. The user's manual move lock
    /// (`anchorThemeKey`) wins over the primary theme.
    static func currentKey(for node: Node) -> String? {
        node.currentKey
    }
}
