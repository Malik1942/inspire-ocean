import Foundation

/// Distills raw fragment content into a short, fully-displayable title.
///
/// Lives in Shared so the app, share extension, and intents all title
/// fragments identically. `LocalOceanAIService` prefers the on-device
/// foundation model and falls back to `essence(from:)`; surfaces without
/// model access (the share extension) call `essence(from:)` directly.
enum TitleDistiller {

    /// Lightly cleans a model-produced title (already short) without truncating meaning.
    static func tidy(_ raw: String) -> String {
        var s = firstLine(of: cleanedQuotes(raw))
        var words = s.split(separator: " ").map(String.init)
        if words.count > 8 { words = Array(words.prefix(8)) }
        s = words.joined(separator: " ")
        if s.count > 48 { s = boundedPrefix(s, 48) }
        return capitalizedFirst(stripTrailingPunctuation(s))
    }

    /// Distills raw content to its essential lead idea — short, readable, and
    /// fully displayable (no ellipsis). A best-effort stand-in for the on-device
    /// model: strip the generic lead-in, keep the lead clause, drop trailing filler.
    static func essence(from raw: String, maxWords: Int = 6, maxChars: Int = 38) -> String {
        var s = stripLeadLabel(firstLine(of: cleanedQuotes(raw)))
        s = leadingClause(s)

        var words = s.split(separator: " ").map(String.init)
        if words.count > maxWords { words = Array(words.prefix(maxWords)) }
        while let last = words.last?.lowercased(), trailingStopwords.contains(last), words.count > 2 {
            words.removeLast()
        }
        s = words.joined(separator: " ")
        if s.count > maxChars { s = boundedPrefix(s, maxChars) }
        s = stripTrailingPunctuation(s)
        return s.isEmpty ? "Untitled drift" : capitalizedFirst(s)
    }

    // MARK: Text helpers

    private static let labelPrefixes = [
        "voice note", "note to self", "screenshot of that", "a screenshot of",
        "screenshot of", "screenshot", "color study", "colour study",
        "half a song lyric", "song lyric", "photo of", "image of"
    ]

    private static let trailingStopwords: Set<String> = [
        "the", "a", "an", "of", "to", "in", "on", "at", "for", "and", "or", "but",
        "with", "that", "this", "my", "your", "as", "if", "so", "by", "from",
        "into", "about", "is", "are", "was", "were"
    ]

    private static func cleanedQuotes(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "")
         .replacingOccurrences(of: "\u{201C}", with: "")
         .replacingOccurrences(of: "\u{201D}", with: "")
         .replacingOccurrences(of: "\u{2018}", with: "")
         .replacingOccurrences(of: "\u{2019}", with: "")
         .replacingOccurrences(of: "'", with: "")
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstLine(of s: String) -> String {
        if let nl = s.firstIndex(where: { $0.isNewline }) {
            return String(s[..<nl]).trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    /// Removes a generic journal lead-in ("Voice note —", "Note to self:", …).
    private static func stripLeadLabel(_ s: String) -> String {
        let lower = s.lowercased()
        for label in labelPrefixes where lower.hasPrefix(label) {
            var rest = Substring(s.dropFirst(label.count))
            rest = rest.drop(while: { " \t:\u{2014}\u{2013}-".contains($0) })
            let trimmed = rest.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 4 { return trimmed }
        }
        return s
    }

    /// The lead clause: text up to the first sentence end, colon, dash or comma.
    private static func leadingClause(_ s: String) -> String {
        var end = s.endIndex
        if let i = s.firstIndex(where: { ".?!:\n".contains($0) }) { end = i }
        for sep in [" \u{2014} ", " \u{2013} ", ", "] {
            if let r = s.range(of: sep), r.lowerBound < end { end = r.lowerBound }
        }
        let clause = String(s[..<end]).trimmingCharacters(in: .whitespaces)
        let wordCount = clause.split(separator: " ").count
        if wordCount >= 2 || (wordCount == 1 && clause.count >= 10) { return clause }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func boundedPrefix(_ s: String, _ maxChars: Int) -> String {
        guard s.count > maxChars else { return s }
        let idx = s.index(s.startIndex, offsetBy: maxChars)
        var cut = String(s[..<idx])
        if let space = cut.lastIndex(of: " ") { cut = String(cut[..<space]) }
        return cut
    }

    private static func stripTrailingPunctuation(_ s: String) -> String {
        var t = s
        while let last = t.last, ".,;:\u{2014}\u{2013}-".contains(last) || last == " " { t.removeLast() }
        return t
    }

    private static func capitalizedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }
}
