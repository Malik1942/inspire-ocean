import Foundation

extension WristSnapshotBuilder.Source {
    /// A thought as the wrist reads it, by the phone's own rule
    /// (`ExpandedNodeView.reading`): a whisper's summary once it has a
    /// transcript, else a link's page summary. The words are the transcript
    /// for a whisper and the text for anything else, as the user left them.
    /// `placeholders` is `VoiceUnderstanding.whisperPlaceholders`.
    init(node: Node, placeholders: Set<String>) {
        let hasTranscript = !(node.transcription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let whisperSummary = hasTranscript ? Self.nonEmpty(node.summary) : nil
        let pageSummary = node.linkURL == nil ? nil : Self.nonEmpty(node.linkSummary)
        self.init(
            id: node.id,
            title: WhisperRules.name(of: node, placeholders: placeholders),
            summary: whisperSummary ?? pageSummary,
            words: node.kind == .voice ? node.transcription : node.text,
            isVoice: node.kind == .voice,
            hasAudio: node.audioData?.isEmpty == false,
            createdAt: node.createdAt
        )
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
