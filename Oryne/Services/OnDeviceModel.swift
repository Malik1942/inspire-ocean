import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether Apple's on-device model (Apple Intelligence) can answer on this
/// device right now, and if not, why, in words a user can read. One check
/// behind titles, themes, current joining, whisper and link summaries and
/// Ask, so Settings and every fallback note tell the same story.
enum OnDeviceModel {
    enum Status: Sendable {
        case ready
        case unavailable(reason: String)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    /// The live status. The query itself can take over a second on
    /// ineligible hardware, so hot paths cache the answer and views read it
    /// off the main thread.
    static var status: Status {
        #if DEBUG
        // Test hook: force either fork regardless of what the device reports,
        // so both paths can be exercised on one simulator. Never compiled into
        // a release build. Set via `simctl launch ... ORYNE_FORCE_MODEL=1|0`
        // (the older ORYNE_FORCE_SUMMARIZATION name still works).
        let env = ProcessInfo.processInfo.environment
        if let forced = env["ORYNE_FORCE_MODEL"] ?? env["ORYNE_FORCE_SUMMARIZATION"] {
            return forced == "1" ? .ready : .unavailable(reason: "forced off for testing")
        }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .ready
            case .unavailable(let reason):
                return .unavailable(reason: describe(reason))
            @unknown default:
                return .unavailable(reason: String(localized: "the on-device model is unavailable"))
            }
        }
        return .unavailable(reason: String(localized: "this device runs an earlier iOS"))
        #else
        return .unavailable(reason: String(localized: "Foundation Models isn't in this build"))
        #endif
    }

    /// `status.isReady`, read once per process: the query is slow on
    /// ineligible hardware and the answer does not change mid-session.
    static let isReadyCached: Bool = status.isReady

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:           return String(localized: "this device isn't eligible for Apple Intelligence")
        case .appleIntelligenceNotEnabled: return String(localized: "Apple Intelligence is turned off")
        case .modelNotReady:               return String(localized: "the on-device model is still downloading")
        @unknown default:                  return String(localized: "Apple Intelligence is unavailable")
        }
    }
    #endif
}
