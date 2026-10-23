import Foundation

/// The deterministic half of reading a thought into its understanding
/// record (docs/plans/memory-layer/SPEC.md, layer 1): the version stamp,
/// the language split, the slugs that make theme keys language-neutral,
/// and the cleaning of what the model returns. The model half is
/// `FoundationThoughtReader`; the two are compiled together by
/// `Scripts/understanding-eval`, so the prompt under test is the app's own.
enum ThoughtReading {

    /// Bump when the record's fields or the reader's prompt change in a way
    /// that makes earlier records worth redoing. Thoughts below this version
    /// are enriched on a later Library open (`UnderstandingBackfill`).
    static let version = 1

    static let maxThemes = 3
    static let maxEntities = 4
    static let maxGistLength = 160

    // MARK: Language

    /// Which language a thought is written in. Han carries about a word per
    /// character and Latin about five letters a word, so the split is by
    /// words, not letters: a Chinese note with one English product name is
    /// Chinese, a half-and-half line is mixed.
    static func language(of text: String) -> ThoughtLanguage {
        var han = 0, latin = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            if scalar.properties.isIdeographic { han += 1 } else { latin += 1 }
        }
        if han == 0 { return .en }
        if latin == 0 { return .zh }
        let hanWords = Double(han)
        let latinWords = Double(latin) / 5
        let hanShare = hanWords / (hanWords + latinWords)
        if hanShare >= 0.8 { return .zh }
        if hanShare <= 0.2 { return .en }
        return .mixed
    }

    /// The language a gist must be in to bridge to the other side.
    static func gistLanguage(for entry: ThoughtLanguage) -> ThoughtLanguage {
        entry == .en ? .zh : .en
    }

    // MARK: Keys

    /// A language-neutral key from a theme label: lowercase, letters and
    /// digits only, one hyphen between words, "&" read as "and". A label
    /// in a non-Latin script passes through lowercased, so a key is never
    /// empty when the label is not ("light & color" → "light-and-color").
    static func slug(_ label: String) -> String {
        let lowered = label.lowercased()
        var out = ""
        var pendingBreak = false
        for scalar in lowered.unicodeScalars {
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                if pendingBreak, !out.isEmpty { out.append("-") }
                pendingBreak = false
                out.unicodeScalars.append(scalar)
            } else if scalar == "&" {
                if !out.isEmpty { out.append("-and") }
                pendingBreak = true
            } else {
                pendingBreak = true
            }
        }
        return out
    }

    /// Keys for a thought's themes: from the model's English rendering when
    /// it gave one, else from the labels themselves. Deduplicated, capped.
    static func keys(fromEnglish english: [String], fallbackLabels labels: [String]) -> [String] {
        let source = english.isEmpty ? labels : english
        var seen = Set<String>()
        var keys: [String] = []
        for label in source {
            let key = slug(label)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            keys.append(key)
        }
        return Array(keys.prefix(maxThemes))
    }

    // MARK: Formal categories

    /// The categories that are a matter of form, decided without the model:
    /// an entry that opens with a quotation mark is a quote, one that ends
    /// with a question mark is a question, a short entry carrying a URL is a
    /// link. The model decides the rest (idea, task, bug, note, memory),
    /// where form says nothing. Measured 2026-10-22: the model called a
    /// quoted Chinese line and a Chinese question both "memory".
    static func formalCategory(for text: String) -> ThoughtCategory? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.first, let last = t.last else { return nil }
        if "\"“「『".contains(first) { return .quote }
        if "?？".contains(last) { return .question }
        if t.count <= 120, t.range(of: "https?://", options: .regularExpression) != nil { return .link }
        return nil
    }

    // MARK: Cleaning the model's record

    private static let edgeTrim = CharacterSet(charactersIn: "\"'“”‘’.,;:。，；：")

    /// Words the model offers as entities that name no one: pronouns and
    /// the writer themself.
    private static let pronounLike: Set<String> = [
        "i", "me", "myself", "self", "we", "us", "you", "they", "them", "author", "writer",
        "我", "我们", "你", "他", "她", "他们", "自己", "大家", "作者"
    ]

    /// Proper names, trimmed and deduplicated case-insensitively, capped. A
    /// Latin entity has to look like a name (a capital, a digit or a dot, as
    /// in "are.na"), so "dentist" and "work" fall out; Han has no capitals,
    /// so a Chinese entity only has to be two characters and not a pronoun.
    static func tidyEntities(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for entity in raw {
            let s = entity
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: edgeTrim)
            let lower = s.lowercased()
            guard !s.isEmpty, s.count <= 40, !pronounLike.contains(lower) else { continue }
            let hasHan = s.unicodeScalars.contains { $0.properties.isIdeographic }
            let looksLikeName = hasHan
                ? s.count >= 2
                : s.contains(where: \.isUppercase) || s.contains(where: \.isNumber) || s.contains(".")
            guard looksLikeName, seen.insert(lower).inserted else { continue }
            out.append(s)
        }
        return Array(out.prefix(maxEntities))
    }

    /// The gist, kept only when its dominant script is the other language's:
    /// a gist in the entry's own language is no bridge, and storing it would
    /// make the thought match itself twice. Dominant script, not a pure
    /// split, because a Chinese gist of an English bug report rightly keeps
    /// "iPhone SE" and "Library" in Latin, and embedding routes by the
    /// dominant language anyway.
    static func tidyGist(_ raw: String?, entryLanguage: ThoughtLanguage) -> String? {
        guard let raw else { return nil }
        var s = raw
            .split(whereSeparator: \.isNewline)
            .first.map(String.init) ?? ""
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.count > maxGistLength { s = String(s.prefix(maxGistLength)) }
        let wantsChinese = gistLanguage(for: entryLanguage) == .zh
        return mostlyChineseByWords(s) == wantsChinese ? s : nil
    }

    /// Whether a line is Chinese by words rather than letters: Han carries
    /// a word per character and Latin about five letters a word, so a
    /// Chinese sentence quoting "iPhone SE" and "Library" still counts as
    /// Chinese even though Latin letters outnumber Han characters.
    static func mostlyChineseByWords(_ text: String) -> Bool {
        var han = 0, latin = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            if scalar.properties.isIdeographic { han += 1 } else { latin += 1 }
        }
        guard han > 0 else { return false }
        return Double(han) >= Double(latin) / 5
    }

    // MARK: Prompt

    /// System instructions for the reader. Shared verbatim by the app and
    /// `Scripts/understanding-eval`. The languages are named per entry in
    /// `prompt(entry:)`, where the small model weighs them most.
    static let instructions = """
    You read one entry from a personal inspiration journal and fill in a record about it. \
    title: at most 6 words (6 to 10 characters when in Chinese), capturing the essence or \
    feeling rather than restating the text; no quotation marks, no trailing punctuation. \
    themes: 1 to 3 conceptual themes, each one to three lowercase words, naming the underlying \
    concept, intention, emotion or domain, never words copied from the entry. \
    themesInEnglish: the same themes in English, in the same order. \
    category, one of: idea, a creative or product idea, a plan for something to make, a \
    brainstorm; task, something the writer has to do; bug, a defect or problem noticed in \
    software or a product; note, a fact or observation about the world, a place, a thing, \
    worth keeping; quote, someone else's words; question, something the writer wonders; \
    link, a saved page or reference; memory, a moment the writer lived through, told as a \
    recollection. A fact about a shop or a schedule is a note, not a memory and not a task. \
    gistInOtherLanguage: one plain sentence saying what the entry is about, in the language \
    the prompt names; never a label, never these instructions. \
    entities: up to 4 names one could look up: a person, a place, a product, a company, a \
    project. Never pronouns, never common nouns such as app, room, work, dentist. Empty when \
    there are none. \
    An entry may carry what the device saw in an attached picture, opening with "Picture of" \
    and "Text in the picture:"; read that as part of the entry, not as the writer's words.
    """

    /// The entry, prefaced with its language and the languages the record
    /// must use, so the model never has to infer them. Title and themes
    /// follow the entry's dominant script (the same rule
    /// `TitleDistiller.speaksLike` checks afterwards); the gist is the other
    /// language.
    static func prompt(entry: String) -> String {
        let language = language(of: entry)
        let entryName: String
        switch language {
        case .en: entryName = "English"
        case .zh: entryName = "Chinese"
        case .mixed: entryName = "a mix of Chinese and English"
        }
        let ownName = dominantScriptIsChinese(entry) ? "Chinese" : "English"
        let gistName = gistLanguage(for: language) == .zh ? "Chinese" : "English"
        return """
        The entry is written in \(entryName). Write title and themes in \(ownName). \
        Write gistInOtherLanguage in \(gistName).

        Entry:
        \(entry)
        """
    }

    /// Han carries a word per character, so a line is Chinese once Han makes
    /// a third of its letters: the split `CurrentSnap.isChinese` and
    /// `TitleDistiller.speaksLike` use, repeated here so the eval script can
    /// compile this file alone.
    static func dominantScriptIsChinese(_ text: String) -> Bool {
        var letters = 0, han = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            if scalar.properties.isIdeographic { han += 1 }
        }
        return han > 0 && han * 3 >= letters
    }
}
