#if DEBUG
import Foundation
import AVFoundation

/// Simulator checks driven by the launch environment (`SIMCTL_CHILD_` prefix
/// on `simctl launch --console-pty`). Each prints one line and exits.
///
/// - `recorder`: records two seconds; the file must decode with a nonzero duration.
/// - `sync`: WatchConnectivity must activate on the paired simulator.
/// - `flow`: toggle, two seconds, toggle; the take must be queued with its
///   file, held through the Undo window, then handed to WatchConnectivity
///   (transfer pending, or already delivered).
/// - `undo`: toggle, two seconds, toggle, Undo; nothing may remain.
/// - `cap` (with `ORYNE_WATCH_CAP_SECONDS=2`): one toggle; the cap must end
///   and catch the take on its own.
@MainActor
enum WatchSelfTest {

    static func runIfRequested(model: WatchCaptureModel, cloudAvailable: Bool) {
        switch ProcessInfo.processInfo.environment["ORYNE_WATCH_SELFTEST"] {
        case "recorder": Task { await recorder() }
        case "sync": Task { await syncCheck(cloudAvailable: cloudAvailable) }
        case "flow": Task { await flow(model) }
        case "undo": Task { await undo(model) }
        case "cap": Task { await cap(model) }
        default: break
        }
    }

    private static func recorder() async {
        let recorder = WatchRecorder()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-\(UUID().uuidString).m4a")
        let start = await recorder.start(writingTo: url)
        guard start == .started else { report("RECORDER", "FAIL start=\(start)") }
        try? await Task.sleep(for: .seconds(2))
        guard let finished = await recorder.stop() else { report("RECORDER", "FAIL stop returned nil") }
        let decoded = (try? AVAudioPlayer(contentsOf: finished.url))?.duration ?? 0
        report("RECORDER", decoded > 1.5 ? "PASS duration=\(decoded)" : "FAIL duration=\(decoded)")
    }

    private static func syncCheck(cloudAvailable: Bool) async {
        let link = PhoneLink()
        link.activate()
        for _ in 0..<50 where !link.isActivated {
            try? await Task.sleep(for: .milliseconds(100))
        }
        report("SYNC", link.isActivated
            ? "PASS activated=true cloud=\(cloudAvailable)"
            : "FAIL activated=false (is the watch simulator paired?)")
    }

    private static func recordTwoSeconds(_ model: WatchCaptureModel, name: String) async -> UUID {
        await model.toggle()
        guard model.stage == .recording else { report(name, "FAIL stage after first toggle=\(model.stage)") }
        try? await Task.sleep(for: .seconds(2))
        await model.toggle()
        guard case .caught(let id) = model.stage else { report(name, "FAIL stage after second toggle=\(model.stage)") }
        return id
    }

    private static func flow(_ model: WatchCaptureModel) async {
        let id = await recordTwoSeconds(model, name: "FLOW")
        guard FileManager.default.fileExists(atPath: model.queue.audioURL(for: id).path),
              model.queue.state.item(id)?.status == .onWatch,
              model.queue.state.item(id)?.phoneTransfer == .notSent
        else { report("FLOW", "FAIL take not queued and held") }
        try? await Task.sleep(for: .seconds(WatchCaptureModel.undoWindow + 1))
        guard let item = model.queue.state.item(id) else { report("FLOW", "FAIL take vanished") }
        // Handed to WatchConnectivity: pending, or already delivered (on the
        // simulator the paired phone often finishes inside the extra second).
        let handedOver = item.phoneTransfer == .pending || item.phoneTransfer == .delivered
        report("FLOW", handedOver && model.stage == .idle
            ? "PASS transfer=\(item.phoneTransfer.rawValue) status=\(item.status.rawValue)"
            : "FAIL transfer=\(item.phoneTransfer.rawValue) stage=\(model.stage)")
    }

    private static func undo(_ model: WatchCaptureModel) async {
        let id = await recordTwoSeconds(model, name: "UNDO")
        model.undo()
        let fileGone = !FileManager.default.fileExists(atPath: model.queue.audioURL(for: id).path)
        report("UNDO", fileGone && model.queue.state.item(id) == nil && model.stage == .idle
            ? "PASS nothing remains"
            : "FAIL fileGone=\(fileGone) queued=\(model.queue.state.item(id) != nil)")
    }

    private static func cap(_ model: WatchCaptureModel) async {
        await model.toggle()
        guard model.stage == .recording else { report("CAP", "FAIL stage after toggle=\(model.stage)") }
        try? await Task.sleep(for: .seconds(WatchRecorder.cap + 2))
        guard case .caught = model.stage else { report("CAP", "FAIL stage after cap=\(model.stage)") }
        report("CAP", "PASS caught at the cap")
    }

    static func report(_ name: String, _ line: String) -> Never {
        print("\(name)_SELFTEST \(line)")
        exit(0)
    }
}
#endif
