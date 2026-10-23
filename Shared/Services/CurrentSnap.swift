import Foundation
import NaturalLanguage

/// An existing current a new thought may join: its key (the exact theme
/// string the Ocean groups by) and a few member titles that show the model
/// what the current is actually about.
struct CurrentCandidate: Equatable, Sendable {
    let key: String
    let examples: [String]
    /// How the current reads to the model; the key when no label is known.
    var label: String = ""

    init(key: String, examples: [String], label: String = "") {
        self.key = key
        self.examples = examples
        self.label = label
    }
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
        /// The current's name as the entry's language reads it, if known.
        var label: String = ""

        init(key: String, title: String, createdAt: Date, label: String = "") {
            self.key = key
            self.title = title
            self.createdAt = createdAt
            self.label = label
        }
    }

    /// The currents offered to a new thought: every current of two or more
    /// thoughts, largest first, each with its most recent member titles, and
    /// a one-thought current only when the entry shares a word with its
    /// title or label. One Ocean across languages (SPEC decision 3): a
    /// Chinese thought about light belongs with "light and color".
    ///
    /// The one-thought rule is structural: measured 2026-10-22, the model
    /// filed a run under a single "Night train to Lisbon" and a job worry
    /// under a single "Why strangers' opinions", and word vectors could not
    /// tell those from true joins (0.69 against 0.53 and up). Two thoughts
    /// earn a current the right to attract; one has to be named.
    static func candidates(from members: [Member], forEntry entry: String) -> [CurrentCandidate] {
        let grouped = Dictionary(grouping: members.filter {
            !$0.key.isEmpty && $0.key.lowercased() != noneChoice
        }, by: \.key)
        let entryWords = contentWords(entry)

        return grouped
            .filter { key, members in
                members.count >= 2 || members.contains { member in
                    !entryWords.isDisjoint(with: contentWords(member.title))
                        || !entryWords.isDisjoint(with: contentWords(member.label.isEmpty ? key.replacingOccurrences(of: "-", with: " ") : member.label))
                }
            }
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .prefix(maxCandidates)
            .map { key, members in
                let examples = members
                    .sorted { $0.createdAt > $1.createdAt }
                    .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .prefix(examplesPerCurrent)
                let label = members.first(where: { !$0.label.isEmpty })?.label ?? ""
                return CurrentCandidate(key: key, examples: Array(examples), label: label)
            }
    }

    /// The key the thought joins: the model's pick when it is exactly one of
    /// the offered keys, else nil. Any other answer, including "none", is no
    /// snap, and the thought founds its own current. With the entry given,
    /// the pick must also be plausible (`plausible(entry:candidate:)`).
    static func joinKey(pick: String?, candidates: [CurrentCandidate], entry: String? = nil) -> String? {
        guard let pick, pick != noneChoice, let candidate = candidates.first(where: { $0.key == pick }) else { return nil }
        if let entry, !plausible(entry: entry, candidate: candidate) { return nil }
        return pick
    }

    // MARK: Plausibility

    /// Word vectors in one space for the check below.
    static let finder = EmbeddingService(
        primary: DualLanguageEmbeddingBackend(),
        fallback: DualLanguageEmbeddingBackend()
    )
    /// Word-vector similarity below which an entry and a current's example
    /// share no ground (unrelated sentence pairs measured at most 0.29 on
    /// 2026-10-22), and the higher bar a bare label must clear, since one
    /// word sits moderately near every sentence.
    static let exampleFloor = 0.45
    static let labelFloor = 0.55

    /// A pick stands when the entry shares ground with the current in the
    /// entry's own script: a content word with an example or the label, or
    /// word-vector similarity above the floor (examples first, the label
    /// only when no example is in the entry's script). A current with
    /// nothing in the entry's script cannot be checked and is allowed (the
    /// cross-language join). Measured 2026-10-22 on one-thought currents:
    /// the model filed a run under travel, invoices under errands, a job
    /// worry under self-worth.
    static func plausible(entry: String, candidate: CurrentCandidate) -> Bool {
        let entryChinese = isChinese(entry)
        let examples = candidate.examples.filter { !$0.isEmpty && isChinese($0) == entryChinese }
        let labels = [candidate.label, candidate.key.replacingOccurrences(of: "-", with: " ")]
            .filter { !$0.isEmpty && isChinese($0) == entryChinese }
        guard !examples.isEmpty || !labels.isEmpty else { return true }
        let entryWords = contentWords(entry)
        for text in examples + labels where !entryWords.isDisjoint(with: contentWords(text)) { return true }
        if !examples.isEmpty {
            return examples.contains { finder.similarity(entry, $0) >= exampleFloor }
        }
        return labels.contains { finder.similarity(entry, $0) >= labelFloor }
    }

    /// Lowercased words of four letters or more, or two or more Han characters.
    static func contentWords(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = lowered
        var words = Set<String>()
        tokenizer.enumerateTokens(in: lowered.startIndex..<lowered.endIndex) { range, _ in
            let token = String(lowered[range])
            let cjk = token.unicodeScalars.contains { $0.properties.isIdeographic }
            if token.count >= (cjk ? 2 : 4) { words.insert(token) }
            return true
        }
        return words
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
    entry is about the same specific subject as those entries, not merely the same \
    area of life. Choose "none" when it is not, or when you are unsure; sharing a \
    mood or a single word is not enough.
    """

    static func prompt(entry: String, candidates: [CurrentCandidate]) -> String {
        let topics = candidates.map { candidate in
            // The key is the answer; a label, when it differs, is how it reads.
            let head = candidate.label.isEmpty || candidate.label == candidate.key
                ? candidate.key
                : "\(candidate.key) (\(candidate.label))"
            return candidate.examples.isEmpty
                ? "- \(head)"
                : "- \(head): " + candidate.examples.map { "\"\($0)\"" }.joined(separator: ", ")
        }
        return "Topics:\n" + topics.joined(separator: "\n") + "\n\nNew entry:\n" + entry
    }
}
