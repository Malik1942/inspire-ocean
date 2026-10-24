import Foundation
import SwiftData
import BackgroundTasks

/// The daily pass while charging (docs/plans/memory-layer/SPEC.md,
/// decision 7): fills understanding records that predate the reader,
/// refreshes current summaries whose membership changed, and maintains
/// what Oryne knows about the person from their recent thoughts, adding
/// what is new and removing what lost its ground. Also runnable by hand
/// from Settings, which is how it is tested on a simulator (background
/// task scheduling is not supported there).
@MainActor
enum Consolidation {
    static let taskIdentifier = "com.inspireocean.consolidation"
    static let lastRunKey = "consolidation.lastRun"
    static let enrichmentPerRun = 60
    static let currentSummariesPerRun = 12
    static let recentDays = 45
    static let recentThoughts = 40

    enum Reason: String { case background, manual, launch }

    struct Summary: Equatable {
        var enriched = 0
        var currentsSummarized = 0
        var recordsAdded = 0
        var recordsRemoved = 0
    }

    static var lastRun: Date? {
        UserDefaults.standard.object(forKey: lastRunKey) as? Date
    }

    // MARK: Background task

    /// Registered before launch finishes (the app delegate), as the system
    /// requires. The handler runs the pass and books the next one.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            let work = Task { @MainActor in
                let ok = await run(context: Persistence.shared.mainContext, ai: LocalOceanAIService(), reason: .background) != nil
                task.setTaskCompleted(success: ok)
            }
            task.expirationHandler = { work.cancel() }
            Task { @MainActor in schedule() }
        }
    }

    /// Once a day at the earliest, only on external power, no network
    /// needed. Submitting again replaces the pending request.
    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: The pass

    static var running = false

    /// Nil when another pass is already running or the device has no model
    /// (the record and the summaries need one; the pass waits).
    @discardableResult
    static func run(context: ModelContext, ai: any OceanAIService, reason: Reason) async -> Summary? {
        guard !running, OnDeviceModel.isReadyCached else { return nil }
        running = true
        defer { running = false }
        var summary = Summary()

        summary.enriched = await enrichUnderstanding(context: context, ai: ai)
        if Task.isCancelled { return summary }
        if #available(iOS 26, *) {
            summary.currentsSummarized = await refreshCurrentSummaries(context: context)
            if Task.isCancelled { return summary }
            let (added, removed) = await maintainMemory(context: context)
            summary.recordsAdded = added
            summary.recordsRemoved = removed
        }
        UserDefaults.standard.set(Date.now, forKey: lastRunKey)
        return summary
    }

    /// Thoughts whose understanding record predates the reader, newest
    /// first, titles and themes kept (the Library does the same on open).
    private static func enrichUnderstanding(context: ModelContext, ai: any OceanAIService) async -> Int {
        let version = ThoughtReading.version
        let descriptor = FetchDescriptor<Node>(
            predicate: #Predicate { !$0.isArchived && !$0.isExample && $0.understandingVersion < version },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let nodes = try? context.fetch(descriptor) else { return 0 }
        var count = 0
        for node in nodes.prefix(enrichmentPerRun) {
            if Task.isCancelled { break }
            let raw = node.rawContent
            guard !raw.isEmpty else { continue }
            let understanding = await ai.understand(raw, currents: [])
            NodeComposer.applyUnderstanding(understanding, to: node, preserveTitle: true, preserveThemes: true)
            count += 1
        }
        if count > 0 {
            try? context.save()
            CurrentRegistry.reconcile(context: context)
        }
        return count
    }

    /// One sentence per current whose membership changed since its last
    /// summary, in the language most of its thoughts are in.
    @available(iOS 26, *)
    private static func refreshCurrentSummaries(context: ModelContext) async -> Int {
        let currents = (try? context.fetch(FetchDescriptor<Current>())) ?? []
        let nodes = (try? context.fetch(FetchDescriptor<Node>(predicate: #Predicate { !$0.isArchived && !$0.isExample }))) ?? []
        var byKey: [String: [Node]] = [:]
        for node in nodes { if let key = node.currentKey { byKey[key, default: []].append(node) } }

        var count = 0
        for current in currents {
            if count >= currentSummariesPerRun || Task.isCancelled { break }
            let members = (byKey[current.key] ?? []).sorted { $0.createdAt > $1.createdAt }
            guard members.count >= 2, members.count != current.summaryMemberCount else { continue }
            let chinese = members.filter { ThoughtReading.dominantScriptIsChinese($0.rawContent) }.count * 2 > members.count
            let lines = members.prefix(10).map { "- “\($0.displayTitle)”: \(String($0.rawContent.prefix(120)))" }
            let name = current.name(preferringChinese: chinese)
            if let text = await FoundationMemoryExtractor.summarizeCurrent(name: name, lines: lines, inChinese: chinese) {
                current.summary = text
                current.summaryMemberCount = members.count
                current.updatedAt = .now
                count += 1
            }
        }
        if count > 0 { try? context.save() }
        return count
    }

    /// Add what the recent thoughts show and is not yet kept; remove what
    /// lost every thought it rested on; never touch what the user edited,
    /// never write again what they sent away.
    @available(iOS 26, *)
    private static func maintainMemory(context: ModelContext) async -> (added: Int, removed: Int) {
        let all = (try? context.fetch(FetchDescriptor<MemoryRecord>())) ?? []
        let tombstones = all.filter(\.isDismissed)
        let records = all.filter { !$0.isDismissed }
        let live = (try? context.fetch(FetchDescriptor<Node>(predicate: #Predicate { !$0.isArchived && !$0.isExample }))) ?? []
        let liveIDs = Set(live.map(\.id))

        // Prune first: a record standing on nothing should not shape what is read next.
        let standing = records.map { MemoryRules.Standing(id: $0.id, evidence: $0.evidenceNodeIDs, userEdited: $0.userEdited, createdAt: $0.createdAt) }
        let pruneIDs = Set(MemoryRules.toPrune(standing, liveThoughtIDs: liveIDs))
        var removed = 0
        for record in records where pruneIDs.contains(record.id) {
            context.delete(record)
            removed += 1
        }

        let since = Date.now.addingTimeInterval(-Double(recentDays) * 86_400)
        let recent = live.filter { $0.createdAt >= since }.sorted { $0.createdAt > $1.createdAt }.prefix(recentThoughts)
        guard recent.count >= 3 else {
            if removed > 0 { try? context.save() }
            return (0, removed)
        }
        // Tombstones are not pruned by evidence (the refusal outlives the
        // thoughts), only capped.
        let dropTombstones = Set(MemoryRules.tombstonesToDrop(tombstones.compactMap { stone in stone.dismissedAt.map { (stone.id, $0) } }))
        for stone in tombstones where dropTombstones.contains(stone.id) { context.delete(stone) }
        let dismissedTexts = tombstones.filter { !dropTombstones.contains($0.id) }.map(\.text)

        var refs: [String: UUID] = [:]
        var texts: [UUID: String] = [:]
        let lines = recent.enumerated().map { index, node -> FoundationMemoryExtractor.Line in
            let ref = "t\(index + 1)"
            refs[ref] = node.id
            texts[node.id] = node.displayTitle + " " + node.rawContent + " " + node.entities.joined(separator: " ")
            var parts = [node.createdAt.formatted(.relative(presentation: .named))]
            if let category = node.category { parts.append(category.rawValue) }
            if !node.entities.isEmpty { parts.append("mentions " + node.entities.joined(separator: ", ")) }
            return .init(
                reference: ref,
                text: "\(parts.joined(separator: " · ")) · “\(node.displayTitle)”: \(String(node.rawContent.prefix(110)))",
                category: node.category?.rawValue,
                entities: node.entities
            )
        }
        let kept = records.filter { !pruneIDs.contains($0.id) }
        let existingTexts = kept.map(\.text)

        guard let proposals = await FoundationMemoryExtractor.extract(lines: Array(lines), existing: existingTexts) else {
            if removed > 0 { try? context.save() }
            return (0, removed)
        }

        var added = 0
        var existing = existingTexts
        for proposal in proposals {
            let fresh = MemoryRules.fresh([proposal.text], against: existing)
            guard let text = fresh.first, !MemoryRules.isDismissed(text, among: dismissedTexts) else { continue }
            // Two distinct thoughts at least (one thought cited twice is
            // still one), and each must actually touch the observation.
            var seen = Set<UUID>()
            let cited = proposal.evidence
                .compactMap { refs[$0.lowercased().trimmingCharacters(in: .whitespaces)] }
                .filter { seen.insert($0).inserted }
            let grounded = MemoryRules.groundedEvidence(for: text, evidence: cited.map { texts[$0] ?? "" })
            let evidence = grounded.map { cited[$0] }
            guard evidence.count >= 2 else { continue }
            let worded = MemoryRules.softened(text, grounded: evidence.count)
            context.insert(MemoryRecord(kind: proposal.kind, text: worded, evidenceNodeIDs: evidence))
            existing.append(worded)
            added += 1
            if kept.count + added >= MemoryRules.maxRecords { break }
        }
        if added > 0 || removed > 0 { try? context.save() }
        return (added, removed)
    }

    // MARK: What Ask reads

    /// The newest records as a short preamble, read on the main actor.
    /// Dismissed records are tombstones, not knowledge.
    static func preamble(context: ModelContext) -> String? {
        var descriptor = FetchDescriptor<MemoryRecord>(
            predicate: #Predicate { $0.dismissedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = MemoryRules.preambleRecords
        let records = (try? context.fetch(descriptor)) ?? []
        return MemoryRules.preamble(records.map { ($0.kind, $0.text) })
    }
}
