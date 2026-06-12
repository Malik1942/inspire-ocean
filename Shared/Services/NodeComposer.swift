import Foundation

/// Builds a fully-formed `Node` from raw captured content: detects themes,
/// derives a stable ocean hue, and seeds a clustered position in the field.
///
/// Lives in Shared so the app, branching, seeding, and the share extension all
/// produce identical-looking drifts.
enum NodeComposer {

    static func make(
        kind: NodeKind,
        title: String = "",
        text: String = "",
        transcription: String? = nil,
        linkURLString: String? = nil,
        audioData: Data? = nil,
        imageData: Data? = nil,
        branchType: BranchType? = nil,
        parent: Node? = nil,
        detectThemes: Bool = true
    ) -> Node {
        let basis = [title, text, transcription ?? "", linkURLString ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // Conceptual themes from the synchronous semantic layer, so every
        // surface (share extension, intents, branches) understands before it
        // labels. The async `understand` pass upgrades them with the language
        // model where available.
        let themes = detectThemes ? SemanticThemes.themes(for: basis) : []
        let mood = ThemeDetector.mood(from: basis)
        let seedKey = (themes.first ?? basis).isEmpty ? UUID().uuidString : (themes.first ?? basis)
        let hue = hue(for: seedKey)
        let anchor = fieldAnchor(themeKey: themes.first ?? "", jitterKey: basis + (linkURLString ?? ""))

        let node = Node(
            kind: kind,
            title: title,
            text: text,
            transcription: transcription,
            linkURLString: linkURLString,
            audioData: audioData,
            imageData: imageData,
            themes: themes,
            mood: mood,
            hue: hue,
            fieldX: anchor.x,
            fieldY: anchor.y,
            branchType: branchType,
            parent: parent
        )
        return node
    }

    /// Applies an async-produced understanding to a node consistently with
    /// how `make` composes one: title, themes, mood, and the theme-derived
    /// hue and field anchor, so the fragment regroups with its concept.
    /// `preserveTitle` keeps an existing title (re-theming migrations).
    ///
    /// Ownership contract: the system fills what the user hasn't touched and
    /// never touches what they have. A user-edited title or theme set is
    /// final until the user explicitly asks to re-derive; a pinned node keeps
    /// its field anchor even when its themes regroup.
    static func applyUnderstanding(
        _ understanding: ThoughtUnderstanding,
        to node: Node,
        preserveTitle: Bool = false
    ) {
        if !node.titleEditedByUser,
           !preserveTitle || node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            node.title = understanding.essence
        }
        if !node.themesEditedByUser, !understanding.themes.isEmpty {
            node.themes = understanding.themes
            if let mood = understanding.mood { node.mood = mood }
            let key = understanding.themes.first ?? ""
            node.hue = hue(for: key.isEmpty ? node.id.uuidString : key)
            if !node.positionPinnedByUser {
                let anchor = fieldAnchor(themeKey: key, jitterKey: node.id.uuidString)
                node.fieldX = anchor.x
                node.fieldY = anchor.y
            }
        }
        node.updatedAt = .now
    }

    /// Stable hue in 0...1 derived from a string.
    static func hue(for key: String) -> Double {
        Double(stableHash(key) % 1000) / 1000.0
    }

    /// A clustered, stable position in the normalized field. Fragments that share
    /// a primary theme gather in the same region (idea clusters, §8), with a small
    /// per-node jitter so they don't overlap exactly.
    static func fieldAnchor(themeKey: String, jitterKey: String) -> (x: Double, y: Double) {
        let clusterSeed = themeKey.isEmpty ? jitterKey : themeKey
        let angle = Double(stableHash(clusterSeed) % 360) * .pi / 180
        let radius = 0.18 + Double(stableHash(clusterSeed + "r") % 100) / 100.0 * 0.20

        let cx = 0.5 + cos(angle) * radius
        let cy = 0.5 + sin(angle) * radius

        let jx = (Double(stableHash(jitterKey + "x") % 100) / 100.0 - 0.5) * 0.16
        let jy = (Double(stableHash(jitterKey + "y") % 100) / 100.0 - 0.5) * 0.16

        return (
            x: min(0.94, max(0.06, cx + jx)),
            y: min(0.92, max(0.08, cy + jy))
        )
    }

    /// A deterministic, platform-stable string hash (FNV-1a) — `Hashable` is
    /// seeded per-launch, which would scramble positions between sessions.
    static func stableHash(_ string: String) -> Int {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return Int(hash % UInt64(Int.max))
    }
}
