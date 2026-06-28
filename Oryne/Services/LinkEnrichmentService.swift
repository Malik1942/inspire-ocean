import Foundation
import SwiftData
import LinkPresentation
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns a bare attached URL into a rich, *understood* link.
///
/// Three independent, best-effort stages, with the path chosen up front from the
/// device's capability (so we never start the heavy path on hardware that can't
/// finish it, and there's no try-then-fail):
///
/// - **Stage A — metadata** (online, fast): title + thumbnail via
///   `LPMetadataProvider`, plus the Open Graph / meta description parsed from the
///   page. This alone makes the link a rich card.
/// - **Stage B — content** (online, full path only): fetch the page and extract
///   Readability-style main text (`PageContent`).
/// - **Stage C — summary** (on-device, full path only): summarize that text with
///   Apple's Foundation Models. The *summary* — not raw page text — is what
///   enters the understanding pipeline.
///
/// On devices without on-device summarization, only Stage A runs and the page
/// description is what feeds context. Every stage degrades to leave the link
/// usable as a plain, tappable URL.
///
/// `@MainActor`: all SwiftData reads/writes happen on the main context; the
/// network and model work is awaited (off-main) and the node is re-fetched by id
/// after each suspension, mirroring `CaptureSession`.
@MainActor
final class LinkEnrichmentService {
    static let shared = LinkEnrichmentService()
    private init() {}

    /// Guards against two concurrent runs for the same node within a session;
    /// the persisted `linkEnrichmentState` guards across launches.
    private var inFlight: Set<UUID> = []

    // MARK: Capability decision (made up front)

    enum Summarization {
        case available
        case unavailable(reason: String)

        var label: String {
            switch self {
            case .available: return "FULL (A+B+C)"
            case .unavailable(let reason): return "METADATA-ONLY (\(reason))"
            }
        }
    }

    /// DEBUG-only stage tracing, surfaced on the console for runtime verification.
    private static func log(_ message: String) {
        #if DEBUG
        print("🔗 LinkEnrichment: \(message)")
        #endif
    }

