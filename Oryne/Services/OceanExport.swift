import Foundation

/// Exports the Ocean to a shareable zip: one Markdown file per theme (the
/// readable layer), a full JSON backup (the faithful layer), and an assets/
/// folder for images and (optionally) voice. Examples are excluded upstream by
/// the caller (it snapshots only non-example nodes).
///
/// Threading: `Node` is a SwiftData `@Model` bound to its main-actor context, so
/// its fields and `Data` cannot be read off the main actor. `snapshot(from:)` runs
/// on the main actor and copies everything into a `Sendable` value; `buildArchive`
/// then writes files and zips entirely off the main actor, never touching a `Node`.
enum OceanExport {

    // MARK: Snapshot (main actor)

    /// An immutable, Sendable copy of one node: every stored field plus the
    /// derived readable strings and the image/audio bytes, all read on the main
    /// actor so the off-main writer can work without a `Node`.
    struct NodeSnapshot: Sendable {
        let id: UUID
        let createdAt: Date
        let updatedAt: Date
        let kindRaw: String
        let kindLabel: String
        let title: String
        let displayTitle: String
        let body: String
        let text: String
        let transcription: String?
        let linkURLString: String?
        let linkTitle: String?
        let linkDescription: String?
        let linkSummary: String?
        let linkEnrichmentStateRaw: String
        let linkEnrichmentNote: String?
        let themes: [String]
        let primaryThemeKey: String?
        let anchorThemeKey: String?
        let mood: String?
        let hue: Double
        let fieldX: Double
        let fieldY: Double
        let isArchived: Bool
        let lastResurfacedAt: Date?
        let titleEditedByUser: Bool
        let themesEditedByUser: Bool
        let transcriptEditedByUser: Bool
        let positionPinnedByUser: Bool
        let branchTypeRaw: String?
        let branchTypeLabel: String?
        let parentID: UUID?
        let childIDs: [UUID]
        let imageDatas: [Data]
        let audioData: Data?
    }

    @MainActor
    static func snapshot(from node: Node) -> NodeSnapshot {
        NodeSnapshot(
            id: node.id,
            createdAt: node.createdAt,
            updatedAt: node.updatedAt,
            kindRaw: node.kindRaw,
            kindLabel: node.kind.label,
            title: node.title,
            displayTitle: node.displayTitle,
            body: node.rawContent,
            text: node.text,
            transcription: node.transcription,
            linkURLString: node.linkURLString,
            linkTitle: node.linkTitle,
            linkDescription: node.linkDescription,
            linkSummary: node.linkSummary,
            linkEnrichmentStateRaw: node.linkEnrichmentStateRaw,
            linkEnrichmentNote: node.linkEnrichmentNote,
            themes: node.themes,
            primaryThemeKey: OceanLayoutEngine.currentKey(for: node),
            anchorThemeKey: node.anchorThemeKey,
            mood: node.mood,
            hue: node.hue,
            fieldX: node.fieldX,
            fieldY: node.fieldY,
            isArchived: node.isArchived,
            lastResurfacedAt: node.lastResurfacedAt,
            titleEditedByUser: node.titleEditedByUser,
            themesEditedByUser: node.themesEditedByUser,
            transcriptEditedByUser: node.transcriptEditedByUser,
            positionPinnedByUser: node.positionPinnedByUser,
            branchTypeRaw: node.branchTypeRaw,
            branchTypeLabel: node.branchType?.label,
            parentID: node.parent?.id,
            childIDs: (node.children ?? []).map(\.id),
            imageDatas: node.imageDatas,
            audioData: node.audioData
        )
    }

    // MARK: JSON backup DTO

