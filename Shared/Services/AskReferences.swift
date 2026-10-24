import Foundation

/// The `[t2]` references the Ask agent cites: found in the model's prose
/// and removed from what the person reads, since the sources are shown
/// under the answer as the thoughts themselves.
enum AskReferences {

    /// Every `[tN]` (also `[t2, t5]`) in the text, in order, as "tN".
    static func references(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\s*(t\d+(?:\s*,\s*t\d+)*)\s*\]"#, options: .caseInsensitive) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).flatMap { match -> [String] in
            guard let group = Range(match.range(at: 1), in: text) else { return [] }
            return text[group]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        }
    }

    /// The prose with each marker resolved, sentence by sentence. In a
    /// sentence where any marker stands in for a noun (a word follows it:
    /// "你记过的 bug 有 [t1] 和 [t2]。"), every marker becomes its thought's
    /// quoted title, so the sentence keeps its nouns; in a sentence where
    /// the markers only cite, at the ends of clauses, they are removed.
    /// Unknown references are removed either way.
    static func resolve(_ text: String, titles: [String: String]) -> String {
        guard let sentences = try? NSRegularExpression(pattern: #"[^.!?。！？\n]*(?:[.!?。！？]+|\n+|$)"#),
              let markers = try? NSRegularExpression(pattern: #"\s*\[\s*(t\d+(?:\s*,\s*t\d+)*)\s*\]"#, options: .caseInsensitive)
        else { return text }
        let ns = text as NSString
        var out = ""
        for sentenceMatch in sentences.matches(in: text, range: NSRange(location: 0, length: ns.length)) where sentenceMatch.range.length > 0 {
            let sentence = ns.substring(with: sentenceMatch.range) as NSString
            let found = markers.matches(in: sentence as String, range: NSRange(location: 0, length: sentence.length))
            guard !found.isEmpty else { out += sentence as String; continue }

            let nounMode = found.contains { match in
                var look = match.range.location + match.range.length
                while look < sentence.length,
                      sentence.substring(with: NSRange(location: look, length: 1)).unicodeScalars.allSatisfy(CharacterSet.whitespaces.contains) {
                    look += 1
                }
                guard look < sentence.length else { return false }
                let next = sentence.substring(with: NSRange(location: look, length: 1))
                return next.unicodeScalars.first.map { CharacterSet.alphanumerics.contains($0) } ?? false
            }

            var cursor = 0
            for match in found {
                out += sentence.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                cursor = match.range.location + match.range.length
                guard nounMode else { continue }
                let names = sentence.substring(with: match.range(at: 1))
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .compactMap { titles[$0] }
                    .map { "“\($0)”" }
                if !names.isEmpty { out += " " + names.joined(separator: ", ") + " " }
            }
            out += sentence.substring(from: cursor)
        }
        return tidy(out)
    }

    /// The prose without its reference markers, and without the space that
    /// held them before punctuation.
    static func strip(from text: String) -> String {
        resolve(text, titles: [:])
    }

    /// The prose without the sentences that stand only on references no
    /// tool handed out: a claim cited to an invented [t99] is the model's,
    /// not the person's, and removing the marker alone would leave the
    /// claim reading as grounded. A sentence that also cites a known
    /// reference stays; it has something real under it.
    static func droppingSentences(citingOnly unknown: Set<String>, from text: String) -> String {
        guard !unknown.isEmpty,
              let sentences = try? NSRegularExpression(pattern: #"[^.!?。！？\n]*(?:[.!?。！？]+|\n+|$)"#)
        else { return text }
        let ns = text as NSString
        var out = ""
        for match in sentences.matches(in: text, range: NSRange(location: 0, length: ns.length)) where match.range.length > 0 {
            let sentence = ns.substring(with: match.range)
            let cited = references(in: sentence)
            let invented = !cited.isEmpty && cited.allSatisfy(unknown.contains)
            if !invented { out += sentence }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tidy(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: #"\s+([,.;:!?，。；：！？])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([“”]) +([，。；：！？、])"#, with: "$1$2", options: .regularExpression)
        s = s.replacingOccurrences(of: #" +([，。；：！？、])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
