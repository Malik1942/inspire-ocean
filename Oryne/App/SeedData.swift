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
        insertExamples(into: context, now: now)

        try? context.save()
        UserDefaults.standard.set(true, forKey: seededKey)
        UserDefaults.standard.set(currentAppLanguage(), forKey: seedLanguageKey)
    }

    /// Inserts the demo example set (a single Introduction current holding a
    /// short app tour and one sample thought) as badged, clearable,
    /// export-excluded nodes. Text resolves via `String(localized:)` against
    /// the current bundle language at call time, so both first-seed and
    /// language re-seed produce content in the active language. Does not save;
    /// the caller owns the transaction.
    @MainActor
    static func insertExamples(into context: ModelContext, now: Date) {

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

    }

    /// Records the app language the example set was last seeded in, so a later
    /// per-app language change can re-localize the demo content (see
    /// `relocalizeExamplesIfNeeded`). Distinct from `seed.completed`.
    static let seedLanguageKey = "seed.language"

    /// The active app language, resolved (en / zh-Hans). Intersects the user's
    /// preferred languages with the bundle's available localizations, so it
    /// matches what `String(localized:)` will actually render.
    static func currentAppLanguage() -> String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// Whether/how to re-localize the demo examples on launch. Pure: no I/O, so
    /// the branching is reviewable by inspection. The caller performs the wipe,
    /// the re-seed, and the UserDefaults writes.
    ///
    /// - `.reseed` only when the store holds nothing but untouched examples AND
    ///   the language changed since they were seeded — i.e. the user has neither
    ///   written, cleared, nor edited anything. This preserves the one-shot
    ///   intent for real data and never adds demo content to a store that has
    ///   real writing.
    /// - `.adoptBaseline` when we have no recorded seed language (an install
    ///   that seeded before this feature shipped): silently record the current
    ///   language as the baseline instead of guessing, so we never wipe an
    ///   existing user's examples on the upgrade launch.
    enum ExampleRelocalization: Equatable {
        case skip
        case adoptBaseline(String)
        case reseed(String)
    }

    static func shouldRelocalizeExamples(
        seeded: Bool,
        realCount: Int,
        exampleCount: Int,
        anyExampleEdited: Bool,
        recordedLanguage: String?,
        currentLanguage: String
    ) -> ExampleRelocalization {
        // Never act before the first seed has happened (seedIfNeeded owns that).
        guard seeded else { return .skip }

        // Upgrade migration: unknown baseline. Adopt the current language rather
        // than risk wiping examples whose seed language we can't determine.
        guard let recordedLanguage else { return .adoptBaseline(currentLanguage) }

        // The narrow re-seed window: examples-only store, nothing written,
        // nothing edited, and the language actually changed.
        if realCount == 0,
           exampleCount > 0,
           !anyExampleEdited,
           recordedLanguage != currentLanguage {
            return .reseed(currentLanguage)
        }

        return .skip
    }

    /// Re-localizes the demo examples after a per-app language change, but only
    /// when the store holds nothing but untouched examples. Runs at launch,
    /// AFTER `seedIfNeeded`, and deliberately does NOT share its `existing == 0`
    /// guard: this path may replace examples with examples, never add demo
    /// content to a store that has real writing.
    ///
    /// Device scope: keyed off `seed.completed`, a per-install UserDefaults flag
    /// that is not CloudKit-synced, so this only ever runs on the device that
    /// originally seeded — a second synced device (existing != 0 on its first
    /// launch, never seeds, never records a seed language) won't re-seed.
    @MainActor
    static func relocalizeExamplesIfNeeded(_ context: ModelContext) {
        let seeded = UserDefaults.standard.bool(forKey: "seed.completed")
        let recorded = UserDefaults.standard.string(forKey: seedLanguageKey)
        let current = currentAppLanguage()

        // Count real vs example nodes without loading full objects where avoidable.
        let realCount = (try? context.fetchCount(
            FetchDescriptor<Node>(predicate: #Predicate { $0.isExample == false })
        )) ?? 0
        let examples = (try? context.fetch(
            FetchDescriptor<Node>(predicate: #Predicate { $0.isExample == true && $0.isArchived == false })
        )) ?? []
        let anyExampleEdited = examples.contains {
            $0.titleEditedByUser || $0.themesEditedByUser
                || $0.transcriptEditedByUser || $0.positionPinnedByUser
        }

        switch shouldRelocalizeExamples(
            seeded: seeded,
            realCount: realCount,
            exampleCount: examples.count,
            anyExampleEdited: anyExampleEdited,
            recordedLanguage: recorded,
            currentLanguage: current
        ) {
        case .skip:
            return

        case .adoptBaseline(let language):
            UserDefaults.standard.set(language, forKey: seedLanguageKey)

        case .reseed(let language):
            // Delete the example roots; the cascade delete rule takes any
            // branch children with their parents. realCount == 0 here, so
            // no real node is ever attached to an example.
            for node in examples where node.parent == nil {
                context.delete(node)
            }
            insertExamples(into: context, now: Date())
            try? context.save()
            UserDefaults.standard.set(language, forKey: seedLanguageKey)
        }
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
