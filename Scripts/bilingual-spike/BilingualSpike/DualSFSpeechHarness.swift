import AVFoundation
import Foundation
import Speech

/// Test B — two concurrent legacy `SFSpeechRecognizer` on-device tasks
/// (zh-CN + en-US), both fed from the SAME tap buffers as they're captured
/// live (S2 in the README). This is the exact shape of BRIEF.md decision
/// 5's live bake-off: two recognition requests sharing one tap. The
/// question this answers is whether iOS runs both on-device tasks cleanly
/// side by side, or throttles/errors one out.
final class DualSFSpeechHarness {
    private let log: SpikeLog

    private var zhRecognizer: SFSpeechRecognizer?
    private var enRecognizer: SFSpeechRecognizer?
    private var zhRequest: SFSpeechAudioBufferRecognitionRequest?
    private var enRequest: SFSpeechAudioBufferRecognitionRequest?
    private var zhTask: SFSpeechRecognitionTask?
    private var enTask: SFSpeechRecognitionTask?

    init(log: SpikeLog) {
        self.log = log
    }

    func start() {
        let zh = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        let en = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        zhRecognizer = zh
        enRecognizer = en

        for (tag, recognizer) in [("B-zh", zh), ("B-en", en)] {
            guard let recognizer else {
                log.append(tag, "SFSpeechRecognizer init failed for this locale")
                continue
            }
            log.append(tag, "supportsOnDeviceRecognition=\(recognizer.supportsOnDeviceRecognition) isAvailable=\(recognizer.isAvailable)")
        }

        let zhReq = Self.makeRequest()
        let enReq = Self.makeRequest()
        zhRequest = zhReq
        enRequest = enReq

        if let zh {
            zhTask = zh.recognitionTask(with: zhReq) { [weak self] result, error in
                self?.handle(tag: "B-zh", result: result, error: error)
            }
        }
        if let en {
            enTask = en.recognitionTask(with: enReq) { [weak self] result, error in
                self?.handle(tag: "B-en", result: result, error: error)
            }
        }
    }

    /// Called on the audio tap thread for every captured buffer — mirrors
    /// the single tap to both recognition requests.
    func append(_ buffer: AVAudioPCMBuffer) {
        zhRequest?.append(buffer)
        enRequest?.append(buffer)
    }

    func stop() {
        zhRequest?.endAudio()
        enRequest?.endAudio()
    }

    private static func makeRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        return request
    }

    private func handle(tag: String, result: SFSpeechRecognitionResult?, error: Error?) {
        if let error {
            let nsError = error as NSError
            log.append(tag, "error: \(nsError.domain) \(nsError.code) — \(nsError.localizedDescription)")
            return
        }
        guard let result else { return }

        let segments = result.bestTranscription.segments
        let avgConfidence = segments.isEmpty
            ? 0
            : segments.map(\.confidence).reduce(0, +) / Float(segments.count)
        let marker = result.isFinal ? "FINAL" : "partial"
        log.append(tag, "[\(marker)] conf=\(String(format: "%.2f", avgConfidence)) text=\(result.bestTranscription.formattedString)")
    }
}
