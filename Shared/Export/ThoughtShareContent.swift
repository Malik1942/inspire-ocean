import Foundation

/// The part of a thought that may leave the device.
///
/// A share is the user's own words: typed text, then a transcript when it
/// says something else, a title only when the user wrote it, their link, and
/// their pictures in saved order. Example thoughts are not shareable, and
/// nothing the device wrote (a distilled title, a summary, a page reading, a
/// picture reading) goes out dressed as theirs. `make` only reads the node.
struct ThoughtShareContent: Equatable {
    var title: String?
    var words: String
    var link: String?
    var images: [Data]

    /// Whether there is text to put on the clipboard. Pictures are not text.
    var hasWords: Bool { !words.isEmpty }

    /// Title, words, and link, with the empty parts left out.
    var plainText: String {
        var parts: [String] = []
        if let title, !title.isEmpty { parts.append(title) }
        if !words.isEmpty { parts.append(words) }
        if let link, !link.isEmpty { parts.append(link) }
        return parts.joined(separator: "\n\n")
    }

    /// Nil when the thought is an example, or when it has no words, link, or
    /// pictures of its own.
    static func make(from node: Node) -> ThoughtShareContent? {
        guard !node.isExample else { return nil }

        let typed = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let spoken = (node.transcription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var wordParts: [String] = []
        if !typed.isEmpty { wordParts.append(typed) }
        if !spoken.isEmpty, spoken != typed { wordParts.append(spoken) }
        let words = wordParts.joined(separator: "\n\n")

        let rawLink = (node.linkURLString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let link: String? = rawLink.isEmpty || words.contains(rawLink) ? nil : rawLink

        let edited = node.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String? = node.titleEditedByUser && !edited.isEmpty && edited != words ? edited : nil

        let images = node.imageDatas
        if title == nil, words.isEmpty, link == nil, images.isEmpty { return nil }

        return ThoughtShareContent(title: title, words: words, link: link, images: images)
    }
}
