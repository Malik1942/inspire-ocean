import Foundation

@MainActor
final class SpikeViewModel: ObservableObject {
    enum TakeLabel: String, CaseIterable, Identifiable {
        case pureMandarin = "pure-mandarin"
        case pureEnglish = "pure-english"
        case codeSwitched = "code-switched"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .pureMandarin: "Pure Mandarin"
            case .pureEnglish: "Pure English"
            case .codeSwitched: "Code-switched"
            }
        }
    }

    @Published var takeLabel: TakeLabel = .pureMandarin
    @Published private(set) var isRecording = false
    @Published private(set) var isRunningTestA = false
    @Published var statusNote: String?

    private let log: SpikeLog
    private let capture = AudioCapture()
    private var dualHarness: DualSFSpeechHarness?
    private var lastFileURL: URL?
    private var didRequestPermissions = false

    var hasRecording: Bool { lastFileURL != nil }

    init(log: SpikeLog) {
        self.log = log
    }

    func requestPermissionsIfNeeded() async {
        guard !didRequestPermissions else { return }
        didRequestPermissions = true
        if let problem = await Permissions.requestAll() {
            statusNote = problem
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        log.append("capture", "— starting take: \(takeLabel.displayName) —")

        let harness = DualSFSpeechHarness(log: log)
        dualHarness = harness
        harness.start()

        capture.onBuffer = { [weak harness] buffer in
            harness?.append(buffer)
        }

        do {
            try capture.start(label: takeLabel.rawValue)
            isRecording = true
        } catch {
            log.append("capture", "failed to start: \(error)")
            dualHarness = nil
        }
    }

    private func stopRecording() {
        capture.stop()
        dualHarness?.stop()
        isRecording = false
        lastFileURL = capture.lastRecordingURL
        if let lastFileURL {
            log.append("capture", "stopped — saved \(lastFileURL.lastPathComponent)")
        }
    }

    func runTestA() {
        guard let url = lastFileURL else {
            log.append("A", "no recording yet — record a take first")
            return
        }
        isRunningTestA = true
        log.append("A", "— running SpeechTranscriber pass (zh-CN, then en-US) on \(url.lastPathComponent) —")
        Task {
            await ModernTranscriberHarness.run(fileURL: url, log: log)
            isRunningTestA = false
        }
    }
}
