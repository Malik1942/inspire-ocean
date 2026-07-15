import Foundation
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
        guard await requestAuthorization() else { return nil }

        let (main, alternate) = await LanguageResolver.resolve()
        let duration = await Self.audioDuration(url: url)

        guard let mainCandidate = await recognize(url: url, locale: main, duration: duration) else {
            // The main recognizer was unavailable or errored outright. A
            // bilingual user still gets one honest attempt in their alternate
            // language before we give up and keep audio only.
            if let alternate,
               let altCandidate = await recognize(url: url, locale: alternate, duration: duration) {
                return altCandidate.transcript.nonEmptyOrNil
            }
            return nil
        }

        if let alternate, TranscriptScorer.hasLoudFailureSignals(mainCandidate),
           let altCandidate = await recognize(url: url, locale: alternate, duration: duration) {
            let winner = TranscriptScorer.pickWinner(mainCandidate, altCandidate)
            return winner.transcript.nonEmptyOrNil
        }

        return mainCandidate.transcript.nonEmptyOrNil
    }

    /// Manual escape hatch (BRIEF decision 8): transcribe once in an explicitly
    /// chosen locale, bypassing resolution and the dual-pass. Used by the
    /// "Re-transcribe in 中文 / English" action.
    func transcribe(url: URL, locale: Locale) async -> String? {
        guard await requestAuthorization() else { return nil }
        let duration = await Self.audioDuration(url: url)
        return (await recognize(url: url, locale: locale, duration: duration))?.transcript.nonEmptyOrNil
    }

    // MARK: - One recognition pass

    /// A single locale's pass over the file, packaged with the signals the
    /// scorer needs. `nil` only when the recognizer for `locale` is
    /// unavailable or the task errors — an empty-but-successful result comes
    /// back as a candidate with an empty transcript so the scorer can judge it.
    private func recognize(url: URL, locale: Locale, duration: TimeInterval) async -> TranscriptCandidate? {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            return nil
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return await withCheckedContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if !finished { finished = true; continuation.resume(returning: nil) }
                    _ = error
                    return
                }
                guard let result, result.isFinal else { return }
                if !finished {
                    finished = true
                    let best = result.bestTranscription
                    let segments = best.segments
                    let averageConfidence = segments.isEmpty
                        ? 0
                        : segments.map { Double($0.confidence) }.reduce(0, +) / Double(segments.count)
                    continuation.resume(returning: TranscriptCandidate(
                        locale: locale,
                        transcript: best.formattedString,
                        averageConfidence: averageConfidence,
                        audioDuration: duration
                    ))
                }
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
