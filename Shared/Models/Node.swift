import Foundation
import SwiftData

/// A single inspiration fragment — a "drift" — captured into the Ocean.
///
/// Branching is modelled as a self-referential relationship: a branch is a new
/// `Node` that points back to its `parent`, so the original thought is never
/// overwritten (Experience Principle: *Branching Over Editing*).
@Model
final class Node {
    // CloudKit mirroring forbids unique constraints and requires every stored
    // property to carry a default (records can materialize partially during a
    // merge). De-duplicate by `id` in fetches if a transient CloudKit merge
    // ever surfaces two — last-writer-wins resolves it.
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    /// Backing storage for `NodeKind` (SwiftData stores the raw value).
    var kindRaw: String = NodeKind.text.rawValue

    var title: String = ""
    var text: String = ""
    var transcription: String?
    var linkURLString: String?

    // MARK: Link enrichment
    //
    // When a link is attached, a best-effort pipeline fills these so the link
    // renders as a rich card and — crucially — so what the link is *about*
    // enters the understanding layer. `linkURLString` above stays the source of
    // truth; everything here is derived and disposable (cleared and re-derived
    // on demand). All optional / defaulted so existing stores migrate
    // lightly and CloudKit can materialize a record partially.

    /// Open Graph / page title (Stage A).
    var linkTitle: String? = nil
    /// Open Graph / meta description (Stage A) — the context input on devices
    /// without on-device summarization.
    var linkDescription: String? = nil
    /// The device-generated (Foundation Models) summary of the page's
    /// substance (Stage C) — preferred over `linkDescription` as context.
    var linkSummary: String? = nil
    /// Thumbnail, stored externally and synced exactly like `imageData`.
    @Attribute(.externalStorage) var linkImageData: Data? = nil

    /// Backing for `linkEnrichmentState` (the reason lives in the note).
    /// Defaulted so existing records migrate to `.notStarted`.
    var linkEnrichmentStateRaw: String = "notStarted"
    /// Why the link is in its current state: the failure reason, or which path
    /// produced (or skipped) the summary. Persisted for trust — it explains
    /// why a given link has, or lacks, a summary.
    var linkEnrichmentNote: String? = nil

    /// Legacy: voice drifts used to live as `.m4a` files in Application Support
    /// with only the file name stored here. Kept for one release as the source
    /// of the one-time migration into `audioData` (see `migrateLegacyAudio`);
    /// delete in a later release once every store has migrated.
    var audioFileName: String?

    /// Voice drift audio, stored in the model (externally) so it syncs through
    /// CloudKit exactly the way `imageData` does — a file on disk would not.
    @Attribute(.externalStorage) var audioData: Data?

    @Attribute(.externalStorage) var imageData: Data?

    /// Lightweight, AI-detected themes used for clustering and rediscovery.
    var themes: [String] = []
    var mood: String?

    /// Visual identity in the Ocean Field.
    var hue: Double = 0.55          // 0...1, mapped to an ocean-toned color
    var fieldX: Double = 0.5        // normalized 0...1 layout anchor
    var fieldY: Double = 0.5        // normalized 0...1 layout anchor

    var isArchived: Bool = false
    var lastResurfacedAt: Date?

    /// Ownership contract: the system may fill fields the user never touched,
    /// and must never overwrite ones they did. Set the moment an edit sheet
    /// save changes the corresponding field; checked by every understanding /
    /// regeneration pass (`NodeComposer.applyUnderstanding`).
    var titleEditedByUser: Bool = false
    var themesEditedByUser: Bool = false
    var transcriptEditedByUser: Bool = false
    /// When true, async understanding keeps the node's field anchor in place.
    var positionPinnedByUser: Bool = false

    /// Spatial anchoring (drift vs. anchor ontology): fresh nodes drift to the
    /// current of their primary theme; once the user edits a node, it stays in
    /// the current it lived in — this records that current's theme key. The
    /// Ocean layout groups by `anchorThemeKey ?? themes.first`, so later theme
    /// edits change the chips without relocating the thought. A future
    /// "Move to new current" action clears this.
    var anchorThemeKey: String?

    /// The branch relationship this node represents relative to its parent.
    var branchTypeRaw: String?

