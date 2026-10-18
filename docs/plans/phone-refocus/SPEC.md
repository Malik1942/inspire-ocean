# Phone refocus: capture, Ask, and the shape of the phone app

**Date:** 2026-10-17 · **Status:** decisions recorded from the 2026-10-15 to 10-17 product conversation (Malik). No prototype first; implementation follows this spec phase by phase.

## Thesis

On the phone, Oryne is an **inspiration intake** and a place where ideas **resurface quickly**. It is not where ideas are explored or developed; that belongs to desktop and iPad environments with real working power. People glance at a phone. Every phone surface is judged by: can it be used in a glance, or in one gesture?

What this rules out on the phone: an explorable map, direct manipulation of groups and links, a four-mode dialogue room, branch composition. What it keeps: capture in under two seconds, today's resurfacing, fast retrieval when the Library gets too big to scan, and a short grounded answer when a question is faster than browsing.

## Decisions

1. **Capture is a bar plus the Fast Capture overlay, not a tab.** The bar sits in the tab bar's accessory slot like a message composer: a field and the disc, never a lone floating button (Malik, 2026-10-17: a voice control on its own outside the composer is not how phones work). Same trigger grammar as Moti; the products differ in what happens after the trigger. The Capture tab goes away.
2. **Voice is a gesture, not a mode.** Hold to whisper, release to catch. Slide up to lock for long takes. Thought and Whisper stop being a picker: typing makes a thought, holding makes a whisper, doing both keeps both.
3. **The review beat goes away.** A whisper is caught the moment the finger lifts (Philosophy §1 already says review never gates capture). What remains is the same Undo pill the typed path has. Words are edited later in the thought, not at the moment of capture.
4. **Ask stays as a surface.** As the Ocean grows the Library cannot be scanned, so a question is a real need. The four modes (Search, Synthesis, Expansion, Research) merge into one input and one answer shape. Summarize is the anchor use.
5. **The Ocean on the phone becomes a surface, not a map.** Water, today's resurfacing lit, the newest few thoughts near the surface. No pan, no zoom, no current orbs to tap. The spatial Ocean with drag-to-regroup and link-drawing is an iPad and Mac product, later.
6. **Exits matter.** Thought development happens elsewhere, so a current must be able to leave: a continuous Markdown mirror and a "take this current to brainstorm" share action. Not "bring your own key" chat inside Oryne.

Decisions 1 to 4 are implemented first. Decisions 5 and 6 are direction, scoped in their own specs when their turn comes.

## Navigation

Visual language (Malik, 2026-10-17, after three rounds): the brand's serif (Instrument Serif, the website's display face) in three display moments only, the Tide title, the italic section labels and the resurfacing title, system type everywhere else (kept after a side-by-side on device); no rendered materials and no hairline borders, surfaces are flat fills; one lamp in the water behind Resurfacing is the page's only light and its label the only warm color; the capture bar is dense material over a deep tint with a shore gradient under it and the tab bar; three controls (Primary, Secondary, Icon) and nothing else. Decided on wireframes and mocks before code, each time.


Three tabs and one button.

| Surface | Job | Glance test |
| --- | --- | --- |
| Tide (was Ocean) | What the tide brought to the surface: Resurfacing, Drifted in, Currents. The Ocean stays the name of the whole water; the Library is its depth | Three seconds: what came back, what I just caught |
| Ask | One question in, one grounded answer out | One question, one scroll |
| Library | Find it: search, time, Related, current filter | Type two words, tap the card |
| Capture bar | Above the tab bar on Ocean and Library (the iOS 26 tab bar accessory; a floating bar before 26): a field to tap and the disc to hold. Hidden on Ask, which has its own input | One gesture |

Deep links and intents keep working: `oryne://capture/thought` opens the overlay typing-first, `oryne://capture/whisper` opens it listening. `OCEAN_START_TAB=capture` is retired; the screenshot and film seeds move to `ocean`.

## Ask: one mode

One field. Placeholder: "Ask the Ocean". No mode picker.

The answer has a fixed shape, and every part is grounded or marked:

1. **Found**: the fragments retrieval chose, as chips that open the real thing. Present whenever anything cleared the similarity floor.
2. **What it means**: one short paragraph composed from those fragments. This is today's Synthesis. When the question is a lookup ("that thing about ferries"), this paragraph is one sentence or absent; the chips are the answer.
3. **Beyond your Ocean** (optional, marked apart): today's Research outward note, only when retrieval was thin or the question clearly asks for the outside world. Never mixed into the paragraph.

Expansion's branch leaps are dropped from the phone. Growing an idea is desktop work; the exit in decision 6 is where it goes.

**Summarize** is a verb, not a mode: on a current's stream sheet and on a Library search result set, "Summarize" sends those fragments through the same answer shape with a fixed question. One tap, no typing.

Honesty states carry over unchanged: "Composed offline", "Nothing in your Ocean matches this yet", the shortened-note notice.

## Voice capture

### The gesture

