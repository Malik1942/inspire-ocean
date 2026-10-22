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
                  var range = Range(match.range, in: text) else { return nil }
            var urlString = url.absoluteString
            // A question that ends on a link keeps its mark: the detector
            // reads a final "?" as an empty query, which means nothing.
            if text[range].hasSuffix("?") {
                range = range.lowerBound..<text.index(before: range.upperBound)
                if urlString.hasSuffix("?") { urlString.removeLast() }
            }
            let typed = text[range].lowercased()
            // A bare domain comes back as http; the web is https now.
            if !typed.hasPrefix("http://"), !typed.hasPrefix("https://"), urlString.hasPrefix("http://") {
                urlString = "https://" + urlString.dropFirst("http://".count)
            }
            return Sensed(urlString: urlString, range: range)
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
            return String(after.drop { $0.isWhitespace || sentenceEnds.contains($0) || joints.contains($0) })
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// What ends a sentence after a link.
    private static let sentenceEnds: Set<Character> = [".", ",", ";", "!", "?", "…", "。", "，", "；", "！", "？"]
    /// What joins a link to the words beside it ("Great read - link",
    /// "link, great read", "看这个：link").
    private static let joints: Set<Character> = ["-", "–", "—", "|", "·", ":", "：", ",", "，", ";", "；"]

    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
}
