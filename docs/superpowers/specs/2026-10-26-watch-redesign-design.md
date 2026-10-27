# Oryne Apple Watch Redesign: Today, Recent, and Replay — Design Spec

**Date:** 2026-10-26 · **Status:** approved section by section in brainstorming (2026-10-26); revised after review (summary-only text, live sync); awaiting review of this written spec
**Builds on:** [`2026-10-18-oryne-apple-watch-capture-design.md`](2026-10-18-oryne-apple-watch-capture-design.md) (the capture flow, queue, and sync paths, all unchanged unless named here)

## Goal

Let the wrist do two small things besides catching: show today's resurfaced
thought, and let the user glance back through recent wrist takes, reading a
short version of the words and hearing the recording. Capture stays where
the app opens, one gesture away from catching (PHILOSOPHY §1). The wrist
stays a glance, not a library: it holds only what the wrist caught plus the
one thought rising today (§6, §8), and only a short reading of each; the
full words live on the phone. Audio comes back so the words can be checked
and re-heard (§2), never to be managed.

## Decisions (from brainstorming, 2026-10-26)

| Decision | Choice |
|---|---|
| What the wrist lists | The last 20 wrist takes, plus today's resurfaced thought (the same pick as the phone and widget) |
| One thought on the wrist | Title and a short reading: the summary when the thought has one, labeled "Summary"; otherwise its own words up to 240 characters. Never the full text of a long thought (Malik, 2026-10-26) |
| Text and audio | The reading stays on screen; a play button in the bottom toolbar plays while the user keeps reading; the Crown scrolls |
| Navigation | Vertical pages: Capture → Today → Recent, by Crown or swipe. A thought is a pushed screen; the system edge swipe goes back. No custom edge entries (the left edge and top edge belong to watchOS) |
| Audio source | Both: wrist takes play from the watch's own copy; anything the watch lacks (Today, takes recorded before this update) is fetched from the phone on tap |
| Sync | Live while the phone is near: the phone sends on every change to the store, and the watch asks for a fresh copy each time it comes on screen (Malik, 2026-10-26) |
| "Last: title" on Capture | Removed; the newest take is one Crown turn away |
| Opening Today on the wrist | Counts as meeting it (`Resurfacing.markMet`), so it rests like it does on the phone |

### Amends the capture spec

The capture spec's §7 "Not in v1" listed "Playback or a list on the watch".
This spec brings both in, scoped as above. Everything else in that list
stays out: typing or dictation on the watch, transcription on the watch,
the Ocean or Ask on the wrist, a standalone app, status in complications.

---

## 1 · On the wrist

### Pages

A vertical page `TabView` (`.tabViewStyle(.verticalPage)`), system paging only:
no new animation or transition parameters (CLAUDE.md, PHILOSOPHY §4).

| Page | Shows |
|---|---|
| **Capture** | Today's capture screen unchanged (record disc, status line, Recording, Caught with Undo, the failure screens) minus the "Last:" line. The app always opens here; the Action Button, complication, and Siri still open straight into recording |
| **Today** | Today's resurfaced thought: title and the first lines of its reading. Tap opens it. The page is absent (not empty) when there is no pick, or when the watch's copy of the pick is from another day |
| **Recent** | The wrist takes, newest first, as a `List` the Crown scrolls. Each row: the title (or the time it was caught, until the phone names it), the relative date and the length, and "Waiting for iPhone" on a take still only on the watch. Absent, like Today, when there is nothing to list |

### One thought

`WatchThoughtView`, pushed from Today or Recent:

- The title in the serif (the wrist's title role), then the reading.
- The reading, as the phone shows it (`ExpandedNodeView`'s Reading rule):
  - A voice thought with a summary, or a link with a page summary: the
    summary under a "Summary" eyebrow (sparkles), the phone's own label. A
    machine reading is never dressed as the user's words (§2, §3).
  - Anything else: its own words (transcript, or the note's text), up to
    240 characters at a word boundary. Longer words end with "Continues on
    iPhone". The user's own text is never summarized.
  - A thought with no words (an image alone, a take not yet transcribed):
    "Not transcribed yet" for a voice thought, nothing for the rest. The play
    control still works.
- The Crown scrolls when the reading runs past the screen.
- When audio exists (on the watch, or on the phone per the snapshot), a
  play/pause button in the bottom toolbar with elapsed and total time.
  Without audio, no control at all.
- Playback runs while the user reads. It stops when the user leaves the
  thought, when the scene goes inactive (wrist down), or when a recording
  starts from any entry (capture wins, §1).
- Opening Today's thought sends "met" to the phone. Opening a Recent take
  does not.

### Copy

Value as key, no em or en dashes. zh reviewed by Malik (2026-10-26) except
where marked.

| EN | zh-Hans |
|---|---|
| Today | 今天 (existing on the phone) |
| Recent | 最近 (existing on the phone) |
| Summary | 摘要 (existing on the phone) |
| Waiting for iPhone | 在等 iPhone (draft, from "%lld 条在等 iPhone") |
| Not transcribed yet | 还未转写 |
| Continues on iPhone | 在 iPhone 上继续 |
| Play | 播放 (draft) |
| Pause | 暂停 (existing on the phone) |
| Getting audio… | 正在读回语音… |
| Your iPhone isn't nearby | iPhone 不在附近 |
| Couldn't get the audio | 语音读取失败 |

"Last: %@" leaves the watch string catalog.

---

## 2 · From the phone to the wrist

### The wrist snapshot (`Shared/Watch/WristSnapshot.swift`)

```swift
struct WristThought: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String?          // nil while the thought has only a placeholder
    var reading: String?        // summary, or its own words capped; nil when none
    var readingIsSummary: Bool  // shows the "Summary" eyebrow
    var continues: Bool         // own words cut at the cap: "Continues on iPhone"
    var hasTranscript: Bool     // drives the wrist's 30-day audio expiry
    var hasAudio: Bool          // the phone still holds a recording
    var isVoice: Bool
    var createdAt: Date
}

struct WristSnapshot: Codable, Equatable {
    static let currentVersion = 1
    var recent: [WristThought]     // newest live wrist takes, newest first, at most 20
    var today: WristThought?
    var todayDay: Date?            // the day `today` was picked
    var deletedIDs: [UUID]         // wrist takes the phone imported that no longer exist
    var generatedAt: Date          // a reply and a context update can cross; newer wins
    var version: Int = WristSnapshot.currentVersion
}
```

At most 21 readings of about 240 characters each keeps a snapshot near
20 KB even in Chinese, well inside what application context and a message
reply carry.

### Building it (`Shared/Watch/WristSnapshotBuilder.swift`, pure)

Input is plain values, never `Node`, so it compiles into the watch target and
`SharedTests` covers it:

- the ledger's take IDs with their import dates;
- for each of those IDs still in the store: its current title (already passed
  through `WhisperRules.name`, so a placeholder arrives as nil), its summary
  (voice `summary`, or a link's `linkSummary`), its own words
  (`transcription` for voice, `text` otherwise), whether it has audio, its
  kind, and its creation date;
- today's pick as the same values, and its day.

Rules:

- `recent`: the newest 20 ledger takes that still exist, newest first.
- `deletedIDs`: ledger takes no longer in the store (archived counts as
  live). The ledger's 90-day retention bounds the list.
- Reading: the summary when there is one (`readingIsSummary`); otherwise the
  user's current words, so an edited transcript is what the wrist shows,
  cut at `readingLimit = 240` characters at a word boundary (`continues`).
  240 is the phone's `CaptureSession.summaryThreshold`: words that long get
  a summary on the phone, so a cut mostly means the summary hasn't landed
  yet.

### When the phone sends it

The phone keeps the watch current whenever the two can talk:

- **On every change to the store.** `WristSnapshotPublisher`
  (`Oryne/Services/`) listens for `ModelContext.didSave` (a new thought, an
  edit, a delete, a title or summary landing) and
  `NSPersistentStoreRemoteChange` (CloudKit bringing in another device's
  edit while the app runs). Changes are coalesced for 2 seconds, and a
  snapshot equal to the last one sent is not sent again. It goes out with
  `updateApplicationContext`, which the system delivers as soon as the
  watch is in range, so a change made away from the watch lands on its own
  when the two meet again.
- **When the watch asks.** Each time the watch app comes on screen with the
  phone reachable, it sends `sendMessage(["snapshotRequest": true])` with a
  reply handler. That wakes Oryne on the phone in the background if it isn't
  running; the phone builds a fresh snapshot (running `Resurfacing.pick`,
  which holds the day's pick so the widget and the Ocean agree) and replies
  with it. So Today is there each day even when the phone app hasn't been
  opened, and edits from other devices are picked up whenever the phone has
  synced them.
- **At activation**, next to the confirmations `WatchBridge.linkActivated`
  already sends.

Both payloads share one application context under `WatchWire.recentKey`
and the new `WatchWire.wristKey`, always written together, since an update
replaces the whole dictionary. `WatchBridge` owns the publisher and hands
it the `WatchLink`, as it does the importer.

What stays out of reach: when the phone is away, nothing changes on the
wrist until it's back (the watch never fetches the Ocean from iCloud, per the
capture spec); and an edit from another device reaches the wrist only once
the phone has received it from iCloud.

### Receiving it (watch)

- `PhoneLink` decodes the snapshot from the context or the reply and hands it
  to `TakeSync`; a snapshot older than the one held (by `generatedAt`) is
  ignored.
- `WristSnapshotStore` (`OryneWatch/Services/`) keeps the latest snapshot as
  JSON in Application Support, so the pages render at launch before the
  session activates or the reply lands.
- The queue applies `deletedIDs` (see §3), then the Recent rows are derived.

### The Recent rows (`Shared/Watch/WristRecent.swift`, pure)

Merges the queue and the snapshot into rows:

- Every take still in the queue appears, confirmed or not. A take on the
  watch or in iCloud is never hidden for want of a snapshot.
- A take the snapshot knows takes its title, reading, and `hasAudio` from
  the snapshot; otherwise its title comes from the confirmations, its reading
  is absent, and its state shows.
- The audio source per row: `.watch` when the queue still holds its file,
  else `.phone` when the snapshot says `hasAudio`, else `.none`.
- Today is shown only when `todayDay` is today in the watch's calendar.

---

## 3 · Audio

### Keeping wrist audio (`TakeQueueState`)

Today the watch deletes a recording once it is in iCloud or confirmed. Now it
keeps it, and a take's audio goes only when:

- the take leaves the queue: Undo, pruning past the newest 20 confirmed, or
  the phone listed it in `deletedIDs` (a new `apply(_ snapshot:)` removes
  confirmed takes the phone deleted; a take not yet confirmed is never
  removed this way); or
- the take is confirmed, older than 30 days, and the snapshot says it has a
  transcript. This mirrors the phone's `expireConfirmedAudio`, so the
  wrist's copy never outlives the phone's.

Everything else in `audioDisposable` keeps its meaning: an `onWatch` take
and any file the index can't account for are never deleted. Every deletion
needs an explicit signal, so mistakes fail toward keeping the user's audio
(§5). About 1 MB per 5-minute take; 20 typical takes are about 2 MB.

`QueuedTake` gains `hasTranscript: Bool = false`. Its decoder reads new
fields with `decodeIfPresent`, so an index written by the current version
still loads.

### Fetching from the phone

For a row whose source is `.phone` (Today, or a take whose watch copy was
deleted before this update):

1. On play, if the phone isn't reachable: "Your iPhone isn't nearby". It
   stays until tapped (§5).
2. Otherwise the watch sends `sendMessage(["audioRequest": id])` with a reply
   handler, which wakes Oryne in the background, and shows "Getting audio…".
3. The phone looks up the node. With audio, it writes the bytes to a temp
   file, starts `transferFile` with metadata `["audioFor": id]`, and replies
   `["ok": true]`. Without audio (expired since the snapshot), it replies
   `["ok": false]`.
4. The watch moves the received file synchronously into a `Playback/` cache
   folder (the system deletes it after the delegate returns) and plays it.
5. A false reply, a message error, or no file within 30 seconds: "Couldn't
   get the audio". It stays until tapped.

The cache is cleared when the user leaves the thought and at launch. Fetched
audio never enters the take queue.

### Playing (`OryneWatch/Services/WatchPlayer.swift`)

`@MainActor`, `AVAudioPlayer` over the take's file or the cached fetch,
`AVAudioSession` category `.playback`. One player at a time. It exposes
elapsed and duration for the toolbar and stops on the rules in §1. Starting
a recording stops it first; `WatchRecorder` owns the session from there.

### Meeting Today

Opening Today's thought sends `transferUserInfo(["met": id])`, which queues
and delivers even when the phone is away. The phone's `WatchLink` resolves
the node and calls `Resurfacing.markMet`; the save that makes sends a fresh
snapshot through the publisher.

---

## 4 · Units and files

| Unit | Where | Does | Depends on |
|---|---|---|---|
| `WristSnapshot`, `WristThought` | `Shared/Watch/` (new) | Wire format; `WatchWire` keys `wrist`, `snapshotRequest`, `audioRequest`, `audioFor`, `met` | Foundation |
| `WristSnapshotBuilder` | `Shared/Watch/` (new) | The 20 limit, the reading rule and cap, deleted IDs | `WristSnapshot` |
| `WristRecent` | `Shared/Watch/` (new) | Rows, audio source, Today's day check | `TakeQueueState`, `WristSnapshot` |
| `TakeQueueState` | `Shared/Watch/` (changed) | Audio retention, `apply(_ snapshot:)`, `hasTranscript` | `WristSnapshot` |
| `WristSnapshotPublisher` | `Oryne/Services/` (new) | Node → builder values; listens for saves and remote changes; coalesces; skips repeats | SwiftData, `Resurfacing`, `WatchLink` |
| `WatchBridge` | `Oryne/Services/` (changed) | Owns the publisher; sends it at activation | `WristSnapshotPublisher` |
| `WatchLink` | `Oryne/Services/` (changed) | Context with both keys; answers snapshot and audio requests; "met" | WatchConnectivity |
| `PhoneLink` | `OryneWatch/Services/` (changed) | Receives the snapshot; asks for it on screen; requests audio and receives the file; sends "met" | WatchConnectivity |
| `TakeSync` | `OryneWatch/Services/` (changed) | Routes the snapshot to the queue and the store; ignores an older one | `TakeQueue` |
| `WristSnapshotStore` | `Shared/Watch/` (new, next to `TakeQueueStore`) | Persists the latest snapshot | Foundation |
| `WristLibrary` | `OryneWatch/Services/` (new, compiled into SharedTests) | The held snapshot the pages observe; ignores an older one | `WristSnapshotStore` |
| `WristSnapshotSource` | `Shared/Services/` (new) | `Node` → builder values, by the thought page's reading rule | `Node`, `WhisperRules` |
| `WatchPlayer` | `OryneWatch/Services/` (new) | Playback | AVFoundation |
| `WatchRootView` | `OryneWatch/Features/` (new) | The three vertical pages; `OryneWatchApp` shows it | SwiftUI |
| `WatchTodayView` | `OryneWatch/Features/Today/` (new) | Today page | OceanTheme |
| `WatchRecentView` | `OryneWatch/Features/Recent/` (new) | Recent list | OceanTheme |
| `WatchThoughtView` + `WatchThoughtModel` | `OryneWatch/Features/Thought/` (new) | One thought: reading, play, fetch states | `WatchPlayer`, `PhoneLink` |
| `WatchCaptureView` | `OryneWatch/Features/Capture/` (changed) | Drops the "Last:" line; stops playback before recording | — |

`Oryne/DesignSystem/` is not edited; the new screens use existing
`OceanTheme`, `OceanType`, and `OceanSpacing` roles. `project.yml` changes
only through `xcodegen generate` picking up the new files.
`WatchStatusLine.lastTitle` goes once nothing reads it.

---

## 5 · Failure handling

| Failure | Behavior |
|---|---|
| No snapshot yet (first launch after the update) | Recent shows the queue with confirmation titles; Today absent |
| Phone away when the watch comes on screen | The held snapshot shows; no request is sent and nothing says "syncing" (§5) |
| Snapshot request errors or times out | The held snapshot stays; the next screen-on asks again |
| Snapshot from another day | Today absent; Recent unaffected |
| Phone not reachable on play | "Your iPhone isn't nearby", until tapped |
| Audio request refused, errored, or timed out | "Couldn't get the audio", until tapped |
| Recording starts during playback | Playback stops; the take records as today |
| Thought deleted on the phone | Leaves Recent with its audio on the next snapshot |
| A reply and a context update cross | The older `generatedAt` is ignored |
| Index from the current version | Decodes; new fields take their defaults |

## 6 · Testing

- **Unit (SharedTests):** builder (the 20 limit, newest first, summary
  preferred and marked, own words cut at 240 at a word boundary with
  `continues`, the user's edited words used, `deletedIDs`, archived counts
  as live, placeholder title as nil); `WristRecent` (queue-only takes always
  listed, snapshot titles win, audio source per row, Today hidden on another
  day); `TakeQueueState` (keeps confirmed audio, 30-day expiry only with a
  transcript, `apply(_ snapshot:)` removes only confirmed takes, old index
  decodes); `WristSnapshot` coding round trip and the older-snapshot check.
- **Simulator:** `ORYNE_WATCH_DEMO` gains `recent` and `today` samples,
  `ORYNE_WATCH_PAGE=today|recent|thought` opens a page, and
  `ORYNE_WATCH_AUDIO=fetching|phoneAway|fetchFailed` sets the audio state,
  so every new screen can be shot. Both schemes build clean
  after `xcodegen generate`; tests pass.
- **Device** (added to `docs/HARDWARE_CHECKLIST.md`): a thought captured on
  the phone, titled, or deleted shows on the wrist within seconds with both
  near; a change made with the watch away lands when they meet; the
  snapshot request wakes a suspended or force-quit phone app and brings
  Today on a day the phone app wasn't opened; playback through the speaker
  and through AirPods; the audio request wakes the phone and the file
  arrives; "met" arrives after the phone was away; a recording started mid
  playback.

## 7 · Not in this spec

Today or Recent in complications; deleting or editing on the wrist; the full
words of a long thought on the wrist; scrubbing or speed control; the full
Library or other devices' captures beyond today's pick; images on the
wrist; the watch reading the Ocean from iCloud directly.

## 8 · Device unknowns that could change the design

1. watchOS may route `.playback` only to Bluetooth for some content. Then the
   play control says to connect AirPods when none are, and the hardware
   checklist records it.
2. A message may not wake a force-quit phone app. Then the snapshot request
   and the audio fetch fail honestly (the held snapshot stays; "Couldn't get
   the audio"), the store-change push still covers every time the phone app
   runs, and only the watch's own copies play.
3. `NSPersistentStoreRemoteChange` may not fire for the SwiftData mirror's
   imports in the background. Then other devices' edits wait for the next
   watch screen-on with the phone near, or the next phone launch.
