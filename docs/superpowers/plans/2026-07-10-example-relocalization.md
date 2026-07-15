# Example Node Re-Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When Oryne's per-app language changes before the user has written anything of their own, regenerate the app-authored example nodes in the new language — never touching real or user-edited content.

**Architecture:** A new, separately-named function `SeedData.relocalizeExamplesIfNeeded(_:)` runs at launch *after* the untouched `seedIfNeeded(_:)`. A pure decision function (`shouldRelocalizeExamples`) reads five gates and returns one of three outcomes (`skip` / `adoptBaseline` / `reseed`); the caller performs the side effects. The example-insertion body is extracted from `seedIfNeeded` into a shared `insertExamples(into:now:)` so first-seed and re-seed produce byte-identical content. A new `seed.language` UserDefaults key records the language the examples were last seeded in.

**Tech Stack:** Swift, SwiftData, SwiftUI (iOS app). Build via `xcodegen` + `xcodebuild`. No unit-test target exists in this project (verification is via simulator runs and DEBUG launch seams, following the existing `OCEAN_SIM_COUNT` / `OCEAN_START_TAB` convention).

## Global Constraints

- **Do NOT modify the existing `existing == 0` guard** in `seedIfNeeded` (`SeedData.swift:13-18`). The re-localization lives in a separate function. (Malik, condition 1.)
- **Never touch real user nodes** (`isExample == false`). Re-seed fires only when real-node count is `0`.
- **Never re-seed after the user cleared examples** — handled automatically: `exampleCount == 0` → skip.
- **Never re-seed after the user edited any example** — skip the whole group if ANY example node has `titleEditedByUser || themesEditedByUser || transcriptEditedByUser || positionPinnedByUser == true`. (Malik, condition 5.) `updatedAt` is NOT a usable signal — the Library backfill bumps it on title-less examples as a system action.
- **Language signal:** `Bundle.main.preferredLocalizations.first ?? "en"`. (Malik, condition 2.)
- **`seed.completed` naturally scopes to the original seeding device** (a per-install UserDefaults flag, not CloudKit-synced) — a lock-in comment must state this. (Malik, condition 3.)
- **No em/en dashes in any user-facing copy** — not applicable here (no new UI strings), but the existing seed strings are already dash-free; keep them so.
- **Branch:** work stays on this worktree's own branch, isolated from `feat/bilingual-voice`. Rename this worktree's branch to `feat/example-relocalization` for clarity. Never check out or touch `feat/bilingual-voice`.

---

## File Structure

- **Modify** `Oryne/App/SeedData.swift` — extract `insertExamples(into:now:)`; add `seed.language` recording to `seedIfNeeded`; add `shouldRelocalizeExamples(...)`, the `ExampleRelocalization` enum, `currentAppLanguage()`, and `relocalizeExamplesIfNeeded(_:)`.
- **Modify** `Oryne/App/OryneApp.swift:22` — add the `relocalizeExamplesIfNeeded` call immediately after `seedIfNeeded`.

No new files. No model changes. No changes to read sites, export, or the edit sheet.

---

## Task 0: Branch setup

- [ ] **Step 1: Confirm the worktree branch is isolated and rename it**

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/confident-feynman-f57aa3
git status                      # expect: clean
git branch --show-current       # expect: claude/confident-feynman-f57aa3
git branch -m feat/example-relocalization
git branch --show-current       # expect: feat/example-relocalization
```

Expected: on `feat/example-relocalization`, clean tree, `feat/bilingual-voice` untouched.

---

## Task 1: Extract `insertExamples` (pure refactor, zero behavior change)

**Files:**
- Modify: `Oryne/App/SeedData.swift:36-90` (the `now`/`ago` block, the `drifts` loop, and the cultivated dialogue pair)

**Interfaces:**
- Produces: `static func insertExamples(into context: ModelContext, now: Date)` — inserts the 7 drifts + the cultivated parent/branch pair as `isExample = true` nodes with back-dated `createdAt`/`updatedAt`. Does NOT call `save()`. Resolves all text via `String(localized:)` against the current bundle language at call time.

- [ ] **Step 1: Add the `insertExamples` function**

Insert this new function into the `SeedData` enum (place it directly after `seedIfNeeded`, before the `#if DEBUG seedSimulated` block):

