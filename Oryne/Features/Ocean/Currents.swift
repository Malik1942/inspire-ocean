import Foundation

/// One current's kinship to another: their streams overlap because a thought
/// expresses both themes. Strength is how much they share, so kinship can be
/// felt by degree, not just present or absent.
struct CurrentKinship: Hashable {
    let key: String
    let strength: Double
}

/// What the app still asks about currents now that the spatial field has
/// left the phone: which current a thought belongs to, how a concept key
/// reads, and which currents overlap. The name stays so callers do not move.
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

    /// Currents that overlap `key` by shared membership: the same relation
    /// that lets one thought visit more than one stream (a stream shows every
    /// thought whose themes include its concept, or that is anchored to it).
    /// Strength is the Jaccard overlap of the two currents' streams. Only
    /// currents that actually exist as orbs (some thought's primary) are
    /// returned, so the field and the detail row agree. Strongest first;
    /// deterministic, so no seed is involved.
    static func relatedCurrents(to key: String, among nodes: [Node]) -> [CurrentKinship] {
        guard key != adriftKey else { return [] }
        let active = nodes.filter { !$0.isArchived }
        let existing = Set(active.compactMap { currentKey(for: $0) })
        func members(_ k: String) -> Set<UUID> {
            Set(active.filter { $0.themes.contains(k) || $0.anchorThemeKey == k }.map(\.id))
        }
        let mine = members(key)
        guard !mine.isEmpty else { return [] }

        var others = Set<String>()
        for node in active where mine.contains(node.id) {
            for theme in node.themes where theme != key && existing.contains(theme) {
                others.insert(theme)
            }
            if let anchor = node.anchorThemeKey, anchor != key, existing.contains(anchor) {
                others.insert(anchor)
            }
        }

        var result: [CurrentKinship] = []
        for other in others where other != adriftKey {
            let theirs = members(other)
            let shared = mine.intersection(theirs).count
            guard shared > 0 else { continue }
            let union = mine.union(theirs).count
            result.append(CurrentKinship(key: other, strength: Double(shared) / Double(union)))
        }
        return result.sorted {
            $0.strength != $1.strength ? $0.strength > $1.strength : $0.key < $1.key
        }
    }
}
