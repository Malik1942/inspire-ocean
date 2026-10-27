# Watch Redesign (Today, Recent, Replay) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Today (the day's resurfaced thought) and Recent (the last 20 wrist takes) as vertical pages below the watch's capture screen, each thought showing a short reading with replayable audio, kept current by a live phone-to-wrist snapshot.

**Architecture:** Pure rules live in `Shared/Watch/` (wire format, snapshot builder, row derivation, queue retention) so `SharedTests` covers them. The phone builds a `WristSnapshot` from live `Node`s on every store change and on the watch's request, and sends it over WatchConnectivity next to the existing confirmations. The watch persists the snapshot, merges it with its take queue into rows, keeps its own recordings for replay, and fetches anything else from the phone on tap.

**Tech Stack:** Swift 5 mode, SwiftUI (watchOS 11, iOS 18), SwiftData, WatchConnectivity, AVFoundation, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-26-watch-redesign-design.md`

## Global Constraints

- Floors: iOS 18.0, watchOS 11.0 (`project.yml`). No third-party dependencies.
- The watch target compiles `Shared/Watch` and the theme only: nothing in `Shared/Watch` may touch SwiftData, `Node`, or WatchKit.
- Files in `OryneWatch/Services/` that `SharedTests` compiles (`TakeSync`, `TakeQueue`, and the new `WristLibrary`) must stay free of WatchKit and WatchConnectivity.
- Do not edit `Oryne/DesignSystem/`. Use the existing roles: `OceanTheme` (`abyss`, `current`, `foam`, `text`, `mist`, `accent`), `OceanType` (`eyebrow`, `body`, `meta`, `note`, `control`), and `OceanSpacing` (`tight`, `gap`).
- No new animation, transition, or motion parameters. The capture screen's existing `.animation(OceanMotion.lift, value: model.stage)` stays as is. Paging is the system's `.verticalPage`.
- User-facing text goes through the watch string catalog (`OryneWatch/Resources/Localizable.xcstrings`), with the value as the key and no em or en dashes. zh-Hans values are exactly: Today 今天 · Recent 最近 · Summary 摘要 · Waiting for iPhone 在等 iPhone · Not transcribed yet 还未转写 · Continues on iPhone 在 iPhone 上继续 · Play 播放 · Pause 暂停 · Getting audio… 正在读回语音… · Your iPhone isn't nearby iPhone 不在附近 · Couldn't get the audio 语音读取失败.
- Reading cap: 240 characters (`WristSnapshotBuilder.readingLimit`). Recent limit: 20 (`TakeQueueState.confirmedKept`). Phone coalescing: 2 seconds. Audio fetch timeout: 30 seconds. Watch audio retention: 30 days, and only for a take with a transcript.
- A failure notice on the wrist stays until tapped (PHILOSOPHY §5). Nothing says "syncing".
- Logs carry failures only, never user content: a take ID at most.
- Run `xcodegen generate` after adding any file. Never edit `project.yml` beyond registering a new file in an existing target.
- Commits only when Malik has asked for them in the session. Small commits, plain messages, and never any AI co-author or generated-by trailer.

### Commands

```bash
xcodegen generate
xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SharedTests/<TestClass>
xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
xcodebuild -scheme OryneWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' build
```

---

### Task 0: Worktree

The main checkout is on `codex/widget-redesign` with uncommitted widget work. This work goes on its own branch off `main`.

- [ ] **Step 1: Create the worktree**

```bash
cd /Users/malik/Documents/inspire-ocean
git worktree add .claude/worktrees/watch-redesign -b am/watch-redesign main
mkdir -p .claude/worktrees/watch-redesign/docs/superpowers/specs .claude/worktrees/watch-redesign/docs/superpowers/plans
cp docs/superpowers/specs/2026-10-26-watch-redesign-design.md .claude/worktrees/watch-redesign/docs/superpowers/specs/
cp docs/superpowers/plans/2026-10-26-watch-redesign.md .claude/worktrees/watch-redesign/docs/superpowers/plans/
cd .claude/worktrees/watch-redesign
xcodegen generate
```

- [ ] **Step 2: Baseline**

Run: `xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: `** TEST SUCCEEDED **`. If it fails on `main` already, stop and tell Malik before changing anything.

All later paths are relative to the worktree.

---

### Task 1: The wrist snapshot wire format

**Files:**
- Create: `Shared/Watch/WristSnapshot.swift`
- Test: `SharedTests/WristSnapshotTests.swift`

**Interfaces:**
- Consumes: `WatchWire.context(for: [WatchConfirmation]) -> [String: Any]`, `WatchWire.confirmations(fromContext:)` (existing, `Shared/Watch/WatchTake.swift`).
- Produces:
  - `struct WristThought: Codable, Hashable, Identifiable` with `id: UUID`, `title: String?`, `reading: String?`, `readingIsSummary: Bool = false`, `continues: Bool = false`, `hasTranscript: Bool = false`, `hasAudio: Bool = false`, `isVoice: Bool = false`, `createdAt: Date`. Memberwise init `WristThought(id:title:createdAt:)` works since the other fields default.
  - `struct WristSnapshot: Codable, Equatable` with `recent: [WristThought]`, `today: WristThought?`, `todayDay: Date?`, `deletedIDs: [UUID]`, `generatedAt: Date`, `version: Int`, plus `isNewer(than: WristSnapshot?) -> Bool`, `hasSameContent(as: WristSnapshot?) -> Bool`, `today(on: Date, calendar: Calendar = .current) -> WristThought?`, `recentThought(_ id: UUID) -> WristThought?`.
  - `WatchWire.wristKey`, `.snapshotRequestKey`, `.audioRequestKey`, `.audioOKKey`, `.audioForKey`, `.metKey`; `WatchWire.encode(_: WristSnapshot) -> Data?`, `WatchWire.decodeSnapshot(_: Data) -> WristSnapshot?`, `WatchWire.context(for: [WatchConfirmation], snapshot: WristSnapshot?) -> [String: Any]`, `WatchWire.snapshot(from: [String: Any]) -> WristSnapshot?`.

- [ ] **Step 1: Write the failing test**

`SharedTests/WristSnapshotTests.swift`:

```swift
import XCTest
import Foundation

final class WristSnapshotTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let thoughtID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let deletedID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func snapshot(builtAfter offset: TimeInterval = 0, title: String = "Lighthouse café") -> WristSnapshot {
        var thought = WristThought(id: thoughtID, title: title, createdAt: t0)
        thought.reading = "A room that tells you to stay."
        thought.readingIsSummary = true
        return WristSnapshot(
            recent: [thought], today: thought, todayDay: t0,
            deletedIDs: [deletedID], generatedAt: t0.addingTimeInterval(offset)
        )
    }

    func test_context_carriesConfirmationsAndTheSnapshotTogether() {
        let confirmations = [WatchConfirmation(id: thoughtID, title: "Lighthouse café")]
        let context = WatchWire.context(for: confirmations, snapshot: snapshot())
        XCTAssertEqual(WatchWire.confirmations(fromContext: context), confirmations)
        XCTAssertEqual(WatchWire.snapshot(from: context), snapshot())
    }

    func test_contextWithoutASnapshot_carriesNone() {
        let context = WatchWire.context(for: [], snapshot: nil)
        XCTAssertNil(WatchWire.snapshot(from: context))
    }

    func test_isNewer_comparesWhenEachWasBuilt() {
        XCTAssertTrue(snapshot().isNewer(than: nil))
        XCTAssertTrue(snapshot(builtAfter: 5).isNewer(than: snapshot()))
        XCTAssertFalse(snapshot().isNewer(than: snapshot(builtAfter: 5)))
        XCTAssertFalse(snapshot().isNewer(than: snapshot()), "the same snapshot again changes nothing")
    }

    func test_hasSameContent_ignoresWhenItWasBuilt() {
        XCTAssertTrue(snapshot(builtAfter: 60).hasSameContent(as: snapshot()))
        XCTAssertFalse(snapshot(title: "Renamed").hasSameContent(as: snapshot()))
        XCTAssertFalse(snapshot().hasSameContent(as: nil))
    }

    func test_today_showsOnlyOnTheDayItWasPicked() {
        XCTAssertEqual(snapshot().today(on: t0.addingTimeInterval(60), calendar: utc)?.id, thoughtID)
        XCTAssertNil(snapshot().today(on: t0.addingTimeInterval(86_400), calendar: utc))
    }

    func test_recentThought_findsByID() {
        XCTAssertEqual(snapshot().recentThought(thoughtID)?.title, "Lighthouse café")
        XCTAssertNil(snapshot().recentThought(deletedID))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SharedTests/WristSnapshotTests`
Expected: build failure, "cannot find 'WristThought' in scope".

- [ ] **Step 3: Write the implementation**

`Shared/Watch/WristSnapshot.swift`:

```swift
import Foundation

/// One thought as the wrist shows it: a name and a short reading, never the
/// full words of a long thought (the phone keeps those). Built on the phone
/// by `WristSnapshotBuilder`.
struct WristThought: Codable, Hashable, Identifiable {
    var id: UUID
    /// Nil while the thought has no name (untitled, or only the placeholder).
    var title: String?
    /// The summary, or the thought's own words cut at the reading limit; nil
    /// when it has no words.
    var reading: String?
    /// The reading is a machine summary: the wrist labels it "Summary", as
    /// the phone does (PHILOSOPHY §3).
    var readingIsSummary: Bool = false
    /// The user's own words were cut at the limit: "Continues on iPhone".
    var continues: Bool = false
    /// A voice thought with a transcript: the watch's copy of its audio
    /// expires as the phone's does.
    var hasTranscript: Bool = false
    /// The phone still holds a recording it can send on request.
    var hasAudio: Bool = false
    var isVoice: Bool = false
    var createdAt: Date
}

/// What the phone tells the wrist about its thoughts: the recent wrist takes
/// as they are now, today's resurfaced thought, and which wrist takes the
/// user deleted. Sent whole each time; the newer one wins.
struct WristSnapshot: Codable, Equatable {
    static let currentVersion = 1

    /// The newest live wrist takes, newest first.
    var recent: [WristThought]
    var today: WristThought?
    /// The day `today` was picked: the wrist shows it on that day only.
    var todayDay: Date?
    /// Wrist takes the phone imported that no longer exist.
    var deletedIDs: [UUID]
    /// A reply and a context update can cross; the newer one wins.
    var generatedAt: Date
    var version: Int = WristSnapshot.currentVersion

    func isNewer(than held: WristSnapshot?) -> Bool {
        guard let held else { return true }
        return generatedAt > held.generatedAt
    }

    /// The same thoughts, whenever each was built: the phone skips a repeat.
    func hasSameContent(as other: WristSnapshot?) -> Bool {
        guard var other else { return false }
        other.generatedAt = generatedAt
        return other == self
    }

    /// Today's thought, only on the day it was picked.
    func today(on now: Date, calendar: Calendar = .current) -> WristThought? {
        guard let today, let todayDay, calendar.isDate(todayDay, inSameDayAs: now) else { return nil }
        return today
    }

    func recentThought(_ id: UUID) -> WristThought? {
        recent.first { $0.id == id }
    }
}

extension WatchWire {
    /// Application context and snapshot replies: the encoded `WristSnapshot`.
    static let wristKey = "wrist"
    /// Watch to phone, with a reply: send a fresh snapshot.
    static let snapshotRequestKey = "snapshotRequest"
    /// Watch to phone, with a reply: send this thought's audio.
    static let audioRequestKey = "audioRequest"
    /// The reply to an audio request: whether a file is on its way.
    static let audioOKKey = "ok"
    /// `transferFile` metadata on fetched audio: the thought's ID.
    static let audioForKey = "audioFor"
    /// Watch to phone user info: today's thought was opened on the wrist.
    static let metKey = "met"

    static func encode(_ snapshot: WristSnapshot) -> Data? {
        try? JSONEncoder().encode(snapshot)
    }

    static func decodeSnapshot(_ data: Data) -> WristSnapshot? {
        try? JSONDecoder().decode(WristSnapshot.self, from: data)
    }

    /// The whole application context. An update replaces the dictionary, so
    /// the confirmations and the snapshot always travel together.
    static func context(for confirmations: [WatchConfirmation], snapshot: WristSnapshot?) -> [String: Any] {
        var context = self.context(for: confirmations)
        if let snapshot, let data = encode(snapshot) { context[wristKey] = data }
        return context
    }

    static func snapshot(from dictionary: [String: Any]) -> WristSnapshot? {
        guard let data = dictionary[wristKey] as? Data else { return nil }
        return decodeSnapshot(data)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SharedTests/WristSnapshotTests`
Expected: `** TEST SUCCEEDED **`, 6 tests.

- [ ] **Step 5: Commit (only if Malik has asked for commits)**

```bash
git add Shared/Watch/WristSnapshot.swift SharedTests/WristSnapshotTests.swift Oryne.xcodeproj
git commit -m "Watch: the wrist snapshot and its wire keys"
```

---

### Task 2: The snapshot builder

**Files:**
- Create: `Shared/Watch/WristSnapshotBuilder.swift`
- Test: `SharedTests/WristSnapshotBuilderTests.swift`

**Interfaces:**
- Consumes: `WristThought`, `WristSnapshot` (Task 1); `TakeQueueState.confirmedKept` (existing, 20).
- Produces:
  - `WristSnapshotBuilder.recentLimit` (20), `WristSnapshotBuilder.readingLimit` (240).
  - `struct WristSnapshotBuilder.Source: Equatable` with `id: UUID`, `title: String?`, `summary: String?`, `words: String?`, `isVoice: Bool`, `hasAudio: Bool`, `createdAt: Date`.
  - `WristSnapshotBuilder.build(ledgerIDs: Set<UUID>, liveIDs: Set<UUID>, recent: [Source], today: Source?, now: Date) -> WristSnapshot`
  - `WristSnapshotBuilder.thought(from: Source) -> WristThought`
  - `WristSnapshotBuilder.cut(_ text: String, limit: Int) -> (String, Bool)`

