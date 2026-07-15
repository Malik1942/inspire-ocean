import Foundation

/// Central timestamped log every harness writes to. Each line is tagged with
/// a stream id so the exported text can be read (or grepped) per-stream:
///   - "capture"      recording lifecycle (start/stop, file saved)
///   - "A-zh" / "A-en" Test A: the iOS 26 SpeechTranscriber, zh-CN pass then en-US pass
///   - "B-zh" / "B-en" Test B: the two concurrent legacy SFSpeechRecognizer tasks
///
/// Not @MainActor: harnesses append from background threads (audio tap,
/// recognizer callback queues, async result loops), so `append` dispatches to
/// main itself rather than forcing every call site through an actor hop.
final class SpikeLog: ObservableObject {
    struct Line: Identifiable {
        let id = UUID()
        let timestamp: Date
        let stream: String
        let text: String
    }

    @Published private(set) var lines: [Line] = []

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    func append(_ stream: String, _ text: String) {
        let line = Line(timestamp: Date(), stream: stream, text: text)
        if Thread.isMainThread {
            lines.append(line)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.lines.append(line)
            }
        }
    }

    func clear() {
        lines.removeAll()
    }

    /// Plain-text export for the Share sheet — one line per log entry,
    /// timestamp first so the two passes / two streams can be interleaved
    /// and still read in order.
    var exportText: String {
        lines
            .map { "[\(Self.timeFormatter.string(from: $0.timestamp))] \($0.stream): \($0.text)" }
            .joined(separator: "\n")
    }
}
