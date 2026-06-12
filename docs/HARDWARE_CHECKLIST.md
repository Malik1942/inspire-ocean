# Hardware test checklist

Things the simulator cannot prove. Run on a real device (signed build, with a
Development Team set so the App Group + CloudKit paths activate) before any
release. Each item names the behavior that must hold — not just "it didn't
crash".

## Recording interruptions

- [ ] **Phone call mid-recording** — receive a call while a whisper is
  recording (Capture tab and Fast Capture). The take must end like a tap on
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
  ready."; Capture tab mic button does nothing destructive.
