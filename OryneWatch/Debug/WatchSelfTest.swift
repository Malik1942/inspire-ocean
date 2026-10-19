#if DEBUG
import Foundation
import AVFoundation

/// Simulator checks driven by the launch environment (`SIMCTL_CHILD_` prefix
/// on `simctl launch --console-pty`). Each prints one line and exits.
///
/// - `ORYNE_WATCH_SELFTEST=recorder`: records two seconds and checks the file
///   decodes with a nonzero duration.
/// - `ORYNE_WATCH_SELFTEST=sync`: waits for WatchConnectivity activation and
///   reports whether the session is active and whether the iCloud inbox is
///   available in this build.
@MainActor
enum WatchSelfTest {

    static func runIfRequested(sync: TakeSync? = nil, cloudAvailable: Bool = false) {
        switch ProcessInfo.processInfo.environment["ORYNE_WATCH_SELFTEST"] {
        case "recorder": Task { await recorder() }
        case "sync": Task { await syncCheck(cloudAvailable: cloudAvailable) }
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

    static func report(_ name: String, _ line: String) -> Never {
        print("\(name)_SELFTEST \(line)")
        exit(0)
    }
}
#endif
