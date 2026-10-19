# Hardware test checklist

Things the simulator cannot prove. Run on a real device (signed build, with a
Development Team set so the App Group + CloudKit paths activate) before any
release. Each item names the behavior that must hold — not just "it didn't
crash".

## Recording interruptions

- [ ] **Phone call mid-recording** — receive a call while a whisper is
  recording (the capture button and every Fast Capture entry point). The take must end like a tap on
  stop: captured capsule / review appears with the words caught so far; never
  a stuck "Listening…" with a frozen timer. Audio recorded up to the
  interruption must play back.
- [ ] **Siri mid-recording** — invoke Siri while recording; same expectation.
- [ ] **AirPods route changes** — start recording on AirPods, put one in the
  case (input route lost → take ends, captured). Then: start recording on the
  built-in mic and *connect* AirPods mid-take (engine reconfiguration → take
  ends, captured, no crash from a stale tap format).

## Launch surfaces

- [ ] **Action Button** — launches Fast Capture, recording starts immediately,
  live words appear, stop → "Captured" review, auto-release after ~3 s.
- [ ] **Camera Control** — same flow via the Camera Control launch path.
- [ ] **Lock-screen widget / Control Center control** — same flow; deep links
  (`oryne://capture/whisper`) still land on the right tab.

## Backgrounding

- [ ] **Background during recording** — start a whisper, swipe to Home. The
  take must be captured (node exists with the words caught so far); returning
  to the app shows idle capture, not a phantom recording.
- [ ] **Background during the captured beat** — stop, then background while
  the capsule shows. Untouched → it must have released (node present,
  understanding runs). Paused mid-edit → the edits made so far must be on the
  node, not lost.
- [ ] **Undo window** — after a capture releases, Undo must stay reachable
  for ~10 seconds: in the capsule, through the post-capture moment, and via
  the quiet Undo pill that outlives the moment (the capture overlay, both typed and whispered; Fast
  Capture — Fast Capture's overlay shrinks to the pill, backdrop gone, before
  closing). A late Undo within the window deletes the node AND restores the
  words/recording to the surface.

## Sync & data

- [ ] **CloudKit two-device sync** — capture and edit on device A; B receives
  the node, the edit (`updatedAt` bump), the ownership flags, and
  `anchorThemeKey`. Edit themes on A → node must NOT move currents on B
  (anchored), chips update.
- [ ] **Old-data migration** — install this build over a store created before
  the ownership flags existed. Library renders, old voice notes play, editing
  works, clustering unchanged (nil `anchorThemeKey` behaves like before), no
  CloudKit schema errors in Console.
- [ ] **Audio expiry** — set a node's `createdAt` back 31+ days (or
  temporarily lower `retentionDays`), relaunch: `audioData` purged only for
  nodes WITH a transcript; the Listen chip disappears gracefully; transcript
  stays; the deletion syncs to the second device.
- [ ] **Offline capture** — airplane mode: live transcription still works on
  on-device-recognition hardware; captures queue and sync when back online.

## Permissions

- [ ] **Speech denied** — deny speech recognition: recording works, review
  opens for manual typing, no permission re-prompt loop, post-hoc
  transcription quietly absent ("No words yet" after 2 min, not
  "Transcribing…" forever).
- [ ] **Mic denied** — Fast Capture falls back to typing with "Typing is
  ready."; the capture button falls back to typing and does nothing destructive.

## Apple Watch

Signed build on a real watch paired with a real iPhone. Simulator cannot
deliver WatchConnectivity files, press the Action Button, or prove
wrist-down recording.

- [ ] **Action Button setup** — on an Ultra: Settings › Action Button ›
  Shortcut. Confirm "Catch a whisper" can be chosen directly; if it must be
  wrapped in a user shortcut, update the Apple Watch section in Settings
  and this item. A press opens Oryne recording.
- [ ] **Second press stops** — press the Action Button again while recording:
  the take is caught. If the press doesn't reach the app, record that, and
  the Apple Watch section in Settings must say stop with a tap or Double Tap.
