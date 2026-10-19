# Oryne Apple Watch Capture — Design Spec

**Date:** 2026-10-18 · **Branch:** `am/oryne-apple-watch-app-177fc5` · **Status:** approved section by section in brainstorming (2026-10-18); awaiting review of this written spec

## Goal

Catch a spoken idea from the wrist in under two seconds, and have it arrive in
the Ocean on its own: transcribed, titled, and drifting into a current, with no
step on the phone. The feel borrows from Apple's Voice Memos (press to record,
press to stop, it just shows up) but not its library: the wrist only catches.
PHILOSOPHY §1 (capture before consciousness) and §2 (audio is provenance, not
an asset to manage) govern every choice below.

## Decisions (from brainstorming, 2026-10-18)

| Decision | Choice |
|---|---|
| What the watch shows | Record disc, one honest status line, and the last thought's title once the phone has named it. No list, no playback |
| Wrist down mid take | Keep recording (screen off) until stopped or a 5 minute cap |
| Which entries record | Action Button, complication, and Siri open into a hot mic. The app icon opens the idle screen and never records |
| Sync | Both paths: WatchConnectivity file transfer always; a CloudKit inbox as fallback when the phone is out of reach |
| Undo | "Caught" offers Undo for 5 seconds; sending waits for the window |
| Wrist mark on thoughts | No. A watch take is an ordinary voice thought; no Node schema change |
| Starting point | Port Phase 1 from `feat/watchos-quick-capture` (unmerged, 77 commits behind main) onto this branch and fix its known bugs; do not merge that branch |
| Floors | watchOS 11 (Double Tap API), iOS 18 (unchanged) |

## Platform facts this design rests on

