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

    /// A prompt queued for the Ask tab, consumed when Ask appears.
    var pendingAskPrompt: String?

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
}
