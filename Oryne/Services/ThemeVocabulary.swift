import Foundation
import SwiftData

/// The themes already living in the ocean, handed to `understand(_:existingThemes:)`
/// so a model-backed interpretation can *reuse* an existing theme rather than
/// coin a near-synonym of it. Currents group by exact theme-string equality
/// (`OceanLayoutEngine`), so "food curiosity" and "food" become separate
/// currents even though they mean the same thing; reuse is what keeps related
/// thoughts converging into one current.
enum ThemeVocabulary {
    /// Distinct themes across the visible ocean, most-used first so the prompt
    /// leads with the currents a new thought is most likely to belong to.
    /// Archived and example thoughts are excluded — they aren't part of the
    /// user's living vocabulary. Capped so the prompt stays bounded as the
    /// ocean grows; the long tail of one-off themes is the least reusable.
    static func current(in context: ModelContext, limit: Int = 40) -> [String] {
        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { !$0.isArchived })
        guard let nodes = try? context.fetch(descriptor) else { return [] }

        var counts: [String: Int] = [:]
        for node in nodes where !node.isExample {
            for theme in node.themes { counts[theme, default: 0] += 1 }
        }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map(\.key)
    }
}
