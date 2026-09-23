import Foundation

/// An existing current a new thought may join: its key (the exact theme
/// string the Ocean groups by) and a few member titles that show the model
/// what the current is actually about.
struct CurrentCandidate: Equatable, Sendable {
    let key: String
    let examples: [String]
}

/// Lets a new thought join an existing current instead of founding its own.
///
/// Currents group by exact theme strings (`Node.currentKey`), and the
/// on-device model themes each thought in isolation, so it almost never
/// reproduces an existing label: measured 2026-09-22, 0 of 21 clearly
/// related thoughts led with their current's exact label ("The room feels
/// slower when the light turns warm." → "light, warmth", never "light and
/// color"). Embedding similarity can't bridge the gap: the live backend
/// scores unrelated sentences ~0.75 and every thought pair 0.84–0.95.
///
/// So the model is asked one constrained question — which of these currents
/// is this entry about, or none — whose answer can only be an exact key
/// (`FoundationCurrentPicker`). This type is the deterministic rest: which
/// currents are offered, how they are described, and how a pick is folded
/// into the thought's themes. A miss keeps today's behavior (the thought
/// founds its own current); a wrong merge hides it, so every doubtful path
/// resolves to no snap. `Scripts/current-snap-eval` measures the pick.
enum CurrentSnap {

    /// The constrained answer that means "none of these currents".
    static let noneChoice = "none"
    /// Bounds the prompt as the Ocean grows; the smallest currents drop first.
    static let maxCandidates = 24
    /// Member titles shown per current. Examples, not bare labels, are what
    /// keep a shared word from passing as a shared subject ("collecting
    /// unpaid invoices" is not the "collecting" current of saved articles).
    static let examplesPerCurrent = 3

    /// One thought's membership, reduced to what the candidate list needs.
    struct Member {
        let key: String
        let title: String
        let createdAt: Date
    }

    /// The currents offered to a new thought: only those in the entry's own
    /// language, largest first, each with its most recent member titles.
    ///
    /// Per-language currents are structural, not prompted: offered English
    /// currents, the model put a Chinese thought into "light and color", so a
    /// Chinese entry is only ever offered Chinese currents (and vice versa).
    static func candidates(from members: [Member], forEntry entry: String) -> [CurrentCandidate] {
        let entryIsChinese = isChinese(entry)
        let grouped = Dictionary(grouping: members.filter {
            !$0.key.isEmpty
                && $0.key.lowercased() != noneChoice
                && isChinese($0.key) == entryIsChinese
        }, by: \.key)

        return grouped
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .prefix(maxCandidates)
            .map { key, members in
                let examples = members
                    .sorted { $0.createdAt > $1.createdAt }
                    .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .prefix(examplesPerCurrent)
                return CurrentCandidate(key: key, examples: Array(examples))
            }
    }

    /// Folds the model's pick into the thought's themes. A valid pick leads,
    /// so the thought joins that current (layout, hue and field anchor all
    /// follow the first theme); the model's own themes stay as chips. Any
    /// pick that isn't exactly one of the offered keys changes nothing.
    static func resolve(themes: [String], pick: String?, candidates: [CurrentCandidate]) -> [String] {
        guard let pick, pick != noneChoice, candidates.contains(where: { $0.key == pick }) else {
            return themes
        }
        return Array(([pick] + themes.filter { $0 != pick }).prefix(3))
    }

    /// Script split, not language detection: the app is zh-Hans + English,
    /// and Han-vs-Latin is unambiguous where `NLLanguageRecognizer` is flaky
    /// on two-word labels. Text counts as Chinese when Han makes up a third
    /// of its letters (Han carries roughly a word per character), so a mixed
    /// line follows its dominant language.
    static func isChinese(_ text: String) -> Bool {
        var letters = 0, han = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            if scalar.properties.isIdeographic { han += 1 }
        }
        return han > 0 && han * 3 >= letters
    }

    // MARK: Prompt

    /// System instructions for the pick. Shared verbatim by the app and
    /// `Scripts/current-snap-eval`.
    static let instructions = """
    You sort entries from a personal inspiration journal into existing topics. \
    Each topic lists some entries already in it. Choose a topic only when the new \
    entry is about the same subject as those entries. Choose "none" when it is not; \
    sharing a mood or a single word is not enough.
    """

    static func prompt(entry: String, candidates: [CurrentCandidate]) -> String {
        let topics = candidates.map { candidate in
            candidate.examples.isEmpty
                ? "- \(candidate.key)"
                : "- \(candidate.key): " + candidate.examples.map { "\"\($0)\"" }.joined(separator: ", ")
        }
        return "Topics:\n" + topics.joined(separator: "\n") + "\n\nNew entry:\n" + entry
    }
}