```swift
    /// Inserts the demo example set (7 drifts + one cultivated dialogue pair)
    /// as badged, clearable, export-excluded nodes. Text resolves via
    /// `String(localized:)` against the current bundle language at call time,
    /// so both first-seed and language re-seed produce content in the active
    /// language. Does not save; the caller owns the transaction.
    @MainActor
    static func insertExamples(into context: ModelContext, now: Date) {
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
    }
```

- [ ] **Step 2: Replace the inlined body in `seedIfNeeded` with a call**

In `seedIfNeeded`, replace the block from `let now = Date()` (line 36) through the `context.insert(branch)` line (line 88) — i.e. everything between the `guard !UserDefaults...` one-shot guard and the final `try? context.save()` — with:

```swift
        let now = Date()
        insertExamples(into: context, now: now)
```

The tail of `seedIfNeeded` (the `try? context.save()` and `UserDefaults.standard.set(true, forKey: seededKey)` lines) stays exactly as is for now (Task 2 adds the language record right after).

- [ ] **Step 3: Verify the build compiles**

Run:
```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/confident-feynman-f57aa3
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Verify first-launch seeding is unchanged (behavior parity)**

Run the app on a clean simulator (erase first so the store is empty) and confirm the same 7 drifts + dialogue pair appear:
```bash
xcrun simctl erase 'iPhone 16' 2>/dev/null; xcrun simctl boot 'iPhone 16' 2>/dev/null
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath /tmp/oryne-dd build 2>&1 | tail -3
xcrun simctl install 'iPhone 16' "$(find /tmp/oryne-dd -name 'Oryne.app' -type d | head -1)"
xcrun simctl launch 'iPhone 16' com.inspireocean.app
```
Then screenshot and confirm the example field looks identical to before:
```bash
xcrun simctl io 'iPhone 16' screenshot /tmp/oryne-task1.png
```
Expected: 8 example nodes present (7 drifts + cultivated parent), same copy as the pre-refactor build.

- [ ] **Step 5: Commit**

```bash
git add Oryne/App/SeedData.swift
git commit -m "refactor(seed): extract insertExamples for reuse by first-seed and re-seed

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Add the pure decision function + language recording

**Files:**
- Modify: `Oryne/App/SeedData.swift` (add enum + two functions; extend `seedIfNeeded` tail)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces:
  - `enum ExampleRelocalization: Equatable { case skip; case adoptBaseline(String); case reseed(String) }`
  - `static func shouldRelocalizeExamples(seeded: Bool, realCount: Int, exampleCount: Int, anyExampleEdited: Bool, recordedLanguage: String?, currentLanguage: String) -> ExampleRelocalization`
  - `static func currentAppLanguage() -> String`
  - `static let seedLanguageKey = "seed.language"` (module-private constant reused by Task 3)

- [ ] **Step 1: Add the language key constant, the language helper, and the decision enum + function**

Add to the `SeedData` enum (place after `insertExamples`):

```swift
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
```

- [ ] **Step 2: Record the seed language on first seed**

In `seedIfNeeded`, immediately after the existing final line `UserDefaults.standard.set(true, forKey: seededKey)`, add:

```swift
        UserDefaults.standard.set(currentAppLanguage(), forKey: seedLanguageKey)
```

- [ ] **Step 3: Verify the build compiles**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Verify the decision table by inspection**

Confirm `shouldRelocalizeExamples` returns the expected outcome for each row (read the code against this table — there is no test runner; this is the review gate):

| seeded | realCount | exampleCount | anyExampleEdited | recorded | current | expected |
|--------|-----------|--------------|------------------|----------|---------|----------|
| false  | 0         | 8            | false            | nil      | en      | `.skip` |
| true   | 0         | 8            | false            | nil      | en      | `.adoptBaseline("en")` |
| true   | 0         | 8            | false            | zh-Hans  | en      | `.reseed("en")` |
| true   | 0         | 8            | false            | en       | en      | `.skip` |
| true   | 3         | 8            | false            | zh-Hans  | en      | `.skip` (real content) |
| true   | 0         | 0            | false            | zh-Hans  | en      | `.skip` (examples cleared) |
| true   | 0         | 8            | true             | zh-Hans  | en      | `.skip` (user edited) |

