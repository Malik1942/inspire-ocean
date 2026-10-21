import Foundation

/// The rules a voice thought (a whisper) follows on its way to being
/// understood, wherever it was caught: in-app capture (`CaptureSession`),
/// wrist takes (`WatchTakeImporter`), and the pass both share
/// (`VoiceUnderstanding`). Pure, so `WhisperRulesTests` holds them.
enum WhisperRules {

    /// A voice thought with no words yet: the recognizer runs before it can
    /// be understood. Whether a transcript may land is the pass's call (one
    /// the user edited is never overwritten).
    static func needsTranscription(_ node: Node) -> Bool {
        node.kind == .voice && (node.transcription ?? "").isEmpty
    }

    /// Whether a thought's title is only the label the Library stamps on an
    /// untitled voice thought ("Whisper", 语音): a placeholder, never a name.
    /// `placeholders` is that label in every language the app ships
    /// (`VoiceUnderstanding.whisperPlaceholders`). A title the user typed is
    /// theirs, whatever it says.
    static func hasPlaceholderTitle(_ node: Node, placeholders: Set<String>) -> Bool {
        node.kind == .voice && !node.titleEditedByUser && placeholders.contains(trimmed(node.title))
    }

    /// The thought's name, as the watch shows it: its trimmed title, or nil
    /// while it has none (untitled, or only the placeholder).
    static func name(of node: Node, placeholders: Set<String>) -> String? {
        let title = trimmed(node.title)
        return title.isEmpty || hasPlaceholderTitle(node, placeholders: placeholders) ? nil : title
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
