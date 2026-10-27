import Foundation

extension WristSnapshotBuilder.Source {
    /// A thought as the wrist reads it, by the phone's own rule
    /// (`ExpandedNodeView.reading`): a whisper's summary once it has a
    /// transcript, else a link's page summary. The words are the transcript
    /// for a whisper and the text for anything else, as the user left them,
    /// except that words which already are the title are dropped so the wrist
    /// never shows one line twice (`ExpandedNodeView.showsWords`). Dropping
    /// them does not clear the transcript: a repeated title was still heard.
    /// `placeholders` is `VoiceUnderstanding.whisperPlaceholders`.
    init(node: Node, placeholders: Set<String>) {
        let hasTranscript = !(node.transcription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let whisperSummary = hasTranscript ? Self.nonEmpty(node.summary) : nil
        let pageSummary = node.linkURL == nil ? nil : Self.nonEmpty(node.linkSummary)
        let title = WhisperRules.name(of: node, placeholders: placeholders)
        let words = node.kind == .voice ? node.transcription : node.text
        self.init(
            id: node.id,
            title: title,
            summary: whisperSummary ?? pageSummary,
            words: Self.trimmed(words) == title ? nil : words,
            isVoice: node.kind == .voice,
            hasAudio: node.audioData?.isEmpty == false,
            createdAt: node.createdAt,
            hasTranscript: hasTranscript
        )
    }

    /// The trimmed text, or nil when blank. `title` is already trimmed
    /// (`WhisperRules.name`), so equal values mean the words repeat the title.
    private static func trimmed(_ text: String?) -> String? {
        nonEmpty(text)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
