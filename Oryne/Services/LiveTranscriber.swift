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
        /// iOS 26 only: the on-device SpeechTranscriber model for the resolved
        /// locale isn't installed yet. Recording proceeds (audio-only) and the
        /// model downloads in the background, so the *next* take is ready —
        /// surfaced as a readiness state, never a silent recording-only degrade
        /// (BRIEF decision 12).
        case preparing
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
    /// Held for the take so a mid-take restart can mint a fresh task.
    private var recognizer: SFSpeechRecognizer?
    /// iOS 26 live-recognition session (SpeechAnalyzer + Speech.SpeechTranscriber),
    /// kept as `AnyObject?` so the stored property doesn't need the iOS 26
    /// availability gate; cast back under `#available` at each use. Mutually
    /// exclusive with the legacy `recognizer`/`task` path.
    private var modernSession: AnyObject?
    /// Monotonic id of the current task's callbacks. A cancelled task still
    /// reports one last event (usually a "canceled" error); acting on it
    /// after a replacement task owns the take would cancel the healthy task
    /// and loop the restart. `handle` drops events from older generations.
    private var taskGeneration = 0
    private(set) var currentURL: URL?

    /// Finished segments of the take. On-device recognition resets its
    /// hypothesis after a silence gap — the partials that follow carry only
    /// the new utterance — so every closed segment is banked here, out of
    /// the recognizer's reach.
    private var committedSegments: [String] = []
    /// The live hypothesis for the current segment. Volatile by design:
    /// partials legitimately rewrite it wholesale (words included), so it is
    /// only trusted once a commit trigger in `handle` banks it.
    private var currentHypothesis = ""
    /// The last committed segment came from a segment-final (metadata)
    /// result. endAudio()'s final usually re-delivers that same segment
    /// improved — punctuation, corrected words — so the final must replace
    /// the segment, not append a near-duplicate. Cleared the moment new
    /// words arrive: from then on the final describes the new segment.
    private var lastSegmentReplaceableByFinal = false
    /// Consecutive mid-take restarts with no result in between. The cap
    /// turns a genuinely broken recognizer into recording-only instead of a
    /// restart loop.
    private var restartCount = 0
    private static let maxConsecutiveRestarts = 3
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

        if authorized {
            // BRIEF decision 1: resolve the recognition locale fresh at every
            // capture and map it to a supported recognition locale — never the
            // raw `Locale.current` (a zh-Hans-US device must resolve to zh-CN,
            // not fail). `alternate` is unused here: the live path is single-
            // locale on both OS generations (Gate S1/S2); bilingual coverage is
            // the post-capture dual-pass's job (B2).
            let resolved = await LanguageResolver.resolve()
            await configureRecognition(mainLocale: resolved.main, tapFormat: format)
        } else {
            speechAvailability = .unavailable
        }

        currentURL = url
        partial = ""
        resetTranscript()
        restartCount = 0
        recognitionEnded = false
        elapsed = 0
        level = 0

        let sampleRate = format.sampleRate
        var frames: AVAudioFramePosition = 0
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.file?.write(from: buffer)
            // Legacy path feeds the SFSpeech request; iOS 26 feeds the analyzer.
            // Both are nil on the other path, so exactly one consumes the buffer.
            self.request?.append(buffer)
            if #available(iOS 26, *), let modern = self.modernSession as? ModernSpeechSession {
                modern.append(buffer)
            }

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

    /// Picks the live-recognition backend for the running OS (BRIEF decision 4)
    /// and starts it on the resolved main locale. Never throws upward: any
    /// failure lands on `speechAvailability`, leaving the recording untouched.
    private func configureRecognition(mainLocale: Locale, tapFormat: AVAudioFormat) async {
        if #available(iOS 26, *) {
            // iOS 26 (Gate S1 = yes): a single `Speech.SpeechTranscriber` on the
            // resolved main locale. It adapts between zh and en mid-stream, so
            // there is no second transcriber and no bake-off.
            switch await ModernSpeechSession.setup(
                locale: mainLocale,
                tapFormat: tapFormat,
                onVolatile: { [weak self] text in self?.modernVolatile(text) },
                onFinal: { [weak self] text in self?.modernFinal(text) }
            ) {
            case .live(let session):
                modernSession = session
                speechAvailability = .live
            case .preparing:
                speechAvailability = .preparing
            case .unavailable:
                speechAvailability = .unavailable
            }
        } else {
            // iOS 18–25 (Gate S2 = no concurrent recognizers): a single
            // `SFSpeechRecognizer` on the resolved main locale. No 2-second
            // bake-off — the alternate language is recovered post-capture by the
            // dual-pass (B2). Wrong-language garbage on this single model is
            // suppressed below a confidence floor in `handle` (BRIEF decision 3).
            let recognizer = SFSpeechRecognizer(locale: mainLocale) ?? SFSpeechRecognizer()
            if let recognizer, recognizer.isAvailable {
                self.recognizer = recognizer
                startRecognitionTask(with: recognizer)
                speechAvailability = .live
            } else {
                speechAvailability = .unavailable
            }
        }
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
        guard isRecording else { return (currentURL, composedTranscript) }

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

        if #available(iOS 26, *), let modern = modernSession as? ModernSpeechSession {
            // Finish the input stream and let the analyzer deliver its final
            // results (banked via the onFinal callback) before we compose.
            await modern.finish()
        } else if let request {
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
        return (currentURL, composedTranscript)
    }

    /// Stops and deletes the recording — nothing entered the Ocean.
    func cancel() async {
        let (url, _) = await stop()
        if let url { try? FileManager.default.removeItem(at: url) }
        currentURL = nil
        partial = ""
        resetTranscript()
    }

    // MARK: Recognition plumbing

    /// The commit-trigger state machine. Partials legitimately rewrite the
    /// current hypothesis wholesale, so it is banked into `committedSegments`
    /// only on the explicit end-of-segment signals:
    ///
    /// - segment-final (`speechRecognitionMetadata`): on-device recognition
    ///   endpointed on a silence — the partials that follow restart from
    ///   empty with only post-pause speech, and would wipe these words.
    /// - `isFinal`: the task is over, either from endAudio() or ended by the
    ///   recognizer mid-take after a long pause — commit, then restart while
    ///   still recording so later speech keeps streaming.
    /// - error: the task died ("no speech detected" during a pause, mostly) —
    ///   bank the hypothesis it heard, then restart while still recording.
    @MainActor
    private func handle(result: SFSpeechRecognitionResult?, error: Error?, generation: Int) {
        guard generation == taskGeneration else { return }
        if let result {
            restartCount = 0
            let text = result.bestTranscription.formattedString
            // BRIEF decision 3: on the single main-locale model, the alternate
            // language recognizes as low-confidence garbage. The confidence-
            // bearing passes (segment-final, final) are dropped below a floor
            // rather than banked — the audio file and the post-capture dual-pass
            // (B2) recover those words in the right language.
            let lowConfidence = Self.isLowConfidence(result.bestTranscription)
            if result.isFinal {
                if lowConfidence {
                    currentHypothesis = ""
                } else if text.isEmpty {
                    // The final pass can return an empty hypothesis for faint
                    // audio — never let it erase words the partials already
                    // heard. The task is over, so bank them now.
                    commitCurrentHypothesis()
                } else {
                    commitFinal(text)
                }
                if isRecording { restartRecognition() } else { resolveFinal() }
            } else if result.speechRecognitionMetadata != nil {
                if lowConfidence { currentHypothesis = "" } else { commitSegment(text) }
            } else if !text.isEmpty {
                currentHypothesis = text
                // New words after a segment commit: the eventual final now
                // describes this segment, not the committed one.
                lastSegmentReplaceableByFinal = false
            }
            if isRecording { partial = composedTranscript }
        }
        if error != nil {
            if isRecording {
                // The dead task's words won't be re-delivered — bank them
                // before the replacement task's partials can overwrite.
                commitCurrentHypothesis()
                restartRecognition()
            } else {
                resolveFinal()
            }
        }
    }

    /// Segment-final: on-device recognition endpointed on a silence. Bank the
    /// segment so the restarted-from-empty partials that follow can't wipe it.
    @MainActor
    private func commitSegment(_ text: String) {
        let segment = text.isEmpty ? currentHypothesis : text
        guard !segment.isEmpty else { return }
        committedSegments.append(segment)
        currentHypothesis = ""
        // endAudio()'s final usually re-delivers this same segment improved
        // (punctuation, corrected words) — it must replace, not append.
        lastSegmentReplaceableByFinal = true
    }

    /// A task's non-empty final result: it either re-delivers the last
    /// metadata-committed segment improved (replace it) or closes the segment
    /// the partials were still drafting (append it).
    @MainActor
    private func commitFinal(_ text: String) {
        if lastSegmentReplaceableByFinal, !committedSegments.isEmpty {
            committedSegments[committedSegments.count - 1] = text
        } else {
            committedSegments.append(text)
        }
        currentHypothesis = ""
        lastSegmentReplaceableByFinal = false
    }

    /// Banks the live hypothesis as-is, for task ends that deliver no final
    /// text (errors, empty finals).
    @MainActor
    private func commitCurrentHypothesis() {
        guard !currentHypothesis.isEmpty else { return }
        committedSegments.append(currentHypothesis)
        currentHypothesis = ""
        // A replacement task never heard this audio; its final must append.
        lastSegmentReplaceableByFinal = false
    }

    /// The recognizer ended its task mid-take (isFinal after a long pause, or
    /// a "no speech" error). The recording itself never stops — so mint a
    /// fresh request/task and keep post-pause speech streaming; the words so
    /// far are already committed.
    ///
    /// Between the old task dying and the new request landing in `request`,
    /// the tap appends buffers to a dead or nil request: that sliver of audio
    /// goes untranscribed by design. The .m4a is unaffected — the file write
    /// is independent of recognition — and the gap sits inside the very
    /// silence that ended the task, so no words are lost. A known, accepted
    /// seam, not a bug.
    @MainActor
    private func restartRecognition() {
        // Invalidate the dying task's last callback before cancelling.
        taskGeneration += 1
        task?.cancel()
        task = nil
        request = nil
        restartCount += 1
        guard restartCount <= Self.maxConsecutiveRestarts,
              let recognizer, recognizer.isAvailable else {
            // Recognition is gone for this take. The recording carries on,
            // and the committed words survive into stop().
            speechAvailability = .unavailable
            return
        }
        recognitionEnded = false
        startRecognitionTask(with: recognizer)
    }

    /// One streaming request + task pair, used at start and again by each
    /// mid-take restart. The tap reads `self.request` on every buffer, so
    /// assigning here is what routes audio into the new task.
    private func startRecognitionTask(with recognizer: SFSpeechRecognizer) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device wherever supported: privacy, and a bus with no signal
        // both want it. Server recognition is the fallback.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        taskGeneration += 1
        let generation = taskGeneration
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in self.handle(result: result, error: error, generation: generation) }
        }
    }

    private func resetTranscript() {
        committedSegments = []
        currentHypothesis = ""
        lastSegmentReplaceableByFinal = false
    }

    /// Committed segments ⧺ the live hypothesis — the transcript as it
    /// stands right now; what `partial` mirrors and `stop()` returns.
    private var composedTranscript: String {
        var segments = committedSegments
        if !currentHypothesis.isEmpty { segments.append(currentHypothesis) }
        return Self.joined(segments)
    }

    /// Segments join with a single space, except across a CJK boundary:
    /// 中文 reads wrong with spaces injected between characters.
    private static func joined(_ segments: [String]) -> String {
        segments.reduce(into: "") { joined, raw in
            let segment = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !segment.isEmpty else { return }
            if joined.isEmpty {
                joined = segment
            } else if isCJK(joined.last), isCJK(segment.first) {
                joined += segment
            } else {
                joined += " " + segment
            }
        }
    }

    /// CJK ideographs and full-width punctuation — the scripts written
    /// without inter-word spaces that this app ships (zh).
    private static func isCJK(_ character: Character?) -> Bool {
        guard let scalar = character?.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3000...0x303F,   // CJK symbols and punctuation (。、「」)
             0x3400...0x4DBF,   // CJK extension A
             0x4E00...0x9FFF,   // CJK unified ideographs
             0xF900...0xFAFF,   // CJK compatibility ideographs
             0xFF00...0xFF65:   // full-width forms (，！？)
            return true
        default:
            return false
        }
    }

    @MainActor
    private func resolveFinal() {
        recognitionEnded = true
        finalContinuation?.resume()
        finalContinuation = nil
    }

    private func teardownRecognition() {
        // Mid-take restarts reuse the same `task` slot, so whichever task is
        // current dies here — none left orphaned. The generation bump makes
        // the dying task's last callback a no-op, whatever it carries.
        taskGeneration += 1
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        if #available(iOS 26, *), let modern = modernSession as? ModernSpeechSession {
            modern.cancel()
        }
        modernSession = nil
    }

    // MARK: iOS 26 SpeechAnalyzer bridge

    /// A volatile (in-progress) analyzer result: the live hypothesis for the
    /// segment being spoken. Volatile by design — it rewrites wholesale until a
    /// final result closes the segment.
    @MainActor
    private func modernVolatile(_ text: String) {
        guard isRecording else { return }
        currentHypothesis = text
        partial = composedTranscript
    }

    /// A finalized analyzer result: the segment is settled. SpeechAnalyzer
    /// finalizes ranges as it goes, so each final covers only its own span and
    /// later volatiles carry the *next* span — bank it and clear the hypothesis.
    @MainActor
    private func modernFinal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        committedSegments.append(trimmed)
        currentHypothesis = ""
        partial = composedTranscript
    }

    /// Below this mean segment confidence, a confidence-bearing legacy result is
    /// treated as wrong-language garbage and dropped (BRIEF decision 3).
    private static let confidenceFloor: Float = 0.3

    /// Whether a confidence-bearing transcription (segment-final or final) sits
    /// below the floor. On-device recognition reports a confidence of exactly 0
    /// for segments it did not score — that is "unscored", not "no confidence",
    /// so those are ignored here; suppressing on them would silently drop
    /// healthy main-language speech. Only genuinely-scored, low-confidence
    /// output is suppressed.
    private static func isLowConfidence(_ transcription: SFTranscription) -> Bool {
        let scored = transcription.segments.filter { $0.confidence > 0 }
        guard !scored.isEmpty else { return false }
        let mean = scored.reduce(Float(0)) { $0 + $1.confidence } / Float(scored.count)
        return mean < confidenceFloor
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

// MARK: - iOS 26 live recognition (SpeechAnalyzer + Speech.SpeechTranscriber)

/// The iOS 26 live-recognition backend (BRIEF decision 4). One
/// `Speech.SpeechTranscriber` on the resolved main locale drives a
/// `SpeechAnalyzer`; the input node's tap buffers are converted to the
/// analyzer's format and streamed in, and volatile/final results are handed
/// back to `LiveTranscriber` through the two callbacks.
///
/// Gate S1 (device-verified) says this single transcriber adapts between zh and
/// en mid-stream, so there is no bake-off and no second transcriber. The whole
/// SpeechAnalyzer path could only be compile-verified here (iOS 26 SDK) — its
/// runtime behavior needs an on-device pass.
@available(iOS 26, *)
private final class ModernSpeechSession {

    /// The outcome of `setup`: a running session, a background asset download
    /// (record audio-only, show the preparing state), or an outright failure
    /// (recording-only degrade).
    enum Setup {
        case live(ModernSpeechSession)
        case preparing
        case unavailable
    }

    private let analyzer: SpeechAnalyzer
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let converter: AVAudioConverter?
    private let analyzerFormat: AVAudioFormat
    private var resultsTask: Task<Void, Never>?

    private init(analyzer: SpeechAnalyzer,
                 continuation: AsyncStream<AnalyzerInput>.Continuation,
                 converter: AVAudioConverter?,
                 analyzerFormat: AVAudioFormat) {
        self.analyzer = analyzer
        self.continuation = continuation
        self.converter = converter
        self.analyzerFormat = analyzerFormat
    }

    /// Builds and starts a session, or reports why it couldn't. Fast paths
    /// (unavailable, unsupported locale, asset-not-installed) return before any
    /// network download so the caller never blocks capture on the model.
    static func setup(locale: Locale,
                      tapFormat: AVAudioFormat,
                      onVolatile: @escaping @MainActor (String) -> Void,
                      onFinal: @escaping @MainActor (String) -> Void) async -> Setup {
        guard SpeechTranscriber.isAvailable,
              let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            return .unavailable
        }

        let transcriber = SpeechTranscriber(
            locale: resolved,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        // BRIEF decision 12: if the model isn't installed, do NOT block capture
        // on a download. Kick the install off in the background so the next take
        // is ready, and tell the caller to record audio-only meanwhile.
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                Task.detached { try? await request.downloadAndInstall() }
                return .preparing
            }
        } catch {
            return .unavailable
        }

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            return .unavailable
        }
        let converter = tapFormat == analyzerFormat ? nil : AVAudioConverter(from: tapFormat, to: analyzerFormat)

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            continuation.finish()
            return .unavailable
        }

        let session = ModernSpeechSession(analyzer: analyzer,
                                          continuation: continuation,
                                          converter: converter,
                                          analyzerFormat: analyzerFormat)
        session.resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        await onFinal(text)
                    } else {
                        await onVolatile(text)
                    }
                }
            } catch {
                // The stream ended or errored; the take's committed words stand.
            }
        }
        return .live(session)
    }

    /// Converts a tap buffer to the analyzer's format and streams it in. Called
    /// from the realtime audio tap, so it stays allocation-light and never
    /// blocks — a failed conversion drops the buffer (the .m4a is unaffected).
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let converted = convert(buffer) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return nil }
        var error: NSError?
        var supplied = false
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }

    /// Graceful stop: close the input, let the analyzer finalize, and wait for
    /// the results loop to drain so every final is banked before compose.
    func finish() async {
        continuation.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
    }

    /// Hard teardown for the non-graceful paths (start failure, cancel). Drops
    /// the results loop without waiting on finalization.
    func cancel() {
        continuation.finish()
        resultsTask?.cancel()
        let analyzer = self.analyzer
        Task { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
    }
}
