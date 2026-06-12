import Foundation
import AVFoundation
import Speech
import Observation

/// Records a voice drift while streaming speech recognition over the same
/// audio, so the words appear as they're spoken and can be corrected before
/// the thought enters the Ocean.
///
/// One `AVAudioEngine` input tap feeds two consumers: an `AVAudioFile`
/// (AAC `.m4a`, byte-compatible with `AVAudioPlayer(data:)` and the existing
/// `audioData` sync path) and an `SFSpeechAudioBufferRecognitionRequest`.
/// The audio is the immutable source of truth; the transcript is an editable
/// interpretation of it.
///
/// When speech permission is denied or the recognizer is unavailable, the
/// recording still happens exactly as before — only the live words are
/// missing (`speechAvailability == .unavailable`).
@Observable
final class LiveTranscriber {

    enum SpeechAvailability {
        /// Not yet determined (no recording started).
        case unknown
        /// Live recognition is running.
        case live
        /// Permission denied or recognizer unavailable — recording only.
        case unavailable
    }

    private(set) var isRecording = false
    /// The partial transcript, updated while speaking.
    private(set) var partial: String = ""
    private(set) var elapsed: TimeInterval = 0
    /// 0...1 input level for the live waveform.
    private(set) var level: Double = 0
    private(set) var speechAvailability: SpeechAvailability = .unknown

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var currentURL: URL?

    private var latestTranscription = ""
    private var recognitionEnded = false
    private var finalContinuation: CheckedContinuation<Void, Never>?
    /// Set synchronously at start() entry: a double-tap on the mic must not
    /// race two starts through the permission await into a second tap install.
    private var isStarting = false

    /// Fired (on the main queue) when the system takes the audio away mid-
    /// recording — a call, Siri, the mic route vanishing, an engine
    /// reconfiguration. The owning view treats it exactly like a tap on stop:
    /// capture whatever was caught, never sit stuck on "Listening…".
    var onInterruption: (() -> Void)?
    private var interruptionObservers: [NSObjectProtocol] = []

    // MARK: Permissions

    func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: Recording

    /// Starts recording to `url` and, where permitted, streaming recognition.
    /// Returns false when the audio session or engine can't start.
    @discardableResult
    func start(writingTo url: URL) async -> Bool {
        guard !isRecording, !isStarting else { return false }
        isStarting = true
        defer { isStarting = false }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            return false
        }

        // Speech permission is asked lazily, on first voice capture. A denial
        // degrades to recording-only — never blocks the capture itself.
        let authorized = await requestSpeechAuthorization()
        let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }

        // AAC in the file so the bytes land in `Node.audioData` playable by
        // AVAudioPlayer(data:) — AVAudioFile encodes the PCM tap buffers.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            file = try AVAudioFile(forWriting: url, settings: settings)
        } catch {
            return false
        }

        if authorized, let recognizer, recognizer.isAvailable {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // On-device wherever supported: privacy, and a bus with no signal
            // both want it. Server recognition is the fallback.
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                Task { @MainActor in self.handle(result: result, error: error) }
            }
            speechAvailability = .live
        } else {
            speechAvailability = .unavailable
        }

        currentURL = url
        partial = ""
        latestTranscription = ""
        recognitionEnded = false
        elapsed = 0
        level = 0

        let sampleRate = format.sampleRate
        var frames: AVAudioFramePosition = 0
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.file?.write(from: buffer)
            self.request?.append(buffer)

            frames += AVAudioFramePosition(buffer.frameLength)
            let elapsed = Double(frames) / sampleRate
            let level = Self.normalizedLevel(of: buffer)
            Task { @MainActor in
                self.elapsed = elapsed
                self.level = level
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            teardownRecognition()
            file = nil
            return false
        }
        isRecording = true
        installInterruptionObservers()
        return true
    }

    /// The system can take the audio away at any moment — a phone call, the
    /// AirPods walking off, a sample-rate change. Each of those funnels into
    /// `onInterruption`, where the owner runs its ordinary stop path with
    /// whatever was already written and recognized.
    private func installInterruptionObservers() {
        let center = NotificationCenter.default
        interruptionObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, self.isRecording else { return }
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init)
            if type == .began { self.onInterruption?() }
        })
        interruptionObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, self.isRecording else { return }
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init)
            // Only the input disappearing ends the take; plugging something
            // IN reconfigures the engine, which the observer below catches.
            if reason == .oldDeviceUnavailable { self.onInterruption?() }
        })
        interruptionObservers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.onInterruption?()
        })
    }

    private func removeInterruptionObservers() {
        interruptionObservers.forEach(NotificationCenter.default.removeObserver)
        interruptionObservers.removeAll()
    }

    /// Stops the engine, finishes the file, and resolves the final transcript
    /// (empty when recognition was unavailable). The file at `currentURL`
    /// holds the finished audio.
    func stop() async -> (audioURL: URL?, transcript: String) {
        guard isRecording else { return (currentURL, latestTranscription) }

        removeInterruptionObservers()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        level = 0
        // Close explicitly: the m4a header is finalized on close, and callers
        // read the bytes immediately after stop() — deallocation alone races
        // with that read and yields an unplayable container.
        file?.close()
        file = nil

        if let request {
            request.endAudio()
            // Wait briefly for the recognizer's final (often better) pass,
            // but never hold the review hostage — fall back to the partial.
            if !recognitionEnded {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    finalContinuation = continuation
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2.5))
                        self.resolveFinal()
                    }
                }
            }
        }
        teardownRecognition()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return (currentURL, latestTranscription)
    }

    /// Stops and deletes the recording — nothing entered the Ocean.
    func cancel() async {
        let (url, _) = await stop()
        if let url { try? FileManager.default.removeItem(at: url) }
        currentURL = nil
        partial = ""
        latestTranscription = ""
    }

    // MARK: Recognition plumbing

    @MainActor
    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
            // The final pass can return an empty hypothesis for faint audio —
            // never let it erase words the partials already heard.
            if !text.isEmpty { latestTranscription = text }
            if isRecording { partial = latestTranscription }
            if result.isFinal { resolveFinal() }
        }
        if error != nil { resolveFinal() }
    }

    @MainActor
    private func resolveFinal() {
        recognitionEnded = true
        finalContinuation?.resume()
        finalContinuation = nil
    }

    private func teardownRecognition() {
        task?.cancel()
        task = nil
        request = nil
    }

    /// RMS of the buffer mapped to 0...1 for the waveform, matching the feel
    /// of the old dBFS metering.
    private static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(n))
        let db = 20 * log10(max(rms, .leastNonzeroMagnitude))
        return min(1, max(0, Double(db + 50) / 50))
    }
}