- [ ] **Step 1: Write the failing test**

`SharedTests/WristSnapshotBuilderTests.swift`:

```swift
import XCTest
import Foundation

final class WristSnapshotBuilderTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func source(
        _ offset: TimeInterval = 0, title: String? = nil, summary: String? = nil,
        words: String? = nil, isVoice: Bool = true, hasAudio: Bool = false
    ) -> WristSnapshotBuilder.Source {
        WristSnapshotBuilder.Source(
            id: UUID(), title: title, summary: summary, words: words,
            isVoice: isVoice, hasAudio: hasAudio, createdAt: now.addingTimeInterval(offset)
        )
    }

    /// Every source is a live wrist take; `gone` were imported and deleted since.
    private func build(_ sources: [WristSnapshotBuilder.Source], gone: Set<UUID> = [],
                       today: WristSnapshotBuilder.Source? = nil) -> WristSnapshot {
        let ids = Set(sources.map(\.id))
        return WristSnapshotBuilder.build(ledgerIDs: ids.union(gone), liveIDs: ids, recent: sources, today: today, now: now)
    }

    func test_recent_isTheNewestTwentyNewestFirst() {
        let sources = (0..<25).map { source(TimeInterval($0)) }
        let snapshot = build(sources.shuffled())
        XCTAssertEqual(snapshot.recent.count, WristSnapshotBuilder.recentLimit)
        XCTAssertEqual(snapshot.recent.first?.id, sources[24].id)
        XCTAssertEqual(snapshot.recent.last?.id, sources[5].id)
    }

    func test_recent_leavesOutThoughtsTheWatchDidntCatch() {
        let wrist = source(), phone = source(1)
        let snapshot = WristSnapshotBuilder.build(
            ledgerIDs: [wrist.id], liveIDs: [wrist.id, phone.id], recent: [wrist, phone], today: nil, now: now
        )
        XCTAssertEqual(snapshot.recent.map(\.id), [wrist.id])
    }

    func test_deletedIDs_areImportedTakesNoLongerInTheStore() {
        let gone = UUID()
        XCTAssertEqual(build([source()], gone: [gone]).deletedIDs, [gone])
        XCTAssertEqual(build([source()]).deletedIDs, [])
    }

    func test_summary_isTheReadingAndIsMarked() {
        let thought = WristSnapshotBuilder.thought(from: source(
            summary: "  A room that tells you to stay. ", words: String(repeating: "word ", count: 80)
        ))
        XCTAssertEqual(thought.reading, "A room that tells you to stay.")
        XCTAssertTrue(thought.readingIsSummary)
        XCTAssertFalse(thought.continues)
    }

    func test_shortWords_areTheWholeReading() {
        let thought = WristSnapshotBuilder.thought(from: source(words: "Lighthouse café at closing time"))
        XCTAssertEqual(thought.reading, "Lighthouse café at closing time")
        XCTAssertFalse(thought.readingIsSummary)
        XCTAssertFalse(thought.continues)
    }

    func test_longWords_areCutAtAWordBoundary() throws {
        let thought = WristSnapshotBuilder.thought(from: source(words: String(repeating: "lighthouse ", count: 40)))
        let reading = try XCTUnwrap(thought.reading)
        XCTAssertTrue(thought.continues)
        XCTAssertLessThanOrEqual(reading.count, WristSnapshotBuilder.readingLimit)
        XCTAssertTrue(reading.hasSuffix("lighthouse"), "never cut mid-word")
    }

    func test_chineseWords_areCutAtTheLimit() {
        let thought = WristSnapshotBuilder.thought(from: source(words: String(repeating: "灯塔咖啡馆", count: 60)))
        XCTAssertEqual(thought.reading?.count, WristSnapshotBuilder.readingLimit)
        XCTAssertTrue(thought.continues)
    }

    func test_noWords_meansNoReading() {
        let thought = WristSnapshotBuilder.thought(from: source(words: "   "))
        XCTAssertNil(thought.reading)
        XCTAssertFalse(thought.hasTranscript)
    }

    func test_hasTranscript_onlyForAVoiceThoughtWithWords() {
        XCTAssertTrue(WristSnapshotBuilder.thought(from: source(words: "words")).hasTranscript)
        XCTAssertFalse(WristSnapshotBuilder.thought(from: source(words: "words", isVoice: false)).hasTranscript)
    }

    func test_titleAndAudio_passThrough() {
        let thought = WristSnapshotBuilder.thought(from: source(title: "Lighthouse café", hasAudio: true))
        XCTAssertEqual(thought.title, "Lighthouse café")
        XCTAssertTrue(thought.hasAudio)
        XCTAssertTrue(thought.isVoice)
    }

    func test_today_carriesTheDayItWasPicked() {
        let pick = source(-40 * 86_400, isVoice: false)
        let with = build([], today: pick)
        XCTAssertEqual(with.today?.id, pick.id)
        XCTAssertEqual(with.todayDay, now)
        let without = build([])
        XCTAssertNil(without.today)
        XCTAssertNil(without.todayDay)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SharedTests/WristSnapshotBuilderTests`
Expected: build failure, "cannot find 'WristSnapshotBuilder' in scope".

- [ ] **Step 3: Write the implementation**

`Shared/Watch/WristSnapshotBuilder.swift`:

```swift
import Foundation

/// Builds the wrist snapshot from plain values, never `Node` (the watch
/// compiles this folder and has no store), so the rules are tested here.
/// The phone's `WristSnapshotPublisher` turns its thoughts into `Source`s.
enum WristSnapshotBuilder {
    /// As many wrist takes as the watch keeps confirmed.
    static let recentLimit = TakeQueueState.confirmedKept
    /// The phone summarizes a whisper this long (`CaptureSession.summaryThreshold`),
    /// so a cut mostly means its summary hasn't landed yet.
    static let readingLimit = 240

    /// One thought as the phone holds it, reduced to what the wrist needs.
    struct Source: Equatable {
        var id: UUID
        /// Already without the placeholder (`WhisperRules.name`).
        var title: String?
        /// A machine reading: a long whisper's summary, or a link's page summary.
        var summary: String?
        /// The thought's own words: its transcript, or its text.
        var words: String?
        var isVoice: Bool
        var hasAudio: Bool
        var createdAt: Date
    }

    /// `ledgerIDs`: every wrist take the phone has imported. `liveIDs`: those
    /// still in the store. `recent`: sources for the newest live takes (more
    /// than the limit is fine; anything not in the ledger is left out).
    static func build(
        ledgerIDs: Set<UUID>, liveIDs: Set<UUID>, recent: [Source], today: Source?, now: Date
    ) -> WristSnapshot {
        let newest = recent
            .filter { ledgerIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(recentLimit)
            .map(thought(from:))
        return WristSnapshot(
            recent: Array(newest),
            today: today.map(thought(from:)),
            todayDay: today == nil ? nil : now,
            deletedIDs: ledgerIDs.subtracting(liveIDs).sorted { $0.uuidString < $1.uuidString },
            generatedAt: now
        )
    }

    /// The summary when there is one; otherwise the user's own current
    /// words, cut at the limit. The user's text is never summarized here.
    static func thought(from source: Source) -> WristThought {
        let words = trimmed(source.words)
        var thought = WristThought(id: source.id, title: source.title, createdAt: source.createdAt)
        thought.isVoice = source.isVoice
        thought.hasAudio = source.hasAudio
        thought.hasTranscript = source.isVoice && words != nil
        if let summary = trimmed(source.summary) {
            thought.reading = summary
            thought.readingIsSummary = true
        } else if let words {
            let (reading, continues) = cut(words, limit: readingLimit)
            thought.reading = reading
            thought.continues = continues
        }
        return thought
    }

    /// Cuts at the last space in the second half of the limit (a word
    /// boundary), else at the limit itself (Chinese has no spaces).
    static func cut(_ text: String, limit: Int) -> (String, Bool) {
        guard text.count > limit else { return (text, false) }
        let head = text.prefix(limit)
        if let space = head.lastIndex(where: \.isWhitespace),
           head.distance(from: head.startIndex, to: space) >= limit / 2 {
            return (String(head[..<space]).trimmingCharacters(in: .whitespacesAndNewlines), true)
        }
        return (String(head).trimmingCharacters(in: .whitespacesAndNewlines), true)
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SharedTests/WristSnapshotBuilderTests`
Expected: `** TEST SUCCEEDED **`, 11 tests.

- [ ] **Step 5: Commit (only if Malik has asked for commits)**

```bash
git add Shared/Watch/WristSnapshotBuilder.swift SharedTests/WristSnapshotBuilderTests.swift Oryne.xcodeproj
git commit -m "Watch: build the wrist snapshot from plain values"
```

---

### Task 3: Reading a thought the way the phone does

**Files:**
- Create: `Shared/Services/WristSnapshotSource.swift`
- Test: `SharedTests/WristSnapshotSourceTests.swift`

Lives in `Shared/Services` next to `WhisperRules` (same precedent: phone-only `Node` rules kept in Shared so `SharedTests` covers them).

**Interfaces:**
- Consumes: `WristSnapshotBuilder.Source` (Task 2); `WhisperRules.name(of:placeholders:)`; `Node` fields `kind`, `title`, `text`, `transcription`, `summary`, `linkURL`, `linkSummary`, `audioData`, `createdAt`.
- Produces: `WristSnapshotBuilder.Source.init(node: Node, placeholders: Set<String>)`.

- [ ] **Step 1: Write the failing test**

`SharedTests/WristSnapshotSourceTests.swift`:

```swift
import XCTest
import Foundation

/// The wrist reads a thought the way the phone's thought page does
/// (`ExpandedNodeView.reading`). No app-module import: SharedTests compiles
/// Shared/ directly.
final class WristSnapshotSourceTests: XCTestCase {

    private let placeholders: Set<String> = ["Whisper", "语音"]

    private func source(_ node: Node) -> WristSnapshotBuilder.Source {
        WristSnapshotBuilder.Source(node: node, placeholders: placeholders)
    }

    func test_whisperWithASummary_readsTheSummary() {
        let node = Node(kind: .voice, title: "Lighthouse café", transcription: "Warm light at closing time")
        node.summary = "A room that tells you to stay."
        let s = source(node)
        XCTAssertEqual(s.summary, "A room that tells you to stay.")
        XCTAssertEqual(s.words, "Warm light at closing time")
        XCTAssertEqual(s.title, "Lighthouse café")
        XCTAssertTrue(s.isVoice)
    }

    func test_summaryWithoutATranscript_isNotRead() {
        let node = Node(kind: .voice, title: "Lighthouse café")
        node.summary = "Stale"
        XCTAssertNil(source(node).summary)
    }

    func test_placeholderTitle_isNoName() {
        XCTAssertNil(source(Node(kind: .voice, title: "Whisper")).title)
        XCTAssertNil(source(Node(kind: .voice, title: "语音")).title)
    }

    func test_link_readsItsPageSummary_andItsOwnText() {
        let node = Node(kind: .link, title: "Grids", text: "Use this for the issue", linkURLString: "https://example.com")
        node.linkSummary = "How magazines build their grids."
        let s = source(node)
        XCTAssertEqual(s.summary, "How magazines build their grids.")
        XCTAssertEqual(s.words, "Use this for the issue")
        XCTAssertFalse(s.isVoice)
    }

    func test_note_readsItsOwnText() {
        let s = source(Node(kind: .text, title: "Warm to cool", text: "Not a filter"))
        XCTAssertNil(s.summary)
        XCTAssertEqual(s.words, "Not a filter")
    }

    func test_audio_isReportedOnlyWhenThere() {
        XCTAssertTrue(source(Node(kind: .voice, audioData: Data([1]))).hasAudio)
        XCTAssertFalse(source(Node(kind: .voice)).hasAudio)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SharedTests/WristSnapshotSourceTests`
Expected: build failure, "extra argument 'node' in call" or "no exact matches in call to initializer".

- [ ] **Step 3: Write the implementation**

`Shared/Services/WristSnapshotSource.swift`:

```swift
import Foundation

extension WristSnapshotBuilder.Source {
    /// A thought as the wrist reads it, by the phone's own rule
    /// (`ExpandedNodeView.reading`): a whisper's summary once it has a
    /// transcript, else a link's page summary. The words are the transcript
    /// for a whisper and the text for anything else, as the user left them.
    /// `placeholders` is `VoiceUnderstanding.whisperPlaceholders`.
    init(node: Node, placeholders: Set<String>) {
        let hasTranscript = !(node.transcription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let whisperSummary = hasTranscript ? Self.nonEmpty(node.summary) : nil
        let pageSummary = node.linkURL == nil ? nil : Self.nonEmpty(node.linkSummary)
        self.init(
            id: node.id,
            title: WhisperRules.name(of: node, placeholders: placeholders),
            summary: whisperSummary ?? pageSummary,
            words: node.kind == .voice ? node.transcription : node.text,
            isVoice: node.kind == .voice,
            hasAudio: node.audioData?.isEmpty == false,
            createdAt: node.createdAt
        )
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SharedTests/WristSnapshotSourceTests`
Expected: `** TEST SUCCEEDED **`, 6 tests.

- [ ] **Step 5: Commit (only if Malik has asked for commits)**

```bash
git add Shared/Services/WristSnapshotSource.swift SharedTests/WristSnapshotSourceTests.swift Oryne.xcodeproj
git commit -m "Watch: read a thought for the wrist the way the thought page does"
```

---

### Task 4: The queue keeps wrist audio and follows the phone

