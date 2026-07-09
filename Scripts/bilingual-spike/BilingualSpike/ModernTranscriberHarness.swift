import Foundation
import Speech
import AVFoundation

/// Test A — the iOS 26 `Speech.SpeechTranscriber` module (S1 in the README).
///
/// `SpeechTranscriber`'s locale is bound at `init` and cannot change
/// mid-stream — there is no API to hot-swap a running transcriber's
/// language. So "mid-stream adaptation" is tested indirectly: the SAME
/// recorded take is run through two separately-configured, single-locale
/// transcribers, one after another — zh-CN first, then en-US — and every
/// partial from both passes is logged. For a code-switched take, comparing
/// the A-zh log against the A-en log shows how each fixed-locale model
/// degrades (or doesn't) once the audio drifts outside its target language.
/// That comparison is BRIEF.md decision 5's "asymmetric tolerance" claim,
/// under this newer API.
enum ModernTranscriberHarness {
    static func run(fileURL: URL, log: SpikeLog) async {
        await runPass(locale: Locale(identifier: "zh-CN"), streamTag: "A-zh", fileURL: fileURL, log: log)
        await runPass(locale: Locale(identifier: "en-US"), streamTag: "A-en", fileURL: fileURL, log: log)
    }

    private static func runPass(locale: Locale, streamTag: String, fileURL: URL, log: SpikeLog) async {
        guard SpeechTranscriber.isAvailable else {
            log.append(streamTag, "SpeechTranscriber.isAvailable == false — needs an iOS 26 device, skipping")
            return
        }
        guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            log.append(streamTag, "no supported locale equivalent to \(locale.identifier) — skipping")
            return
        }

        // volatileResults so we see live-partial-equivalent output, not just
        // the final sentence; no attributeOptions — we only need text for S1.
        let transcriber = SpeechTranscriber(
            locale: resolved,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                log.append(streamTag, "downloading \(resolved.identifier) asset…")
                try await request.downloadAndInstall()
                log.append(streamTag, "asset install complete")
            }

            let audioFile = try AVAudioFile(forReading: fileURL)
            let analyzer = SpeechAnalyzer(modules: [transcriber])

            // finishAfterFile: true drives the analyzer to finalize once the
            // file is fully read, which is what lets the `results` sequence
            // below terminate on its own instead of needing a manual
            // finalize call raced against an unknown read-completion time.
            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

            for try await result in transcriber.results {
                let marker = result.isFinal ? "FINAL" : "volatile"
                log.append(streamTag, "[\(marker)] \(String(result.text.characters))")
            }

            log.append(streamTag, "pass complete")
        } catch {
            log.append(streamTag, "pass failed: \(error)")
        }
    }
}