    /// The faithful, round-trippable layer. Captures every field plus the
    /// relationships (parent id, children ids); the bytes live in assets/, so
    /// this references them by filename and stays lean.
    struct NodeBackup: Codable {
        let id: UUID
        let parentID: UUID?
        let childIDs: [UUID]
        let kind: String
        let branchType: String?
        let title: String
        let displayTitle: String
        let text: String
        let transcription: String?
        let linkURLString: String?
        let linkTitle: String?
        let linkDescription: String?
        let linkSummary: String?
        let linkEnrichmentState: String
        let linkEnrichmentNote: String?
        let themes: [String]
        let primaryTheme: String?
        let anchorThemeKey: String?
        let mood: String?
        let hue: Double
        let fieldX: Double
        let fieldY: Double
        let createdAt: Date
        let updatedAt: Date
        let lastResurfacedAt: Date?
        let titleEditedByUser: Bool
        let themesEditedByUser: Bool
        let transcriptEditedByUser: Bool
        let positionPinnedByUser: Bool
        let imageFiles: [String]
        let audioFile: String?

        init(from s: NodeSnapshot, imageFiles: [String], audioFile: String?) {
            id = s.id
            parentID = s.parentID
            childIDs = s.childIDs
            kind = s.kindRaw
            branchType = s.branchTypeRaw
            title = s.title
            displayTitle = s.displayTitle
            text = s.text
            transcription = s.transcription
            linkURLString = s.linkURLString
            linkTitle = s.linkTitle
            linkDescription = s.linkDescription
            linkSummary = s.linkSummary
            linkEnrichmentState = s.linkEnrichmentStateRaw
            linkEnrichmentNote = s.linkEnrichmentNote
            themes = s.themes
            primaryTheme = s.primaryThemeKey
            anchorThemeKey = s.anchorThemeKey
            mood = s.mood
            hue = s.hue
            fieldX = s.fieldX
            fieldY = s.fieldY
            createdAt = s.createdAt
            updatedAt = s.updatedAt
            lastResurfacedAt = s.lastResurfacedAt
            titleEditedByUser = s.titleEditedByUser
            themesEditedByUser = s.themesEditedByUser
            transcriptEditedByUser = s.transcriptEditedByUser
            positionPinnedByUser = s.positionPinnedByUser
            self.imageFiles = imageFiles
            self.audioFile = audioFile
        }
    }

    struct OceanBackup: Codable {
        let format = "oryne-export-v1"
        let exportedAt: Date
        let nodeCount: Int
        let nodes: [NodeBackup]
    }

    enum ExportError: Error { case zipFailed }

    // MARK: Build (off main)

    /// Writes the folder and returns a stable temp .zip URL to hand to a share
    /// sheet. Runs entirely off the main actor over Sendable snapshots.
    static func buildArchive(from snapshots: [NodeSnapshot], includeVoice: Bool) throws -> URL {
        let fm = FileManager.default
        let stamp = dateStamp(Date())
        let folderName = "Oryne-Export-\(stamp)"
        let root = fm.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
        let assets = root.appendingPathComponent("assets", isDirectory: true)
        try? fm.removeItem(at: root)
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)

        // 1. Assets, recording the relative paths each node contributes.
        var imageFilesByID: [UUID: [String]] = [:]
        var audioFileByID: [UUID: String] = [:]
        for s in snapshots {
            for (i, data) in s.imageDatas.enumerated() {
                let name = "\(s.id.uuidString)-\(i).jpg"
                try data.write(to: assets.appendingPathComponent(name))
                imageFilesByID[s.id, default: []].append("assets/\(name)")
            }
            // Older voice notes lose their audio 30 days after transcription
            // (expireConfirmedAudio), so audioData is often nil: skip silently.
            if includeVoice, let audio = s.audioData {
                let name = "\(s.id.uuidString).m4a"
                try audio.write(to: assets.appendingPathComponent(name))
                audioFileByID[s.id] = "assets/\(name)"
            }
        }