**Files:**
- Modify: `Shared/Watch/TakeQueueState.swift` (`QueuedTake`, `audioDisposable`, new `apply(_ snapshot:)`, `audioRetention`)
- Modify: `Shared/Watch/TakeQueueStore.swift:43-56` (`sweep` gains `now`)
- Modify: `OryneWatch/Services/TakeQueue.swift` (new `hasAudio`)
- Test: `SharedTests/TakeQueueStateTests.swift`, `SharedTests/TakeQueueStoreTests.swift`

**Interfaces:**
- Consumes: `WristSnapshot`, `WristThought` (Task 1).
- Produces:
  - `QueuedTake.hasTranscript: Bool` (default false; an earlier index decodes).
  - `TakeQueueState.audioRetention: TimeInterval` (30 days).
  - `TakeQueueState.audioDisposable(_ id: UUID, now: Date = .now) -> Bool`.
  - `TakeQueueState.apply(_ snapshot: WristSnapshot)`.
  - `TakeQueueStore.sweep(_ state: TakeQueueState, now: Date = .now)`.
  - `TakeQueue.hasAudio(_ id: UUID) -> Bool`.

- [ ] **Step 1: Write the failing tests**

In `SharedTests/TakeQueueStateTests.swift`, replace `test_audioDisposable_followsWhereTheTakeIsSafe` with the tests below, and add the helper under `take(_:)`:

```swift
    private func snapshot(_ thoughts: [WristThought] = [], deleted: [UUID] = []) -> WristSnapshot {
        WristSnapshot(recent: thoughts, today: nil, todayDay: nil, deletedIDs: deleted, generatedAt: t0)
    }

    private func transcribed(_ take: WatchTake, title: String? = nil) -> WristThought {
        var thought = WristThought(id: take.id, title: title, createdAt: take.createdAt)
        thought.hasTranscript = true
        return thought
    }

    func test_audioDisposable_keepsEveryRecordingTheWristCanReplay() {
        var state = TakeQueueState()
        let onWatch = take(), clouded = take(1), confirmed = take(2)
        [onWatch, clouded, confirmed].forEach { state.add($0, phoneReachableAtStop: true) }
        state.markInICloud(clouded.id)
        state.apply([WatchConfirmation(id: confirmed.id, title: nil)])
        let soon = t0.addingTimeInterval(60)

        XCTAssertFalse(state.audioDisposable(onWatch.id, now: soon))
        XCTAssertFalse(state.audioDisposable(clouded.id, now: soon))
        XCTAssertFalse(state.audioDisposable(confirmed.id, now: soon))
        XCTAssertFalse(state.audioDisposable(UUID(), now: soon), "a recording the queue can't account for is never deleted")
    }

    func test_audioDisposable_expiresATranscribedTakeAsThePhoneDoes() {
        var state = TakeQueueState()
        let withWords = take(), withoutWords = take(1)
        [withWords, withoutWords].forEach { state.add($0, phoneReachableAtStop: true) }
        state.apply([WatchConfirmation(id: withWords.id, title: nil), WatchConfirmation(id: withoutWords.id, title: nil)])
        state.apply(snapshot([transcribed(withWords)]))
        let retention = TakeQueueState.audioRetention

        XCTAssertFalse(state.audioDisposable(withWords.id, now: t0.addingTimeInterval(retention - 10)))
        XCTAssertTrue(state.audioDisposable(withWords.id, now: t0.addingTimeInterval(retention + 10)))
        XCTAssertFalse(state.audioDisposable(withoutWords.id, now: t0.addingTimeInterval(retention + 10)),
                       "with no transcript the recording is the only copy of the words")
    }

    func test_applySnapshot_removesOnlyConfirmedTakesThePhoneDeleted() {
        var state = TakeQueueState()
        let waiting = take(), confirmed = take(1)
        [waiting, confirmed].forEach { state.add($0, phoneReachableAtStop: true) }
        state.apply([WatchConfirmation(id: confirmed.id, title: nil)])
        let before = state

        state.apply(snapshot(deleted: [waiting.id, confirmed.id]))

        XCTAssertNotNil(state.item(waiting.id), "the phone can't have deleted a take it never confirmed")
        XCTAssertNil(state.item(confirmed.id))
        XCTAssertEqual(state.idsRemoved(since: before), [confirmed.id])
    }

    func test_applySnapshot_takesCurrentTitles_butANilTitleNeverErases() {
        var state = TakeQueueState()
        let renamed = take(), unnamed = take(1)
        [renamed, unnamed].forEach { state.add($0, phoneReachableAtStop: true) }
        state.apply([
            WatchConfirmation(id: renamed.id, title: "Lighthouse café"),
            WatchConfirmation(id: unnamed.id, title: "Old idea"),
        ])

        state.apply(snapshot([transcribed(renamed, title: "The café by the lighthouse"), transcribed(unnamed)]))

        XCTAssertEqual(state.item(renamed.id)?.title, "The café by the lighthouse")
        XCTAssertEqual(state.item(unnamed.id)?.title, "Old idea")
        XCTAssertEqual(state.item(renamed.id)?.hasTranscript, true)
    }

    func test_indexFromAnEarlierVersion_stillLoads() throws {
        let id = UUID()
        let json = """
        {"takes":[{"take":{"id":"\(id.uuidString)","createdAt":0,"duration":3,"version":1},\
        "status":"confirmed","phoneTransfer":"delivered","phoneReachableAtStop":true,"title":"Lighthouse café"}]}
        """
        let state = try JSONDecoder().decode(TakeQueueState.self, from: Data(json.utf8))
        XCTAssertEqual(state.item(id)?.title, "Lighthouse café")
        XCTAssertEqual(state.item(id)?.hasTranscript, false)
    }
```

In `SharedTests/TakeQueueStoreTests.swift`, replace `test_sweep_deletesOnlyAudioSafeElsewhere` with:

```swift
    func test_sweep_deletesOnlyExpiredTranscribedAudio() throws {
        var state = TakeQueueState()
        let waiting = take(), clouded = take(1), confirmed = take(2), expired = take(3)
        let unlisted = UUID()
        [waiting, clouded, confirmed, expired].forEach { state.add($0, phoneReachableAtStop: true) }
        state.markInICloud(clouded.id)
        state.apply([WatchConfirmation(id: confirmed.id, title: nil), WatchConfirmation(id: expired.id, title: nil)])
        var words = WristThought(id: expired.id, title: nil, createdAt: expired.createdAt)
        words.hasTranscript = true
        state.apply(WristSnapshot(recent: [words], today: nil, todayDay: nil, deletedIDs: [], generatedAt: expired.createdAt))
        for id in [waiting.id, clouded.id, confirmed.id, expired.id, unlisted] { try writeAudio(id) }

        store.sweep(state, now: expired.createdAt.addingTimeInterval(TakeQueueState.audioRetention + 60))

        XCTAssertTrue(audioExists(waiting.id))
        XCTAssertTrue(audioExists(clouded.id), "kept for replay")
        XCTAssertTrue(audioExists(confirmed.id), "no transcript: kept")
        XCTAssertFalse(audioExists(expired.id))
        XCTAssertTrue(audioExists(unlisted), "a recording the index doesn't list is never guessed away")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SharedTests/TakeQueueStateTests -only-testing:SharedTests/TakeQueueStoreTests`
Expected: build failure, "value of type 'QueuedTake' has no member 'hasTranscript'".

- [ ] **Step 3: Write the implementation**

In `Shared/Watch/TakeQueueState.swift`, replace `QueuedTake` with:

```swift
struct QueuedTake: Codable, Equatable, Identifiable {
    var take: WatchTake
    var status: TakeStatus = .onWatch
    var phoneTransfer: PhoneTransfer = .notSent
    /// Whether the phone was reachable when the take was caught. A take
    /// caught out of reach goes to the iCloud inbox at once.
    var phoneReachableAtStop: Bool
    var title: String? = nil
    /// The phone has a transcript for it, so its audio here may expire as
    /// the phone's does.
    var hasTranscript: Bool = false

    var id: UUID { take.id }
}

extension QueuedTake {
    private enum CodingKeys: String, CodingKey {
        case take, status, phoneTransfer, phoneReachableAtStop, title, hasTranscript
    }

    /// Fields added after an index was written decode to their defaults, so
    /// an index from an earlier version still loads (and its takes stay).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        take = try container.decode(WatchTake.self, forKey: .take)
        status = try container.decodeIfPresent(TakeStatus.self, forKey: .status) ?? .onWatch
        phoneTransfer = try container.decodeIfPresent(PhoneTransfer.self, forKey: .phoneTransfer) ?? .notSent
        phoneReachableAtStop = try container.decode(Bool.self, forKey: .phoneReachableAtStop)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        hasTranscript = try container.decodeIfPresent(Bool.self, forKey: .hasTranscript) ?? false
    }
}
```

In `TakeQueueState`, add under `cloudRetryInterval`:

```swift
    /// How long the watch keeps a transcribed take's audio: the phone's own
    /// retention (`OryneApp.expireConfirmedAudio`), so the wrist's copy
    /// never outlives the phone's.
    static let audioRetention: TimeInterval = 30 * 24 * 60 * 60
```

Add under `apply(_ confirmations:)`:

```swift
    /// Applies the phone's snapshot: current titles and transcripts for the
    /// takes it lists, and takes the user deleted leave the queue (their
    /// audio with them). Only a confirmed take can leave this way: the phone
    /// can't have deleted a take it never confirmed. A missing title never
    /// erases one the watch already has.
    mutating func apply(_ snapshot: WristSnapshot) {
        for thought in snapshot.recent {
            update(thought.id) {
                $0.hasTranscript = thought.hasTranscript
                if let title = thought.title { $0.title = title }
            }
        }
        let deleted = Set(snapshot.deletedIDs)
        takes.removeAll { $0.status == .confirmed && deleted.contains($0.id) }
    }
```

Replace `audioDisposable(_:)` (doc comment and body) with:

```swift
    /// Whether the watch may delete this take's audio while the take stays
    /// in the queue. It keeps every recording the wrist can replay; only a
    /// confirmed take with a transcript expires, after `audioRetention`, as
    /// the phone's copy does. A take leaving the queue (Undo, pruning, deleted
    /// on the phone) takes its audio through `TakeQueue.change`. A recording
    /// the queue can't account for (an unreadable index, a crash mid-recording)
    /// is never deleted: guessing wrong loses a caught take.
    func audioDisposable(_ id: UUID, now: Date = .now) -> Bool {
        guard let item = item(id), item.status == .confirmed, item.hasTranscript else { return false }
        return now.timeIntervalSince(item.take.createdAt) > Self.audioRetention
    }
```

In `Shared/Watch/TakeQueueStore.swift`, replace `sweep`:

```swift
    /// Deletes audio the state says the wrist no longer needs. A recording
    /// the index doesn't list (one being recorded, an unreadable index, a
    /// crash mid-recording) is kept: `audioDisposable` never guesses about it.
    func sweep(_ state: TakeQueueState, now: Date = .now) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        for file in files where file.pathExtension == "m4a" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  state.audioDisposable(id, now: now)
            else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
```

In `OryneWatch/Services/TakeQueue.swift`, add under `audioURL(for:)`:

```swift
    /// Whether the watch still holds this take's recording.
    func hasAudio(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: store.audioURL(for: id).path)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SharedTests/TakeQueueStateTests -only-testing:SharedTests/TakeQueueStoreTests -only-testing:SharedTests/TakeSyncTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit (only if Malik has asked for commits)**

```bash
git add Shared/Watch/TakeQueueState.swift Shared/Watch/TakeQueueStore.swift OryneWatch/Services/TakeQueue.swift SharedTests/TakeQueueStateTests.swift SharedTests/TakeQueueStoreTests.swift
git commit -m "Watch: keep wrist audio for replay; follow the phone's deletions and expiry"
```

---

### Task 5: The Today and Recent rows

**Files:**
- Create: `Shared/Watch/WristRecent.swift`
- Test: `SharedTests/WristRecentTests.swift`

**Interfaces:**
- Consumes: `TakeQueueState`, `QueuedTake` (Task 4); `WristSnapshot.today(on:calendar:)`, `.recentThought(_:)` (Task 1).
- Produces:
  - `struct WristRow: Hashable, Identifiable` with `id: UUID`, `title: String?`, `caughtAt: Date`, `duration: TimeInterval?`, `isWaiting: Bool`, `reading: String?`, `readingIsSummary: Bool`, `continues: Bool`, `isVoice: Bool`, `audio: WristRow.Audio` (`.watch`, `.phone`, `.none`), `isToday: Bool`.
  - `WristRecent.rows(queue: TakeQueueState, snapshot: WristSnapshot?, hasLocalAudio: (UUID) -> Bool) -> [WristRow]`
  - `WristRecent.today(snapshot: WristSnapshot?, queue: TakeQueueState, now: Date, calendar: Calendar = .current, hasLocalAudio: (UUID) -> Bool) -> WristRow?`

- [ ] **Step 1: Write the failing test**

`SharedTests/WristRecentTests.swift`:

```swift
import XCTest
import Foundation