    @Relationship(deleteRule: .cascade) var children: [Node]?
    @Relationship(inverse: \Node.children) var parent: Node?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        kind: NodeKind = .text,
        title: String = "",
        text: String = "",
        transcription: String? = nil,
        linkURLString: String? = nil,
        audioData: Data? = nil,
        imageData: Data? = nil,
        themes: [String] = [],
        mood: String? = nil,
        hue: Double = 0.55,
        fieldX: Double = 0.5,
        fieldY: Double = 0.5,
        isArchived: Bool = false,
        branchType: BranchType? = nil,
        parent: Node? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.kindRaw = kind.rawValue
        self.title = title
        self.text = text
        self.transcription = transcription
        self.linkURLString = linkURLString
        self.audioData = audioData
        self.imageData = imageData
        self.themes = themes
        self.mood = mood
        self.hue = hue
        self.fieldX = fieldX
        self.fieldY = fieldY
        self.isArchived = isArchived
        self.lastResurfacedAt = nil
        self.branchTypeRaw = branchType?.rawValue
        self.parent = parent
    }
}

// MARK: - Convenience

extension Node {
    var kind: NodeKind {
        get { NodeKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    var branchType: BranchType? {
        get { branchTypeRaw.flatMap(BranchType.init(rawValue:)) }
        set { branchTypeRaw = newValue?.rawValue }
    }

    var linkURL: URL? {
        guard let linkURLString else { return nil }
        return URL(string: linkURLString)
    }

    /// The link's display host, stripped of a leading `www.` (e.g. "nytimes.com").
    var linkDomain: String? {
        guard let host = linkURL?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var linkEnrichmentState: LinkEnrichmentState {
        get {
            switch linkEnrichmentStateRaw {
            case "fetchingMeta":    return .fetchingMeta
            case "fetchingContent": return .fetchingContent
            case "summarizing":     return .summarizing
            case "enriched":        return .enriched
            case "failed":          return .failed(reason: linkEnrichmentNote ?? "Couldn't enrich this link.")
            default:                return .notStarted
            }
        }
        set {
            linkEnrichmentStateRaw = newValue.persistedKey
            if case let .failed(reason) = newValue { linkEnrichmentNote = reason }
        }
    }

    /// Enough metadata arrived to render a rich card rather than a bare URL.
    var hasRichLink: Bool {
        linkURL != nil && (linkTitle?.isEmpty == false || linkImageData != nil)
    }

    /// What the link is about, for the understanding pipeline: its title plus
    /// the device summary when present, else the page description. Empty when
    /// nothing has been derived yet (so a fresh link doesn't pollute meaning
    /// with a bare URL).
    var linkContext: String {
        guard linkURL != nil else { return "" }
        let body = linkSummary ?? linkDescription
        return [linkTitle, body]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    /// Resets all derived link fields back to "never enriched" — used when the
    /// URL changes or is removed, so a stale card/summary never lingers.
    func clearLinkEnrichment() {
        linkTitle = nil
        linkDescription = nil
        linkSummary = nil
        linkImageData = nil
        linkEnrichmentNote = nil
        linkEnrichmentStateRaw = "notStarted"
    }

    var isBranch: Bool { parent != nil }

    /// A short, human-friendly display title, derived from content when empty.
    var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        let source = !text.isEmpty ? text : (transcription ?? linkTitle ?? linkURLString ?? kind.label)
        let firstLine = source
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? source
        return String(firstLine.prefix(80))
    }

    /// The text used for semantic similarity and theme detection. A link's
    /// enriched context joins in so link drifts cluster and surface by what
    /// they're actually about, not by their URL.
    var searchableText: String {
        [title, text, transcription ?? "", linkContext, themes.joined(separator: " ")]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The thought's own content (interpreted essence + raw text, no theme
    /// labels) — used for meaning-level similarity where themes are weighed
    /// separately, so a shared theme isn't counted twice. A link contributes
    /// its enriched context (what it's about), never its bare URL.
    var meaningText: String {
        [title, text, transcription ?? "", linkContext]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var snippet: String {
        let source = !text.isEmpty
            ? text
            : (transcription ?? linkSummary ?? linkDescription ?? linkURLString ?? "")
        return String(source.prefix(140))
    }

    /// The raw content used to interpret a concise title from. For a link, that
    /// is what enrichment learned about it (title + summary/description); a bare
    /// URL only as a last resort.
    var rawContent: String {
        if !text.isEmpty { return text }
        if let transcription, !transcription.isEmpty { return transcription }
        if !linkContext.isEmpty { return linkContext }
        return linkURLString ?? ""
    }

    /// Freezes the node's place in the Ocean before a user edit changes its
    /// meaning fields: fresh nodes drift by semantic current; edited nodes
    /// keep their spatial anchor. (Themeless floaters simply stay floaters.)
    func anchorInPlace() {
        if anchorThemeKey == nil { anchorThemeKey = themes.first }
        positionPinnedByUser = true
    }
}
