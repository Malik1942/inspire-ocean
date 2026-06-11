import Foundation
import SwiftUI
import Observation

enum OceanTab: Hashable {
    case capture
    case ocean
    case ask
    case library
}

/// Lightweight cross-tab coordinator (e.g. "Ask Ocean about this node" jumps
/// from the Expanded Node View to the Ask tab with a prefilled prompt).
@Observable
final class AppState {
    var selectedTab: OceanTab = .ocean
    var fastCaptureRequest: FastCaptureRequest?

    /// A prompt queued for the Ask tab, consumed when Ask appears.
    var pendingAskPrompt: String?

    /// A node queued for the Ocean tab (e.g. tapping the Resurfacing widget),
    /// consumed when the Ocean Field appears: it focuses and opens the node.
    var pendingFocusNodeID: UUID?

    init() {
        // Testing seam: launch straight into a tab via the OCEAN_START_TAB env var
        // (e.g. `SIMCTL_CHILD_OCEAN_START_TAB=ask`). No effect in normal use.
        switch ProcessInfo.processInfo.environment["OCEAN_START_TAB"]?.lowercased() {
        case "capture": selectedTab = .capture
        case "ask": selectedTab = .ask
        case "library": selectedTab = .library
        case "ocean": selectedTab = .ocean
        default: break
        }
    }

    func ask(_ prompt: String) {
        pendingAskPrompt = prompt
        selectedTab = .ask
    }

    func startFastCapture(
        source: FastCaptureLaunchSource = .inApp,
        inputPreference: FastCaptureInputPreference? = nil,
        imageData: Data? = nil,
        seedText: String = ""
    ) {
        fastCaptureRequest = FastCaptureRequest(
            source: source,
            inputPreference: inputPreference ?? FastCapturePreferences.inputPreference,
            imageData: imageData,
            seedText: seedText
        )
    }

    func consumePendingFastCapture() {
        guard let request = FastCaptureLaunchStore.consumePendingRequest() else { return }
        fastCaptureRequest = request
    }

    // MARK: Deep links (widgets, Control Center, Lock Screen)

    /// Routes `oryn://` URLs (the legacy `inspireocean://` scheme is still accepted so existing Shortcuts keep working):
    /// - `oryn://capture/thought` — Fast Capture, typing first
    /// - `oryn://capture/whisper` — Fast Capture, voice first
    /// - `oryn://capture` — Fast Capture, user's preferred input
    /// - `oryn://node/<uuid>` — focus + open a node in the Ocean
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "oryn" || url.scheme == "inspireocean" else { return }
        let path = [url.host, url.pathComponents.dropFirst().first]
            .compactMap { $0 }

        switch path.first {
        case "capture":
            let mode = path.count > 1 ? path[1] : nil
            let preference: FastCaptureInputPreference? = switch mode {
            case "thought": .typingFirst
            case "whisper": .voiceFirst
            default: nil
            }
            startFastCapture(source: .widget, inputPreference: preference)

        case "node":
            guard path.count > 1, let id = UUID(uuidString: path[1]) else { return }
            pendingFocusNodeID = id
            selectedTab = .ocean

        default:
            break
        }
    }
}
