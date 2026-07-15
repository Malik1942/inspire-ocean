import AVFoundation
import Foundation

/// Records the mic to a `.caf` file (the tap's native format, uncompressed —
/// Test A re-opens this file afterward) and mirrors every buffer live to
/// `onBuffer`, for Test B's two concurrent SFSpeechRecognizer requests.
///
/// Not @MainActor: `installTap`'s callback runs on a real-time audio thread.
/// Isolating the whole class would force every tap callback through an actor
/// hop, which real-time audio code avoids; instead only `start`/`stop` (both
/// called from SwiftUI button actions, i.e. already on the main thread)
/// touch the @Published properties.
final class AudioCapture: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var lastRecordingURL: URL?

    private let engine = AVAudioEngine()
    private var outputFile: AVAudioFile?

    /// Fired on the audio thread for every tap buffer while recording.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    func start(label: String) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bilingual-spike", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Self.stampFormatter.string(from: Date())
        let url = dir.appendingPathComponent("\(label)-\(stamp).caf")

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        outputFile = file

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            try? self?.outputFile?.write(from: buffer)
            self?.onBuffer?(buffer)
        }

        try engine.start()

        isRecording = true
        lastRecordingURL = url
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        outputFile = nil
        onBuffer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss-SSS"
        return formatter
    }()
}
