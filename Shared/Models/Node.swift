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

    var isBranch: Bool { parent != nil }

    /// A short, human-friendly display title, derived from content when empty.
    var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        let source = !text.isEmpty ? text : (transcription ?? linkURLString ?? kind.label)
        let firstLine = source
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? source
        return String(firstLine.prefix(80))
    }

    /// The text used for semantic similarity and theme detection.
    var searchableText: String {
        [title, text, transcription ?? "", themes.joined(separator: " ")]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The thought's own content (interpreted essence + raw text, no theme
    /// labels) — used for meaning-level similarity where themes are weighed
    /// separately, so a shared theme isn't counted twice.
    var meaningText: String {
        [title, text, transcription ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var snippet: String {
        let source = !text.isEmpty ? text : (transcription ?? linkURLString ?? "")
        return String(source.prefix(140))
    }

    /// The raw content used to interpret a concise title from.
    var rawContent: String {
        if !text.isEmpty { return text }
        if let transcription, !transcription.isEmpty { return transcription }
        return linkURLString ?? ""
    }
}
