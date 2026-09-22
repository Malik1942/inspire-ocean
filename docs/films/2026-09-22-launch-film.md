# Oryne — Launch film (HyperFrames)

**Date:** 2026-09-22 · **Branch:** `am/oryne-launch-film` · **Status:** design approved in chat (2026-09-22); this written script awaits Malik's review. No capture and no render before that.

Working files live in `~/Desktop/oryne-launch/`. This is the first Oryne film built with HyperFrames (HTML → MP4) instead of the product-film Swift compositor. The product-film taste and engineering laws still apply unless this script overrides them.

```
FILM: Oryne launch film
SURFACE: iOS app, iPhone 17 Pro simulator, English, Debug build of inspire-ocean @ f4f698e
PLACEMENT: official website, YouTube, portfolio, X (the file is delivered; nothing is posted)
CANVAS: 2560x1440, 60 fps
TARGET LENGTH: ~56s (window 45–60s)
VIBE: the website brought to life — calm, spatial, breathing; one continuous ocean behind the phone
  biggest moment: the thought released into the Ocean (chime + two flat rings on the water)
  avoid: small dots/motes of any kind (trypophobia ruling on the site), all caps, the v23 pixel font,
         launch-ad punchiness, cross-dissolves, music

OPENING: Catch ideas before they *drift away.*
SCENES:
1. Catch — idea: one tap from the Home Screen, a thought is caught and let go in seconds
   start: iOS Home Screen holding Oryne's Quick Capture (medium) and Resurfacing widgets
   interaction: tap the widget's Thought button → Fast Capture opens typing-first →
                type "The room feels slower when the light turns warm." live → tap Release
   payoff: the full line readable before release (touch dot never covers it); chime on the release
           frame; two wide flat rings open on the water behind the phone
   data: screenshot seed (10 English thoughts); the line is entered live
   ~11s
2. Find its place — idea: related thoughts gather on their own, no folders   [revised 2026-09-22, see Revision 1]
   start: the Fast Capture sheet right after the release (same launch as scene 1)
   interaction: hold while the sheet turns into the app's "Understood as … · Drifts near "<neighbour>"" card,
                then tap the "Light And Color" current in the Ocean
   payoff: 1) the card naming the new thought's neighbour (a Light And Color thought), held ≥2s;
           2) the Light And Color sheet with that neighbour in it, held ≥2s
   data: seed "light and color" current (4 thoughts) + the scene-1 thought
   ~11s
3. Get it back — idea: a forgotten idea comes back on its own
   start: Home Screen, Resurfacing widget showing today's pick (an older seeded thought)
   interaction: tap the Resurfacing widget
   payoff: that thought opens with its age and its nearby thoughts, held ≥2s;
           the ocean's warm sun rises behind the phone
   data: seed (>3 live thoughts, one older than 2 days — satisfied)
   ~9s
4. Ask — idea: ask your ideas what they mean
   start: Ask tab, Synthesis mode
   interaction: type a question close to the light/color cluster (working draft:
                "What keeps pulling me toward warm light?") → send
   payoff: the on-device answer composing, with its sources, held ≥2s at the final state
   data: seed; answer engine = what the Release build does (Apple on-device model if the simulator
         has it, else the offline composed answer). No cloud key.
   ~11s
TITLE CARDS (one before each scene, ~2s each):
  1 "Catch it *in seconds.*"   2 "Watch it *find its place.*"   3 "*Get it back.*"   4 "Ask what it *all means.*"
END CARD (~5s): Oryne mark → wordmark "Oryne" → "Now on the App Store" → official black
  "Download on the App Store" badge (website/assets/img/badge-en.svg, unmodified). No price.
BRAND: Instrument Serif 400 for display, italic <em> accents as on the site; Inter 300–500 for small text
  (website/assets/fonts/*.woff2, OFL). Sentence case. Colors, lamps and breathing from the website
  (website/assets/css/site.css, assets/js/lamps.js, breath.js). Mobile path: website/assets/img/phone-frame.webp,
  glow off; screen cutout and corner radius measured from the PNG alpha and used for both the clip and the frame.
SOUND: the website's ocean ambience (sound.js: deep brown-noise bed, pink-noise swells per breath wave,
  white-noise wash at each crest), rendered offline with a fixed seed, swells locked to the same breath
  timeline as the lamps; plus the app's real OceanReceived chime on the release frame. No music.
```

