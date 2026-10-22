import Foundation

/// Links in what the user typed, sensed rather than entered: the composer
/// has no link field. The first web link the user hasn't dismissed becomes
/// the thought's link. At the start or end of the words it leaves them (its
/// card carries it); in the middle of a sentence it stays.
enum LinkSensing {

    /// One web link in the words.
    struct Sensed: Equatable {
        /// What the thought stores: a link typed without a scheme gets https.
        let urlString: String
        /// Where it sits in the words it was found in.
        let range: Range<String.Index>

        /// The site's name for the composer's tile, without "www.".
        var host: String {
            let host = URL(string: urlString)?.host ?? urlString
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
    }

    /// Every http and https link in `text`, in order. Emails and other
    /// schemes are not links here.
    static func links(in text: String) -> [Sensed] {
        let whole = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: whole).compactMap { match in
            guard let url = match.url, let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let found = Range(match.range, in: text) else { return nil }
            var typed = String(text[found])
            // The detector carries prose typed right against a link into it
            // (Chinese needs no space, a curly quote, dash or emoji none
            // either): the link ends where that prose begins.
            if let end = linkEnd(in: typed) {
                typed = String(typed[..<end])
                // A cut right after a dot leaves the sentence's dot behind.
                while typed.hasSuffix(".") { typed.removeLast() }
            }
            // A final "?" belongs to the sentence, not the URL: the detector
            // reads it as an empty query.
            while typed.hasSuffix("?") { typed.removeLast() }
            let lowered = typed.lowercased()
            // A bare domain gets https; the web is https now.
            let candidate = lowered.hasPrefix("http://") || lowered.hasPrefix("https://") ? typed : "https://" + typed
            guard let link = URL(string: candidate), link.host?.isEmpty == false else { return nil }
            let range = found.lowerBound..<text.index(found.lowerBound, offsetBy: typed.count)
            return Sensed(urlString: link.absoluteString, range: range)
        }
    }

    /// The link a release attaches: the first one the user hasn't dismissed.
    static func chosen(in text: String, dismissed: Set<String> = []) -> Sensed? {
        links(in: text).first { !dismissed.contains($0.urlString) }
    }

    /// The words a thought keeps, trimmed. When `urlString` sits at their
    /// start or end it leaves them, with the punctuation that ended it or
    /// joined it to them; anywhere else the words keep it.
    static func words(_ text: String, lifting urlString: String?) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let urlString,
              let link = links(in: text).first(where: { $0.urlString == urlString }) else { return text }
        let before = text[..<link.range.lowerBound]
        let after = text[link.range.upperBound...]
        // The end first: a link followed by nothing but its sentence's end
        // leaves no words of its own behind, wherever it starts.
        if after.allSatisfy({ $0.isWhitespace || sentenceEnds.contains($0) }) {
            var kept = before
            while let last = kept.last, last.isWhitespace || joints.contains(last) { kept.removeLast() }
            return String(kept)
        }
        if before.allSatisfy(\.isWhitespace) {
            let spaced = after.first?.isWhitespace ?? true
            var rest = after.drop(while: \.isWhitespace)
            let marks = rest.prefix { joints.contains($0) || sentenceEnds.contains($0) }
            let past = rest.dropFirst(marks.count)
            if !marks.isEmpty, past.first?.isWhitespace ?? true || marks.contains(where: isCJK) {
                // A separator after the link goes with it: "link, words",
                // "link - words", "link。字".
                rest = past.drop(while: \.isWhitespace)
            } else if !spaced, !(rest.first.map(isCJK) ?? false) {
                // Nothing sets the link apart from what follows
                // ("stripe.com’s docs"): the words keep it.
                return text
            }
            return String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// What ends a sentence after a link.
    private static let sentenceEnds: Set<Character> = [".", ",", ";", "!", "?", "…", "。", "，", "；", "！", "？", "、"]
    /// What joins a link to the words beside it ("Great read - link",
    /// "link, great read", "看这个：link").
    private static let joints: Set<Character> = ["-", "–", "—", "|", "·", ":", "：", ",", "，", ";", "；", "、"]

    /// CJK text and its marks: they need no space to end a link.
    private static func isCJK(_ character: Character) -> Bool {
        isCJKLetter(character) || character.unicodeScalars.contains { scalar in
            (0x3000...0x303F).contains(scalar.value) || (0xFF00...0xFFEF).contains(scalar.value)
        }
    }

    /// Han, kana and hangul.
    private static func isCJKLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x2FFF, 0x3040...0x30FF, 0x3400...0x4DBF,
                 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }

    /// Where a link the detector ran on really ends: at CJK text and marks,
    /// curly quotes, dashes or emoji typed right against it. CJK letters
    /// that open a path segment are the link's own ("/wiki/海洋").
    private static func linkEnd(in typed: String) -> String.Index? {
        // The path starts at the first slash after the host, not in "://".
        let host = typed.range(of: "://")?.upperBound ?? typed.startIndex
        var inPath = false
        var segmentIsCJK = false
        var previous: Character?
        for index in typed.indices {
            let character = typed[index]
            defer { previous = character }
            if character == "/" {
                if index >= host { inPath = true }
                segmentIsCJK = false
            } else if isCJKLetter(character) {
                if inPath, previous == "/" { segmentIsCJK = true }
                if !segmentIsCJK { return index }
            } else if isCJK(character) || isProseMark(character) {
                return index
            }
        }
        return nil
    }

    /// Curly quotes, dashes and emoji: prose, never part of a typed link.
    private static func isProseMark(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x2010...0x201F).contains(scalar.value)
                || scalar.properties.isEmojiPresentation
                || scalar.value == 0xFE0F
        }
    }

    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
}
