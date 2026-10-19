import Foundation
import NaturalLanguage

/// An answer is a glance: the prompt asks for at most four sentences, and the
/// small on-device model sometimes runs on (and drifts from the fragments as
/// it does). Everything after the fourth sentence is cut, in any language.
enum AnswerLength {
    static let maxSentences = 4

    static func capped(_ text: String, sentences limit: Int = maxSentences) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var ends: [String.Index] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ends.append(range.upperBound)
            return ends.count < limit + 1
        }
        guard ends.count > limit else { return text }
        return String(text[..<ends[limit - 1]]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Ocean answers arrive as markdown — the model leans on **emphasis** to
/// shape a reply — but SwiftUI's plain-String `Text` shows the markers
/// verbatim. This is the parsing step in between: inline-only, so emphasis
/// becomes styling while blank-line paragraph breaks reach `Text` intact
/// (full markdown parsing would swallow them into block structure `Text`
/// can't render).
enum AnswerMarkdown {
    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(text)
    }
}
