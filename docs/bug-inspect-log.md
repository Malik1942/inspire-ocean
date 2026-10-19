# Bug Inspect Log

A running record of code/flow inspections: what was found, what was fixed, and
what was deliberately deferred (so nobody re-chases a known-and-parked issue, and
so the next person can pick up the open items with enough context to act).

**Legend**
- Severity: 🔴 blocker · 🟠 major · 🟡 minor
- Verdict (from adversarial verify): **CONFIRMED** (inputs → wrong output named) · **PLAUSIBLE** (mechanism real, trigger uncertain)
- Status: ✅ fixed · 🅜 mitigated · ⏳ open (deferred) · ⓘ noted / by-design

---

## 2026-07-05 — "Polish & Trust" handoffs review

**Scope:** the three pre-promo handoffs —
`f70660e` (App Store review ask), `ee82a34` (cultivated examples + Clear examples),
`712c878` (export the Ocean). 10 files, ~1,109-line combined diff.

**Method:** multi-agent review (`/code-review` + `/product-evaluation`), 54 agents —
5 code finder angles + 3 flow teardowns → adversarial verify (REFUTED dropped) → sweep.
Combined diff saved at `scratchpad/handoffs.diff`; workflow run `wf_0c8f021e-e1b`.

**Verification gaps (not runtime-tested):** the Simulator UI taps were not driven
(control was declined at review time). These were verified by code reading, not by
observing the live UI: the Clear-examples tap, the export tap → zip inspection, and
the actual App Store review-sheet presentation timing. Build + seed-store SQLite
checks + adversarial review stood in. Worth a manual pass before release.

### ✅ Fixed this session (working tree, uncommitted)

| # | Sev | Issue | Fix |
|---|-----|-------|-----|
| F1 | 🔴 | Review ask could present **over** the resurfaced-thought sheet. `OceanFieldView.open()` starts a 2s timer and presents `sheet = .thought(node)` in the same breath; 2s later `requestReview()` fired over the still-open sheet — the exact "never over a sheet" case the design forbids, and it burned the once-ever ask (`hasRequested` is set before the system call). | `RootTabView` now gates `fulfill()` on `canFulfillReview` (no Fast Capture overlay, no onboarding, no Ocean sheet) and **retries** via `onChange` when that clears, with a 500ms settle. New `AppState.isPresentingOceanSheet` (kept in sync by `OceanFieldView`) feeds the gate. |
| F2 | 🟠 | 5th-capture trigger armed with **zero settle delay** — `ReviewPrompt.recordCapture()` runs synchronously inside `CaptureSession.release()`, so the ask could drop over the Fast Capture overlay mid-animation. | Same gate — `fastCaptureRequest` is one of the tracked signals, so a capture-armed ask waits until the overlay tears down. |
| F3 | 🟠 | Export failures were **silent** — every throw in `buildArchive` was swallowed by `try?`; on failure the UI reverted to the idle "Prepare archive" button, indistinguishable from success. | Added `ExportState.failed` with a localized "Could not pack the archive." + "Try again"; `buildExport()` uses `do/catch` instead of `try?`. |
| F4 | 🟠 | `Resurfacing.pick()` drew from all non-archived nodes **without excluding `isExample`**, so a seeded demo drift could become "today's resurfaced fragment" on a fresh install and arm the review ask off content the user never wrote. | `pick()` now filters `!$0.isExample` — fixes both call sites (Ocean field + widget) at the shared source. |

### 🅜 Mitigated (not fully closed)

- **🟡 CONFIRMED — `OceanFieldView.open()` resurfaced-open `Task` is unstructured/uncancelled** (`OceanFieldView.swift` ~L133). If the user opens the resurfaced thought and backs out within 2s, the `Task` still fires `recordResurfacedOpen()`. **After F1** it can no longer present *over* the sheet (the gate holds it until at-rest), so the harm is largely neutralized — but the timer itself is still not tied to the sheet lifecycle. If you want it exact, cancel the arming `Task` on sheet dismiss (or arm on `onDismiss` instead of a blind timer).

