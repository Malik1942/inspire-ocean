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

        // One starter current, named for what it is, holding exactly two
        // example thoughts: a short tour of the app, and one idea so the
        // reader sees what a captured thought looks like. Read once, then
        // cleared from Settings. Export leaves examples out.
        //
        // Titles and themes are pre-set and marked user-owned so the
        // understanding backfill never retitles them or re-themes the pair
        // apart into separate currents.
        let introTheme = String(localized: "introduction")

        let intro = NodeComposer.make(
            kind: .text,
            title: String(localized: "How Oryne works"),
            text: String(localized: "Oryne is a quiet ocean for whatever crosses your mind. Capture a thought in text, voice, or an image, and it drifts in as a glowing mote. Thoughts that share a theme gather into currents like this one. Open a thought to grow it with a question, or ask across the whole Ocean from the Ask tab. Old thoughts resurface on their own when it matters, and the Library lays everything out when you want to browse. Seen enough? Clear these examples in Settings."),
            detectThemes: false
        )
        let example = NodeComposer.make(
            kind: .text,
            title: String(localized: "Ideas arrive in the shower"),
            text: String(localized: "Why do my best ideas arrive in the shower and never at the desk? Something about not gripping them too hard."),
            detectThemes: false
        )

        // The tour reads first: streams surface the newest thought on top.
        for (node, minutesAgo) in [(intro, 5.0), (example, 30.0)] {
            node.isExample = true
            node.themes = [introTheme]
            node.hue = NodeComposer.hue(for: introTheme)
            node.titleEditedByUser = true
            node.themesEditedByUser = true
            node.createdAt = now.addingTimeInterval(-minutesAgo * 60)
            node.updatedAt = node.createdAt
            context.insert(node)
        }

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
