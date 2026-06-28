import Foundation

/// The lifecycle of a link's enrichment — fetching its metadata, reading its
/// content, and summarizing it on-device for the understanding pipeline.
///
/// Persisted on `Node` as a raw case string plus a free-text note (the failure
/// reason, or which path produced — or deliberately skipped — the summary), so
/// it stays visible *why* a given link does or doesn't carry a summary.
enum LinkEnrichmentState: Equatable {
    /// No enrichment attempted yet (a freshly attached link, or a legacy node
    /// captured before this feature existed).
    case notStarted
    /// Stage A: fetching Open Graph metadata (title, thumbnail, description).
    case fetchingMeta
    /// Stage B: fetching the page and extracting readable content.
    case fetchingContent
    /// Stage C: summarizing the extracted content on-device.
    case summarizing
    /// Done: the card is rich and context has whatever the device could give
    /// it (an on-device summary on capable devices, the page description on
    /// the rest). `Node.linkEnrichmentNote` records which.
    case enriched
    /// Something past the URL failed. The URL — and whatever metadata Stage A
    /// managed to get — is kept; the row offers a retry.
    case failed(reason: String)

    /// The persisted case key (the reason travels separately, in the note).
    var persistedKey: String {
        switch self {
        case .notStarted:      return "notStarted"
        case .fetchingMeta:    return "fetchingMeta"
        case .fetchingContent: return "fetchingContent"
        case .summarizing:     return "summarizing"
        case .enriched:        return "enriched"
        case .failed:          return "failed"
        }
    }

    /// Whether enrichment is mid-flight (used to gate re-entry and to drive
    /// the progressive UI).
    var isInProgress: Bool {
        switch self {
        case .fetchingMeta, .fetchingContent, .summarizing: return true
        default: return false
        }
    }
}
