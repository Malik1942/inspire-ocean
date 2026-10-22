import Foundation
import SwiftData

/// A current as an entity (docs/plans/memory-layer/SPEC.md, layer 2): the
/// thoughts that share a `key` belong to it, and it carries what a bare
/// string could not: a name the user chose, a label per language, a
/// summary, and what was merged into it. Membership stays on the thought
/// (`Node.anchorThemeKey`, read through `Node.currentKey`), so a current is
/// never out of step with its thoughts; `CurrentRegistry.reconcile` creates
/// and removes these rows to match.
@Model
final class Current {
    // CloudKit mirroring: no unique constraints, every stored property defaulted.
    var id: UUID = UUID()
    /// Language-neutral: an English slug ("light-and-color") or, for a
    /// current founded by a Chinese thought no English rendering reached, the
    /// Chinese label itself. `ThoughtReading.slug` makes them.
    var key: String = ""
    var labelEN: String? = nil
    var labelZH: String? = nil
    /// The user's name for it. Final: no pass rewrites it (decision 2).
    var pinnedName: String? = nil
    /// A model-written line on what runs through it (phase 4 fills it).
    var summary: String? = nil
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// Keys of currents merged into this one, oldest merge first.
    var mergedFromKeys: [String] = []

    init(key: String, labelEN: String? = nil, labelZH: String? = nil, pinnedName: String? = nil) {
        self.id = UUID()
        self.key = key
        self.labelEN = labelEN
        self.labelZH = labelZH
        self.pinnedName = pinnedName
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// What the user reads: their own name, else the label in their
    /// language, else the other language's, else the key made readable.
    func name(preferringChinese: Bool) -> String {
        CurrentKey.name(pinnedName: pinnedName, labelEN: labelEN, labelZH: labelZH, key: key, preferringChinese: preferringChinese)
    }
}

/// How keys read when nothing better is known.
enum CurrentKey {
    /// The one naming rule, shared by the row and the in-memory directory.
    static func name(pinnedName: String?, labelEN: String?, labelZH: String?, key: String, preferringChinese: Bool) -> String {
        if let pinnedName, !pinnedName.isEmpty { return pinnedName }
        let preferred = preferringChinese ? (labelZH ?? labelEN) : (labelEN ?? labelZH)
        if let preferred, !preferred.isEmpty { return humanized(preferred) }
        return humanized(key)
    }

    private static let smallWords: Set<String> = ["and", "of", "the", "in", "on", "at", "to", "a", "an"]

    /// "light-and-color" and "light & color" both read "Light and Color";
    /// a Chinese key reads as it is.
    static func humanized(_ key: String) -> String {
        let words = key
            .split(whereSeparator: { $0 == "-" || $0 == " " })
            .map(String.init)
        guard !words.isEmpty else { return key }
        return words.enumerated().map { index, word in
            if word == "&" { return "&" }
            if index > 0, smallWords.contains(word.lowercased()) { return word.lowercased() }
            return word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}
