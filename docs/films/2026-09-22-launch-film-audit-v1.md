# Oryne launch film — Gap Audit (v1, delivery)

**File:** `~/Desktop/oryne-launch/renders/Oryne Launch v1.mp4` · **Date:** 2026-09-22
**Script:** `docs/films/2026-09-22-launch-film.md` (the original script, plus Revision 1 for scene 2 and Revision 2 for camera and music)
**Evidence:** every verdict below is based on a frame pulled from the delivered file (`renders/stills-v1/*.png`, `renders/stills-v1/extra/*.png`), read at 2560×1440. Hold durations come from 2 fps contact sheets of the delivered file (`extra/sheet-*.png`).

## File facts

| | |
|---|---|
| Size | 108,684,406 bytes (108.7 MB / 103.6 MiB) |
| Video | H.264, 2560×1440, 60/1 fps (avg 60/1), 3255 frames, 15.8 Mb/s |
| Audio | one stream, AAC 48 kHz stereo, 193 kb/s |
| Duration | 54.250 s (container, video and audio). `film.json` total is 54.249 s, so the difference is +0.001 s. The allowed window is 45–60 s |
| Loudness | −15.9 LUFS integrated, LRA 4.1 LU |
| True peak | −1.7 dBTP (target ≤ −1.0) |
| Render | `npx -y hyperframes@0.8.62 render film -o "renders/Oryne Launch v1.mp4" --fps 60 --quality delivery --strict --no-browser-gpu --video-frame-format png --workers 1`. It finished in 11 m 44 s with exit 0. `hyperframes check` beforehand gave 0 errors and 0 warnings. The render log carries 9 compiler "sparse keyframes" warnings on the takes, the same as every draft; no frozen frames have been found at any join since Task 10 |
| Soundtrack | one master WAV (`film/assets/audio/soundtrack.wav`), made by `audio/scores/make-master.py`: apple-pulse score + ocean bed at −10 dB + chime at 13.150 s, +1.49 dB to −16 LUFS, then a 4× oversampled limiter at −1.7 dBFS. The delivered audio matches the master to a gain of −0.04 dB, and the residual is 29.5 dB below the programme (AAC coding only). It matches the approved preview `bgm-preview-1-apple-pulse.mp4` with lag 0 |
| Chime | Cross-correlation places the chime at **13.150 s** in the delivered file (release.t = 13.15). The 560–920 Hz band (the chime's D5/A5 range) jumps **+13 dB** at 13.17 s (−36.2 to −22.9 dB). In the 0.5 s after the release, the chime is **+4.7 dB K-weighted over the music** (−19.7 vs −24.4 LUFS) and +4.3 dB over music + bed. The peak margin is +4.8 dB. The music sits 8.2 dB (K-weighted) lower than in the 0.5 s before the release. With the chime, the delivered window reads −18.4 LUFS; without it, music + bed read −24.0 |

## Audit of v1

Each scene is graded as a whole (**bold** verdict). The sub-rows grade each promise inside the scene.

| # | Script promise | What the delivered file shows (still) | Verdict |
|---|---|---|---|
| 0 | Opening: "Catch ideas before they *drift away.*" | `card-opening` (1.40 s): "Catch ideas before / they *drift away.*". "drift away." is italic in the pale accent, on the living ocean with the portal ring | **MET** |
| C1 | Card "Catch it *in seconds.*" | `card-card-catch` (4.90 s): "Catch it *in seconds.*" | **MET** |
| 1 | **Catch** | | **MET** |
| 1a | Starts on the Home Screen with Quick Capture (medium) and Resurfacing widgets | `extra/t6.2` (6.20 s): Resurfacing widget "Warm to cool, not a filter · 1 week ago" above "Oryne: Fast Capture" (Thought / Whisper) | MET (see the continuity note under "Minor notes") |
| 1b | Tap the widget's Thought button | `cue-catch-0` (6.68 s): the dot is on **Thought** | MET |
| 1c | Type the line live; the full line is readable before release; the dot never covers it | `payoff-catch` (12.85 s) and `cue-catch-1` (13.03 s): "The room feels slower when the light turns warm." is complete and uncovered. The dot is on **Release** | MET |
| 1d | Chime on the release frame | Audio: chime at 13.150 s, +4.7 dB K-weighted over the music | MET |
| 1e | Two wide, flat rings open on the water behind the phone | `release` (15.35 s): two flat rings under the release words. `extra/t13.55`: the first ring under the phone during the pull-back | MET |
| C2 | Card "Watch it *find its place.*" | `card-card-currents` (15.75 s): exact words. The release words and a ring are still sinking at lower left | **MET** |
| 2 | **Find its place.** Original: the new thought joins the Light And Color current. Revision 1: the result card names the neighbour, then the neighbour's current | | **DEVIATES** (changed by direction, Revision 1). Every Revision 1 payoff is MET |
| 2a | "Understood as … · Drifts near "<a Light And Color thought>"", held ≥ 2 s | `extra/t19.0` (19.00 s): "Understood as / **Warm Light Slows Time** / Drifts near "Golden hour on the walk home"". The card is on screen from about 17.75 s to 21.75 s, roughly 4 s | MET |
| 2b | Tap the Light And Color current | `cue-currents-0` (24.68 s): the dot is on the **Light And Color** orb | MET |
| 2c | The Light And Color sheet with the neighbour in it, held ≥ 2 s | `payoff-currents` (26.72 s): "Light And Color · 4 thoughts drift here": Desk at 6pm, Warm to cool not a filter, **Golden hour on the walk home**, Sunset gradient study. The final framing holds about 1.97 s, or about 2.4 s counting the fade | MET (the 2 s minimum is only just cleared) |
| C3 | Card "*Get it back.*" | `card-card-resurface` (29.12 s): "*Get it back.*", all italic | **MET** |
| 3 | **Get it back** | | **MET** (sub-row 3d is PARTIAL) |
| 3a | Home Screen, with the Resurfacing widget showing today's pick (an older seeded thought) | `cue-resurface-0` (30.90 s): "Resurfacing · Apple Design Principles · The HIG contains guidance… · 2 weeks ago" | MET |
| 3b | Tap the Resurfacing widget | `cue-resurface-0`: the dot is on the widget | MET |
| 3c | That thought opens with its age and nearby thoughts, held ≥ 2 s | `payoff-resurface` (33.93 s): the HIG text · "Captured **3 weeks ago**" · Themes: user experience, interface design · Nearby thoughts: A button that doesn't need a label, Are.na Editorial, Warm to cool not a filter (the 4th row, Desk at 6pm, sits below the frame edge at this framing). It is on screen from about 31.25 s to 34.5 s, roughly 3 s | MET |
| 3d | The ocean's warm sun rises behind the phone | `extra/t32.6`: only a faint warm glow at the phone's edges. Measured beside the phone, R−B rises from +3.5 to +5.8 between 31.0 and 33.5 s. At s 1.9 the phone covers most of the sun | PARTIAL |
| C4 | Card "Ask what it *all means.*" | `card-card-ask` (36.33 s): exact words | **MET** |
| 4 | **Ask** | | **PARTIAL** |
| 4a | Ask tab, Synthesis mode | `payoff-ask`: the Synthesis segment is selected ("See the thread running through") | MET |
| 4b | Type the question and send | `cue-ask-0` (38.11 s): the dot is on the input. `cue-ask-1` (42.36 s): "What keeps pulling me toward warm light?" is typed, and the dot is on **Send** | MET |
| 4c | The on-device answer composing, held ≥ 2 s at its final state | `payoff-ask` (48.25 s): question bubble, then the answer "What keeps pulling you toward warm light? / The fragments are all about light and color, and how they change, and how you want to capture them. They're also all about design and interface, about how you want to see the world. The fragments are all about how you want to…". The composing steps show "Reading across your currents…" at 44.3–45.3 s and the answer appearing at 46.2 s. The final state holds from about 46.7 s to the fade at 48.85 s, roughly 2.1 s | MET (the answer reads thin and repeats itself; see "Deviations") |
| 4d | …"with its sources" | Only the pill "Found 8 fragments that drift near this" appears, for about 0.5 s (45.75 s). No source list is ever on screen: the answer runs under the input bar, and in the take the keyboard stays up and hides the rest | PARTIAL |
| E | End card: mark → "Oryne" → "Now on the App Store" → official black badge; no price | `end` (52.25 s): mark, "Oryne", "Now on the App Store", black "Download on the App Store" badge. No price | **MET** |
| S | Sound: website ocean ambience + chime; original script said "No music" | Apple-pulse score with the ocean bed at −10 dB underneath and the chime on the release frame | **DEVIATES** (changed by direction, Revision 2) |

**Counts (10 graded rows: opening, 4 cards, 4 scenes, end card):** 8 MET · 1 PARTIAL (scene 4) · 1 DEVIATES (scene 2, by direction) · 0 CONTRADICTED · 0 MISSING.
Sub-promises: 14 MET and 2 PARTIAL (3d the warm sun; 4d the sources). The sound row is a separate DEVIATES by direction.

## The gulfs (ranked)

1. **Ask never shows its sources (4d, PARTIAL).** Scene 4 promises an answer "with its sources". The film shows the answer and a 0.5 s "Found 8 fragments" pill, and nothing more. The answer also reads thin: the model repeats "The fragments are all about…".
2. **Scene 2 shows a neighbour, not the new thought joining a current (DEVIATES, by direction).** The idea "related thoughts gather on their own" is carried by the "Drifts near" card and the neighbour's current, never by the new thought appearing inside it. The card title "Find its place" still fits, and Malik approved this chain in Revision 1.
3. **The warm sun barely reads (3d, PARTIAL).** It rises as specified, but at the Revision 2 framing (s 1.9) the phone covers it.

## Root causes

| Gap | Cause | Who can fix it |
|---|---|---|
| 4d sources not shown | **Capture/product.** After send, the Ask keyboard stays up (tap and swipe don't dismiss it) and covers the source list. The source list was never on screen in take C | Needs a retake after an app change, or a keyboard dismissal the app supports |
| 4c answer reads thin | **Capture/product.** This is Apple's on-device model output on the seeded data. The spec's fallback says to ship it as is and say so | App/model, not the edit |
| 2 deviation | **Product.** Currents are keyed by the exact first-theme string (`OceanLayout.currentKey`). The seeded theme "light and color" is hand-written, while new thoughts get free-form model themes, so a new thought cannot join a seeded current | App change, then a retake |
| 3d faint sun | **Editing.** The deeper camera (Revision 2, s 1.9) covers the part of the ocean where the sun rises | Fixable from existing footage (see "Remaining gaps") |

## Deviations from the original script (all carried on purpose, recorded here)

- **Scene 2, Revision 1.** The film shows the result card "Understood as Warm Light Slows Time · Drifts near "Golden hour on the walk home"", then the Light And Color sheet (4 thoughts, the neighbour among them), not the new thought inside the current. The typed line is **unchanged** ("The room feels slower when the light turns warm."); no fallback line was needed, because its neighbour is a Light And Color thought. Scene 2 runs 10.97 s against the revised ~11 s.
- **Resurfacing pick: Apple Design Principles.** The rig expected "Warm to cool, not a filter". The widget only refreshes at midnight and held a stale node after reseeding, so resizing it (small → medium) forced a fresh timeline, and the real fresh pick was Apple Design Principles. It was kept as found.
- **Scene 3 cuts across the cold launch.** Take B is a cold launch, because a warm-app tap only brings the Ocean forward. The edit hard-cuts from the widget press (the dimmed launch zoom) to the thought sheet sliding up, and skips the black launch screen and grey flash. Scene 3 runs 4.82 s against the ~9 s target.
- **Ask keyboard hides the sources** (see 4d). The camera frames the question bubble and answer body above the keyboard.
- **Ask used Apple's on-device model** (prose, not the offline composed template). The question is **unchanged** ("What keeps pulling me toward warm light?") and cleared the 0.70 floor ("Found 8 fragments").
- **Deeper camera (Revision 2).** Taps and payoffs are framed at s 1.9–2.3, the resting framing is ≥ 1.3, and the camera pulls back briefly at the release. App body text renders 37–42 px on the canvas.
- **Music added (Revision 2; the original said "No music").** Score 1, apple-pulse (A major, 123.19 BPM, release on the beat), with the ocean bed at −10 dB, the chime on the release frame, a ~6–8 dB music dip under the chime and ducks into each card. The master is −15.9 LUFS / −1.7 dBTP.
- **Length:** 54.25 s against the ~56 s target (inside the 45–60 s window). Slot timings follow the measured takes, not the target table.

## Product issues found while filming (for the app, not the edit)

1. **Currents can't be joined by new thoughts.** New captures get free-form model themes, and currents are keyed by the exact first-theme string, so a new "light" thought never joins the seeded "light and color" current.
2. **Warm widget deep link.** With the app running, tapping the Resurfacing widget only foregrounds the Ocean. The `oryne://node/<uuid>` deep link does not open the thought.
3. **Widget stale until midnight.** After a reseed, the Resurfacing widget keeps a stale node ID until its midnight refresh. The same film shows this: scene 1's widget reads "Warm to cool, not a filter", and scene 3's reads "Apple Design Principles".
4. **Age mismatch.** The Resurfacing widget says "Apple Design Principles · **2 weeks ago**", and the detail says "Captured **3 weeks ago**". Likewise, scene 1's widget says "Warm to cool, not a filter · **1 week ago**", and the Light And Color sheet lists it as "**2 weeks ago**".
5. **Ask keyboard stays up after send.** Tap and swipe don't dismiss it, and it hides the rest of the answer and its sources.

## Minor notes (known, accepted for v1)

- **Release words pass behind the phone during the pull-back.** At about 13.3–14.3 s, "The room feels slower when the l…" is cut by the phone's left edge (`extra/t13.55`). From about 14.8 s (+1.7 s after release) they are fully clear (`release`).
- **Sheet hold ≈ 2 s.** The Light And Color sheet holds about 1.97 s at its final framing, or about 2.4 s counting the fade. The Ask final state holds about 2.1 s. Both only just clear the 2 s minimum.
- **Bezel mildly soft at the deepest zoom** (currents card, s 2.3). The silver rail's edge is a 4–6 px gradient: the site's phone frame is upsampled about 1.44×. There is no stair-stepping, and the corners match.
- **Small app caption text is 18–24 px** ("Understood as", "Drifts near …", row meta). This comes from the app's type scale; even the 2.4× native cap would only reach about 25 px.
- **Currents idle stretch.** After the result card fades (about 21.75 s), the Ocean holds with no action until the tap at 24.68 s, about 2.9 s.
- **Scene 1 and scene 3 widgets disagree** (product issue 3). A viewer who watches the Home Screen closely sees two different Resurfacing picks.
- The small dots around the Light And Color orb are the app's own UI. The film layer has no dots.

## Resolutions applied in v1 (vs approved draft v5 + chosen score)

- **Soundtrack integrated.** The two `<audio>` elements (bed, chime) in `index.html` are replaced by one `<audio id="soundtrack">` (`assets/audio/soundtrack.wav`, 0 → 54.249 s, volume 1). The master is built by `audio/scores/make-master.py`, the same recipe as the approved preview. The test (`test-assemble.mjs`) now asserts the soundtrack element and the absence of separate bed/chime elements. It failed first, then passed (12/12).
- **Delivery render** at 60 fps and delivery quality with deterministic flags (software GL, PNG frames, 1 worker).
- The picture is unchanged from draft v5: cards, words, cuts, camera and ocean are all the same. Only `film/index.html` changed on regeneration.

## Verification (from the delivered file)

- ffprobe and loudness: see "File facts". 2560×1440, 60/1, 54.250 s, one AAC stream, −15.9 LUFS, −1.7 dBTP.
- Chime: at 13.150 s by cross-correlation (ncorr 0.79). Band jump +13 dB at 13.17 s. K-weighted margin +4.7 dB, identical to the approved preview's +4.7 dB.
- All 17 `stills.mjs` stills (6 cues, 4 payoffs, 5 cards, the end card, the release still) plus 4 extra full frames (6.2, 13.55, 19.0, 32.6 s) were read at 2560×1440. Hold durations were read from 3 contact sheets (currents, resurface, ask). Every tap dot lands on its control; every card reads its exact words.

## Remaining gaps (unfixed, with what would close each)

| Gap | Type | What closes it |
|---|---|---|
| 4d, Ask sources not shown | Capture | An app build where the keyboard dismisses after send (or a scroll to the sources), then a retake of take C that holds on the source list for ≥ 2 s |
| Answer reads thin and repeats | Capture/product | A better on-device prompt, or the composed answer, then a retake of take C. Ship v1 as is, per the fallback |
| Scene 2, new thought never shown inside a current | Capture/product | An app change so new thoughts can join a seeded current (theme normalisation), then a retake of take A showing the Light And Color sheet with "The room feels slower…" in it |
| 3d, warm sun faint | Editing | A camera change in `takes/cuts.json` (resurface key at t 2.3: s 1.9 → about 1.5, or delay that key until the sun is up at about 32.5 s), then re-render. This trades against Malik's "more interface" note |
| Widgets disagree between scenes 1 and 3 | Capture | Re-film take A after the widget has refreshed (resize small → medium after the seeded launch, as was done for take B), so both scenes show the same pick |
| Release words behind the phone | Editing | Start the pull-back earlier, or move the words' path further left (`ocean.html` / camera keys). Not done: approved as is in v5 |