### ⏳ Open — deferred (by scope choice: "blocker + majors only")

**Export (`Oryne/Services/OceanExport.swift`, `OceanSettingsView.swift`)**

- **🟠 CONFIRMED — audio blob faulted into memory even when the voice toggle is OFF.** `snapshot(from:)` unconditionally reads `audioData: node.audioData` (`OceanExport.swift:94`); `buildExport()` maps `realNodes` on the **main actor** (`OceanSettingsView.swift:299`) before detaching. With the toggle off, every non-expired `.m4a` is faulted off external storage into RAM on the main thread, then discarded in `buildArchive` (the only `includeVoice` check is off-actor). Fix: thread `includeVoice` into `snapshot(from:)` so `audioData` is read only when true. (Images are fine — always exported.)
- **🟠 CONFIRMED — toggling `includeVoice` mid-build resurrects a stale archive.** `buildExport()`'s `Task` (`OceanSettingsView.swift:297`) is not stored/cancelled. The `onChange(of: includeVoice)` handler (~L280) resets to `.idle`/`nil`, but the in-flight build (captured old `voice`) later completes and sets `zipURL`/`.ready`, re-showing a Share button for an archive built with the *pre-toggle* setting — contradicting the "toggling invalidates the archive" comment. Fix: hold the `Task` handle and cancel it in the `onChange`, or check `Task.isCancelled` / re-compare the captured `voice` before committing state.
- **🟡 CONFIRMED — two theme labels that sanitize to the same filename overwrite each other.** Groups are keyed by display label (`buildArchive`), but files are written to `sanitizeFilename(label).md` (`OceanExport.swift:308`) which collapses `/` and `:` to `-`. Labels `a/b` and `a:b` both write `a-b.md`; the second clobbers the first (`write(atomically:)`). JSON backup keeps all nodes; only the Markdown layer silently loses a theme. Fix: de-dup filenames (append a counter on collision).
- **🟡 CONFIRMED — image assets always named `.jpg` regardless of actual bytes.** `OceanExport.swift:198` hardcodes `-\(i).jpg`, but `imageDatas` can be PNG/HEIC (Shortcuts "Save image" intent, Context Capture screenshots, `ImageDownsampler` fallback returns original bytes on decode failure). A `.jpg` name over PNG/HEIC bytes mis-decodes in strict extension-dispatch pipelines. Fix: sniff magic bytes and pick the extension (or re-encode to JPEG on export).
- **🟡 CONFIRMED — user text is emitted into Markdown unescaped.** `render()` writes `s.body` verbatim (`OceanExport.swift:254`). A thought whose text starts with `#`, `---`, or `![](…)` alters headings/frontmatter/embeds in a Markdown viewer. JSON backup is faithful. Fix: escape leading block-markers (or fence bodies).
- **🟡 CONFIRMED — Markdown drops a link's enriched context when the user also typed a note.** `s.body` = `node.rawContent`, which returns `text` first and never reaches `linkContext` when `text` is non-empty; `render()` emits nothing else for a link. So a link drift with a note loses its title/summary in the readable layer (JSON keeps all fields). Fix: for `.link` kind, emit `linkContext` (and/or the URL) in addition to the note.
- **🟡 CONFIRMED — `realNodes` `@Query` has no sort → non-deterministic `backup.json` order.** `OceanSettingsView.swift:37`. `backup.json`'s `nodes` array preserves the unsorted fetch order, so two exports of an unchanged Ocean can differ byte-for-byte, undercutting the "faithful, round-trippable" framing and making archive diffs noisy. (Per-`.md` content is stable — roots/children are sorted by `createdAt`.) Fix: add `sort: [SortDescriptor(\.createdAt)]` to the query (or sort snapshots before mapping).
- **🟡 CONFIRMED — a real branch grown off a since-excluded example loses its branch framing.** When the example parent isn't in the export set, `parentInSet(s)` is false, so `render()` prints `<date> · <kind>` instead of `<branchTypeLabel>: <title>` even though `branchTypeLabel` is non-nil. Fix: gate the branch header on `s.branchTypeLabel != nil`, independent of `parentInSet`.
- **🟡 PLAUSIBLE — date-only zip filename collides on same-day re-export.** `buildArchive` stamps `yyyy-MM-dd` only (`OceanExport.swift:186`); `zipFolder` writes a fixed `Oryne-Export-<date>.zip` and `removeItem`s any existing one (`:325`). A second same-day export deletes/overwrites the prior zip while an in-flight `ShareLink` may still be reading it (AirDrop/Mail read lazily). Fix: add a time/UUID suffix, or copy into a per-export subdir.
- **🟡 CONFIRMED (cleanup) — `exportState` + `zipURL` are redundant derivable state.** `.ready` ⟺ `zipURL != nil`, and the `.ready` branch re-guards with `if let zipURL`. Fold the payload into the case: `case ready(URL)`.
- **🟡 CONFIRMED (cleanup) — each theme subtree is walked twice** (once by `descendants()` for count/date-span, once by `render()`). `OceanExport.swift:238,245`. Low impact (small sets). Accumulate count + min/max dates during `render()` instead.
- **🟡 PLAUSIBLE (cleanup) — `realNodes` `@Query` fully materializes the whole non-example graph** for the lifetime of the Settings sheet, used only for `isEmpty` gates + an on-tap snapshot. A `fetchCount` emptiness check + fetching inside `buildExport()` would avoid holding hundreds of live `Node`s resident.

