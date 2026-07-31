import Foundation

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
