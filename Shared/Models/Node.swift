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

    /// Legacy single-image storage. Superseded by the `images` relationship
    /// (multiple images per node); kept as the source of the one-time back-fill
    /// `migrateLegacyImages` and as the fallback in `imageDatas` so an image
    /// never blanks out in the window before migration runs (or for a legacy
    /// node arriving late over CloudKit). New nodes write `images`, never this.
    @Attribute(.externalStorage) var imageData: Data?

    /// Ordered set of attached images, each its own externally-stored blob.
    /// Optional + cascade-deleted with the node, mirroring `children`.
    @Relationship(deleteRule: .cascade) var images: [NodeImage]?

    // MARK: Picture reading (docs/plans/memory-layer/SPEC.md, pictures)
    //
    // The on-device model takes no images on iOS 26, so what a picture
    // holds reaches the understanding layer as words the device read off
    // it: the text in it and what it shows. Derived and disposable, like
    // the link fields; small text, so it syncs and a second device never
    // reads the pictures again. Every field is defaulted for CloudKit.

    /// The words in the attached pictures, as Vision read them, in the
    /// pictures' own languages.
    var pictureText: String? = nil
    /// What the pictures show: a few lowercase English labels from scene
    /// classification ("sunset", "beach").
    var pictureLabels: [String] = []
    /// `PictureReading.version` when the pictures were last read, else 0 so
    /// a later open reads them (and a better reader rereads them).
    var pictureReadingVersion: Int = 0

    /// Lightweight, AI-detected themes used for clustering and rediscovery.
    var themes: [String] = []
    var mood: String?

    /// Visual identity in the Ocean Field.
    var hue: Double = 0.55          // 0...1, mapped to an ocean-toned color
    var fieldX: Double = 0.5        // normalized 0...1 layout anchor
    var fieldY: Double = 0.5        // normalized 0...1 layout anchor

    var isArchived: Bool = false
    /// Seeded starter content: quietly badged and clearable from Settings once
    /// the user has thoughts of their own. Export will leave examples out.
    var isExample: Bool = false
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

    // MARK: Understanding record (docs/plans/memory-layer/SPEC.md, layer 1)
    //
    // What the understanding step knows about the thought beyond its title
    // and themes. Small text, so it syncs through CloudKit like the rest of
    // the Ocean (decision 5); the vectors derived from it do not. Every field
    // is defaulted so existing stores migrate lightly.

    /// One of `ThoughtCategory`; nil until a model has read the thought.
    var categoryRaw: String? = nil
    /// One of `ThoughtLanguage`.
    var languageRaw: String? = nil
    /// One line on what the thought is about, in the other language (Chinese
    /// for an English thought, English for a Chinese or mixed one), so a
    /// question in either language can reach it.
    var gistOther: String? = nil
    /// Proper names the thought mentions: people, places, products, projects.
    var entities: [String] = []
    /// Language-neutral theme keys (English slugs), the bridge toward one
    /// Ocean across languages. Phase 1 stores them; phase 3 groups by them.
    var themeKeys: [String] = []
    /// `ThoughtStatus` for a task or bug. The user's alone.
    var statusRaw: String? = nil
    /// `ThoughtReading.version` when a model produced the full record, else 0
    /// so a later open with a model can enrich it.
    var understandingVersion: Int = 0
    /// `UnderstandingSource` of the last pass.
    var understandingSourceRaw: String? = nil

    /// A short reading of a long whisper, written by the on-device model in
    /// the words' own language. Shown above the transcript; never replaces it.
    var summary: String?
    /// The recognition locale the kept transcript came from ("en-US").
    var transcriptLocale: String?
    /// The other language's pass, kept only when the two passes scored close
    /// enough that the user should be the judge. Swapping makes it the
    /// transcript and keeps the previous one here.
    var alternateTranscription: String?
    var alternateTranscriptLocale: String?

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
        self.isExample = false
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

    // MARK: Images

    /// Hard cap on attached images per node — enforced in Capture, the edit
    /// sheet, and the branch composer.
    static let maxImages = 10

    /// Attached images in display order.
    var orderedImages: [NodeImage] { (images ?? []).sorted { $0.sortIndex < $1.sortIndex } }

    /// The node's image bytes in order. Prefers the `images` relationship and
    /// falls back to the legacy single `imageData`, so an image never blanks out
    /// before `migrateLegacyImages` runs — or for a legacy node arriving late
    /// over CloudKit. After migration the fallback is moot (legacy field nil).
    var imageDatas: [Data] {
        let fromChildren = orderedImages.compactMap(\.data)
        if !fromChildren.isEmpty { return fromChildren }
        if let imageData { return [imageData] }
        return []
    }

    /// Whether the node carries any image (the new set, or a not-yet-migrated
    /// legacy single image).
    var hasImages: Bool { !(images?.isEmpty ?? true) || imageData != nil }

    /// What the device read off the attached pictures, as one passage the
    /// understanding and retrieval layers take alongside the words
    /// (`PictureReading.context`). Empty without pictures or before they
    /// were read.
    var pictureContext: String {
        guard hasImages else { return "" }
        return PictureReading.context(text: pictureText, labels: pictureLabels)
    }

    /// Whether the pictures still wait for the current reader.
    var needsPictureReading: Bool {
        hasImages && pictureReadingVersion < PictureReading.version
    }

    /// Drops the derived picture fields so a changed set is read afresh.
    func clearPictureReading() {
        pictureText = nil
        pictureLabels = []
        pictureReadingVersion = 0
    }

    var isBranch: Bool { parent != nil }

    /// The current this thought belongs to: the user's placement
    /// (`anchorThemeKey`) wins over the primary theme. Nil for a themeless
    /// thought, which drifts in the adrift current.
    var currentKey: String? {
        if let anchorThemeKey, !anchorThemeKey.isEmpty { return anchorThemeKey }
        return themes.first.map(ThoughtReading.slug)
    }

    // MARK: Understanding record accessors

    var category: ThoughtCategory? {
        get { categoryRaw.flatMap(ThoughtCategory.init(rawValue:)) }
        set { categoryRaw = newValue?.rawValue }
    }

    var language: ThoughtLanguage? {
        get { languageRaw.flatMap(ThoughtLanguage.init(rawValue:)) }
        set { languageRaw = newValue?.rawValue }
    }

    var status: ThoughtStatus? {
        get { statusRaw.flatMap(ThoughtStatus.init(rawValue:)) }
        set { statusRaw = newValue?.rawValue }
    }

    var understandingSource: UnderstandingSource? {
        understandingSourceRaw.flatMap(UnderstandingSource.init(rawValue:))
    }

    /// The texts a question is compared against, one per language the
    /// thought can be reached in: its own words, and its gist in the other
    /// language. Apple's embeddings live in per-script spaces, so this is
    /// what lets a Chinese question meet an English thought.
    var retrievalTexts: [String] {
        [searchableText, gistOther ?? ""].filter { !$0.isEmpty }
    }

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
        [title, text, transcription ?? "", linkContext, pictureContext, themes.joined(separator: " "), entities.joined(separator: " ")]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The thought's own content (interpreted essence + raw text, no theme
    /// labels) — used for meaning-level similarity where themes are weighed
    /// separately, so a shared theme isn't counted twice. A link contributes
    /// its enriched context (what it's about), never its bare URL; a picture
    /// what the device read off it.
    var meaningText: String {
        [title, text, transcription ?? "", linkContext, pictureContext]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var snippet: String {
        let source = !text.isEmpty
            ? text
            : (summary ?? transcription ?? linkSummary ?? linkDescription ?? linkURLString ?? "")
        return String(source.prefix(140))
    }

    /// The raw content used to interpret a concise title from. For a link, that
    /// is what enrichment learned about it (title + summary/description); for
    /// a picture, what the device read off it; a bare URL only as a last resort.
    var rawContent: String {
        if !text.isEmpty { return text }
        if let transcription, !transcription.isEmpty { return transcription }
        if !linkContext.isEmpty { return linkContext }
        if !pictureContext.isEmpty { return pictureContext }
        return linkURLString ?? ""
    }

    /// Freezes the node's place in the Ocean before a user edit changes its
    /// meaning fields: fresh nodes drift by semantic current; edited nodes
    /// keep their spatial anchor. (Themeless floaters simply stay floaters.)
    func anchorInPlace() {
        if anchorThemeKey == nil { anchorThemeKey = currentKey }
        positionPinnedByUser = true
    }
}
