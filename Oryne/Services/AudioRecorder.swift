import Foundation
import AVFoundation
import Observation

/// Records a voice drift to a file in the app's Audio directory.
@Observable
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// 0...1 input level for a simple live waveform.
    private(set) var level: Double = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentURL: URL?

    static var audioDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for fileName: String) -> URL {
        audioDirectory.appendingPathComponent(fileName)
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    @discardableResult
    func start() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            return false
        }

        let fileName = "drift-\(UUID().uuidString).m4a"
        let url = AudioRecorder.url(for: fileName)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record() else { return false }
            self.recorder = recorder
            self.currentURL = url
            self.isRecording = true
            self.elapsed = 0
            startTimer()
            return true
        } catch {
            return false
        }
    }

    /// Stops recording and returns the file name (relative to the Audio dir).
    @discardableResult
    func stop() -> String? {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let name = currentURL?.lastPathComponent
        recorder = nil
        return name
    }

    func cancel() {
        let name = stop()
        if let name { try? FileManager.default.removeItem(at: AudioRecorder.url(for: name)) }
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
