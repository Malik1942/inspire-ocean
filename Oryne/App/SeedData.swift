import Foundation
import SwiftData

/// Seeds a small, evocative Ocean on first launch so the field feels alive and
/// rediscovery/dialogue can be demonstrated immediately.
enum SeedData {

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let seededKey = "seed.completed"
        let descriptor = FetchDescriptor<Node>()
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        guard existing == 0 else {
            // An established (e.g. CloudKit-synced) store: never drift demo
            // examples into it later, even if the user empties it.
            UserDefaults.standard.set(true, forKey: seededKey)
            return
        }

        #if DEBUG
        // Perf and legibility seam, following the OCEAN_START_TAB pattern:
        // OCEAN_SIM_COUNT=60 (or 200) fills an empty store with a synthetic
        // themed ocean instead of the demo drifts. Debug builds only. This
        // seam predates and deliberately ignores the seed.completed one-shot.
        if let raw = ProcessInfo.processInfo.environment["OCEAN_SIM_COUNT"],
           let count = Int(raw), count > 0 {
            seedSimulated(count: count, context: context)
            return
        }
        #endif

        // One-shot per install: once the starter examples have seeded, clearing
        // them (or later deleting every real thought) must never re-seed.
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }

        let now = Date()
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

        // Seeded thoughts are examples: quietly badged and clearable from Settings
        // once the user has thoughts of their own. Export will leave them out.
        let drifts: [(String, NodeKind, Double)] = [
            (String(localized: "The ocean keeps every river that ever fed it. Maybe memory works the same way: nothing lost, only carried."), .text, 0.5),
            (String(localized: "Bioluminescence: light that living things make in the dark. Like ideas that only glow once you stop looking for them."), .text, 1.2),
            (String(localized: "Voice note: I keep returning to the feeling of the tide. Things leaving and coming back without me forcing them."), .voice, 2.0),
            (String(localized: "Why do my best ideas arrive in the shower and never at the desk? Something about not gripping them too hard."), .text, 4.4),
            (String(localized: "A reading list that only grows, never finishes. Maybe the point was never to finish, only to drift through."), .text, 6.0),
            (String(localized: "Color study: deep teal fading into violet at the horizon. I want a whole app to feel like dusk underwater."), .image, 11.0),
            (String(localized: "Note to self: capture before consciousness. The thought before you judge the thought."), .text, 18.0)
        ]

        for (textBody, kind, daysAgo) in drifts {
            let node: Node
            switch kind {
            case .voice:
                node = NodeComposer.make(kind: .voice, transcription: textBody)
            case .image:
                node = NodeComposer.make(kind: .image, text: textBody)
            default:
                node = NodeComposer.make(kind: .text, text: textBody)
            }
            node.isExample = true
            node.createdAt = ago(daysAgo)
            node.updatedAt = ago(daysAgo)
            context.insert(node)
        }

        // The one cultivated example: a fragment and the question grown from it,
        // so a new Ocean shows what living alongside an idea (延展) looks like,
        // not only a field of one-liners.
        let parent = NodeComposer.make(
            kind: .text,
            text: String(localized: "I keep meeting the same idea wearing different clothes. Maybe the repetition is the point, not the noise.")
        )
        parent.isExample = true
        parent.createdAt = ago(16.0)
        parent.updatedAt = ago(16.0)
        context.insert(parent)

        let branch = NodeComposer.make(
            kind: .text,
            text: String(localized: "What is the one question all these disguises keep circling?"),
            branchType: .question,
            parent: parent
        )
        branch.isExample = true
        branch.createdAt = ago(14.0)
        branch.updatedAt = ago(14.0)
        context.insert(branch)

        try? context.save()
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    #if DEBUG
    /// A deterministic synthetic ocean for frame-rate and legibility runs:
    /// clustered themes, a sprinkle of floaters, and capture dates spread
    /// from today back through two months so the energy gradient shows.
    @MainActor
    private static func seedSimulated(count: Int, context: ModelContext) {
        let themePool = [
            "water & ocean", "memory", "light & color", "sound & rhythm",
            "tools", "attention", "dreams", "tide & return"
        ]
        let now = Date()
        for index in 0..<count {
            // Titled on purpose: the Library backfill re-understands any node
            // without a title, which would re-theme the whole synthetic ocean
            // into one current moments after launch.
            let node = NodeComposer.make(
                kind: .text,
                title: "Synthetic drift \(index + 1)",
                text: "Synthetic drift \(index + 1), a placeholder thought for performance and layout runs.",
                detectThemes: false
            )
            // Every fifth thought floats free; the rest gather into currents.
            if index % 5 != 4 {
                let theme = themePool[index % themePool.count]
                node.themes = [theme]
                node.hue = NodeComposer.hue(for: theme)
            }
            let daysAgo = Double(index) * 60.0 / Double(max(1, count))
            node.createdAt = now.addingTimeInterval(-daysAgo * 86_400)
            node.updatedAt = node.createdAt
            context.insert(node)
        }
        try? context.save()
    }
    #endif
}