- [ ] **Complication tap** — tap the Oryne complication (circular, corner,
  rectangular, and the Smart Stack): Oryne opens recording; tap again while
  recording: the take is caught. (The watch simulator's LaunchServices
  ignores declared URL schemes, so `oryne://watch/catch` could only be
  checked on a real watch.)
- [ ] **Double Tap stop** — Series 9+ or Ultra 2+: Double Tap while recording
  catches the take.
- [ ] **Wrist down keeps recording** — start a take, lower the wrist, keep
  talking 20 s, raise, stop: the take holds all of it. If recording stops
  when the app suspends, fall back to "wrist down ends the take" (spec §9.3).
- [ ] **Always On** — wrist down while recording shows the timer alone, and
  Double Tap still stops the take.
- [ ] **Stop from a dimmed screen** — with Always On and the wrist down, stop
  with the Action Button or Double Tap; on raising the wrist, Caught and Undo
  appear (the take is held, not sent at once). If it sends at once, record
  it.
- [ ] **5 minute cap** — a haptic and the take is caught at 5:00.
- [ ] **Call mid take** — a call ends and catches the take; no stuck screen.
- [ ] **Interrupted take keeps its length** — a call or lost mic mid-take:
  the caught take keeps the time actually recorded (not dropped as a reflex
  press).
- [ ] **Caught off screen** — a take that ends by the cap or a call while the
  wrist is down sends at once (no Undo hold); raising the wrist shows the
  idle screen and the status line.
- [ ] **Delivery with the phone app force quit** — catch a take with Oryne
  force quit on the phone, phone nearby: within a minute the thought is in
  Library (does the wake ping deliver the file?). Record the latency.
- [ ] **Background transcription** — catch a take with the phone locked; once
  imported it gets a transcript and title. If it stays a bare Whisper,
  opening Oryne retries it.
- [ ] **iCloud fallback** — phone in airplane mode, watch on Wi-Fi or LTE:
  catch a take; the watch says "On its way"; turn the phone back on; the
  thought arrives and the watch says "In your Ocean" with its title.
- [ ] **Background refresh** — with a take waiting and the phone unreachable,
  the iCloud fallback runs roughly 2 minutes after the take stopped without
  opening the app (watchOS treats the time as a hint; record the actual
  delay).
- [ ] **Both paths, one thought** — catch a take that goes over both paths:
  exactly one thought in Library; the iCloud record is gone afterwards.
- [ ] **Many takes at once** — catch more than 20 takes away from the phone,
  then bring it back: every one is confirmed and the watch ends on "In your
  Ocean" (the phone confirms its newest 200; check that the application
  context with titled entries arrives).
- [ ] **Undo** — Undo within 5 s: nothing reaches the phone or iCloud.
- [ ] **Microphone denied** — deny on first use: the one-line message, no
  loop; allow in Settings, return: the idle screen is back. Confirm the
  Settings path the message names.
- [ ] **Cold launch with the mic undecided** — fresh install, trigger from
  the Action Button and from Siri ("Whisper to Oryne"): the mic prompt
  appears; after allowing, recording starts; after denying, the one-line
  denied screen shows.
- [ ] **Nothing was caught** — a take that can't be decoded shows "Nothing was
  caught" with a failure haptic, and it stays until tapped.
- [ ] **Phone capture unchanged** — on the phone, hold the capture bar to
  whisper, and whisper from the Fast Capture overlay; the transcript and title
  still land (the understanding step moved into `VoiceUnderstanding`).
- [ ] **SwiftData sync unaffected** — after installing this build (it adds an
  app delegate for the inbox push), run the CloudKit two-device sync item
  above again.
- [ ] **Production schema** — before deploying, write one complete
  `WatchTake` record (all four fields: `createdAt`, `duration`, `version`,
  `audio`) in the development environment so every field exists in the
  schema. Then, before release, deploy the `WatchTake` record type in
  CloudKit Console (development creates it on first write).
