import Foundation
import SwiftData

/// Turns a thought's pictures into words it can be understood and found by
/// (docs/plans/memory-layer/SPEC.md, pictures).
///
/// Two steps, like a link's enrichment: `read` stores what the device read
/// off the pictures (`PictureReader`), and `enrich` reads then re-derives the
/// understanding record from the words and the pictures together. Capture
/// reads before its one understanding pass (`VoiceUnderstanding`), so a
/// thought with a picture is understood once, with the picture; the Library
/// backfill, the edit sheet and the intents go through `enrich`.
///
/// `@MainActor`: SwiftData on the main context; Vision is awaited off-main
/// and the node re-fetched by id afterwards, mirroring `LinkEnrichmentService`.
@MainActor
final class PictureEnrichmentService {
    static let shared = PictureEnrichmentService()
    private init() {}

    /// One read per node at a time within a session; the persisted
    /// `pictureReadingVersion` guards across launches.
    private var inFlight: Set<UUID> = []

    private static func log(_ message: String) {
        #if DEBUG
        print("🖼 PictureReading: \(message)")
        #endif
    }

    // MARK: Read

    /// Reads the node's pictures and stores the reading, when they still
    /// wait for the current reader (or `force`). Returns true when a reading
    /// with any words or labels landed on the node.
    @discardableResult
    func read(nodeID: UUID, context: ModelContext, force: Bool = false) async -> Bool {
        guard !inFlight.contains(nodeID) else { return false }
        guard let node = Self.fetch(nodeID, in: context), node.hasImages,
              force || node.needsPictureReading else { return false }
        inFlight.insert(nodeID)
        defer { inFlight.remove(nodeID) }

        let datas = node.imageDatas
        let reading = await PictureReader.read(datas)
        guard let fresh = Self.fetch(nodeID, in: context) else { return false }
        fresh.pictureText = reading.text
        fresh.pictureLabels = reading.labels
        fresh.pictureReadingVersion = PictureReading.version
        try? context.save()
        Self.log("\(datas.count) picture(s) → labels: \(reading.labels.joined(separator: ", ")); text: \(reading.text?.count ?? 0) chars")
        return !reading.isEmpty
    }

    // MARK: Enrich

    /// Reads the pictures, then re-derives the understanding record from
    /// the thought's words and pictures together. Safe to call repeatedly:
    /// it no-ops when the pictures were read by the current reader.
    func enrich(nodeID: UUID, context: ModelContext, ai: any OceanAIService, force: Bool = false) {
        guard !inFlight.contains(nodeID) else { return }
        guard let node = Self.fetch(nodeID, in: context), node.hasImages,
              force || node.needsPictureReading else { return }
        Task {
            guard await read(nodeID: nodeID, context: context, force: force) else { return }
            await Self.rederive(nodeID: nodeID, context: context, ai: ai)
        }
    }

    /// The understanding pass over words and pictures. A thought with words
    /// of its own keeps the title those words gave it; the picture deepens
    /// its themes and record. User-edited fields stay the user's
    /// (`NodeComposer.applyUnderstanding`).
    static func rederive(nodeID: UUID, context: ModelContext, ai: any OceanAIService) async {
        guard let node = fetch(nodeID, in: context) else { return }
        let basis = node.meaningText
        guard !basis.isEmpty else { return }
        let currents = CurrentSnap.candidates(in: context, excluding: nodeID, forEntry: basis)
        let understanding = await ai.understand(basis, currents: currents)
        guard let fresh = fetch(nodeID, in: context) else { return }
        let hasOwnWords = !fresh.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(fresh.transcription ?? "").isEmpty
        NodeComposer.applyUnderstanding(understanding, to: fresh, preserveTitle: hasOwnWords)
        try? context.save()
        CurrentRegistry.reconcile(context: context)
    }

    private static func fetch(_ id: UUID, in context: ModelContext) -> Node? {
        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