`*…*` marks the italic accent. Every `~s` is a target; real lengths come from the measured takes.

## Revision 1 (2026-09-22): scene 2 after the first take

A live capture cannot join a seeded current: currents are keyed by the exact first-theme string
(`OceanLayout.currentKey` = `anchorThemeKey ?? themes.first`), the seed's theme is the hand-written
"light and color", and new thoughts get free-form themes from the on-device model ("light", "warmth"…).
The app's own "found its place" signal is the Fast Capture result card, "Understood as … · Drifts near
"<related thought>"". Malik chose to film that card, then the neighbour's current (Light And Color), as an
honest chain: new thought → its neighbour → the neighbour's current. Scene 2 becomes ~11 s. The typed line
stays as written if its neighbour is a Light And Color thought; otherwise the first fallback line
("Warm light at dusk makes the room feel slower.", which drifted near "Golden hour on the walk home").

## Timeline (targets)

| t (s) | Segment |
|---|---|
| 0.0–3.5 | Opening card |
| 3.5–5.5 | Card 1 → zoom-through |
| 5.5–16.5 | Scene 1, Catch |
| 16.5–18.5 | Card 2 |
| 18.5–27.5 | Scene 2, Find its place |
| 27.5–29.5 | Card 3 |
| 29.5–38.5 | Scene 3, Get it back |
| 38.5–40.5 | Card 4 |
| 40.5–51.5 | Scene 4, Ask |
| 51.5–56.5 | End card |

Cards sit on the living ocean (lamps keep breathing), not on black. Handovers are zoom-throughs; no dissolves, no side pushes.

## Capture

App code, seed and assets are not modified.

- Build: `xcodegen generate`; `xcodebuild -scheme Oryne` for an iPhone 17 Pro simulator, Debug.
- Launch env via `SIMCTL_CHILD_`: `OCEAN_SCREENSHOT_SEED=1` (wipes and reseeds on every launch, marks onboarding done), `OCEAN_START_TAB` per scene; `-AppleLanguages '(en)'`. `OCEAN_SHOW_PERF` stays off.
- Status bar: `simctl status_bar booted override --time 9:41` with full signal and battery.
- Widgets: place Quick Capture (medium) and Resurfacing (medium) on the Home Screen once, before any take, by driving the simulator UI. Resurfacing only fills after a seeded launch.
- Deep links available as fallbacks: `oryne://capture/thought`, `oryne://node/<uuid>`.
- Record: `xcrun simctl io booted recordVideo --codec h264 <take>.mov`; stop by signalling the real simctl process and wait for finalization (product-film mistake row). Check size > 0.
- Scenes 1 and 2 are one continuous launch (the seed resets per launch). Scenes 3 and 4 are separate launches.
- Ingest: conform each take to constant 60 fps before anything else; extract a frame from every take to confirm its content before cutting.
- Measure: frame-scan every take for the real tap frames and payoff frames. Trims, cue times and camera keyframes come from these measurements, never from planned timings.

First-take checks, before building around them:
- Scene 1's line actually joins "light and color" (the app's embeddings decide). If not, reword the line toward that current and retake; never fake the grouping.
- Scene 4's question clears Ask's 0.70 similarity floor. If Ask answers "nothing matches", rephrase toward the light/color thoughts.
- Scene 3's pick is readable and makes sense on its own. The pick can't be chosen without changing the seed; if it is weak, report it rather than editing the seed.

## Build (HyperFrames)

