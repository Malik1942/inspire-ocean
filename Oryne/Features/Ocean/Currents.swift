import Foundation

/// What the app still asks about currents now that the spatial field has
/// left the phone: which current a thought belongs to and how a concept key
/// reads. The name stays so callers do not move.
enum OceanLayoutEngine {
    /// Stream key for thoughts without themes.
    static let adriftKey = "adrift"

    /// Concept keys are stored lowercase; currents wear them in Title Case.
    static func displayLabel(for key: String) -> String {
        key.split(separator: " ")
            .map { $0 == "&" ? "&" : $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// The current a node belongs to. The user's manual move lock
    /// (`anchorThemeKey`) wins over the primary theme.
    static func currentKey(for node: Node) -> String? {
        node.currentKey
    }
}