**Examples / seed (`SeedData.swift`, `OceanSettingsView.swift`)**

- **🟡 PLAUSIBLE — `clearExamples()` only deletes example roots with `parent == nil`.** `OceanSettingsView.swift:212`. Any example with a non-nil, non-example parent is never detached and never deleted → orphaned badged example. Not reachable from today's seed (examples are roots + one example-under-example), but a future seed change or a CloudKit reparent could trigger it. Fix: delete every example not reachable from a deleted root (or detach-and-delete all examples explicitly).
- **🟡 PLAUSIBLE (convention) — `seed.completed` lives in `UserDefaults.standard`**, while install-scoped flags elsewhere use the App Group suite `FastCapturePreferences.defaults` (with keyed constants in `FastCapturePreferenceKeys`). `SeedData.swift:10,16,34,91`. No functional break today (main-app-only, in-process). Note: `Hints.swift` and `LibraryView.swift` also use `.standard`, so it follows an existing (inconsistent) app-only-flag pattern. Fix if standardizing: move to `FastCapturePreferences.defaults` + a named key constant.

**Design system (`NodeRow.swift`)**

- **🟡 PLAUSIBLE (convention) — "Example" badge background hardcodes `Color.white.opacity(0.06)`** (`NodeRow.swift:66`) instead of an `OceanTheme` token. Literally against the "never hardcode colors" rule, **but** it matches the unchanged line right below it (`:74`) and 50+ existing `Color.white.opacity(N)` glass fills across the design system; there is no existing "chip/glass fill" token to reuse. Best treated as a codebase-wide pattern to address system-wide, not a lone regression.

### ⓘ Investigated and cleared (REFUTED — don't re-chase)

- `clearExamples()` cascade-deleting a user's real branch grown off an example — **guarded**: non-example children are detached (`child.parent = nil`) before deleting roots.
- The Share Extension incrementing `review.captureCount` / cross-process review races — **false**: `recordCapture()` is called only from `CaptureSession.release()` (`CaptureSession.swift:132`), never from the extension.
- The `.image` seed drift with no image data showing a broken/empty image card — **false**: every image-render site is nil-guarded.
- `clearExamples()`'s trailing `try? context.save()` racing `deleteNodeSafely`'s deferred save — **false**: runs synchronously on main; the deferred delete is scheduled, not concurrent.

---

<!-- Append new inspections above this line, newest date first. -->
