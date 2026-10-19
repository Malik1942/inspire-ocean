import Foundation
import AVFoundation
import Observation

/// Records a wrist take to an AAC `.m4a`, byte-compatible with the phone
/// recorder (`kAudioFormatMPEG4AAC`, mono, 12 kHz), so it drops straight into
/// `Node.audioData` on the phone. The watch never transcribes.
///
/// Main-actor isolated: metering, `level`, and `elapsed` all live on the main
/// actor (Phase 1 ran its timer off the main run loop, and the timer froze).
/// `stop()` waits for the recorder's finish callback, so the file is
/// complete before anyone reads it.
@MainActor
@Observable
final class WatchRecorder: NSObject {

    enum StartResult {
        case started
        case permissionDenied
        case failed
    }

    struct Finished {
        let url: URL
        let duration: TimeInterval
    }

    /// The hard cap on one take (spec: 5 minutes). DEBUG builds read
    /// `ORYNE_WATCH_CAP_SECONDS` so the cap path can be tested in seconds.
    static let cap: TimeInterval = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["ORYNE_WATCH_CAP_SECONDS"],
           let seconds = TimeInterval(raw) { return seconds }
        #endif
        return 5 * 60
    }()

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// 0...1 input level for the waveform.
    private(set) var level: Double = 0

    /// The take ended without a stop from the user: the cap, an interruption
    /// (a call, Siri), or an encoder error. The owner finishes the take
    /// exactly as if the user had stopped it.
    @ObservationIgnored var onEndedBySystem: (() -> Void)?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var finishWaiter: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var finishedFlag: Bool?
    @ObservationIgnored private var fallbackTask: Task<Void, Never>?
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    private static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 12_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
    ]

    var permissionDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    /// Prompts on first use; after a denial it returns false at once, so the
    /// denied state never loops.
    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start(writingTo url: URL) async -> StartResult {
        guard !isStopping else { return .failed }
        guard !isRecording, !isStarting else { return .started }
        isStarting = true
        defer { isStarting = false }
        guard await requestPermission() else { return .permissionDenied }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            return .failed
        }
        do {
            let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                deactivateSession()
                return .failed
            }
            self.recorder = recorder
            finishedFlag = nil
            isRecording = true
            elapsed = 0
            startMetering()
            observeInterruptions()
            return .started
        } catch {
            deactivateSession()
            return .failed
        }
    }

    /// Stops, waits for the file to be finalized, and returns it. Nil when
    /// nothing was recording or the encoder reported failure.
    func stop() async -> Finished? {
        guard let recorder, isRecording else { return nil }
        isStopping = true
        // `currentTime` reads 0 once the system has stopped the recorder; the
        // metered `elapsed` keeps a long take from being dropped as a reflex press.
        let duration = max(recorder.currentTime, elapsed)
        let url = recorder.url
        stopMetering()
        isRecording = false
        level = 0

        let succeeded: Bool
        if let finishedFlag {
            // The system already closed the file (an interruption stopped it).
            succeeded = finishedFlag
        } else {
            succeeded = await withCheckedContinuation { continuation in
                finishWaiter = continuation
                recorder.stop()
                // Never hang on a finish callback that doesn't come.
                fallbackTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    self?.finished(recorder, successfully: FileManager.default.fileExists(atPath: url.path))
                }
            }
        }
        if self.recorder === recorder { self.recorder = nil }
        removeInterruptionObserver()
        deactivateSession()
        isStopping = false
        return succeeded ? Finished(url: url, duration: duration) : nil
    }

    /// Stops and deletes: a take nobody meant to keep.
    func cancel() async {
        if let finished = await stop() {
            try? FileManager.default.removeItem(at: finished.url)
        }
    }

    // MARK: Metering

    private func startMetering() {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)   // dBFS, about -160...0
                self.level = min(1, Double(max(0, (power + 50) / 50)))
                // Never falls back to 0 when the system stops the recorder, so
                // `stop()`'s duration keeps the time actually recorded.
                self.elapsed = max(self.elapsed, recorder.currentTime)
                if self.elapsed >= Self.cap {
                    self.onEndedBySystem?()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
    }

    // MARK: Interruptions and session

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began
            else { return }
            MainActor.assumeIsolated { self?.onEndedBySystem?() }
        }
    }

    private func removeInterruptionObserver() {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    fileprivate func finished(_ finishedRecorder: AVAudioRecorder, successfully flag: Bool) {
        // Only the current take's recorder counts: a late callback or fallback
        // from an earlier take must never decide this one.
        guard finishedRecorder === recorder else { return }
        fallbackTask?.cancel()
        fallbackTask = nil
        if finishedFlag == nil { finishedFlag = flag }
        if let waiter = finishWaiter {
            finishWaiter = nil
            waiter.resume(returning: flag)
        } else if isRecording {
            // The system closed the file without a stop from the user, a lost
            // mic: end the take like stop.
            onEndedBySystem?()
        }
    }
}

extension WatchRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.finished(recorder, successfully: flag) }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            if recorder === self.recorder { self.onEndedBySystem?() }
        }
    }
}
