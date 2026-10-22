import Foundation
import SwiftData

/// Keeps `Current` rows true to the thoughts (docs/plans/memory-layer/
/// SPEC.md, layer 2), and does the three things a user can do to a current:
/// rename, merge, and move thoughts into a new one (a split). Membership
/// lives on the thought as `anchorThemeKey`, so every operation here writes
/// thoughts first and lets `reconcile` make the rows follow.
enum CurrentRegistry {

    /// One-time: every live thought gets an explicit key (its old anchor or
    /// first theme, slugged), so currents that were exact strings become
    /// keyed entities. Stored keys that already are keys pass through.
    static let migrationDefaultsKey = "currents.keyed.v1"

    @MainActor
    static func migrateIfNeeded(context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migrationDefaultsKey) else { return }
        let nodes = (try? context.fetch(FetchDescriptor<Node>())) ?? []
        for node in nodes {
            let source = node.anchorThemeKey ?? node.themes.first
            guard let source, !source.isEmpty else { continue }
            let key = ThoughtReading.slug(source)
            if node.anchorThemeKey != key { node.anchorThemeKey = key }
        }
        try? context.save()
        reconcile(context: context)
        defaults.set(true, forKey: migrationDefaultsKey)
    }

    // MARK: Reconcile

    /// Creates a row for every key the living Ocean uses, fills labels from
    /// members whose own theme names the current, and removes rows no
    /// thought belongs to. Cheap: one fetch each way.
    @MainActor
    static func reconcile(context: ModelContext) {
        let nodes = (try? context.fetch(FetchDescriptor<Node>(predicate: #Predicate { !$0.isArchived && !$0.isExample }))) ?? []
        let currents = (try? context.fetch(FetchDescriptor<Current>())) ?? []
        var byKey = Dictionary(currents.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        var membersByKey: [String: [Node]] = [:]
        for node in nodes {
            guard let key = node.currentKey, !key.isEmpty else { continue }
            membersByKey[key, default: []].append(node)
        }

        for (key, members) in membersByKey {
            let current = byKey[key] ?? {
                let fresh = Current(key: key)
                context.insert(fresh)
                byKey[key] = fresh
                return fresh
            }()
            let labels = labels(for: key, from: members.map { ($0.themes.first, $0.themeKeys.first, $0.language ?? ThoughtReading.language(of: $0.rawContent)) })
            if current.labelEN == nil, let en = labels.en { current.labelEN = en; current.updatedAt = .now }
            if current.labelZH == nil, let zh = labels.zh { current.labelZH = zh; current.updatedAt = .now }
        }

        for current in currents where membersByKey[current.key] == nil {
            context.delete(current)
        }
        try? context.save()
    }

    /// Labels a current can take from its members: a member whose first
    /// theme slugs to the key names it in that member's language; a member
    /// whose English rendering is the key names it in the member's language
    /// too (a Chinese thought in an English current gives the Chinese label).
    static func labels(for key: String, from members: [(theme: String?, themeKey: String?, language: ThoughtLanguage)]) -> (en: String?, zh: String?) {
        var en: String?, zh: String?
        for member in members {
            guard let theme = member.theme, !theme.isEmpty else { continue }
            let names = ThoughtReading.slug(theme) == key || member.themeKey == key
            guard names else { continue }
            if ThoughtReading.dominantScriptIsChinese(theme) {
                if zh == nil { zh = theme }
            } else if en == nil {
                en = theme
            }
            if en != nil, zh != nil { break }
        }
        return (en, zh)
    }

    // MARK: Rename, merge, move

    @MainActor
    static func rename(_ current: Current, to name: String, context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        current.pinnedName = trimmed
        current.updatedAt = .now
        try? context.save()
    }

    /// Every thought of `from` moves to `into`; `into` remembers the key and
    /// takes any label it lacked; `from` goes. The user's name on `into`
    /// stays; a name on `from` is kept only when `into` had none.
    @MainActor
    static func merge(_ from: Current, into: Current, context: ModelContext) {
        guard from.key != into.key else { return }
        let fromKey = from.key
        let nodes = (try? context.fetch(FetchDescriptor<Node>())) ?? []
        for node in nodes where node.currentKey == fromKey {
            node.anchorThemeKey = into.key
            node.updatedAt = .now
        }
        if into.labelEN == nil { into.labelEN = from.labelEN }
        if into.labelZH == nil { into.labelZH = from.labelZH }
        if into.pinnedName == nil { into.pinnedName = from.pinnedName }
        into.mergedFromKeys.append(fromKey)
        into.mergedFromKeys.append(contentsOf: from.mergedFromKeys)
        into.updatedAt = .now
        context.delete(from)
        try? context.save()
        reconcile(context: context)
    }

    /// Moves thoughts into the current with `key`, founding it under `name`
    /// when it does not exist yet (a split, or a move to a new current). The
    /// move is also the lock: no understanding pass re-files these thoughts.
    @MainActor
    static func move(_ nodes: [Node], toKey key: String, name: String? = nil, context: ModelContext) {
        guard !key.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<Current>(predicate: #Predicate { $0.key == key })))?.first
        if existing == nil {
            let fresh = Current(key: key, pinnedName: name)
            if let name {
                if ThoughtReading.dominantScriptIsChinese(name) { fresh.labelZH = name } else { fresh.labelEN = name }
            }
            context.insert(fresh)
        }
        for node in nodes {
            node.anchorThemeKey = key
            node.positionPinnedByUser = true
            node.updatedAt = .now
        }
        try? context.save()
        reconcile(context: context)
    }

    // MARK: Suggested merges

    struct MergeSuggestion: Equatable, Identifiable {
        let fromKey: String
        let intoKey: String
        var id: String { fromKey + ">" + intoKey }
    }

    /// Currents in different scripts that the thoughts themselves say are
    /// one topic: at least three in five members of a Chinese-keyed current
    /// carry, as their English theme key, the key of an existing current (or
    /// the reverse). Deterministic, from the understanding record; the user
    /// confirms (decision 2), nothing merges on its own.
    static func suggestions(
        currentKeys: Set<String>,
        members: [(currentKey: String, themeKey: String?)]
    ) -> [MergeSuggestion] {
        var byKey: [String: [String?]] = [:]
        for member in members { byKey[member.currentKey, default: []].append(member.themeKey) }
        var out: [MergeSuggestion] = []
        for (key, themeKeys) in byKey {
            guard currentKeys.contains(key), !themeKeys.isEmpty else { continue }
            let counts = themeKeys.compactMap { $0 }
                .filter { $0 != key && currentKeys.contains($0) }
                .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            guard let (target, count) = counts.max(by: { $0.value < $1.value }) else { continue }
            let differentScript = ThoughtReading.dominantScriptIsChinese(key) != ThoughtReading.dominantScriptIsChinese(target)
            guard differentScript, count * 5 >= themeKeys.count * 3 else { continue }
            out.append(MergeSuggestion(fromKey: key, intoKey: target))
        }
        return out.sorted { $0.fromKey < $1.fromKey }
    }

    static let dismissedMergesKey = "currents.dismissedMerges"

    static func dismissedMerges(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: dismissedMergesKey) ?? [])
    }

    static func dismiss(_ suggestion: MergeSuggestion, defaults: UserDefaults = .standard) {
        var set = dismissedMerges(defaults: defaults)
        set.insert(suggestion.id)
        defaults.set(Array(set).sorted(), forKey: dismissedMergesKey)
    }
}