- **Tap** the capture button: the overlay opens typing-first, keyboard up.
- **Hold** the capture button: listening starts under the finger. Lift to catch. A short press (under about 300 ms) is a tap.
- **Slide up** while holding: locks the take. The button becomes a single Stop. Stop catches, same as lifting.
- While a take is live, nothing else on the overlay is tappable. A call, Siri, a lost mic, or backgrounding ends the take as a lift would (Philosophy §1).

Accessibility: with VoiceOver, Switch Control, or Calm Accessibility Mode on, the button is tap-to-start, tap-to-stop with the same two states. The hold gesture is an optimisation, never the only path.

### What the user sees while holding

One indicator. The button breathes with the microphone level; the waveform, the monospaced timer, and the "Listening" label are gone.

Words land directly on the water as subtitles: large, word by word, no frame around them, trailing lines fading. When speech recognition is unavailable or still preparing, the subtitle area shows nothing and a single small line sits under the button: "Words will follow." The audio is captured either way; the post-capture pass recovers the words as it does today.

### What happens on release

1. The words shrink and settle into the water; the OceanReceived chime and swell play, as the typed path does today.
2. The thought is saved before anything says so (Philosophy §5). The settle animation is the confirmation and runs only after the save is checked.
3. An **Undo** pill holds for the same window the typed path uses, then goes. Tapping it removes the thought, by name.
4. The Fast Capture result card ("Understood as … · Drifts near …") stays, because it is the one moment the Ocean answers a capture. It appears after the settle, and the overlay closes from it as today.

Gone: "Captured", "Tap words to keep editing", Edit, Keep, the auto-release countdown, the review transcript editor, the Listen chip at capture time. Editing words, re-transcribing, and listening to the audio live in the thought's expanded view, where they already exist.

### Thought and Whisper together

The overlay has a text field and the button. Typing before holding keeps the typed words as the note on the whisper (today's "both survive" rule). Holding and then typing adds a note to the thought already caught. No picker, no camera-style paging. `NodeKind` stays: a thought with audio is `.voice`, without is `.text`; the kind follows what happened, not what was chosen.

### Code shape

`FastCaptureSessionView` and `CaptureView` carry the same states twice (about 1600 lines). After this change there is one capture surface, the overlay, built on the existing `FastCaptureSession` and `DriftTranscriber`. `CaptureView` and `PostCaptureMoment` are removed with the tab; whatever `PostCaptureMoment` does that the overlay's result card does not is folded into the card first.

The capture pipeline underneath (`NodeComposer`, understanding, bilingual dual pass, undo window) does not change.

## Philosophy amendments

This spec needs `PHILOSOPHY.md` amended before the code lands, not after:

- **§3 AI behavior**: "reflective partner" stays, but the four dialogue modes are no longer named as the product. Ask is one grounded answer; growing ideas is out of scope on the phone.
- **§4 Motion**: unchanged for now. The surface Ocean (decision 5) will need motion to carry "new since last time", and that amendment is made in that spec.
- **§7 Retrieval**: "cluster streams" stop being a retrieval path on the phone once the map goes; the Library's current filter takes that sentence.
- **§8 Calm computing**: add the glance test: "would this need more than a glance or one gesture on a phone? Then it belongs on the desk."

## Phases

| Phase | Scope | Done when |
| --- | --- | --- |
| 1 | Voice capture in the Fast Capture overlay: hold gesture, lock, subtitles on the water, settle, Undo pill; review beat removed | Every entry point (widget, Action Button, Control Center, Siri, deep link, share sheet) lands on the new overlay; a whisper from press to settle needs one gesture. **Built 2026-10-17 on `feat/phone-refocus`.** |
| 2 | Capture tab removed; floating capture button over the three tabs; `CaptureView` and `PostCaptureMoment` folded into the overlay | Three tabs; `OCEAN_START_TAB=capture` retired; onboarding and the Introduction copy no longer mention a Capture tab. **Built 2026-10-17.** |
| 3 | Ask merged into one mode with the fixed answer shape; Summarize verb on streams and search results | No mode picker; the four `DialogueMode` cases collapse behind one entry; summarize works offline with the grounded fallback. **Built 2026-10-17.** |
| 4 | Ocean surface (own spec) | |
| 5 | Exits: Markdown mirror, take-to-brainstorm (own spec) | |

Each phase ships on its own branch and is used on-device for a few days before the next starts. The launch film's scene 2 depends on tapping a current in the map; it is re-cut after phase 4, not before.

## Out of scope

iPad and Mac Oryne, direct manipulation of currents, bring-your-own-key chat, any digest or feed surface, streaks or counts of any kind.

## Open questions

- ~~Hold-to-whisper from the Home Screen widget and Control Center~~: decided in Phase 1. Those entry points have no finger to hold, so the take opens locked and runs until Stop. The same happens when the finger leaves during the first-run permission ask.
- Subtitle language for a bilingual take: show the resolved main locale's words only, or both passes as they land?
- ~~Where does the capture button sit relative to the tab bar on iOS 26~~: in the accessory slot (`tabViewBottomAccessory`), disabled on Ask from iOS 26.1; on 26.0 it also shows on Ask.
