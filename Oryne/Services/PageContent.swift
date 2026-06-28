import Foundation

/// Stage B's substrate: fetch a web page and pull out its Open Graph metadata
/// and a Readability-style block of readable main text — *without* a third-party
/// dependency.
///
/// Why no package: a maintained Swift Readability port (e.g. SwiftSoup +
/// heuristics) would add a build/SPM-resolution surface to an XcodeGen project
/// and a supply-chain dependency, for a stage whose output is only ever fed to a
/// summarizer that tolerates noise. A focused, self-contained extractor that
/// strips scripts/nav/chrome and prefers `<article>`/`<main>` gets the model
/// clean-enough substance, with nothing new to resolve or sign.
///
/// Everything here is best-effort: any step can return nil and the caller
/// degrades gracefully.
enum PageContent {

    /// Fetches HTML for `url` with a sane timeout and a desktop User-Agent (so
    /// sites return real markup, not a bot stub). Returns nil on any network or
    /// decoding failure, or if the response isn't HTML.
    static func fetchHTML(_ url: URL, timeout: TimeInterval = 10) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                guard (200..<300).contains(http.statusCode) else { return nil }
                if let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
                   !type.contains("html"), !type.contains("xml") {
                    return nil
                }
            }
            // Honor the charset when declared; default to UTF-8, then Latin-1.
            if let html = String(data: data, encoding: .utf8) { return html }
            return String(data: data, encoding: .isoLatin1)
        } catch {
            return nil
        }
    }

    // MARK: Open Graph / meta tags

    /// `<meta property="og:title">` or `<meta name="og:title">`, falling back to
    /// the document `<title>`.
    static func ogTitle(from html: String) -> String? {
        metaContent(in: html, keys: ["og:title", "twitter:title"])
            ?? titleTag(from: html)
    }

    /// `og:description` / `twitter:description` / `<meta name="description">`.
    static func metaDescription(from html: String) -> String? {
        metaContent(in: html, keys: ["og:description", "twitter:description", "description"])
    }

    /// The absolute URL of the page's preferred preview image, if declared.
    static func ogImageURL(from html: String, relativeTo base: URL) -> URL? {
        guard let raw = metaContent(in: html, keys: ["og:image", "og:image:url", "twitter:image"]) else {
            return nil
        }
        return URL(string: raw, relativeTo: base)?.absoluteURL ?? URL(string: raw)
    }

    // MARK: Readable main content

    /// A Readability-style block of the page's main prose: scripts, style, and
    /// site chrome stripped; `<article>`/`<main>` preferred when present; tags
    /// removed and entities decoded. Truncated to `maxCharacters` so the
    /// on-device model stays inside its context budget. Returns nil if too
    /// little survives to be worth summarizing.
    static func readableText(from html: String, maxCharacters: Int = 4_000) -> String? {
        // 1. Drop everything that is never readable content.
        var working = html
        for pattern in [
            "(?is)<script\\b[^>]*>.*?</script>",
            "(?is)<style\\b[^>]*>.*?</style>",
            "(?is)<noscript\\b[^>]*>.*?</noscript>",
            "(?is)<template\\b[^>]*>.*?</template>",
            "(?is)<svg\\b[^>]*>.*?</svg>",
            "(?is)<head\\b[^>]*>.*?</head>",
            "(?is)<!--.*?-->"
        ] {
            working = working.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        // 2. Prefer the main content region when the page marks one.
        let region = largestMatch(in: working, tag: "article")
            ?? largestMatch(in: working, tag: "main")
            ?? bodyOrWhole(working)

        // 3. Strip site chrome that survives inside the region.
        var content = region
        for pattern in [
            "(?is)<nav\\b[^>]*>.*?</nav>",
            "(?is)<header\\b[^>]*>.*?</header>",
            "(?is)<footer\\b[^>]*>.*?</footer>",
            "(?is)<aside\\b[^>]*>.*?</aside>",
            "(?is)<form\\b[^>]*>.*?</form>",
            "(?is)<figure\\b[^>]*>.*?</figure>"
        ] {
            content = content.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        // 4. Block-level tags become line breaks so words don't fuse together,
        //    then every remaining tag is removed.
        content = content.replacingOccurrences(
            of: "(?is)</(p|div|li|h[1-6]|br|tr|section)>",
            with: "\n",
            options: .regularExpression
        )
        content = content.replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)

        // 5. Decode entities and collapse whitespace.
        content = decodeEntities(content)
        content = content.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        content = content.replacingOccurrences(of: "\\s*\\n\\s*", with: "\n", options: .regularExpression)
        content = content.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard content.count >= 200 else { return nil }
        guard content.count > maxCharacters else { return content }
        // Truncate on a word boundary near the budget.
        let cut = content.index(content.startIndex, offsetBy: maxCharacters)
        let head = content[..<cut]
        if let lastSpace = head.lastIndex(of: " ") {
            return String(head[..<lastSpace])
        }
        return String(head)
    }

    // MARK: - Internals

    /// Reads the `content` of the first `<meta>` tag whose `property`/`name`
    /// matches one of `keys` (case-insensitive, attribute order independent).
    private static func metaContent(in html: String, keys: [String]) -> String? {
        let wanted = Set(keys.map { $0.lowercased() })
        let metaTags = matches(in: html, pattern: "(?is)<meta\\b[^>]*>")
        for tag in metaTags {
            let attrs = attributes(in: tag)
            let id = (attrs["property"] ?? attrs["name"])?.lowercased()
            guard let id, wanted.contains(id), let content = attrs["content"] else { continue }
            let value = decodeEntities(content).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func titleTag(from html: String) -> String? {
        guard let raw = matches(in: html, pattern: "(?is)<title\\b[^>]*>(.*?)</title>").first else {
            return nil
        }
        let inner = raw
            .replacingOccurrences(of: "(?is)^<title\\b[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?is)</title>$", with: "", options: .regularExpression)
        let value = decodeEntities(inner).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// The text of the longest `<tag>…</tag>` block (the real article usually
    /// dwarfs any boilerplate ones).
    private static func largestMatch(in html: String, tag: String) -> String? {
        matches(in: html, pattern: "(?is)<\(tag)\\b[^>]*>.*?</\(tag)>")
            .max(by: { $0.count < $1.count })
    }

    private static func bodyOrWhole(_ html: String) -> String {
        largestMatch(in: html, tag: "body") ?? html
    }

    /// Parses `key="value"` / `key='value'` pairs out of a single tag.
    private static func attributes(in tag: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = "([\\w:-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return result
        }
        let ns = tag as NSString
        for m in regex.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: m.range(at: 1)).lowercased()
            let valRange = m.range(at: 2).location != NSNotFound ? m.range(at: 2) : m.range(at: 3)
            guard valRange.location != NSNotFound else { continue }
            if result[key] == nil { result[key] = ns.substring(with: valRange) }
        }
        return result
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    /// Decodes the handful of HTML entities that actually matter for prose,
    /// plus numeric (decimal and hex) references.
    private static func decodeEntities(_ string: String) -> String {
        var s = string
        // Everything except `&amp;` — these decode to characters that can't
        // begin another entity, so the order among them doesn't matter.
        let named: [String: String] = [
            "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&apos;": "'", "&#39;": "'", "&nbsp;": " ", "&hellip;": "…",
            "&mdash;": "—", "&ndash;": "–", "&rsquo;": "’", "&lsquo;": "‘",
            "&ldquo;": "“", "&rdquo;": "”", "&copy;": "©", "&reg;": "®",
            "&trade;": "™", "&deg;": "°", "&eacute;": "é", "&egrave;": "è"
        ]
        for (entity, value) in named {
            s = s.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        // Numeric references: &#1234; and &#x1F600;
        s = replaceNumericEntities(in: s)
        // `&amp;` LAST: decoding it earlier could revive an escaped entity —
        // a literal "&lt;" written as "&amp;lt;" would wrongly become "<".
        // Done last, doubly-encoded text survives intact.
        s = s.replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
        return s
    }

    private static func replaceNumericEntities(in string: String) -> String {
        guard string.contains("&#"),
              let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") else {
            return string
        }
        let ns = string as NSString
        var result = string
        // Replace from the end so earlier ranges stay valid.
        for m in regex.matches(in: string, range: NSRange(location: 0, length: ns.length)).reversed() {
            let isHex = !ns.substring(with: m.range(at: 1)).isEmpty
            let digits = ns.substring(with: m.range(at: 2))
            guard let code = UInt32(digits, radix: isHex ? 16 : 10),
                  let scalar = Unicode.Scalar(code) else { continue }
            let whole = m.range(at: 0)
            if let swiftRange = Range(whole, in: result) {
                result.replaceSubrange(swiftRange, with: String(Character(scalar)))
            }
        }
        return result
    }
}