Expected: every row matches. If any doesn't, fix the function before committing.

- [ ] **Step 5: Commit**

```bash
git add Oryne/App/SeedData.swift
git commit -m "feat(seed): pure decision for example re-localization + record seed language

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Wire up `relocalizeExamplesIfNeeded` and call it at launch

**Files:**
- Modify: `Oryne/App/SeedData.swift` (add `relocalizeExamplesIfNeeded`)
- Modify: `Oryne/App/OryneApp.swift:22` (add the call)

**Interfaces:**
- Consumes: `insertExamples(into:now:)` (Task 1); `shouldRelocalizeExamples`, `currentAppLanguage`, `seedLanguageKey`, `ExampleRelocalization` (Task 2); `Node.isExample` and the four ownership flags (existing model).
- Produces: `static func relocalizeExamplesIfNeeded(_ context: ModelContext)`.

- [ ] **Step 1: Add `relocalizeExamplesIfNeeded`**

Add to the `SeedData` enum (after `shouldRelocalizeExamples`):

```swift
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
            FetchDescriptor<Node>(predicate: #Predicate { $0.isExample == true })
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
            // Delete the example roots; the cascade delete rule takes the
            // cultivated branch child with its parent. realCount == 0 here, so
            // no real node is ever attached to an example.
            for node in examples where node.parent == nil {
                context.delete(node)
            }
            insertExamples(into: context, now: Date())
            try? context.save()
            UserDefaults.standard.set(language, forKey: seedLanguageKey)
        }
    }
```

- [ ] **Step 2: Call it at launch, after `seedIfNeeded`**

In `Oryne/App/OryneApp.swift`, in the `.task { ... }` block, immediately after the `SeedData.seedIfNeeded(container.mainContext)` line (:22), add:

```swift
            SeedData.relocalizeExamplesIfNeeded(container.mainContext)