        // 2. One Markdown file per theme. A thought is filed under its primary
        // theme; a branch follows its parent, so the thread reads continuously.
        let byID = Dictionary(snapshots.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let uncategorized = String(localized: "Uncategorized")

        // Roots: no parent, or a parent that isn't in the export set (e.g. a real
        // branch grown off an excluded example) so it stands on its own.
        func parentInSet(_ s: NodeSnapshot) -> Bool { s.parentID.flatMap { byID[$0] } != nil }
        let roots = snapshots.filter { !parentInSet($0) }

        // Derive child lists from parentID (the same field roots key off), not
        // from each node's childIDs, so grouping and recursion can never disagree:
        // a node with a set parent is always reached, even if a transient CloudKit
        // merge left the parent's children half-materialized (see the note atop Node).
        var childrenByParent: [UUID: [NodeSnapshot]] = [:]
        for s in snapshots where parentInSet(s) {
            childrenByParent[s.parentID!, default: []].append(s)
        }

        var groups: [String: [NodeSnapshot]] = [:]
        for r in roots {
            let label = r.primaryThemeKey.map { OceanLayoutEngine.displayLabel(for: $0) } ?? uncategorized
            groups[label, default: []].append(r)
        }

        // `seen` guards against a pathological parent/child cycle (a normal SwiftData
        // tree cannot cycle) and against a node reachable from two roots.
        func descendants(_ s: NodeSnapshot, _ seen: inout Set<UUID>) -> [NodeSnapshot] {
            guard seen.insert(s.id).inserted else { return [] }
            var out = [s]
            for c in childrenByParent[s.id] ?? [] { out.append(contentsOf: descendants(c, &seen)) }
            return out
        }

        func render(_ s: NodeSnapshot, level: Int, _ seen: inout Set<UUID>) -> String {
            guard seen.insert(s.id).inserted else { return "" }
            let hashes = String(repeating: "#", count: min(level, 6))
            var out: String
            if parentInSet(s), let bt = s.branchTypeLabel {
                out = "\(hashes) \(bt): \(s.displayTitle)\n\n"
            } else {
                out = "\(hashes) \(dateStamp(s.createdAt)) · \(s.kindLabel)\n\n"
            }
            let body = s.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { out += "\(body)\n\n" }
            for path in imageFilesByID[s.id] ?? [] { out += "![](\(path))\n\n" }
            let kids = (childrenByParent[s.id] ?? []).sorted { $0.createdAt < $1.createdAt }
            for k in kids { out += render(k, level: level + 1, &seen) }
            return out
        }

        for (label, themeRoots) in groups {
            let sortedRoots = themeRoots.sorted { $0.createdAt > $1.createdAt }
            var countSeen = Set<UUID>()
            let all = sortedRoots.flatMap { descendants($0, &countSeen) }
            let dates = all.map(\.createdAt).sorted()
            var md = "---\n"
            md += "theme: \"\(label)\"\n"
            md += "thoughts: \(all.count)\n"
            if let first = dates.first, let last = dates.last {
                md += "earliest: \(dateStamp(first))\n"
                md += "latest: \(dateStamp(last))\n"
            }
            md += "---\n\n# \(label)\n\n"
            var renderSeen = Set<UUID>()
            for r in sortedRoots { md += render(r, level: 2, &renderSeen) }
            let file = root.appendingPathComponent("\(sanitizeFilename(label)).md")
            try md.write(to: file, atomically: true, encoding: .utf8)
        }

        // 3. Faithful JSON backup of every exported node.
        let backupNodes = snapshots.map {
            NodeBackup(from: $0, imageFiles: imageFilesByID[$0.id] ?? [], audioFile: audioFileByID[$0.id])
        }
        let backup = OceanBackup(exportedAt: Date(), nodeCount: backupNodes.count, nodes: backupNodes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(backup).write(to: root.appendingPathComponent("backup.json"))

        // 4. Zip the folder with no dependency, then drop the working copy.
        let zipURL = try zipFolder(root, name: folderName)
        try? fm.removeItem(at: root)
        return zipURL
    }

    // MARK: Helpers

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dateStamp(_ date: Date) -> String { stampFormatter.string(from: date) }

    private static func sanitizeFilename(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    /// Zips a folder using the system coordinator (no third-party dependency).
    /// `.forUploading` hands back a temporary .zip valid only inside the closure,
    /// so copy it to a stable temp URL we own before returning.
    private static func zipFolder(_ folder: URL, name: String) throws -> URL {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var copyError: Error?
        var result: URL?
        coordinator.coordinate(readingItemAt: folder, options: .forUploading, error: &coordError) { zipped in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).zip")
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: zipped, to: dest)
                result = dest
            } catch {
                copyError = error
            }
        }
        if let coordError { throw coordError }
        if let copyError { throw copyError }
        guard let result else { throw ExportError.zipFailed }
        return result
    }
}
