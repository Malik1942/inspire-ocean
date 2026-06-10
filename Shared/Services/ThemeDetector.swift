import Foundation
import NaturalLanguage

/// Lightweight, on-device theme detection used at capture time.
///
/// This is intentionally cheap and explainable (Risk mitigation: *AI behavior
/// should remain explainable and evidence-based*). It extracts salient nouns
/// and lemmatizes them into a small set of recurring themes.
enum ThemeDetector {

    /// Nouns too generic to be a meaningful theme.
    private static let genericNouns: Set<String> = [
        "thing", "things", "stuff", "way", "ways", "lot", "lots", "kind", "sort",
        "people", "person", "time", "times", "day", "today", "tomorrow", "yesterday",
        "idea", "ideas", "note", "notes", "something", "anything", "everything",
        "one", "ones", "bit", "part", "parts", "moment", "place", "thingy"
    ]

    /// Purely grammatical words that carry no meaning on their own. When the
    /// tagger cannot determine the language it tags every token `.otherWord`
    /// and lemmatization is unavailable, so this list carries common
    /// inflections, not just base forms. Words of one or two letters are
    /// already dropped by length. Shared with `SemanticThemes`, which strips
    /// the same words before embedding a thought's content words.
    static let grammaticalWords: Set<String> = [
        // Articles, demonstratives, quantifiers
        "the", "this", "that", "these", "those", "all", "any", "both", "each",
        "either", "neither", "few", "many", "much", "more", "most", "some",
        "such", "other", "another", "same", "own", "every",
        // Pronouns
        "she", "her", "hers", "herself", "him", "his", "himself", "its", "itself",
        "they", "them", "their", "theirs", "themselves", "you", "your", "yours",
        "yourself", "our", "ours", "ourselves", "mine", "myself", "who", "whom",
        "whose", "which", "what", "whatever", "someone", "somebody", "anyone",
        "anybody", "everyone", "everybody", "nothing", "none",
        // Conjunctions, prepositions, adverbs
        "and", "but", "for", "nor", "yet", "because", "while", "until", "unless",
        "though", "although", "about", "above", "across", "after", "against",
        "along", "around", "before", "behind", "below", "beneath", "beside",
        "between", "beyond", "during", "from", "inside", "into", "near", "off",
        "onto", "out", "outside", "over", "past", "through", "toward", "towards",
        "under", "upon", "with", "within", "without",
        "not", "now", "then", "than", "there", "here", "where", "when", "why",
        "how", "again", "almost", "already", "also", "always", "away", "back",
        "even", "ever", "just", "maybe", "never", "often", "only", "once",
        "perhaps", "quite", "rather", "really", "still", "too", "very",
        // Auxiliaries and modals
        "are", "was", "were", "been", "being", "has", "have", "had", "having",
        "does", "did", "doing", "done", "can", "cannot", "could", "will",
        "would", "shall", "should", "may", "might", "must"
    ]

    /// Common light verbs: too generic to *be* a theme chip, but they still
    /// carry meaning ("returning", "keeps") — so they are excluded from
    /// keyword themes here, while `SemanticThemes` keeps them as embedding
    /// signal. Verbs are already excluded by lexical class when tagging works;
    /// this list covers the no-language fallback path.
    static let lightVerbs: Set<String> = [
        "get", "gets", "getting", "got", "gotten", "keep", "keeps", "keeping",
        "kept", "make", "makes", "making", "made", "take", "takes", "taking",
        "took", "taken", "come", "comes", "coming", "came", "going", "goes",
        "went", "gone", "want", "wants", "wanted", "need", "needs", "needed",
        "try", "tries", "trying", "tried", "use", "uses", "using", "used",
        "say", "says", "saying", "said", "see", "sees", "seeing", "saw", "seen",
        "know", "knows", "knowing", "knew", "known", "think", "thinks",
        "thinking", "thought", "feel", "feels", "feeling", "felt", "seem",
        "seems", "seemed", "let", "lets", "letting", "put", "puts", "putting",
        "look", "looks", "looking", "looked", "give", "gives", "giving", "gave",
        "given", "find", "finds", "finding", "found", "tell", "tells", "telling",
        "told", "ask", "asks", "asking", "asked", "turn", "turns", "turning",
        "turned", "return", "returns", "returning", "returned", "start",
        "starts", "starting", "started", "stop", "stops", "stopping", "stopped"
    ]

    private static let stopwords = genericNouns.union(grammaticalWords).union(lightVerbs)

    static func themes(from text: String, max: Int = 4) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 2 else { return [] }

        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = trimmed

        // On short captures language detection can fail; the tagger then marks
        // every token `.otherWord` (so articles and verbs leak through as
        // "themes") and lemmatization returns nil. Fall back to English so
        // function words get a real lexical class and are excluded.
        if tagger.dominantLanguage == nil {
            tagger.setLanguage(.english, range: trimmed.startIndex..<trimmed.endIndex)
        }

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

            let raw = word.lowercased()
            // Prefer the lemma so "drawings" and "drawing" collapse together.
            let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue.lowercased()
            let token = lemma ?? raw

            // Check the raw word as well as the lemma: when lemmatization is
            // unavailable the inflected form is all we have.
            guard token.count > 2,
                  !stopwords.contains(token),
                  !stopwords.contains(raw),
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