    /// Whether the device can summarize on-device right now, and if not, why —
    /// the reason is persisted so it's visible why a link lacks a summary.
    static var summarization: Summarization {
        #if DEBUG
        // Test hook: force either fork regardless of what the device reports, so
        // both paths can be exercised on a single simulator. Never compiled into
        // a release build. Set via `simctl launch ... ORYNE_FORCE_SUMMARIZATION=1|0`.
        if let forced = ProcessInfo.processInfo.environment["ORYNE_FORCE_SUMMARIZATION"] {
            return forced == "1" ? .available : .unavailable(reason: "forced off for testing")
        }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                return .unavailable(reason: describe(reason))
            @unknown default:
                return .unavailable(reason: "the on-device model is unavailable")
            }
        }
        return .unavailable(reason: "this device runs an earlier iOS")
        #else
        return .unavailable(reason: "Foundation Models isn't in this build")
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:           return "this device isn't eligible for Apple Intelligence"
        case .appleIntelligenceNotEnabled: return "Apple Intelligence is turned off"
        case .modelNotReady:               return "the on-device model is still downloading"
        @unknown default:                  return "Apple Intelligence is unavailable"
        }
    }
    #endif

    // MARK: Entry point

    /// Kicks off (or retries) enrichment for the node's attached link. Safe to
    /// call repeatedly — it no-ops when already in flight, and skips work that's
    /// already done unless `force` is set (a manual refresh).
    func enrich(nodeID: UUID, context: ModelContext, ai: any OceanAIService, force: Bool = false) {
        guard !inFlight.contains(nodeID) else { return }
        guard let node = Self.fetch(nodeID, in: context), let url = node.linkURL else { return }
        switch node.linkEnrichmentState {
        case .enriched where !force:                            return
        case .fetchingMeta, .fetchingContent, .summarizing:     return
        default:                                                break
        }
        inFlight.insert(nodeID)
        Task { await run(nodeID: nodeID, url: url, context: context, ai: ai) }
    }

    // MARK: Pipeline

    private func run(nodeID: UUID, url: URL, context: ModelContext, ai: any OceanAIService) async {
        defer { inFlight.remove(nodeID) }

        // Decide the path before doing anything heavy.
        let summarization = Self.summarization
        Self.log("start \(url.host ?? url.absoluteString) — path: \(summarization.label)")

        // ---- Stage A: metadata ----
        setState(.fetchingMeta, nodeID: nodeID, context: context)

        let lp = await Self.fetchLinkMetadata(url)          // title + image (LinkPresentation)
        let html = await PageContent.fetchHTML(url)          // one fetch: description now, content later
        Self.log("Stage A — lpTitle:\(lp.title != nil) lpImage:\(lp.imageData != nil) html:\(html?.count ?? 0)b")

        var thumbnail = lp.imageData.flatMap { Self.thumbnail(from: $0) }
        if thumbnail == nil, let html, let imageURL = PageContent.ogImageURL(from: html, relativeTo: url),
           let bytes = await Self.downloadData(imageURL, timeout: 8) {
            thumbnail = Self.thumbnail(from: bytes)
        }
        let title = (lp.title ?? html.flatMap(PageContent.ogTitle))?.trimmed
        let description = html.flatMap(PageContent.metaDescription)

        var gotMeta = false
        if let node = Self.fetch(nodeID, in: context) {
            if let title, !title.isEmpty { node.linkTitle = title; gotMeta = true }
            if let thumbnail { node.linkImageData = thumbnail; gotMeta = true }
            if let description, !description.isEmpty { node.linkDescription = description; gotMeta = true }
            try? context.save()
        }

        // ---- Fork on capability ----
        if case .unavailable(let reason) = summarization {
            await finishMetadataOnly(nodeID: nodeID, gotMeta: gotMeta, reason: reason, context: context, ai: ai)
            return
        }

        // ---- Stage B: readable content (full path) ----
        setState(.fetchingContent, nodeID: nodeID, context: context)
        let readableText = html.flatMap { PageContent.readableText(from: $0) }
        Self.log("Stage B — readable:\(readableText?.count ?? 0) chars")
        guard let readable = readableText else {
            Self.log("Stage B failed — failing with retry (deriveContext:\(gotMeta))")
            await fail(
                nodeID: nodeID,
                reason: gotMeta
                    ? "Couldn't read the page to summarize. Tap to retry."
                    : "Couldn't reach this link. Tap to retry.",
                deriveContext: gotMeta, context: context, ai: ai
            )
            return
        }

        // ---- Stage C: on-device summary (full path) ----
        setState(.summarizing, nodeID: nodeID, context: context)
        let summary = await Self.summarize(readable, title: title)

        if let summary, !summary.isEmpty {
            Self.log("Stage C — summarized (\(summary.count) chars) → enriched, re-deriving context")
            if let node = Self.fetch(nodeID, in: context) {
                node.linkSummary = summary
                node.linkEnrichmentNote = "Summarized on-device."
                node.linkEnrichmentState = .enriched
                try? context.save()
            }
            await rederiveContext(nodeID: nodeID, context: context, ai: ai)
        } else {
            Self.log("Stage C — no summary (model declined/empty) → failed+retry, context from description")
            // The model declined or returned nothing usable (guardrail,
            // context length, transient): the summary is an enhancement, never a
            // requirement — keep the rich card, derive context from the
            // description, and offer a retry for the summary itself.
            await fail(
                nodeID: nodeID,
                reason: "Couldn't summarize this on-device. Tap to retry.",
                deriveContext: true, context: context, ai: ai
            )
        }
    }

    /// Metadata-only path (no on-device summarization): Stage A is the whole
    /// story. The page description — when we got one — feeds context.
    private func finishMetadataOnly(
        nodeID: UUID, gotMeta: Bool, reason: String,
        context: ModelContext, ai: any OceanAIService
    ) async {
        guard let node = Self.fetch(nodeID, in: context) else { return }
        if gotMeta {
            Self.log("metadata-only → enriched (no summary); context from description. reason: \(reason)")
            node.linkEnrichmentNote = "Apple Intelligence unavailable (\(reason)) — using the page description for context."
            node.linkEnrichmentState = .enriched
            try? context.save()
            await rederiveContext(nodeID: nodeID, context: context, ai: ai)
        } else {
            Self.log("metadata-only → no metadata reached → failed+retry")
            node.linkEnrichmentState = .failed(reason: "Couldn't reach this link. Tap to retry.")
            try? context.save()
        }
    }

    // MARK: Context hook

    /// Re-derives the node's automatic title & themes from its meaning text —
    /// which now includes the link's summary (preferred) or description. Goes
    /// through `NodeComposer.applyUnderstanding`, so a title or themes the user
    /// edited by hand are never overwritten; only auto-derived ones are upgraded.
    private func rederiveContext(nodeID: UUID, context: ModelContext, ai: any OceanAIService) async {
        guard let node = Self.fetch(nodeID, in: context) else { return }
        let basis = node.meaningText
        guard !basis.isEmpty else { return }
        let understanding = await ai.understand(basis)
        guard let fresh = Self.fetch(nodeID, in: context) else { return }
        NodeComposer.applyUnderstanding(understanding, to: fresh)
        try? context.save()
    }

    // MARK: State helpers

    private func setState(_ state: LinkEnrichmentState, nodeID: UUID, context: ModelContext) {
        guard let node = Self.fetch(nodeID, in: context) else { return }
        node.linkEnrichmentState = state
        try? context.save()
    }

    private func fail(
        nodeID: UUID, reason: String, deriveContext: Bool,
        context: ModelContext, ai: any OceanAIService
    ) async {
        if let node = Self.fetch(nodeID, in: context) {
            node.linkEnrichmentState = .failed(reason: reason)
            try? context.save()
        }
        if deriveContext { await rederiveContext(nodeID: nodeID, context: context, ai: ai) }
    }

    // MARK: Stage A — LinkPresentation

    /// Title + a preview image via `LPMetadataProvider` (the system's blessed
    /// rich-link path). Best-effort: returns nils on any failure.
    private static func fetchLinkMetadata(_ url: URL) async -> (title: String?, imageData: Data?) {
        await withCheckedContinuation { continuation in
            let provider = LPMetadataProvider()
            provider.timeout = 10
            provider.startFetchingMetadata(for: url) { [provider] metadata, error in
                _ = provider   // keep the provider alive until completion
                guard let metadata, error == nil else {
                    continuation.resume(returning: (nil, nil))
                    return
                }
                let title = metadata.title
                guard let imageProvider = metadata.imageProvider,
                      imageProvider.canLoadObject(ofClass: UIImage.self) else {
                    continuation.resume(returning: (title, nil))
                    return
                }
                imageProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    let data = (object as? UIImage)?.pngData()   // downsampled by the caller
                    continuation.resume(returning: (title, data))
                }
            }
        }
    }

    private static func downloadData(_ url: URL, timeout: TimeInterval) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        guard let (data, response) = try? await URLSession(configuration: config).data(for: request) else {
            return nil
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return data
    }

    /// Card-sized preview JPEG, via the shared downsampler (so the link
    /// thumbnail and the main image attachment share one compression path).
    private static func thumbnail(from data: Data) -> Data? {
        ImageDownsampler.downsample(data, maxPixel: ImageDownsampler.Size.thumbnail, quality: 0.7)
    }

    // MARK: Stage C — on-device summary

    /// Summarizes the page's substance with Apple's Foundation Models. The input
    /// is truncated to a safe budget before sending; guardrail refusals,
    /// context-length, and any other model error degrade to nil (no summary).
    private static func summarize(_ text: String, title: String?) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else { return nil }
        let input = String(text.prefix(4_000))
        do {
            let session = LanguageModelSession {
                """
                You summarize web pages for a personal inspiration journal, so a \
                saved link carries what it is about. Read the page content and \
                reply with two or three plain sentences capturing its substance — \
                its main subject and key points, not its navigation, ads, or \
                boilerplate. No preamble, no lists, no markdown — just the summary.
                """
            }
            let prompt = title.map { "Title: \($0)\n\nContent:\n\(input)" } ?? "Content:\n\(input)"
            let response = try await session.respond(to: prompt)
            let summary = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty ? nil : summary
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: Fetch

    private static func fetch(_ id: UUID, in context: ModelContext) -> Node? {
        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
