import WidgetKit
import SwiftUI
import AppIntents

/// Drift Capture from Control Center (PRD §7: "Control Center shortcut").
///
/// One tap stages a Fast Capture request (same App-Group pipeline the Action
/// Button uses) and opens the app straight into the capture overlay.
struct FastCaptureControl: ControlWidget {
    let kind = "com.inspireocean.app.widgets.fastcapturecontrol"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: kind) {
            ControlWidgetButton(action: OpenFastCaptureIntent()) {
                Label("Fast Capture", systemImage: "drop")
            }
        }
        .displayName("Fast Capture")
        .description("Catch a thought before it disappears.")
    }
}

/// Runs in the widget extension: stage the request, then open the app.
struct OpenFastCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Fast Capture"
    static let description = IntentDescription(
        "Open Oryne in a lightweight capture state.",
        categoryName: "Capture"
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        FastCaptureLaunchStore.stagePendingRequest(source: .controlCenter)
        return .result()
    }
}
