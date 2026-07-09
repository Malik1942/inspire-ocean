import Foundation
import Speech

/// Transcribes a recorded voice drift using on-device speech recognition where
/// available. Returns nil (gracefully) when permission is denied or recognition
/// fails — the audio is always kept regardless.
final class DriftTranscriber {

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func transcribe(url: URL) async -> String? {
        guard await requestAuthorization() else { return nil }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else { return nil }

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
                    let text = result.bestTranscription.formattedString
                    continuation.resume(returning: text.isEmpty ? nil : text)
                }
            }
        }
    }
}