- **Action Button.** Only Apple Watch Ultra models have one, and Settings ›
  Action Button lists only workout and dive apps directly (`StartWorkoutIntent`,
  `StartDiveIntent`). Any other app gets in through the button's **Shortcut**
  option, running an App Shortcut. Posing as a workout app is not an option.
  ([Apple: Responding to the Action button on Apple Watch Ultra](https://developer.apple.com/documentation/appintents/actionbuttonarticle))
- **Containers are not shared.** The watch app and the iPhone app do not share
  an App Group container. Phase 1's comment ("the watch writes pending
  captures into the same shared container the phone reads") is wrong and goes.
- **WatchConnectivity file delivery.** The receiving delegate must move the
  file synchronously before returning, or the system deletes it. Simulator
  never calls it; it is device only. Whether iOS wakes a suspended app just
  for a file transfer is not documented, hence the wake message below.
  ([Apple: session(_:didReceive:)](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate/session(_:didreceive:)))
- **Background recording.** Developer reports say a recording started in the
  foreground continues with the screen off (with the `audio` background mode),
  while starting one from the background fails. Unproven for us until a device
  run. ([forum](https://developer.apple.com/forums/thread/750432), [forum](https://developer.apple.com/forums/thread/751866))

---

## 1 · On the wrist

### Entry points

| Entry | Behavior |
|---|---|
| Action Button (Ultra) | Shortcut slot runs the watch app's **Catch a thought** App Shortcut → app opens recording. A second press while recording stops and catches (device-verify; Double Tap and tap remain if it doesn't) |
| Complication | `accessoryCircular`, `accessoryCorner`, and `accessoryRectangular` (Smart Stack). A static launcher: deep link `oryne://watch/catch` → recording |
| Siri | Same intent. Phrases **"Whisper to Oryne"** and **"Record a thought in Oryne"**. ("Catch this in Oryne" already belongs to iPhone Fast Capture in `CaptureIntents.swift`; the watch must not collide with it) |
| App icon | Idle screen. Never records |

The Action Button and Siri run one intent, `CatchThoughtIntent`
(`openAppWhenRun = true`, implemented in the watch app itself, not an
extension). The complication's deep link calls the same rule: idle or
Caught → start recording (a pending Caught take sends at once); recording →
stop and catch.

### Recording

- "Listening…", a flat waveform, a monospaced timer, one flat stop disc. All
  from the shared OceanTheme tokens: near monochrome, matte, a circle only as
  a flat control disc, never a lit orb.
- Stop: tap the disc, Double Tap (`handGestureShortcut(.primaryAction)`,
  Series 9+ and Ultra 2+), or a second Action Button press.
- Wrist down keeps recording. Always On dims to the timer alone.
- Cap at 5 minutes: a haptic, and the take is caught.
- A call, Siri, or a lost mic ends the take the way stop does: catch what was
  caught.
- A take shorter than 0.6 s is discarded silently (a reflex press).

### Caught

A success haptic, "Caught", and an **Undo** button for 5 seconds. Sending
starts when the window closes, or at once if the app leaves the screen. Undo
deletes the local file; nothing was sent, so nothing exists anywhere else.
Then the idle screen.

### Idle

The record disc, one status line, and the last title. The status line is
derived from the queue, and never claims more than is true:

| Queue state | Line |
|---|---|
| Any take only on the watch | "1 waiting for iPhone" (plural variants) |
| None only on the watch, some in iCloud but unconfirmed | "On its way" |
| Everything confirmed | "In your Ocean" |
| Nothing ever caught | No line |

Below it, "Last: Lighthouse café": the title of the newest confirmed take,
shown only once the phone has named it. Before that, nothing; no placeholder.

### Failure states on the wrist

- Microphone denied: one line naming where to turn it on, no retry loop.
- Recorder failed to start: "Couldn't start. Tap to try again."
- Empty or undecodable file: "Nothing was caught" (nothing is queued).

### Copy (EN, with zh drafts to confirm against `docs/localization-glossary.md`)

No em or en dashes in any UI string; value as key, so EN and zh move together.

| EN | zh-Hans (draft) |
|---|---|
| Listening… | 聆听中… (existing) |
| Caught | 接住了 |
| Undo | 撤销 |
| %lld waiting for iPhone | %lld 条在等 iPhone |
| On its way | 正在汇入 |
| In your Ocean | 已汇入你的海洋 |
| Last: %@ | 上一条：%@ |
| Couldn't start. Tap to try again. | 没能开始。轻点再试一次。 |
| Nothing was caught | 什么也没接住 |
| Catch a thought (shortcut title) | 捕捉灵感 |

---

## 2 · From wrist to Ocean

### One ID per take

The watch mints a UUID when recording starts. It becomes the Node's `id`, the
CloudKit record name, and the dedupe key on every path.

### Shared wire format (`Shared/Watch/WatchTake.swift`)

`WatchTake: Codable` — `id: UUID`, `createdAt: Date`, `duration: TimeInterval`,
`version: Int` (1). Encoded into WatchConnectivity transfer metadata and
mirrored as CloudKit fields. Audio is AAC `.m4a`, mono, 12 kHz, the same
settings as the phone recorder.

### The watch queue

The watch keeps an index (JSON) and the `.m4a` files in its own Application
Support `Takes/` folder. Each take moves through:

`onWatch` → `inICloud` → `confirmed(title?)`

- The audio file is deleted once the take is durable elsewhere: `inICloud` or
  `confirmed`.
- `confirmed` entries keep only id, date, and title; prune all but the newest
  20.

### Path 1: WatchConnectivity (every take)

After the Undo window: `transferFile(_:metadata:)` with the encoded
`WatchTake`. If `isReachable`, also `sendMessage(["wake": id])` with no reply
handler, so iOS launches Oryne in the background and the queued transfer is
delivered now rather than at the next launch. On session activation, re-send
any `onWatch` take that has no entry in `outstandingFileTransfers`.

### Path 2: CloudKit inbox (fallback)

- Container `iCloud.com.inspireocean.app`, private database, custom zone
  **`WatchInbox`**. Separate from the SwiftData mirror's zone, so the two
  never touch. The watch creates the zone if missing (idempotent).
- Record type **`WatchTake`**, `recordName = id.uuidString`, fields
  `createdAt` (Date), `duration` (Double), `version` (Int64), `audio`
  (CKAsset).
- When: at send time if the phone is not reachable; and on any later
  foreground or background refresh, for any take still `onWatch` after 2
  minutes. Success moves the take to `inICloud`. `isReachable` is only
  meaningful while the watch app is on screen, so the reading taken at stop
  decides; a take sent after the screen goes off uses that reading.
- The watch only uploads. It never fetches the Ocean or any other record.

### Import exactly once (phone)

Both paths feed one `@MainActor` importer. Its dedupe source is a phone-local
**import ledger** (`[takeID: {state, at}]`, states `imported` and
`understood`, pruned after 90 days), not "does a Node with this id exist":
a thought the user deleted must not return when a late copy arrives over the
other path. After a successful import the phone deletes the inbox record by
ID (unknown item is fine) and the local inbox file.

**Only the paired iPhone imports** (`WCSession.isSupported() && isPaired`).
An iPad never reads the inbox; two importers would mint duplicates.

### Confirmation back to the watch

The phone calls `updateApplicationContext(["recent": [{id, title?}]])` with the
newest 20 imported takes, after each import and again when a title lands.
The watch marks those `confirmed` (title when present) and refreshes Idle.
A take imported over iCloud while the watch was away is confirmed on the next
WatchConnectivity contact.

### Release task

Deploy the `WatchTake` record type and the `WatchInbox` zone usage to the
**production** CloudKit schema (CloudKit Console) before shipping. The
development environment creates them on first write.

---

## 3 · On the phone

- **`WatchLink`** (`Oryne/Services`): owns the iOS `WCSession`, activated in
  `OryneApp.init` so background deliveries reach it. `didReceive file`
  (background thread) synchronously moves the file into the App Group
  `WatchInbox/` folder, named by take ID, then hands off to the importer.
  `didReceiveMessage` for the wake ping does nothing beyond activating.
- **`WatchInboxReader`** (`Oryne/Services`): a `CKRecordZoneSubscription` on
  `WatchInbox` (silent push; the app already has the `remote-notification`
  background mode; adds a `UIApplicationDelegateAdaptor` to receive it), plus
  a zone-changes fetch at launch and on foreground with a persisted change
  token. Downloads each asset into the same `WatchInbox/` folder → importer.
  Runs only on the paired iPhone.
- **`WatchTakeImporter`** (`Oryne/Services`): ledger check → `NodeComposer.make(kind: .voice, audioData:)`
  with `id` and `createdAt` from the take → insert and save → ledger
  `imported` → delete inbox file and inbox record → confirm to the watch →
  understanding → ledger `understood` → confirm again with the title. Wraps
  the work in `beginBackgroundTask`. A refused save leaves the ledger and the
  inbox file untouched so the launch sweep retries.
- **Launch sweep** (in `OryneApp`'s launch task): import any file in
  `WatchInbox/` not in the ledger; finish understanding for ledger entries
  still `imported`.
- **`VoiceUnderstanding`** (`Oryne/Services`): the transcribe-then-understand
  steps now private in `CaptureSession` (`transcribeThenUnderstand`,
  `understand`, lines 196 to 230) move here, taking a node ID, an optional
  temp audio URL, a context, and the AI service. `CaptureSession` calls it and
  keeps its `onUnderstood` callback; behavior is unchanged. Ownership checks
  (`transcriptEditedByUser`, `NodeComposer.applyUnderstanding`) stay intact.
- **No Node schema change.** Pending state lives in the ledger. The thought
  shows in Library and the Ocean at once as "Whisper" until named, exactly
  like a phone take. The existing 30 day audio expiry applies.
- **Setup help:** one row in Fast Capture settings explaining the Ultra Action
  Button setup. Exact path written after the device check.
- **Packaging:** the watch app is embedded in the iOS app (companion, not
  standalone).

---

## 4 · Units and files

| Unit | Where | Does | Depends on |
|---|---|---|---|
| `WatchTake` | `Shared/Watch/` | Wire format, both paths | Foundation |
| `TakeQueueState` | `Shared/Watch/` | Pure state transitions and pruning for the watch queue | `WatchTake` |
| `WatchStatusLine` | `Shared/Watch/` | Pure derivation of the status line and last title from queue state | `TakeQueueState` |
| `ImportLedger` | `Shared/Watch/` | Pure dedupe decisions and pruning | `WatchTake` |
| `WatchRecorder` | `OryneWatch/Services/` | Record, meter, finalize, cap, interruptions | AVFoundation |
| `TakeQueue` | `OryneWatch/Services/` | Persists the index and files; applies `TakeQueueState` | `TakeQueueState` |
| `PhoneLink` | `OryneWatch/Services/` | Watch `WCSession`: send, wake, receive context | WatchConnectivity |
| `CloudInbox` | `OryneWatch/Services/` | Zone setup and upload | CloudKit |
| `CatchThoughtIntent` + App Shortcuts | `OryneWatch/Intents/` | One intent for Action Button, complication, Siri | AppIntents |
| Capture, Caught, Idle views | `OryneWatch/Features/Capture/` | The three screens | OceanTheme |
| Complications | `OryneWatchWidgets/` (new watchOS widget extension) | Static launchers | WidgetKit |
| `WatchLink`, `WatchInboxReader`, `WatchTakeImporter`, `VoiceUnderstanding` | `Oryne/Services/` | Phone side, above | WatchConnectivity, CloudKit, SwiftData |

The watch target compiles `Shared/Watch` and the theme only, never the rest of
`Shared/` (no SwiftData, no Node, no CloudKit mirror). It needs no App Group.
Pure units live in `Shared/Watch` so `SharedTests` covers them.

OceanTheme: main keeps it at `Oryne/DesignSystem/OceanTheme.swift`, shared to
the widget by path. The watch references it the same way; if it uses iOS only
API, guard or lift it to `Shared/` (Phase 1 lifted it).

---

## 5 · Failure handling

| Failure | Behavior |
|---|---|
| Mic denied | One line naming where to enable it; re-checks on next appear |
| Recorder start fails | "Couldn't start. Tap to try again."; audio session deactivated |
| File not finalized / empty / undecodable | Wait for the recorder's finish callback before queueing; "Nothing was caught" if bad |
| Phone away for days | Takes accumulate (about 1 MB per 5 minute take); the count shows it |
| WC transfer error | Re-sent on next activation |
| iCloud signed out, offline, or full | Take stays `onWatch`; status keeps saying "waiting for iPhone" |
| Phone save refused | No ledger entry, no confirmation; watch keeps the take; inbox file retried at launch |
| Transcription fails | Stays a Whisper with its audio (today's behavior) |
| Both paths deliver | Ledger dedupes; second copy's inbox record and file are deleted |
| Deleted thought, late copy | Ledger says imported; nothing is recreated |

## 6 · Testing

- **Unit (SharedTests):** `TakeQueueState` transitions and pruning;
  `WatchStatusLine` for every row of the table above; `WatchTake` coding
  round trip; `ImportLedger` for WC first, iCloud first, both at once,
  deleted then late copy, and 90 day pruning.
- **Simulator:** all watch screen states; a recording that `AVAudioPlayer(data:)`
  decodes with nonzero duration; intent start/stop toggle; complication deep
  link; app icon opens Idle; iOS build with the embedded watch app. Both
  schemes build clean after `xcodegen generate`.
- **Device** (added to `docs/HARDWARE_CHECKLIST.md`): Action Button Shortcut
  slot and the second press stop; whether the App Shortcut is selectable
  directly or must be wrapped in a user shortcut; Double Tap stop; wrist down
  recording with Always On; 5 minute cap; a call mid take; delivery with the
  phone app force quit (does the wake work); airplane mode phone → iCloud
  fallback over watch Wi-Fi or LTE; the same take over both paths; mic denied.

## 7 · Not in v1

Playback or a list on the watch; typing, Scribble, or dictation on the watch;
transcription on the watch; the Ocean or Ask on the wrist; a standalone watch
app; a "from your wrist" mark; iPad importing; status inside complications.

## 8 · Porting Phase 1

From `feat/watchos-quick-capture` take: the `OryneWatch` target block in
`project.yml`, the icon asset catalog, `WatchAudioRecorder` (as the base of
`WatchRecorder`), and `WatchCaptureView` (as the base of the recording
screen). Leave its unrelated commits (delete flow, glass confirmation) and
its App Group entitlement. Fix its recorded defects:

- metering timer off the main run loop; `level` and `elapsed` mutated off
  main → isolate the recorder to `@MainActor`
- `.m4a` finalization not awaited → implement the delegate and await it
- re-open from background landed idle → intent entries now always record;
  the icon lands idle by design
- denied state had no recovery after granting
- audio session not deactivated on start failure; no double start guard
- Always On and VoiceOver polish on the capture screen
- the wrist down rule flips from "end the take" to "keep recording"

## 9 · Device unknowns that could change the design

1. A second Action Button press may not reach a foreground app's intent. Then
   stop is tap or Double Tap only, and the setup row says so.
2. The wake message may not prompt delivery of a queued file. Then delivery
   happens at the phone app's next launch or via the iCloud path; the status
   line stays truthful either way.
3. Wrist down recording may stop when the app is suspended. Then fall back to
   Phase 1's rule (wrist down ends the take) and record the finding.
4. A CloudKit upload from a suspended watch app may not finish. Then uploads
   happen on foreground only.