Project at `~/Desktop/oryne-launch/film/`, `hyperframes init --non-interactive`, 2560×1440, `data-fps` 60. Every scene is a sub-composition (`data-composition-src`), one element kind per track.

| File | Job |
|---|---|
| `compositions/ocean.html` | The website's lamps and breath ported to a timeline-driven, seeded form (no `Date.now`, no `Math.random`, no rAF clock). Carries the portal lamp, the four current pools, the rising sun and the release rings. Lowest track, spans the film. |
| `compositions/phone.html` | `phone-frame.webp` with the take as `<video muted>` inside the measured cutout, clipped to the measured radius. |
| `compositions/beat-catch.html`, `beat-currents.html`, `beat-resurface.html`, `beat-ask.html` | One take each: trim, camera (GSAP scale/translate on the phone group: to the tap, out to the payoff), touch-dot cue timed to the measured tap frame, with a visible press and ripple before every reveal. |
| `compositions/card-*.html`, `end.html` | Cards in Instrument Serif and Inter from the site's woff2 files; words rise and settle like the site's headlines. |
| `index.html` | Root timeline: places everything on the table above; zoom-through handovers. |

Camera moves only to show something: no idle drift. The phone frame is 900×1840; at hero size it renders around 1150 px tall, so any punch past about 1.6× upsamples the bezel. If the bezel softens visibly, switch to product-film's `assets/iphone-17-pro-silver.png` (1120×2289) and re-measure its cutout.

## Sound

- `~/Desktop/oryne-launch/audio/ocean-bed.mjs` (working folder, not the repo): an offline port of `website/assets/js/sound.js` with a seeded noise generator. Deep: brown noise → lowpass 220–420 Hz. Swell: pink noise → lowpass swept about 380 → 1600 Hz and back, stereo pan per wave, envelopes on the same breath-wave timeline `ocean.html` uses. Wash: white noise → highpass 2.5 kHz, a short hiss at each crest. Output `ocean-bed.wav`, film length, fades in at the start and out under the end card.
- Chime: `python3 tools/generate_ocean_received.py --wav-out <workdir>/chime.wav --out <workdir>/chime.caf`. Never run with the default `--out`, which writes into the app bundle.
- Both are placed as `<audio>` in `index.html` and mixed there (`hyperframes-audio`). The chime lands on the scene-1 release frame; the bed dips slightly under it. Master peak about −1 dBTP; the bed sits well below the chime.

## Verification and delivery

1. `hyperframes check` passes with zero errors; warnings reviewed.
2. Render `--quality delivery`; ffprobe confirms 2560×1440, 60 fps, audio present, length within 45–60s.
3. Every card read at full resolution against this script's exact words; card ink centroid measured within a few px of canvas centre.
4. Stills at every tap cue (dot visible, on the right control) and every payoff (proof readable, held ≥2s).
5. Lamps checked for determinism: the same frame rendered twice is identical.
6. Gap audit per product-film `references/gap-audit.md`: each scene graded MET / PARTIAL / CONTRADICTED / MISSING / DEVIATES from extracted frames, split into editing gaps and capture gaps. Delivered with the film.

Deliverables: `~/Desktop/oryne-launch/renders/Oryne Launch v1.mp4` and the audit.

## Fallbacks

| Risk | Fallback |
|---|---|
| Lamp port can't be made seek-safe | CSS radial-gradient lamps animated on the GSAP timeline, same cast and sizes; reported |
| Widget placement can't be driven in the simulator | Scene 1 starts on the Home Screen without the widget and opens via `oryne://capture/thought` with a tap cue on the app icon; scene 3 opens via the in-app Resurfacing banner. Reported as a capture gap |
| On-device Ask answer reads thin | Ship it as is and say so in the audit; no cloud key |
| Phone bezel softens at punch depth | Swap to `iphone-17-pro-silver.png` |

## Out of scope

A 9:16 cut, Chinese version, voice capture, music, posting anywhere, changes to the app or the website.
