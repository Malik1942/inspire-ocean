import Foundation

/// What the automatic pass settled on: the kept transcript with its locale,
/// and the other language's pass when it was too close to call.
struct TranscriptOutcome {
    let text: String
    let localeID: String
    let alternateText: String?
    let alternateLocaleID: String?

    init?(candidate: TranscriptCandidate, alternate: TranscriptCandidate?) {
        guard let text = candidate.transcript.nonEmptyOrNil else { return nil }
        self.text = text
        self.localeID = candidate.locale.identifier
        self.alternateText = alternate?.transcript.nonEmptyOrNil
        self.alternateLocaleID = alternateText == nil ? nil : alternate?.locale.identifier
    }
}
import Speech
import AVFoundation

/// Transcribes a recorded voice drift using on-device speech recognition where
/// available. Returns nil (gracefully) when permission is denied or recognition
/// fails — the audio is always kept regardless (BRIEF invariant: audio is the
/// immutable source of truth; only transcripts are recomputable).
///
/// Recognition locale is never `Locale.current` (BRIEF decision 1): the main
/// locale is resolved fresh from live system state by `LanguageResolver`, and a
/// bilingual user gets a second pass in their alternate language when the main
/// transcript looks bad (BRIEF decision 7). The manual escape hatch
/// (BRIEF decision 8) calls `transcribe(url:locale:)` with an explicit choice.
///
/// Kept on the `SFSpeechRecognizer` / `SFSpeechURLRecognitionRequest` file path
/// for all OS versions — it still works on iOS 26. (A follow-up could rebuild
/// file transcription on the iOS 26 `SpeechAnalyzer` API; not done here.)
final class DriftTranscriber {

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Automatic path used by the capture/enrichment pipeline: resolve the main
    /// (and, for bilingual users, alternate) locale, transcribe with the main
    /// locale, and re-run in the alternate only when the main transcript shows
    /// loud failure signals — then keep whichever transcript the scorer picks.
    func transcribe(url: URL) async -> String? {
        await transcribe(url: url, vocabulary: [])?.text
    }

    /// Automatic path used by the capture pipeline. A bilingual user gets a
    /// pass in each language; the scorer keeps the better one, and when the
    /// two are too close to call the other is kept too, for the user to
    /// switch to. `vocabulary` is the user's own words (names, English terms
    /// inside Chinese speech) handed to the recognizer as contextual strings.
    func transcribe(url: URL, vocabulary: [String]) async -> TranscriptOutcome? {
        guard await requestAuthorization() else { return nil }

        let (main, alternate) = await LanguageResolver.resolve()
        let duration = await Self.audioDuration(url: url)

        let mainCandidate = await recognize(url: url, locale: main, duration: duration, vocabulary: vocabulary)
        let altCandidate: TranscriptCandidate? = alternate == nil
            ? nil
            : await recognize(url: url, locale: alternate!, duration: duration, vocabulary: vocabulary)

        switch (mainCandidate, altCandidate) {
        case (nil, nil):
            return nil
        case (let m?, nil):
            return TranscriptOutcome(candidate: m, alternate: nil)
        case (nil, let a?):
            return TranscriptOutcome(candidate: a, alternate: nil)
        case (let m?, let a?):
            let winner = TranscriptScorer.pickWinner(m, a)
            let loser = winner.locale == m.locale ? a : m
            let keepLoser = TranscriptScorer.areClose(m, a)
            return TranscriptOutcome(candidate: winner, alternate: keepLoser ? loser : nil)
        }
    }

    /// Manual escape hatch (BRIEF decision 8): transcribe once in an explicitly
    /// chosen locale, bypassing resolution and the dual-pass. Used by the
    /// "Re-transcribe in 中文 / English" action.
    func transcribe(url: URL, locale: Locale, vocabulary: [String] = []) async -> String? {
        guard await requestAuthorization() else { return nil }
        let duration = await Self.audioDuration(url: url)
        return (await recognize(url: url, locale: locale, duration: duration, vocabulary: vocabulary))?.transcript.nonEmptyOrNil
    }

    // MARK: - One recognition pass

    /// A single locale's pass over the file, packaged with the signals the
    /// scorer needs. `nil` only when the recognizer for `locale` is
    /// unavailable or the task errors before hearing anything — an
    /// empty-but-successful result comes back as a candidate with an empty
    /// transcript so the scorer can judge it.
    ///
    /// On-device recognition resets after every pause, and the final result
    /// describes only the last segment: the words are banked segment by
    /// segment (`TranscriptSegments`), the same way the live take banks them,
    /// or a whisper of several paragraphs comes back as its last sentence.
    private func recognize(url: URL, locale: Locale, duration: TimeInterval, vocabulary: [String]) async -> TranscriptCandidate? {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            return nil
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        // Partials keep the segment in progress, so an error mid-segment
        // still leaves its words to bank.
        request.shouldReportPartialResults = true
        if !vocabulary.isEmpty { request.contextualStrings = vocabulary }
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return await withCheckedContinuation { continuation in
            var finished = false
            var words = TranscriptSegments()
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result {
                    let best = result.bestTranscription
                    let text = best.formattedString
                    let confidences = best.segments.map(\.confidence)
                    if result.isFinal {
                        // An empty final never erases words already heard.
                        if text.isEmpty { words.commitHypothesis() } else { words.commitFinal(text, confidences: confidences) }
                    } else if result.speechRecognitionMetadata != nil {
                        words.commitSegment(text, confidences: confidences)
                    } else {
                        words.hypothesize(text)
                    }
                }
                guard result?.isFinal == true || error != nil else { return }
                finished = true
                if error != nil {
                    // The task died; what it heard before dying still counts.
                    words.commitHypothesis()
                    guard !words.text.isEmpty else {
                        continuation.resume(returning: nil)
                        return
                    }
                }
                continuation.resume(returning: TranscriptCandidate(
                    locale: locale,
                    transcript: words.text,
                    averageConfidence: words.averageConfidence,
                    audioDuration: duration
                ))
            }
        }
    }

    /// Length of the recording in seconds — the denominator for the scorer's
    /// "output relative to duration" signal. 0 when it can't be measured, which
    /// the scorer treats as "don't judge density".
    private static func audioDuration(url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }
}

private extension String {
    var nonEmptyOrNil: String? { isEmpty ? nil : self }
}
