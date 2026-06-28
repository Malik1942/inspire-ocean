import Foundation
import AVFoundation
import Observation

/// Records a wrist whisper to an AAC `.m4a` on the watch.
///
/// The format mirrors the phone recorder exactly (`kAudioFormatMPEG4AAC`, mono)
/// so the bytes are decodable by `AVAudioPlayer(data:)` on the phone and drop
/// straight into the existing `Node.audioData` / CloudKit path once they arrive
/// — the watch never transcribes or organizes, it only catches the audio.
///
/// Recordings land in the App Group container so a later watch widget or the
/// capture intent can see the pending queue; on an unsigned build (no
/// entitlement) it falls back to app-local storage, same as the phone stack.
@Observable
final class WatchAudioRecorder: NSObject, AVAudioRecorderDelegate {

    enum StartResult {
        case started
        case permissionDenied
        case failed
    }

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// 0...1 input level for the live waveform.
    private(set) var level: Double = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var currentURL: URL?

    /// Byte-identical to the phone recorder so a watch whisper plays back and
    /// syncs indistinguishably from a phone-captured one.
    private static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 12_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
    ]

    /// Where finished recordings live until the phone confirms receipt. The
    /// App Group container keeps them reachable from the capture intent and a
    /// future Smart Stack widget; app-local is the unsigned-build fallback.
    static var captureDirectory: URL {
        let base = AppGroup.containerURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Permission

    /// Prompts on first use; on a prior denial this returns `false` immediately
    /// (no second prompt), so a denied state never loops.
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: Lifecycle

    /// Requests permission (if needed), configures the session, and starts
    /// recording — the capture screen's only entry point, so opening straight
    /// into a hot mic is one call.
    @discardableResult
    func start() async -> StartResult {
        guard !isRecording else { return .started }
        guard await requestPermission() else { return .permissionDenied }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            return .failed
        }

        let url = Self.captureDirectory
            .appendingPathComponent("whisper-\(UUID().uuidString).m4a")
        do {
            let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record() else { return .failed }
            self.recorder = recorder
            self.currentURL = url
            self.isRecording = true
            self.elapsed = 0
            startTimer()
            return .started
        } catch {
            return .failed
        }
    }

    /// Stops and finalizes, returning the file and its duration. Duration is
    /// read before `stop()` because `currentTime` is only valid while running.
    @discardableResult
    func stop() -> (url: URL, duration: TimeInterval)? {
        timer?.invalidate()
        timer = nil
        guard let recorder else {
            isRecording = false
            return nil
        }
        let duration = recorder.currentTime
        recorder.stop()
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let url = currentURL
        self.recorder = nil
        guard let url else { return nil }
        return (url, duration)
    }

    /// Stops and deletes — for a recording the user never meant to keep.
    func cancel() {
        let result = stop()
        if let url = result?.url { try? FileManager.default.removeItem(at: url) }
        currentURL = nil
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0) // dBFS, ~ -160...0
            let normalized = max(0, (power + 50) / 50)
            self.level = min(1, Double(normalized))
            self.elapsed = recorder.currentTime
        }
    }
}
