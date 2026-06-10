import Foundation
import NaturalLanguage

/// Lightweight, on-device theme detection used at capture time.
///
/// This is intentionally cheap and explainable (Risk mitigation: *AI behavior
/// should remain explainable and evidence-based*). It extracts salient nouns
/// and lemmatizes them into a small set of recurring themes.
enum ThemeDetector {

    private static let stopwords: Set<String> = [
        "thing", "things", "stuff", "way", "ways", "lot", "lots", "kind", "sort",
        "people", "person", "time", "times", "day", "today", "tomorrow", "yesterday",
        "idea", "ideas", "note", "notes", "something", "anything", "everything",
        "one", "ones", "bit", "part", "parts", "moment", "place", "thingy"
    ]

    static func themes(from text: String, max: Int = 4) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 2 else { return [] }

        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = trimmed

        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .omitOther]
        var counts: [String: Int] = [:]
        var order: [String] = []

        tagger.enumerateTags(
            in: trimmed.startIndex..<trimmed.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: options
        ) { tag, range in
            guard let tag, tag == .noun || tag == .otherWord else { return true }

            let word = String(trimmed[range])
            guard word.count > 2 else { return true }

            // Prefer the lemma so "drawings" and "drawing" collapse together.
            let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
            let token = (lemma ?? word).lowercased()

            guard token.count > 2,
                  !stopwords.contains(token),
                  token.rangeOfCharacter(from: .letters) != nil
            else { return true }

            if counts[token] == nil { order.append(token) }
            counts[token, default: 0] += 1
            return true
        }

        let ranked = order.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        return Array(ranked.prefix(max))
    }

    /// A very small valence heuristic used only as a soft "emotional pattern"
    /// signal in the Ocean. Returns nil when there is no clear signal.
    static func mood(from text: String) -> String? {
        let lowered = text.lowercased()
        let positive = ["love", "excited", "joy", "beautiful", "hope", "calm", "grateful", "wonder", "play", "light"]
        let restless = ["stuck", "anxious", "tired", "lost", "confused", "doubt", "afraid", "heavy", "dark", "worry"]
        let pos = positive.filter { lowered.contains($0) }.count
        let neg = restless.filter { lowered.contains($0) }.count
        if pos == 0 && neg == 0 { return nil }
        return pos >= neg ? "bright" : "deep"
    }
}