```

- [ ] **Step 3: Verify the build compiles**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Oryne/App/SeedData.swift Oryne/App/OryneApp.swift
git commit -m "feat(seed): re-localize examples on language change (examples-only store)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: End-to-end simulator verification

No unit-test runner exists; this task is the behavioral gate. `-AppleLanguages "(xx)"` as a launch argument drives BOTH `String(localized:)` and `Bundle.main.preferredLocalizations`, so it exercises the real path.

**Files:** none (verification only).

- [ ] **Step 1: Build and install once on a clean simulator**

```bash
xcrun simctl erase 'iPhone 16' 2>/dev/null; xcrun simctl boot 'iPhone 16' 2>/dev/null
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath /tmp/oryne-dd build 2>&1 | tail -3
xcrun simctl install 'iPhone 16' "$(find /tmp/oryne-dd -name 'Oryne.app' -type d | head -1)"
```

- [ ] **Step 2: Scenario A — first seed in Chinese**

```bash
xcrun simctl launch 'iPhone 16' com.inspireocean.app -AppleLanguages "(zh-Hans)"
sleep 4
xcrun simctl io 'iPhone 16' screenshot /tmp/oryne-A-zh.png
xcrun simctl terminate 'iPhone 16' com.inspireocean.app
```
Expected in `/tmp/oryne-A-zh.png`: example nodes render in 简体中文. (This also records `seed.language = zh-Hans`.)

- [ ] **Step 3: Scenario B — relaunch in English → examples re-localize**

```bash
xcrun simctl launch 'iPhone 16' com.inspireocean.app -AppleLanguages "(en)"
sleep 4
xcrun simctl io 'iPhone 16' screenshot /tmp/oryne-B-en.png
xcrun simctl terminate 'iPhone 16' com.inspireocean.app
```
Expected in `/tmp/oryne-B-en.png`: the SAME example set now renders in English (re-seed fired: examples-only store, nothing edited, language changed). Confirm the count is unchanged (7 drifts + cultivated pair).

- [ ] **Step 4: Scenario C — edited example is preserved across a language change**

Relaunch in English (no-op now that recorded == en), open one example via the edit sheet, change its body, save (this sets `transcriptEditedByUser`). Then relaunch in Chinese:
```bash
xcrun simctl launch 'iPhone 16' com.inspireocean.app -AppleLanguages "(en)"
# --- MANUAL: tap an example, edit its text, save. Then terminate. ---
xcrun simctl terminate 'iPhone 16' com.inspireocean.app
xcrun simctl launch 'iPhone 16' com.inspireocean.app -AppleLanguages "(zh-Hans)"
sleep 4
xcrun simctl io 'iPhone 16' screenshot /tmp/oryne-C-edited.png
xcrun simctl terminate 'iPhone 16' com.inspireocean.app
```
Expected in `/tmp/oryne-C-edited.png`: examples are UNCHANGED (still English, including the edit) — `anyExampleEdited == true` forced `.skip`. No re-seed despite the language change.

- [ ] **Step 5: Scenario D — real content blocks re-seed**

Erase, install, launch in Chinese (seeds zh), capture one real thought, then relaunch in English:
```bash
xcrun simctl erase 'iPhone 16'; xcrun simctl boot 'iPhone 16'
xcrun simctl install 'iPhone 16' "$(find /tmp/oryne-dd -name 'Oryne.app' -type d | head -1)"
xcrun simctl launch 'iPhone 16' com.inspireocean.app -AppleLanguages "(zh-Hans)"
# --- MANUAL: capture one real thought. Then terminate. ---
xcrun simctl terminate 'iPhone 16' com.inspireocean.app
xcrun simctl launch 'iPhone 16' com.inspireocean.app -AppleLanguages "(en)"
sleep 4
xcrun simctl io 'iPhone 16' screenshot /tmp/oryne-D-real.png
xcrun simctl terminate 'iPhone 16' com.inspireocean.app
```
Expected in `/tmp/oryne-D-real.png`: examples stay Chinese (real node present → `realCount > 0` → `.skip`); the real thought is untouched.

- [ ] **Step 6: Record results**

Confirm A→B flipped language, C and D did not re-seed. If all four hold, the feature is verified. Attach the four screenshots to the PR / report to Malik.

---

## Self-Review

**Spec coverage:**
- Condition 1 (separate function, guard untouched) → Task 3 (`relocalizeExamplesIfNeeded` is separate; `existing == 0` guard never edited). ✓
- Condition 2 (`preferredLocalizations.first`) → Task 2 `currentAppLanguage()`. ✓
- Condition 3 (`seed.completed` device scope + comment) → Task 3 doc comment. ✓
- Gates: seeded / realCount==0 / exampleCount>0 / language mismatch → Task 2 `shouldRelocalizeExamples`. ✓
- Condition 5 (edited example skips whole group, via ownership flags) → Task 3 `anyExampleEdited`. ✓
- Constraint: never touch real/user-edited nodes → realCount==0 gate + anyExampleEdited gate. ✓
- Branch isolation → Task 0. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; no "handle edge cases" hand-waving. The two MANUAL simulator steps (C/D) are inherent to UI-driven verification, with exact surrounding commands. ✓

**Type consistency:** `insertExamples(into:now:)`, `shouldRelocalizeExamples(...)`, `ExampleRelocalization` (`.skip`/`.adoptBaseline`/`.reseed`), `currentAppLanguage()`, `seedLanguageKey`, and the four ownership-flag names (`titleEditedByUser`/`themesEditedByUser`/`transcriptEditedByUser`/`positionPinnedByUser`) are used identically across Tasks 1–3. ✓

## Open note for reviewer

One behavior is deliberately accepted, not a bug: an install that seeded in Chinese, was upgraded to this build, AND had already switched to English *before* upgrading will `.adoptBaseline("en")` and keep its Chinese examples (we can't recover the original seed language post-hoc). New installs and same-session switches are fully covered. Flag to Malik if he wants a one-time heuristic for that cohort — out of scope here.