final class WristRecentTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let noAudio: (UUID) -> Bool = { _ in false }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func take(_ offset: TimeInterval) -> WatchTake {
        WatchTake(id: UUID(), createdAt: t0.addingTimeInterval(offset), duration: 8)
    }

    private func thought(_ id: UUID, title: String? = nil, hasAudio: Bool = false, at date: Date? = nil) -> WristThought {
        var thought = WristThought(id: id, title: title, createdAt: date ?? t0)
        thought.reading = "A room that tells you to stay."
        thought.hasAudio = hasAudio
        thought.isVoice = true
        return thought
    }

    private func snapshot(_ recent: [WristThought] = [], today: WristThought? = nil, deleted: [UUID] = []) -> WristSnapshot {
        WristSnapshot(recent: recent, today: today, todayDay: today == nil ? nil : t0, deletedIDs: deleted, generatedAt: t0)
    }

    func test_queueTakes_areListedNewestFirst_withoutASnapshot() {
        var queue = TakeQueueState()
        let older = take(0), waiting = take(60)
        queue.add(older, phoneReachableAtStop: true)
        queue.add(waiting, phoneReachableAtStop: false)
        queue.apply([WatchConfirmation(id: older.id, title: "Lighthouse café")])

        let rows = WristRecent.rows(queue: queue, snapshot: nil, hasLocalAudio: noAudio)

        XCTAssertEqual(rows.map(\.id), [waiting.id, older.id])
        XCTAssertTrue(rows[0].isWaiting)
        XCTAssertNil(rows[0].title)
        XCTAssertEqual(rows[1].title, "Lighthouse café")
        XCTAssertFalse(rows[1].isWaiting)
        XCTAssertEqual(rows[1].duration, 8)
    }

    func test_snapshot_givesTheCurrentTitleAndReading() {
        var queue = TakeQueueState()
        let a = take(0)
        queue.add(a, phoneReachableAtStop: true)
        queue.apply([WatchConfirmation(id: a.id, title: "Lighthouse café")])

        let row = WristRecent.rows(queue: queue, snapshot: snapshot([thought(a.id, title: "The café by the lighthouse")]), hasLocalAudio: noAudio).first

        XCTAssertEqual(row?.title, "The café by the lighthouse")
        XCTAssertEqual(row?.reading, "A room that tells you to stay.")
    }

    func test_deletedTake_isNotListed() {
        var queue = TakeQueueState()
        let a = take(0)
        queue.add(a, phoneReachableAtStop: true)
        XCTAssertTrue(WristRecent.rows(queue: queue, snapshot: snapshot(deleted: [a.id]), hasLocalAudio: noAudio).isEmpty)
    }

    func test_takeOnlyTheSnapshotKnows_isListedAndPlaysFromThePhone() {
        let id = UUID()
        let rows = WristRecent.rows(queue: TakeQueueState(), snapshot: snapshot([thought(id, hasAudio: true)]), hasLocalAudio: noAudio)
        XCTAssertEqual(rows.map(\.id), [id])
        XCTAssertEqual(rows.first?.audio, .phone)
        XCTAssertNil(rows.first?.duration)
    }

    func test_audio_prefersTheWatchsOwnCopy() {
        var queue = TakeQueueState()
        let local = take(0), remote = take(1), silent = take(2)
        [local, remote, silent].forEach { queue.add($0, phoneReachableAtStop: true) }
        let snap = snapshot([thought(local.id, hasAudio: true), thought(remote.id, hasAudio: true), thought(silent.id)])

        let rows = WristRecent.rows(queue: queue, snapshot: snap) { $0 == local.id }
        let audio = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.audio) })

        XCTAssertEqual(audio[local.id], .watch)
        XCTAssertEqual(audio[remote.id], .phone)
        XCTAssertEqual(audio[silent.id], WristRow.Audio.none)
    }

    func test_today_showsOnItsDayOnly_andIsMarked() {
        let pick = thought(UUID(), title: "Warm to cool", hasAudio: true, at: t0.addingTimeInterval(-40 * 86_400))
        let snap = snapshot(today: pick)

        let row = WristRecent.today(snapshot: snap, queue: TakeQueueState(), now: t0.addingTimeInterval(60), calendar: utc, hasLocalAudio: noAudio)
        XCTAssertEqual(row?.id, pick.id)
        XCTAssertEqual(row?.isToday, true)
        XCTAssertEqual(row?.audio, .phone)

        XCTAssertNil(WristRecent.today(snapshot: snap, queue: TakeQueueState(), now: t0.addingTimeInterval(86_400), calendar: utc, hasLocalAudio: noAudio))
        XCTAssertNil(WristRecent.today(snapshot: nil, queue: TakeQueueState(), now: t0, calendar: utc, hasLocalAudio: noAudio))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SharedTests/WristRecentTests`
Expected: build failure, "cannot find 'WristRecent' in scope".

- [ ] **Step 3: Write the implementation**

`Shared/Watch/WristRecent.swift`:

```swift
import Foundation

/// One row on the wrist's Today or Recent page, and the thought it opens.
struct WristRow: Hashable, Identifiable {
    enum Audio: Hashable {
        /// The watch still holds the recording.
        case watch
        /// The phone holds it and sends it on request.
        case phone
        /// Nothing to play: no control.
        case none
    }

    var id: UUID
    /// Nil until the phone names it: the row shows the time it was caught.
    var title: String?
    var caughtAt: Date
    /// The take's length; nil for a thought the watch has no take for.
    var duration: TimeInterval?
    /// Still only on the watch: "Waiting for iPhone".
    var isWaiting: Bool
    var reading: String?
    var readingIsSummary: Bool
    var continues: Bool
    var isVoice: Bool
    var audio: Audio
    /// Opened from Today: opening it tells the phone it was met.
    var isToday: Bool
}

/// The wrist's Today and Recent rows, from the queue (what the watch caught)
/// and the phone's snapshot (what those takes are now). Pure, so the rules
/// are tested without a watch.
enum WristRecent {
    /// Every take still in the queue, whatever its state (a take on the
    /// watch or in iCloud is never hidden for want of a snapshot), and every
    /// take the snapshot lists; never one the phone deleted. Newest first.
    static func rows(queue: TakeQueueState, snapshot: WristSnapshot?, hasLocalAudio: (UUID) -> Bool) -> [WristRow] {
        let deleted = Set(snapshot?.deletedIDs ?? [])
        var rows: [WristRow] = []
        var listed: Set<UUID> = []
        for item in queue.takes where !deleted.contains(item.id) {
            rows.append(row(
                thought: snapshot?.recentThought(item.id), id: item.id, fallbackTitle: item.title,
                caughtAt: item.take.createdAt, duration: item.take.duration, isWaiting: item.status == .onWatch,
                isVoice: true, hasLocalAudio: hasLocalAudio(item.id), isToday: false
            ))
            listed.insert(item.id)
        }
        for thought in snapshot?.recent ?? [] where !listed.contains(thought.id) {
            rows.append(row(
                thought: thought, id: thought.id, fallbackTitle: nil, caughtAt: thought.createdAt,
                duration: nil, isWaiting: false, isVoice: thought.isVoice,
                hasLocalAudio: hasLocalAudio(thought.id), isToday: false
            ))
        }
        return rows.sorted { $0.caughtAt > $1.caughtAt }
    }

    /// Today's resurfaced thought, only on the day the phone picked it.
    static func today(
        snapshot: WristSnapshot?, queue: TakeQueueState, now: Date,
        calendar: Calendar = .current, hasLocalAudio: (UUID) -> Bool
    ) -> WristRow? {
        guard let thought = snapshot?.today(on: now, calendar: calendar) else { return nil }
        return row(
            thought: thought, id: thought.id, fallbackTitle: nil, caughtAt: thought.createdAt,
            duration: queue.item(thought.id)?.take.duration, isWaiting: false, isVoice: thought.isVoice,
            hasLocalAudio: hasLocalAudio(thought.id), isToday: true
        )
    }

    private static func row(
        thought: WristThought?, id: UUID, fallbackTitle: String?, caughtAt: Date, duration: TimeInterval?,
        isWaiting: Bool, isVoice: Bool, hasLocalAudio: Bool, isToday: Bool
    ) -> WristRow {
        let audio: WristRow.Audio = hasLocalAudio ? .watch : (thought?.hasAudio == true ? .phone : .none)
        return WristRow(
            id: id, title: thought?.title ?? fallbackTitle, caughtAt: caughtAt, duration: duration,
            isWaiting: isWaiting, reading: thought?.reading, readingIsSummary: thought?.readingIsSummary ?? false,
            continues: thought?.continues ?? false, isVoice: isVoice, audio: audio, isToday: isToday
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SharedTests/WristRecentTests`
Expected: `** TEST SUCCEEDED **`, 6 tests.

- [ ] **Step 5: Commit (only if Malik has asked for commits)**

```bash
git add Shared/Watch/WristRecent.swift SharedTests/WristRecentTests.swift Oryne.xcodeproj
git commit -m "Watch: derive the Today and Recent rows from the queue and the snapshot"
```

---

### Task 6: The watch holds the snapshot

**Files:**
- Create: `Shared/Watch/WristSnapshotStore.swift` (next to `TakeQueueStore`, the same kind of file; the spec's unit table placed it in `OryneWatch/Services`, Shared keeps it tested)
- Create: `OryneWatch/Services/WristLibrary.swift`
- Modify: `project.yml:118-122` (register `WristLibrary.swift` in `SharedTests`)
- Test: `SharedTests/WristLibraryTests.swift`

**Interfaces:**
- Consumes: `WristSnapshot`, `WatchWire.encode/decodeSnapshot` (Task 1).
- Produces:
  - `struct WristSnapshotStore` with `init(url: URL)`, `static var standard`, `load() -> WristSnapshot?`, `save(_:)`.
  - `@MainActor @Observable final class WristLibrary` with `init(store: WristSnapshotStore = .standard)`, `private(set) var snapshot: WristSnapshot?`, `@discardableResult func receive(_ incoming: WristSnapshot) -> Bool`, and `#if DEBUG func showDemo(_:)`.

- [ ] **Step 1: Register the file for tests**

In `project.yml`, under `SharedTests.sources`, replace the watch block with:

```yaml
      # The watch's sender, the queue it drives, and the snapshot holder hold
      # no watch API, so their tests (TakeSyncTests, WristLibraryTests) run
      # here with the rest. Keep them free of WatchKit.
      - path: OryneWatch/Services/TakeSync.swift
      - path: OryneWatch/Services/TakeQueue.swift
      - path: OryneWatch/Services/WristLibrary.swift
```

- [ ] **Step 2: Write the failing test**

`SharedTests/WristLibraryTests.swift`:

```swift
import XCTest
import Foundation

final class WristLibraryTests: XCTestCase {

    private var directory: URL!
    private var store: WristSnapshotStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WristLibraryTests-\(UUID().uuidString)", isDirectory: true)
        store = WristSnapshotStore(url: directory.appendingPathComponent("snapshot.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func snapshot(builtAt seconds: TimeInterval, deleted: [UUID] = []) -> WristSnapshot {
        WristSnapshot(recent: [], today: nil, todayDay: nil, deletedIDs: deleted,
                      generatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds))
    }

    func test_store_loadsNothingBeforeTheFirstSave() {
        XCTAssertNil(store.load())
    }

    func test_store_roundTrips() {
        let snap = snapshot(builtAt: 0, deleted: [UUID()])
        store.save(snap)
        XCTAssertEqual(store.load(), snap)
    }

    func test_store_unreadableFileLoadsNothing() throws {
        try Data("nope".utf8).write(to: store.url)
        XCTAssertNil(store.load())
    }

    @MainActor
    func test_library_keepsTheNewerSnapshot_acrossLaunches() {
        let library = WristLibrary(store: store)
        XCTAssertTrue(library.receive(snapshot(builtAt: 10)))
        XCTAssertEqual(WristLibrary(store: store).snapshot, snapshot(builtAt: 10))
    }

    @MainActor
    func test_library_ignoresAnOlderSnapshot() {
        let library = WristLibrary(store: store)
        library.receive(snapshot(builtAt: 10))
        XCTAssertFalse(library.receive(snapshot(builtAt: 5, deleted: [UUID()])))
        XCTAssertEqual(library.snapshot, snapshot(builtAt: 10))
        XCTAssertEqual(store.load(), snapshot(builtAt: 10))
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SharedTests/WristLibraryTests`
Expected: build failure, "cannot find 'WristSnapshotStore' in scope".

- [ ] **Step 4: Write the implementation**

`Shared/Watch/WristSnapshotStore.swift`:

```swift
import Foundation

/// The phone's latest wrist snapshot on the watch's own disk, so Today and
/// Recent show at launch before the phone answers. One JSON file in the
/// watch app's Application Support.
struct WristSnapshotStore {
    let url: URL

    init(url: URL) {
        self.url = url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    static var standard: WristSnapshotStore {
        WristSnapshotStore(url: URL.applicationSupportDirectory
            .appendingPathComponent("Wrist", isDirectory: true)
            .appendingPathComponent("snapshot.json"))
    }

    /// Nil before the first snapshot, or when the file can't be read: the
    /// pages then show the queue alone until the phone sends another.
    func load() -> WristSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return WatchWire.decodeSnapshot(data)
    }

    func save(_ snapshot: WristSnapshot) {
        guard let data = WatchWire.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
```

`OryneWatch/Services/WristLibrary.swift`:

```swift
import Foundation
import Observation

/// The phone's latest word on the wrist's thoughts, as the Today and Recent
/// pages read it. Kept on disk so the pages render at launch. A snapshot
/// older than the one held (a reply and a context update crossing) changes
/// nothing.
///
/// No watch API in here: SharedTests compiles this file (see project.yml).
@MainActor
@Observable
final class WristLibrary {
    private(set) var snapshot: WristSnapshot?
    @ObservationIgnored private let store: WristSnapshotStore
    #if DEBUG
    @ObservationIgnored private var isShowingDemo = false
    #endif

    init(store: WristSnapshotStore = .standard) {
        self.store = store
        snapshot = store.load()
    }

    /// True when the snapshot was newer and is now the one held.
    @discardableResult
    func receive(_ incoming: WristSnapshot) -> Bool {
        guard incoming.isNewer(than: snapshot) else { return false }
        snapshot = incoming
        #if DEBUG
        // A screenshot demo never touches the real snapshot on disk.
        if isShowingDemo { return true }
        #endif
        store.save(incoming)
        return true
    }

    #if DEBUG
    /// Screenshot seam: show a snapshot without touching disk.
    func showDemo(_ demo: WristSnapshot) {
        isShowingDemo = true
        snapshot = demo
    }
    #endif
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SharedTests/WristLibraryTests`
Expected: `** TEST SUCCEEDED **`, 5 tests.

- [ ] **Step 6: Commit (only if Malik has asked for commits)**

```bash
git add Shared/Watch/WristSnapshotStore.swift OryneWatch/Services/WristLibrary.swift SharedTests/WristLibraryTests.swift project.yml Oryne.xcodeproj
git commit -m "Watch: hold the phone's latest snapshot on disk"
```

---

### Task 7: The watch's link receives snapshots, asks for them, and fetches audio

**Files:**
- Create: `OryneWatch/Services/PlaybackCache.swift`
- Modify: `OryneWatch/Services/TakeSync.swift` (protocol, init, snapshot handling, `requestSnapshot`)
- Modify: `OryneWatch/Services/PhoneLink.swift` (full replacement below)
- Modify: `OryneWatch/OryneWatchApp.swift:9-27` (pass a `WristLibrary`)
- Test: `SharedTests/TakeSyncTests.swift`

**Interfaces:**
- Consumes: `WristLibrary.receive` (Task 6), `TakeQueueState.apply(_ snapshot:)` and `TakeQueue.hasAudio` (Task 4), `WatchWire` keys (Task 1).
- Produces:
  - `PhoneLinking.onSnapshot: (@MainActor (WristSnapshot) -> Void)?` and `PhoneLinking.requestSnapshot()`.
  - `TakeSync.init(queue:link:cloud:library:scheduleRefresh:)` and `TakeSync.requestSnapshot()`.
  - `PhoneLink.AudioFetch` (`.file(URL)`, `.phoneAway`, `.failed`), `PhoneLink.fetchAudio(_ id: UUID) async -> AudioFetch`, `PhoneLink.sendMet(_ id: UUID)`.
  - `PlaybackCache.url(for:)`, `.remove(_:)`, `.clear()`.

- [ ] **Step 1: Write the failing tests**

In `SharedTests/TakeSyncTests.swift`:

Replace the fixture's stored properties and `init` with:

```swift
        let queue: TakeQueue
        let library: WristLibrary
        let link = FakePhoneLink()
        let cloud = FakeCloudInbox()
        var scheduled: [Date] = []
        private(set) var sync: TakeSync!

        init(directory: URL) {
            queue = TakeQueue(store: TakeQueueStore(directory: directory))
            library = WristLibrary(store: WristSnapshotStore(url: directory.appendingPathComponent("wrist.json")))
            sync = TakeSync(queue: queue, link: link, cloud: cloud, library: library) { [unowned self] date in
                self.scheduled.append(date)
            }
        }
```

In `FakePhoneLink`, add under `onActivated`:

```swift
        var onSnapshot: (@MainActor (WristSnapshot) -> Void)?
        private(set) var snapshotRequests = 0

        func requestSnapshot() {
            snapshotRequests += 1
        }
```

Add before `// MARK: - Background refresh`:

```swift
    // MARK: - The wrist snapshot

    @MainActor
    func test_snapshot_dropsATakeDeletedOnThePhone_withItsAudio() throws {
        let f = makeFixture()
        let id = f.catchTake(reachable: true)
        try Data([1]).write(to: f.queue.audioURL(for: id))
        f.link.onConfirmations?([WatchConfirmation(id: id, title: "Lighthouse café")])
        let snapshot = WristSnapshot(recent: [], today: nil, todayDay: nil, deletedIDs: [id], generatedAt: Date())

        f.link.onSnapshot?(snapshot)

        XCTAssertNil(f.item(id))
        XCTAssertFalse(f.queue.hasAudio(id))
        XCTAssertEqual(f.library.snapshot, snapshot)
    }

    @MainActor
    func test_olderSnapshot_changesNothing() {
        let f = makeFixture()
        let id = f.catchTake(reachable: true)
        f.link.onConfirmations?([WatchConfirmation(id: id, title: nil)])
        let now = Date()
        let newer = WristSnapshot(recent: [], today: nil, todayDay: nil, deletedIDs: [], generatedAt: now)
        let older = WristSnapshot(recent: [], today: nil, todayDay: nil, deletedIDs: [id], generatedAt: now.addingTimeInterval(-5))

        f.link.onSnapshot?(newer)
        f.link.onSnapshot?(older)

        XCTAssertNotNil(f.item(id), "a crossed, older snapshot deletes nothing")
        XCTAssertEqual(f.library.snapshot, newer)
    }

    @MainActor
    func test_activation_asksForAFreshSnapshot() async {
        let f = makeFixture()
        f.link.onActivated?()
        await f.sync.flush()
        XCTAssertEqual(f.link.snapshotRequests, 1)
    }

    @MainActor
    func test_requestSnapshot_asksTheLink() {
        let f = makeFixture()
        f.sync.requestSnapshot()
        XCTAssertEqual(f.link.snapshotRequests, 1)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SharedTests/TakeSyncTests`
Expected: build failure, "extra argument 'library' in call".

- [ ] **Step 3: Update `TakeSync`**

In `OryneWatch/Services/TakeSync.swift`, add to `PhoneLinking` under `onActivated`:

```swift
    var onSnapshot: (@MainActor (WristSnapshot) -> Void)? { get set }
```

and under `func wake(_ id: UUID)`:

```swift
    /// Asks the phone for a fresh wrist snapshot; nothing when it's out of reach.
    func requestSnapshot()
```

Add the stored property under `cloud`:

```swift
    private let library: WristLibrary
```

Replace `init` with:

```swift
    /// `scheduleRefresh` asks the system to wake the app for
    /// `refreshIdentifier` around the given date.
    init(
        queue: TakeQueue,
        link: any PhoneLinking,
        cloud: (any CloudInboxUploading)?,
        library: WristLibrary,
        scheduleRefresh: @escaping @MainActor (Date) -> Void
    ) {
        self.queue = queue
        self.link = link
        self.cloud = cloud
        self.library = library
        self.scheduleRefresh = scheduleRefresh
        link.onConfirmations = { [weak self] confirmations in
            self?.queue.change { $0.apply(confirmations) }
        }
        link.onSnapshot = { [weak self] snapshot in
            // A reply and a context update can cross: only a newer snapshot
            // changes anything.
            guard let self, self.library.receive(snapshot) else { return }
            self.queue.change { $0.apply(snapshot) }
        }
        link.onTransferFinished = { [weak self] id, delivered in
            // A failed transfer is retried on the next flush, not in a loop.
            self?.queue.change { $0.markPhoneTransfer(id, delivered ? .delivered : .notSent) }
        }
        link.onActivated = { [weak self] in
            self?.reconcile()
            self?.requestSnapshot()
            Task { await self?.flush() }
        }
    }
```

Add under `start()`:

```swift
    /// On screen with the phone in reach: ask it for a fresh snapshot. Out
    /// of reach this does nothing; the held snapshot stays, and nothing says
    /// "syncing" (PHILOSOPHY §5).
    func requestSnapshot() {
        link.requestSnapshot()
    }
```

- [ ] **Step 4: Create `PlaybackCache`**

`OryneWatch/Services/PlaybackCache.swift`:

```swift
import Foundation

/// Audio fetched from the phone for one listen. Never part of the take
/// queue: cleared when the thought closes and at launch.
enum PlaybackCache {
    static var folder: URL {
        URL.cachesDirectory.appendingPathComponent("Playback", isDirectory: true)
    }

    static func url(for id: UUID) -> URL {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(id.uuidString).m4a")
    }

    static func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(id.uuidString).m4a"))
    }

    static func clear() {
        try? FileManager.default.removeItem(at: folder)
    }
}
```

- [ ] **Step 5: Replace `PhoneLink`**

`OryneWatch/Services/PhoneLink.swift`, whole file:

```swift
import Foundation
import WatchConnectivity
import os

/// Failures only, and never user content: a take ID at most.
private let log = Logger(subsystem: "com.inspireocean.app.watchkitapp", category: "sync")

/// The watch's end of WatchConnectivity: hands takes to the system as file
/// transfers, pings the phone awake, receives the phone's confirmations and
/// wrist snapshot (application context, or a reply when the watch asks),
/// fetches a thought's audio for replay, and says when today's thought was
/// met. Delegate callbacks arrive off the main thread and hop to the main
/// actor before touching anything.
final class PhoneLink: NSObject, WCSessionDelegate {
    /// What an audio fetch came to.
    enum AudioFetch: Equatable {
        /// The recording, in `PlaybackCache`.
        case file(URL)
        /// The phone can't be reached right now.
        case phoneAway
        /// Refused (no audio any more), an error, or no file in time.
        case failed
    }

    static let audioFetchTimeout: Duration = .seconds(30)

    var onConfirmations: (@MainActor ([WatchConfirmation]) -> Void)?
    var onSnapshot: (@MainActor (WristSnapshot) -> Void)?
    var onTransferFinished: (@MainActor (_ id: UUID, _ delivered: Bool) -> Void)?
    var onActivated: (@MainActor () -> Void)?

    private let session = WCSession.default

    private struct AudioWaiter {
        let token: UUID
        let continuation: CheckedContinuation<AudioFetch, Never>
    }

    /// Fetches waiting for their file, by thought ID. Delegate callbacks
    /// reach this off the main thread, hence the lock.
    private let waitersLock = NSLock()
    private var audioWaiters: [UUID: AudioWaiter] = [:]

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    var isActivated: Bool {
        session.activationState == .activated
    }

    /// Meaningful only while the watch app is on screen.
    var isReachable: Bool {
        isActivated && session.isReachable
    }

    /// Take IDs whose transfer the system still holds.
    var outstandingTakeIDs: Set<UUID> {
        Set(session.outstandingFileTransfers.compactMap { WatchWire.take(fromMetadata: $0.file.metadata)?.id })
    }

    /// Queues the file with the system. False when the session isn't active.
    func send(_ take: WatchTake, audioURL: URL) -> Bool {
        guard isActivated else { return false }
        session.transferFile(audioURL, metadata: WatchWire.metadata(for: take))
        return true
    }

    /// Wakes the phone app so a queued transfer is delivered now rather than
    /// at its next launch.
    func wake(_ id: UUID) {
        guard isReachable else { return }
        session.sendMessage([WatchWire.wakeKey: id.uuidString], replyHandler: nil, errorHandler: nil)
    }

    /// Asks the phone, which wakes in the background if it must, for a fresh
    /// snapshot. Out of reach this does nothing: the held snapshot stays.
    func requestSnapshot() {
        guard isReachable else { return }
        session.sendMessage(
            [WatchWire.snapshotRequestKey: true],
            replyHandler: { [weak self] reply in
                guard let snapshot = WatchWire.snapshot(from: reply) else { return }
                Task { @MainActor in self?.onSnapshot?(snapshot) }
            },
            errorHandler: { error in
                let error = error as NSError
                log.error("Snapshot request failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            }
        )
    }

    /// Asks the phone for one thought's audio and waits for the file:
    /// `.phoneAway` at once when it can't be reached; `.failed` on a refusal,
    /// an error, or no file within `audioFetchTimeout`.
    func fetchAudio(_ id: UUID) async -> AudioFetch {
        guard isReachable else { return .phoneAway }
        let token = UUID()
        return await withCheckedContinuation { continuation in
            waitersLock.lock()
            let replaced = audioWaiters.updateValue(AudioWaiter(token: token, continuation: continuation), forKey: id)
            waitersLock.unlock()
            replaced?.continuation.resume(returning: .failed)
            session.sendMessage(
                [WatchWire.audioRequestKey: id.uuidString],
                replyHandler: { [weak self] reply in
                    guard reply[WatchWire.audioOKKey] as? Bool != true else { return }
                    self?.finishAudio(id, .failed, token: token)
                },
                errorHandler: { [weak self] error in
                    let error = error as NSError
                    log.error("Audio request for \(id.uuidString, privacy: .public) failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
                    self?.finishAudio(id, .failed, token: token)
                }
            )
            Task { [weak self] in
                try? await Task.sleep(for: Self.audioFetchTimeout)
                self?.finishAudio(id, .failed, token: token)
            }
        }
    }

    /// Today's thought was opened on the wrist. Queued by the system, so it
    /// reaches the phone even when the phone is away now.
    func sendMet(_ id: UUID) {
        guard isActivated else { return }
        session.transferUserInfo([WatchWire.metKey: id.uuidString])
    }

    /// Answers the fetch waiting on `id`, once. `token` ties a refusal or a
    /// timeout to the fetch that sent it, so a late one never fails a newer
    /// fetch; a file answers whichever fetch waits, and a file nobody waits
    /// for is deleted.
    private func finishAudio(_ id: UUID, _ result: AudioFetch, token: UUID? = nil) {
        waitersLock.lock()
        let waiter = audioWaiters[id].flatMap { token == nil || $0.token == token ? $0 : nil }
        if waiter != nil { audioWaiters[id] = nil }
        waitersLock.unlock()
        guard let waiter else {
            if case .file(let url) = result { try? FileManager.default.removeItem(at: url) }
            return
        }
        waiter.continuation.resume(returning: result)
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let context = session.receivedApplicationContext
        let confirmations = WatchWire.confirmations(fromContext: context)
        let snapshot = WatchWire.snapshot(from: context)
        Task { @MainActor in
            self.onActivated?()
            if !confirmations.isEmpty { self.onConfirmations?(confirmations) }
            if let snapshot { self.onSnapshot?(snapshot) }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let confirmations = WatchWire.confirmations(fromContext: applicationContext)
        let snapshot = WatchWire.snapshot(from: applicationContext)
        Task { @MainActor in
            self.onConfirmations?(confirmations)
            if let snapshot { self.onSnapshot?(snapshot) }
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard let id = WatchWire.take(fromMetadata: fileTransfer.file.metadata)?.id else { return }
        if let error = error as NSError? {
            log.error("Transfer of take \(id.uuidString, privacy: .public) finished with an error: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        }
        let delivered = error == nil
        Task { @MainActor in self.onTransferFinished?(id, delivered) }
    }

    /// Audio the phone sent for replay. Moved before returning: the system
    /// deletes the file afterwards.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let raw = file.metadata?[WatchWire.audioForKey] as? String, let id = UUID(uuidString: raw) else { return }
        let destination = PlaybackCache.url(for: id)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: file.fileURL, to: destination)
        } catch {
            let error = error as NSError
            log.error("Couldn't keep audio for \(id.uuidString, privacy: .public): \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            finishAudio(id, .failed)
            return
        }
        finishAudio(id, .file(destination))
    }
}

extension PhoneLink: PhoneLinking {}
```

- [ ] **Step 6: Pass a library in `OryneWatchApp`**

In `OryneWatch/OryneWatchApp.swift`, replace the `TakeSync` construction with:

```swift
        let library = WristLibrary()
        let sync = TakeSync(queue: queue, link: PhoneLink(), cloud: cloud, library: library) { date in
```

(Task 10 replaces this file whole; the library is held there.)

- [ ] **Step 7: Run tests and the watch build**

Run: `xcodegen generate && xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SharedTests/TakeSyncTests`
Expected: `** TEST SUCCEEDED **`.
Run: `xcodebuild -scheme OryneWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit (only if Malik has asked for commits)**

```bash
git add OryneWatch/Services/PlaybackCache.swift OryneWatch/Services/TakeSync.swift OryneWatch/Services/PhoneLink.swift OryneWatch/OryneWatchApp.swift SharedTests/TakeSyncTests.swift Oryne.xcodeproj
git commit -m "Watch: receive and ask for the wrist snapshot; fetch audio from the phone"
```

---

### Task 8: The phone publishes the snapshot and answers the watch

**Files:**
- Create: `Oryne/Services/WristSnapshotPublisher.swift`
- Modify: `Oryne/Services/WatchLink.swift` (full replacement below)
- Modify: `Oryne/Services/WatchBridge.swift` (`start`, `linkActivated`, a stored `publisher`)

**Interfaces:**
- Consumes: `WristSnapshotBuilder.build` and `Source(node:placeholders:)` (Tasks 2 and 3), `WatchWire` keys and `context(for:snapshot:)` (Task 1), `ImportLedger.load(from:)` and `.entries`, `Resurfacing.pick(from:now:)` and `.markMet(_:context:)`, `VoiceUnderstanding.whisperPlaceholders`.
- Produces:
  - `WristSnapshotPublisher(context:defaults:link:)` with `start()`, `schedule()`, `@discardableResult publish(now: Date = .now) -> WristSnapshot`, `audio(for: UUID) -> Data?`, `markMet(_ id: UUID)`.
  - `WatchLink.send(_ snapshot: WristSnapshot)`, `WatchLink.snapshotProvider`, `.audioProvider`, `.onMet`.

No unit tests here: SwiftData and WatchConnectivity glue, covered by the device checklist (Task 11). The rules it calls are tested in Tasks 2 and 3.

- [ ] **Step 1: Replace `WatchLink`**

`Oryne/Services/WatchLink.swift`, whole file:

```swift
import Foundation
import WatchConnectivity
import os

/// Failures only, and never user content: a take ID at most.
private let log = Logger(subsystem: "com.inspireocean.app", category: "watch")

/// The phone's end of WatchConnectivity. Receives wrist takes as files,
/// answers the watch's wake ping, tells the watch which takes are in the
/// Ocean and what its thoughts are now (application context), answers its
/// requests for a fresh snapshot or a thought's audio, and hears when
/// today's thought was met on the wrist. Delegate callbacks arrive on a
/// background queue; anything that touches the store hops to the main actor.
final class WatchLink: NSObject, WCSessionDelegate {
    private let folder: WatchInboxFolder

    /// A take landed in the inbox folder, or the watch pinged: import now.
    var onArrival: (() -> Void)?
    /// Activation finished; `isPaired` is now meaningful.
    var onActivated: ((_ isPaired: Bool) -> Void)?
    /// A fresh snapshot, for a watch that asked.
    var snapshotProvider: (@MainActor () -> WristSnapshot?)?
    /// One thought's recording, for the watch to replay.
    var audioProvider: (@MainActor (UUID) -> Data?)?
    /// Today's thought was opened on the wrist.
    var onMet: (@MainActor (UUID) -> Void)?

    /// The last of each sent. An application context update replaces the
    /// whole dictionary, so both always go together.
    private var confirmations: [WatchConfirmation] = []
    private var snapshot: WristSnapshot?

    init(folder: WatchInboxFolder) {
        self.folder = folder
    }

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    var isSupported: Bool { WCSession.isSupported() }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// The latest confirmations. A no-op until a watch with Oryne installed
    /// is paired.
    func send(_ confirmations: [WatchConfirmation]) {
        self.confirmations = confirmations
        pushContext()
    }

    /// The latest wrist snapshot, delivered by the system as soon as the
    /// watch is in range.
    func send(_ snapshot: WristSnapshot) {
        self.snapshot = snapshot
        pushContext()
    }

    private func pushContext() {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled
        else { return }
        do {
            try session.updateApplicationContext(WatchWire.context(for: confirmations, snapshot: snapshot))
        } catch {
            let error = error as NSError
            log.error("updateApplicationContext failed (\(self.confirmations.count, privacy: .public) confirmations): \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        }
    }

    /// Writes the recording to a temporary file and hands it to the system;
    /// the file goes once the transfer finishes. False when there's nothing
    /// to send.
    @MainActor
    private func sendAudio(_ id: UUID) -> Bool {
        guard let session, session.activationState == .activated,
              let data = audioProvider?(id), !data.isEmpty
        else { return false }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wrist-audio-\(id.uuidString).m4a")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            let error = error as NSError
            log.error("Couldn't stage audio for \(id.uuidString, privacy: .public): \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            return false
        }
        session.transferFile(url, metadata: [WatchWire.audioForKey: id.uuidString])
        return true
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error = error as NSError? {
            log.error("Activation finished with an error (state \(activationState.rawValue, privacy: .public)): \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        }
        onActivated?(activationState == .activated && session.isPaired)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched watches: activate again for the new one.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let take = WatchWire.take(fromMetadata: file.metadata) else {
            log.error("A received file had undecodable metadata; the system deletes it")
            return
        }
        // Move before returning: the system deletes the file afterwards.
        do {
            try folder.accept(take, movingAudioFrom: file.fileURL)
        } catch {
            // The watch keeps the take until it is confirmed: it falls back to iCloud.
            let error = error as NSError
            log.error("Couldn't accept take \(take.id.uuidString, privacy: .public): \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            return
        }
        onArrival?()
    }

    /// Audio sent for replay: its temporary file goes once the system is done.
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard let raw = fileTransfer.file.metadata?[WatchWire.audioForKey] as? String else { return }
        if let error = error as NSError? {
            log.error("Audio for \(raw, privacy: .public) finished with an error: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        }
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }

    /// The wake ping. Being launched to receive it is the point: once the
    /// session is active, the queued file transfer is delivered.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        onArrival?()
    }

    /// The watch's requests that wait for an answer: a fresh snapshot, or a
    /// thought's audio (the reply says whether a file is on its way).
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if message[WatchWire.snapshotRequestKey] != nil {
            Task { @MainActor in
                let data = self.snapshotProvider?().flatMap(WatchWire.encode)
                replyHandler(data.map { [WatchWire.wristKey: $0] } ?? [:])
            }
        } else if let raw = message[WatchWire.audioRequestKey] as? String, let id = UUID(uuidString: raw) {
            Task { @MainActor in
                replyHandler([WatchWire.audioOKKey: self.sendAudio(id)])
            }
        } else {
            replyHandler([:])
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let raw = userInfo[WatchWire.metKey] as? String, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in self.onMet?(id) }
    }
}
```

- [ ] **Step 2: Create the publisher**

`Oryne/Services/WristSnapshotPublisher.swift`:

```swift
import Foundation
import SwiftData
import CoreData

/// Keeps the wrist's snapshot current (watch redesign spec §2): rebuilt
/// after every save to the store and every change CloudKit brings in,
/// coalesced, and sent only when it differs from the last one sent. The
/// watch also asks for one each time it comes on screen (`publish()`), which
/// is what brings Today on a day the phone app wasn't opened.
@MainActor
final class WristSnapshotPublisher {
    static let coalescing: Duration = .seconds(2)

    private let context: ModelContext
    private let defaults: UserDefaults
    private let link: WatchLink
    private var lastSent: WristSnapshot?
    private var pending: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(context: ModelContext, defaults: UserDefaults, link: WatchLink) {
        self.context = context
        self.defaults = defaults
        self.link = link
    }

    /// Listens for local saves (a new thought, an edit, a delete, a title or
    /// summary landing) and for CloudKit bringing in another device's change.
    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [ModelContext.didSave, Notification.Name.NSPersistentStoreRemoteChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        }
    }

    /// One publish for a burst of saves.
    func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.coalescing)
            guard !Task.isCancelled else { return }
            self?.publish()
        }
    }

    /// Builds the snapshot now, and sends it when it differs from the last
    /// one sent. Returned for a watch that asked.
    @discardableResult
    func publish(now: Date = .now) -> WristSnapshot {
        let snapshot = build(now: now)
        if !snapshot.hasSameContent(as: lastSent) {
            link.send(snapshot)
            lastSent = snapshot
        }
        return snapshot
    }

    func audio(for id: UUID) -> Data? {
        node(id)?.audioData
    }

    /// Today's thought was opened on the wrist: met, as an open on the phone
    /// is. The save publishes a fresh snapshot.
    func markMet(_ id: UUID) {
        guard let node = node(id) else { return }
        Resurfacing.markMet(node, context: context)
    }

    /// Only the newest wrist takes become sources: reading `audioData` loads
    /// the recording, so the rest are counted by ID alone.
    private func build(now: Date) -> WristSnapshot {
        let ids = Array(ImportLedger.load(from: defaults).entries.keys)
        let placeholders = VoiceUnderstanding.whisperPlaceholders
        let wrist = (try? context.fetch(FetchDescriptor<Node>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        let newest = wrist
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(WristSnapshotBuilder.recentLimit)
            .map { WristSnapshotBuilder.Source(node: $0, placeholders: placeholders) }
        let everything = (try? context.fetch(FetchDescriptor<Node>())) ?? []
        let today = Resurfacing.pick(from: everything, now: now)
        return WristSnapshotBuilder.build(
            ledgerIDs: Set(ids),
            liveIDs: Set(wrist.map(\.id)),
            recent: Array(newest),
            today: today.map { WristSnapshotBuilder.Source(node: $0, placeholders: placeholders) },
            now: now
        )
    }

    private func node(_ id: UUID) -> Node? {
        try? context.fetch(FetchDescriptor<Node>(predicate: #Predicate { $0.id == id })).first
    }
}
```

- [ ] **Step 3: Wire it into `WatchBridge`**

In `Oryne/Services/WatchBridge.swift`, add the stored property under `inboxFolder`:

```swift
    private var publisher: WristSnapshotPublisher?
```

In `start(context:ai:)`, insert after the `link.onActivated = { ... }` block and before `self.importer = importer`:

```swift
        let publisher = WristSnapshotPublisher(context: context, defaults: FastCapturePreferences.defaults, link: link)
        link.snapshotProvider = { [weak publisher] in publisher?.publish() }
        link.audioProvider = { [weak publisher] id in publisher?.audio(for: id) }
        link.onMet = { [weak publisher] id in publisher?.markMet(id) }
        self.publisher = publisher
        publisher.start()
```

In `linkActivated(isPaired:)`, replace

```swift
        // A watch that missed an update catches up on activation.
        link?.send(importer.recentConfirmations)
```

with

```swift
        // A watch that missed an update catches up on activation.
        link?.send(importer.recentConfirmations)
        publisher?.publish()
```

- [ ] **Step 4: Build and test the phone**

Run: `xcodegen generate && xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: `** BUILD SUCCEEDED **`.
Run: `xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit (only if Malik has asked for commits)**

```bash
git add Oryne/Services/WristSnapshotPublisher.swift Oryne/Services/WatchLink.swift Oryne/Services/WatchBridge.swift Oryne.xcodeproj
git commit -m "Phone: keep the wrist snapshot current and answer the watch's requests"
```

---

### Task 9: Playback, and capture always wins

**Files:**
- Create: `OryneWatch/Services/WatchPlayer.swift`
- Modify: `OryneWatch/Features/Capture/WatchCaptureModel.swift` (init takes a player; `begin` stops it; `sceneBecameActive` asks for a snapshot; `lastTitle` goes)
- Modify: `OryneWatch/Features/Capture/WatchCaptureView.swift:42-50` (the "Last:" line goes)
- Modify: `Shared/Watch/WatchStatusLine.swift:24-32` (`lastTitle` goes)
- Modify: `SharedTests/WatchStatusLineTests.swift:43-71` (its three `lastTitle` tests go)
- Modify: `OryneWatch/OryneWatchApp.swift` (pass a player)

**Interfaces:**
- Consumes: `TakeSync.requestSnapshot()` (Task 7).
- Produces:
  - `@MainActor @Observable final class WatchPlayer` with `state: WatchPlayer.State` (`.idle`, `.playing`, `.paused`), `currentID: UUID?`, `elapsed: TimeInterval`, `duration: TimeInterval`, `@discardableResult play(_ url: URL, id: UUID) -> Bool`, `pause()`, `stop()`.
  - `WatchCaptureModel.init(queue:sync:player:)`, `WatchCaptureModel.player`.

- [ ] **Step 1: Create the player**

`OryneWatch/Services/WatchPlayer.swift`:

```swift
import Foundation
import AVFoundation
import Observation

/// Replays one recording at a time on the wrist: a take's own file, or
/// audio fetched from the phone. Playback is for checking the words
/// (PHILOSOPHY §2): play, pause, and nothing to manage. Capture always wins:
/// a recording stops it first (`WatchCaptureModel.begin`).
@MainActor
@Observable
final class WatchPlayer {
    enum State: Equatable {
        case idle
        case playing
        case paused
    }

    private(set) var state: State = .idle
    /// The thought being played or paused.
    private(set) var currentID: UUID?
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// Resumes `id` when it is the paused one, else plays `url` from the
    /// start. False when the file doesn't play.
    @discardableResult
    func play(_ url: URL, id: UUID) -> Bool {
        if currentID == id, state == .paused, let player {
            player.play()
            state = .playing
            startTicking()
            return true
        }
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            self.player = player
            guard player.play() else {
                stop()
                return false
            }
            currentID = id
            duration = player.duration
            elapsed = 0
            state = .playing
            startTicking()
            return true
        } catch {
            stop()
            return false
        }
    }

    func pause() {
        guard state == .playing else { return }
        player?.pause()
        ticker?.cancel()
        state = .paused
    }

    /// Releases the audio session only when this player held it, so a stop
    /// arriving after a recording began (the thought closing as Capture
    /// returns) never takes the session from the recorder.
    func stop() {
        let held = player != nil
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        currentID = nil
        elapsed = 0
        duration = 0
        state = .idle
        if held {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Reads the position for the toolbar's time, and ends playback when the
    /// file runs out.
    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let player = self.player else { return }
                if player.isPlaying {
                    self.elapsed = player.currentTime
                } else if self.state == .playing {
                    self.stop()
                    return
                }
            }
        }
    }
}
```

- [ ] **Step 2: The capture model takes the player**

In `OryneWatch/Features/Capture/WatchCaptureModel.swift`:

Add under `let queue: TakeQueue`:

```swift
    let player: WatchPlayer
```

Replace `init(queue:sync:)` with:

```swift
    init(queue: TakeQueue, sync: TakeSync, player: WatchPlayer) {
        self.queue = queue
        self.sync = sync
        self.player = player
        recorder.onEndedBySystem = { [weak self] in
            Task { await self?.finish() }
        }
    }
```

Delete the `lastTitle` property (lines 52-54).

In `begin()`, insert after the `guard stage != .starting, stage != .recording else { return }` line:

```swift
        // Capture wins (PHILOSOPHY §1): a replay stops before the mic opens.
        player.stop()
```

In `sceneBecameActive()`, replace the final `await sync.flush()` with:

```swift
        sync.requestSnapshot()
        await sync.flush()
```

- [ ] **Step 3: The "Last:" line goes**

In `OryneWatch/Features/Capture/WatchCaptureView.swift`, delete this block from `idle`:

```swift
            if let title = model.lastTitle {
                // A thought's title is New York on the phone: the meta
                // line's size in the serif, the wrist's own role.
                Text("Last: \(title)")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
```

In `Shared/Watch/WatchStatusLine.swift`, delete `lastTitle(from:)` and its doc comment. In `SharedTests/WatchStatusLineTests.swift`, delete `test_lastTitle_isTheNewestConfirmedTakesTitle`, `test_lastTitle_isNilWhileTheNewestConfirmedIsUnnamed`, and `test_lastTitle_ignoresUnconfirmedTakes`.

- [ ] **Step 4: Pass a player in `OryneWatchApp`**

In `OryneWatch/OryneWatchApp.swift`, replace `let model = WatchCaptureModel(queue: queue, sync: sync)` with:

```swift
        let model = WatchCaptureModel(queue: queue, sync: sync, player: WatchPlayer())
```

- [ ] **Step 5: Build and test**

Run: `xcodegen generate && xcodebuild -scheme OryneWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' build`
Expected: `** BUILD SUCCEEDED **`.
Run: `xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SharedTests/WatchStatusLineTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit (only if Malik has asked for commits)**

```bash
git add OryneWatch/Services/WatchPlayer.swift OryneWatch/Features/Capture OryneWatch/OryneWatchApp.swift Shared/Watch/WatchStatusLine.swift SharedTests/WatchStatusLineTests.swift Oryne.xcodeproj
git commit -m "Watch: a player for replay; recording stops it; the Last line leaves Capture"
```

---

### Task 10: The pages, the thought, and the copy

**Files:**
- Create: `OryneWatch/Features/WatchRootView.swift`
- Create: `OryneWatch/Features/Today/WatchTodayView.swift`
- Create: `OryneWatch/Features/Recent/WatchRecentView.swift`
- Create: `OryneWatch/Features/Thought/WatchThoughtModel.swift`
- Create: `OryneWatch/Features/Thought/WatchThoughtView.swift`
- Modify: `OryneWatch/OryneWatchApp.swift` (full replacement below)
- Modify: `OryneWatch/Features/Capture/WatchCaptureModel.swift` (`applyDemoEnvironment(library:)`)
- Modify: `OryneWatch/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `WristRow`, `WristRecent` (Task 5), `WristLibrary` (Task 6), `PhoneLink.fetchAudio/sendMet`, `PlaybackCache` (Task 7), `WatchPlayer`, `WatchCaptureModel.player` (Task 9), `TakeQueue.hasAudio/audioURL` (Task 4).
- Produces: the UI; DEBUG seams `ORYNE_WATCH_DEMO=recent|today`, `ORYNE_WATCH_PAGE=today|recent|thought`, `ORYNE_WATCH_AUDIO=fetching|phoneAway|fetchFailed`.

The Recent page, like Today, is absent rather than empty when there is nothing to list (a fresh install shows Capture alone, as today).

- [ ] **Step 1: The thought's model**

`OryneWatch/Features/Thought/WatchThoughtModel.swift`:

```swift
import Foundation
import Observation

/// One thought on the wrist: its reading, and its recording from the watch
/// or fetched from the phone. A notice about the audio stays until tapped
/// (PHILOSOPHY §5: failure never fades on its own).
@MainActor
@Observable
final class WatchThoughtModel {
    enum Audio: Equatable {
        /// Nothing to play: no control.
        case none
        case ready
        case fetching
        case phoneAway
        case failed
    }

    let row: WristRow
    let player: WatchPlayer
    private(set) var audio: Audio
    @ObservationIgnored private let queue: TakeQueue
    @ObservationIgnored private let link: PhoneLink
    @ObservationIgnored private var fetched: URL?
    @ObservationIgnored private var metSent = false

    init(row: WristRow, queue: TakeQueue, player: WatchPlayer, link: PhoneLink) {
        self.row = row
        self.queue = queue
        self.player = player
        self.link = link
        audio = row.audio == .none ? .none : .ready
        #if DEBUG
        // Screenshot seam: `ORYNE_WATCH_AUDIO=fetching|phoneAway|fetchFailed`.
        switch ProcessInfo.processInfo.environment["ORYNE_WATCH_AUDIO"] {
        case "fetching": audio = .fetching
        case "phoneAway": audio = .phoneAway
        case "fetchFailed": audio = .failed
        default: break
        }
        #endif
    }

    var isPlaying: Bool {
        player.currentID == row.id && player.state == .playing
    }

    var isPlayerOnThis: Bool {
        player.currentID == row.id
    }

    /// Opening Today's thought tells the phone it was met, once.
    func appeared() {
        guard row.isToday, !metSent else { return }
        metSent = true
        link.sendMet(row.id)
    }

    func togglePlay() async {
        if isPlaying {
            player.pause()
            return
        }
        switch row.audio {
        case .none:
            return
        case .watch:
            if !player.play(queue.audioURL(for: row.id), id: row.id) { audio = .failed }
        case .phone:
            await playFromPhone()
        }
    }

    func dismissNotice() {
        if audio == .phoneAway || audio == .failed { audio = .ready }
    }

    /// The wrist went down: playback stops; the fetched copy stays for this visit.
    func sceneWentInactive() {
        if isPlayerOnThis { player.stop() }
    }

    /// Leaving the thought: playback stops and fetched audio goes.
    func leave() {
        if isPlayerOnThis { player.stop() }
        if fetched != nil {
            PlaybackCache.remove(row.id)
            fetched = nil
        }
    }

    private func playFromPhone() async {
        if let fetched {
            if !player.play(fetched, id: row.id) { audio = .failed }
            return
        }
        guard audio != .fetching else { return }
        audio = .fetching
        switch await link.fetchAudio(row.id) {
        case .file(let url):
            fetched = url
            audio = .ready
            if !player.play(url, id: row.id) { audio = .failed }
        case .phoneAway:
            audio = .phoneAway
        case .failed:
            audio = .failed
        }
    }
}
```

- [ ] **Step 2: The thought's screen**

`OryneWatch/Features/Thought/WatchThoughtView.swift`:

```swift
import SwiftUI

/// One thought on the wrist (watch redesign spec §1): its name, a short
/// reading, and its recording. The Crown scrolls; play sits in the bottom
/// toolbar while the words stay on screen. A machine summary wears the
/// phone's "Summary" label (PHILOSOPHY §3).
struct WatchThoughtView: View {
    @State private var model: WatchThoughtModel
    @Environment(\.scenePhase) private var scenePhase

    init(model: WatchThoughtModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OceanSpacing.gap) {
                if let title = model.row.title {
                    Text(title)
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(OceanTheme.foam)
                }
                notice
                reading
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
        .background(OceanTheme.abyss.ignoresSafeArea())
        .toolbar {
            if model.audio != .none {
                ToolbarItemGroup(placement: .bottomBar) {
                    playControl
                }
            }
        }
        .onAppear { model.appeared() }
        .onDisappear { model.leave() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.sceneWentInactive() }
        }
    }

    @ViewBuilder private var reading: some View {
        if let reading = model.row.reading {
            if model.row.readingIsSummary {
                Label("Summary", systemImage: "sparkles")
                    .font(OceanType.eyebrow)
                    .foregroundStyle(OceanTheme.mist)
            }
            Text(reading)
                .font(OceanType.body)
                .foregroundStyle(OceanTheme.text)
            if model.row.continues {
                Text("Continues on iPhone")
                    .font(OceanType.note)
                    .foregroundStyle(OceanTheme.mist)
            }
        } else if model.row.isVoice {
            Text("Not transcribed yet")
                .font(OceanType.meta)
                .foregroundStyle(OceanTheme.mist)
        }
    }

    /// Stays until tapped.
    @ViewBuilder private var notice: some View {
        switch model.audio {
        case .phoneAway: noticeButton(Text("Your iPhone isn't nearby"))
        case .failed: noticeButton(Text("Couldn't get the audio"))
        default: EmptyView()
        }
    }

    private func noticeButton(_ text: Text) -> some View {
        Button { model.dismissNotice() } label: {
            text
                .font(OceanType.meta)
                .foregroundStyle(OceanTheme.foam)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var playControl: some View {
        if model.audio == .fetching {
            Text("Getting audio…")
                .font(OceanType.note)
                .foregroundStyle(OceanTheme.mist)
        } else {
            Button { Task { await model.togglePlay() } } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
            }
            .accessibilityLabel(model.isPlaying ? Text("Pause") : Text("Play"))
            if model.isPlayerOnThis {
                Text(verbatim: "\(Self.time(model.player.elapsed)) / \(Self.time(model.player.duration))")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(OceanTheme.mist)
            }
        }
    }

    private static func time(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
```

- [ ] **Step 3: Today and Recent**

`OryneWatch/Features/Today/WatchTodayView.swift`:

```swift
import SwiftUI

/// Today's resurfaced thought (watch redesign spec §1): the same pick as the
/// phone and the widget, its name and the first lines of its reading. Tap
/// opens it, text first.
struct WatchTodayView: View {
    let row: WristRow

    var body: some View {
        NavigationLink(value: row) {
            VStack(alignment: .leading, spacing: OceanSpacing.gap) {
                Text("Today")
                    .font(OceanType.eyebrow)
                    .foregroundStyle(OceanTheme.mist)
                if let title = row.title {
                    Text(title)
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(OceanTheme.foam)
                        .lineLimit(3)
                }
                if let reading = row.reading {
                    Text(reading)
                        .font(OceanType.meta)
                        .foregroundStyle(OceanTheme.text)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .background(OceanTheme.abyss.ignoresSafeArea())
    }
}
```

`OryneWatch/Features/Recent/WatchRecentView.swift`:

```swift
import SwiftUI

/// The wrist takes, newest first (watch redesign spec §1). The Crown scrolls
/// the list; a row opens its thought.
struct WatchRecentView: View {
    let rows: [WristRow]

    var body: some View {
        List(rows) { row in
            NavigationLink(value: row) {
                RecentRow(row: row)
            }
        }
        .navigationTitle(Text("Recent"))
    }
}

/// A take's name (or the time it was caught, until the phone names it),
/// when and how long, and whether it still waits for the phone.
private struct RecentRow: View {
    let row: WristRow

    var body: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.tight) {
            Group {
                if let title = row.title {
                    Text(title)
                } else {
                    Text(row.caughtAt, style: .time)
                }
            }
            // The wrist's title role: the meta line's size in the serif.
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(OceanTheme.foam)
            .lineLimit(2)
            HStack(spacing: OceanSpacing.tight) {
                Text(row.caughtAt, format: .relative(presentation: .named))
                if let duration = row.duration {
                    Text(verbatim: String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60))
                }
            }
            .font(OceanType.note)
            .foregroundStyle(OceanTheme.mist)
            if row.isWaiting {
                Text("Waiting for iPhone")
                    .font(OceanType.note)
                    .foregroundStyle(OceanTheme.mist)
            }
        }
    }
}
```

- [ ] **Step 4: The pages**

`OryneWatch/Features/WatchRootView.swift`:

```swift
import SwiftUI

/// The wrist's vertical pages (watch redesign spec §1): Capture, where the
/// app always opens; Today, when a thought is rising today; and Recent. The
/// Crown or a swipe moves between them; a thought opens on top, and the
/// system's edge swipe comes back. Any recording entry (the Action Button,
/// the complication, Siri) brings Capture back first.
struct WatchRootView: View {
    let model: WatchCaptureModel
    let library: WristLibrary
    let link: PhoneLink

    private enum Page: Hashable {
        case capture, today, recent
    }

    @State private var page: Page = .capture
    @State private var path: [WristRow] = []

    var body: some View {
        let rows = recentRows
        let today = todayRow
        NavigationStack(path: $path) {
            TabView(selection: $page) {
                WatchCaptureView(model: model).tag(Page.capture)
                if let today {
                    WatchTodayView(row: today).tag(Page.today)
                }
                if !rows.isEmpty {
                    WatchRecentView(rows: rows).tag(Page.recent)
                }
            }
            .tabViewStyle(.verticalPage)
            .navigationDestination(for: WristRow.self) { row in
                WatchThoughtView(model: WatchThoughtModel(row: row, queue: model.queue, player: model.player, link: link))
            }
        }
        .onChange(of: model.stage) { _, stage in
            guard stage == .starting || stage == .recording else { return }
            path = []
            page = .capture
        }
        #if DEBUG
        .onAppear(perform: applyDemoPage)
        #endif
    }

    private var recentRows: [WristRow] {
        WristRecent.rows(queue: model.queue.state, snapshot: library.snapshot) { model.queue.hasAudio($0) }
    }

    private var todayRow: WristRow? {
        WristRecent.today(snapshot: library.snapshot, queue: model.queue.state, now: .now) { model.queue.hasAudio($0) }
    }

    #if DEBUG
    /// Screenshot seam: `ORYNE_WATCH_PAGE=today|recent|thought` opens that
    /// page; `thought` opens Today's thought, else the newest take.
    private func applyDemoPage() {
        switch ProcessInfo.processInfo.environment["ORYNE_WATCH_PAGE"] {
        case "today": page = .today
        case "recent": page = .recent
        case "thought": if let row = todayRow ?? recentRows.first { path = [row] }
        default: break
        }
    }
    #endif
}
```

- [ ] **Step 5: The app**

`OryneWatch/OryneWatchApp.swift`, whole file:

```swift
import SwiftUI
import AppIntents
import WatchKit

@main
struct OryneWatchApp: App {
    private let model: WatchCaptureModel
    private let library: WristLibrary
    private let link: PhoneLink

    init() {
        // Fetched audio is for one listen; anything left from the last run goes.
        PlaybackCache.clear()
        let queue = TakeQueue()
        let cloud = CloudInbox.makeIfAvailable()
        let link = PhoneLink()
        let library = WristLibrary()
        let sync = TakeSync(queue: queue, link: link, cloud: cloud, library: library) { date in
            WKApplication.shared().scheduleBackgroundRefresh(
                withPreferredDate: date,
                userInfo: TakeSync.refreshIdentifier as NSString
            ) { _ in }
        }
        let model = WatchCaptureModel(queue: queue, sync: sync, player: WatchPlayer())
        self.model = model
        self.library = library
        self.link = link
        // The Action Button and Siri reach the same model the screen shows.
        AppDependencyManager.shared.add { model }
        sync.start()
        #if DEBUG
        model.applyDemoEnvironment(library: library)
        WatchSelfTest.runIfRequested(model: model, cloudAvailable: cloud != nil)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model, library: library, link: link)
                .onOpenURL { url in
                    // The complication: same rule as the Action Button.
                    guard WatchDeepLink.isCatch(url) else { return }
                    Task { await model.toggle() }
                }
        }
        .backgroundTask(.appRefresh(TakeSync.refreshIdentifier)) { [model] in
            await model.backgroundRefresh()
        }
    }
}
```

- [ ] **Step 6: Demo data for the new pages**

In `OryneWatch/Features/Capture/WatchCaptureModel.swift`, replace the `#if DEBUG` block holding `applyDemoEnvironment()` with:

```swift
    #if DEBUG
    /// Screenshot seams (`SIMCTL_CHILD_` prefix on `simctl launch`):
    /// `ORYNE_WATCH_DEMO=empty|waiting|onItsWay|inOcean|recent|today` shows a
    /// sample queue (`recent` and `today` add a sample snapshot);
    /// `ORYNE_WATCH_STAGE=recording|caught|denied|failed|nothing` shows that screen;
    /// `ORYNE_WATCH_DEMO_TITLE` names the sample's last whisper.
    func applyDemoEnvironment(library: WristLibrary) {
        let env = ProcessInfo.processInfo.environment
        let now = Date()
        func take(_ secondsAgo: TimeInterval) -> WatchTake {
            WatchTake(id: UUID(), createdAt: now.addingTimeInterval(-secondsAgo), duration: 8)
        }
        var demo = TakeQueueState()
        let named = take(600)
        let title = env["ORYNE_WATCH_DEMO_TITLE"] ?? "Lighthouse café"
        demo.add(named, phoneReachableAtStop: true)
        demo.apply([WatchConfirmation(id: named.id, title: title)])
        switch env["ORYNE_WATCH_DEMO"] {
        case "empty":
            queue.showDemo(TakeQueueState())
        case "waiting":
            demo.add(take(60), phoneReachableAtStop: false)
            demo.add(take(30), phoneReachableAtStop: false)
            queue.showDemo(demo)
        case "onItsWay":
            let clouded = take(60)
            demo.add(clouded, phoneReachableAtStop: false)
            demo.markInICloud(clouded.id)
            queue.showDemo(demo)
        case "inOcean":
            queue.showDemo(demo)
        case "recent", "today":
            demo.add(take(60), phoneReachableAtStop: false)
            queue.showDemo(demo)
            library.showDemo(Self.demoSnapshot(named: named, title: title, now: now, withToday: env["ORYNE_WATCH_DEMO"] == "today"))
        default:
            break
        }
        switch env["ORYNE_WATCH_STAGE"] {
        case "recording": Task { await begin() }
        case "caught": demoStageAwaitingActive = .caught(UUID())
        case "denied": stage = .denied
        case "failed": stage = .failed
        case "nothing": stage = .nothingCaught
        default: break
        }
    }

    private static func demoSnapshot(named: WatchTake, title: String, now: Date, withToday: Bool) -> WristSnapshot {
        var whisper = WristThought(id: named.id, title: title, createdAt: named.createdAt)
        whisper.reading = "Warm light on the counter at closing time, the menu chalked in two languages. A room that tells you to stay."
        whisper.readingIsSummary = true
        whisper.hasTranscript = true
        whisper.isVoice = true
        var today = WristThought(id: UUID(), title: "Warm to cool, not a filter", createdAt: now.addingTimeInterval(-40 * 86_400))
        today.reading = "Grade the photo by the time of day it was taken, not by a preset."
        return WristSnapshot(
            recent: [whisper], today: withToday ? today : nil, todayDay: withToday ? now : nil,
            deletedIDs: [], generatedAt: now
        )
    }
    #endif
```

- [ ] **Step 7: The copy**

Run from the worktree root:

```bash
python3 - <<'EOF'
import json
path = 'OryneWatch/Resources/Localizable.xcstrings'
with open(path) as f:
    catalog = json.load(f)
strings = catalog['strings']
strings.pop('Last: %@', None)
for key, zh in [
    ("Today", "今天"),
    ("Recent", "最近"),
    ("Summary", "摘要"),
    ("Waiting for iPhone", "在等 iPhone"),
    ("Not transcribed yet", "还未转写"),
    ("Continues on iPhone", "在 iPhone 上继续"),
    ("Play", "播放"),
    ("Pause", "暂停"),
    ("Getting audio…", "正在读回语音…"),
    ("Your iPhone isn't nearby", "iPhone 不在附近"),
    ("Couldn't get the audio", "语音读取失败"),
]:
    strings[key] = {"localizations": {"zh-Hans": {"stringUnit": {"state": "needs_review", "value": zh}}}}
with open(path, 'w') as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2, separators=(',', ' : '))
    f.write('\n')
EOF
git diff --stat OryneWatch/Resources/Localizable.xcstrings
```

Expected: the catalog changes; no other file does.

- [ ] **Step 8: Build everything**

Run: `xcodegen generate && xcodebuild -scheme OryneWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' build`
Expected: `** BUILD SUCCEEDED **`, and no new warnings about missing localizations.
Run: `xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 9: Look at every new screen in the simulator**

```bash
xcrun simctl boot "Apple Watch Series 11 (46mm)" || true
APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-watchsimulator/OryneWatch.app' -maxdepth 6 | head -1)
xcrun simctl install "Apple Watch Series 11 (46mm)" "$APP"
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")
shoot() {
  name=$1; shift
  xcrun simctl terminate "Apple Watch Series 11 (46mm)" "$BUNDLE" 2>/dev/null
  env "$@" xcrun simctl launch "Apple Watch Series 11 (46mm)" "$BUNDLE"
  sleep 3
  xcrun simctl io "Apple Watch Series 11 (46mm)" screenshot "/tmp/watch-$name.png"
}
shoot capture SIMCTL_CHILD_ORYNE_WATCH_DEMO=today
shoot today SIMCTL_CHILD_ORYNE_WATCH_DEMO=today SIMCTL_CHILD_ORYNE_WATCH_PAGE=today
shoot recent SIMCTL_CHILD_ORYNE_WATCH_DEMO=recent SIMCTL_CHILD_ORYNE_WATCH_PAGE=recent
shoot thought SIMCTL_CHILD_ORYNE_WATCH_DEMO=recent SIMCTL_CHILD_ORYNE_WATCH_PAGE=thought
shoot fetching SIMCTL_CHILD_ORYNE_WATCH_DEMO=today SIMCTL_CHILD_ORYNE_WATCH_PAGE=thought SIMCTL_CHILD_ORYNE_WATCH_AUDIO=fetching
shoot phoneAway SIMCTL_CHILD_ORYNE_WATCH_DEMO=today SIMCTL_CHILD_ORYNE_WATCH_PAGE=thought SIMCTL_CHILD_ORYNE_WATCH_AUDIO=phoneAway
shoot fetchFailed SIMCTL_CHILD_ORYNE_WATCH_DEMO=today SIMCTL_CHILD_ORYNE_WATCH_PAGE=thought SIMCTL_CHILD_ORYNE_WATCH_AUDIO=fetchFailed
```

Expected, checked by eye on each PNG:
- capture: the record disc and status line, no "Last:" line.
- today: "Today", "Warm to cool, not a filter" in the serif, two lines of reading.
- recent: "Lighthouse café" with a relative date and 0:08, and an untitled row showing a time and "Waiting for iPhone".
- thought: the title, "Summary" with sparkles, the reading, and a play button in the bottom toolbar. In the today variant, plain reading with no "Summary".
- fetching / phoneAway / fetchFailed: "Getting audio…" in the toolbar, or the notice under the title.
- Relaunch one with `SIMCTL_CHILD_AppleLanguages="(zh-Hans)"` and confirm the zh strings render.

- [ ] **Step 10: Commit (only if Malik has asked for commits)**

```bash
git add OryneWatch Oryne.xcodeproj
git commit -m "Watch: Today and Recent pages, a thought with its reading and replay"
```

---

### Task 11: Device checklist and the full gate

**Files:**
- Modify: `docs/HARDWARE_CHECKLIST.md` (append to `## Apple Watch`)

- [ ] **Step 1: Add the device checks**

Append under the last item of `## Apple Watch`:

```markdown
- [ ] **Live wrist snapshot** — with the phone near and both apps running,
  capture a thought on the phone, rename a wrist take, and delete another:
  within a few seconds the watch's Recent shows the new title and the
  deleted take is gone (its audio too). Record the latency.
- [ ] **Snapshot while away** — make the same changes with the watch out of
  range: they land on their own once the two are near again.
- [ ] **Today with the phone app closed** — on a day the phone app hasn't
  been opened, force quit it, raise the watch with the phone near: Today
  appears (the snapshot request wakes the phone). If it doesn't, record it
  (spec §8.2).
- [ ] **Another device's edit** — rename a wrist take on a Mac or iPad: it
  reaches the watch once the phone has synced it, with the phone app
  running, or at the next watch screen-on. Record whether the remote change
  notification fired in the background (spec §8.3).
- [ ] **Replay from the watch** — open a recent take, play: it plays at once
  through the watch speaker, and through AirPods when connected. Lower the
  wrist: it stops. If speaker playback is refused, record it (spec §8.1).
- [ ] **Replay from the phone** — open Today on a voice thought under 30
  days old, play: "Getting audio…", then it plays. With the phone in
  airplane mode: "Your iPhone isn't nearby", which stays until tapped.
- [ ] **Capture wins** — play a take, then press the Action Button: playback
  stops, the watch returns to Capture, and the take records cleanly.
- [ ] **Met on the wrist** — open Today on the watch with the phone away,
  then bring it back: the phone treats that thought as met (it doesn't rise
  again for two weeks).
```

- [ ] **Step 2: The full gate**

Run:

```bash
xcodegen generate
xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
xcodebuild -scheme OryneWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' build
```

Expected: `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Scope check**

Run: `git diff --stat main -- Oryne/DesignSystem project.yml`
Expected: no `Oryne/DesignSystem` changes; `project.yml` shows only the `WristLibrary.swift` registration and its comment.

Run: `git diff main -- OryneWatch/Features/Capture/WatchCaptureView.swift`
Expected: only the "Last:" block removed; the `.animation(OceanMotion.lift, …)` line untouched.

- [ ] **Step 4: Commit (only if Malik has asked for commits)**

```bash
git add docs/HARDWARE_CHECKLIST.md
git commit -m "Hardware checklist: the wrist snapshot, replay, and Today on the watch"
```
