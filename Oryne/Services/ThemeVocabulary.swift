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

    /// Only the themes in `entry`'s language, so reuse can never put an
    /// English chip on a Chinese thought (or vice versa): a zh entry that
    /// found "food" in the vocabulary would reuse it verbatim — the reuse
    /// instruction reliably beats the write-in-the-entry's-language one, as
    /// the eval measured — so the cross-language candidates must simply not
    /// be offered. Each language then converges on its own anchor (`food`
    /// / `美食`). Mixed entries follow their dominant script.
    ///
    /// Script split, not language detection: the app is zh-Hans + English,
    /// and Han-vs-Latin is unambiguous where `NLLanguageRecognizer` is
    /// flaky on two-word fragments. An entry counts as Chinese when Han
    /// makes up a third of its letters — Han carries roughly a word per
    /// character, so even a mixed line like "今天吃了个 burger" is
    /// dominantly Chinese while an English sentence quoting one Chinese
    /// word is not.
    static func filtered(_ themes: [String], forEntry entry: String) -> [String] {
        themes.filter { isChinese($0) == isChinese(entry) }
    }

    private static func isChinese(_ text: String) -> Bool {
        var letters = 0, han = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            if scalar.properties.isIdeographic { han += 1 }
        }
        return han * 3 >= letters && han > 0
    }
}
