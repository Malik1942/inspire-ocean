# Oryne Official Website — Design Spec

**Date:** 2026-09-18 · **Branch:** `am/oryne-official-website-08655b` · **Status:** approved (2026-09-18); revised 2026-09-19 after visual review (see Revision 1)

## Goal

The official product website for Oryne: a real product page (in the mould of
Apple's app pages and Notion's product pages) that shows **what Oryne can do**
and **who it is for**, wrapped in Oryne's own atmosphere: black, spatial,
breathing, ocean, waves, and sound.

## Decisions (from brainstorming, 2026-09-18)

| Decision | Choice |
|---|---|
| Where | New top-level `website/` folder in this repo |
| Stack | Plain HTML, CSS, JS (ES modules). No dependencies, no build step. Deployable to any static host |
| Languages | English + 简体中文 at launch |
| App Store | Live; URL to be supplied (placeholder until then). CTAs use Apple's official black "Download on the App Store" badge (English and Chinese), unmodified |
| Price | Free for now, may change: the site does not mention price anywhere at launch |
| Pages | Landing + Privacy + Support, in both languages |
| Direction | **A. The Descent**: one continuous ocean behind the page; scrolling descends; a few large lights re-choreograph per chapter; real app screens; a release-a-thought moment with the app's chime |
| Type (Revision 1) | Instrument Serif for headlines, with italic accents in English; Inter for text; both self-hosted woff2 under the SIL Open Font License. Chinese: Songti SC headlines, PingFang body |
| Lights (Revision 1) | Only large circles: the portal lit like a sunset lamp, four big out-of-focus pools, one rising sun, and huge blurred glows. Never small dots |
| Content voice | **A product website, not a case study** (Malik, mid-brainstorm): lead with capabilities and use cases; philosophy shows up as product promises, never as essay |

## Revision 1 (2026-09-19): visual review

Malik's feedback on the first build: the English font was "too plain and too
bold, not premium at all", and the small bubbles read as trypophobic
(密集恐惧症): blur them or remove them, keep only large circles like a sunset
lamp with a halo at the edge; the background may hold different, heavily
blurred glows, but nothing small. He chose Instrument Serif, self-hosted.

What changed, superseding the older text below where they disagree:

- **Type.** Instrument Serif 400 for display, headlines, card, panel, FAQ, and
  policy titles, with italic `em` accents in English headlines (Chinese keeps
  them upright). Inter 300 to 500 for text: leads and body copy 300, labels
  and buttons 500, nothing at 600. Chinese headlines fall through to Songti
  SC (the fonts carry a Latin `unicode-range`), body to PingFang.
- **No small lights anywhere.** No motes, stars, dotted trails, or source
  dots; no words drawn in the water. Every visible light has a radius of at
  least 60 pt (`MIN_LAMP`, tested).
- **Sunset-lamp lights.** In focus, a lamp is a flat disc of light, warm in the
  middle and deeper in color toward a soft edge, with a halo band glowing
  around that edge. Out of focus it is only a pool of light with no edge and
  no ring. The portal behind the hero phone is the largest lamp: a disc that
  shades from moonlit lilac at the top to dusk at the waterline, edge glowing.
- **Cast.** Four currents as large out-of-focus pools that drift at the edges
  and gather around the Currents phone; one warm sun that rises out of the
  depth behind the Resurfacing widgets and comes into focus; four huge
  blurred glows in the water per chapter.
- **Vignettes** use the same large lights (a pale light setting into the
  water, three pools gathering, a sun rising, one light with its answer),
  with every edge faded out.
- **Release demo.** The words sink inside a large soft light, then two wide,
  flat rings open on the water.

## Non-goals

Blog, changelog, press kit, waitlist or newsletter, analytics, CMS, deployment
(host and domain chosen later), Apple Watch (branch not merged), localized
app screenshots, testimonials, logos, or usage numbers (none exist yet, and
none will be invented).

---

## 1. Information architecture

Reference patterns (surveyed 2026-09-18: notion.com, notion.com/product/calendar,
apple.com/ios, apple.com/apple-books, mymind.com): a slim product bar with one
download action; verb cards right after the hero; one chapter per capability
with sentence-titled items and one phone screen each; varied pacing (big rows,
then text-only minis); use cases by role and moment; privacy as a short list of
what we leave out; an "and more" icon grid; a short FAQ; one final call to
action. Avoided: logo walls, testimonials, statistics, competing CTAs, feature
sprawl with footnotes.

### Product bar (sticky, all pages)

`Oryne` lockup · Features (`#how`) · Use cases (`#use-cases`) · Privacy
(`#privacy`) · FAQ (`#faq`) · language button · Sound toggle · **Download**
(App Store URL). The hero's Listen button and the Sound toggle share one
state. Under 720px wide the section links collapse away; lockup, language,
sound, and Download remain.

The language control is **one button** (Revision 2, 2026-09-20): a capsule
with a globe and the language it switches to ("中文" in English, "English" in
Chinese), labelled for screen readers in the page's own language and carrying
`data-lang-switch` so the choice is remembered. The footer keeps both
languages as plain links.

### Landing page, top to bottom

| # | Section (`id`) | Pattern | Visual | Water (choreography) |
|---|---|---|---|---|
| 1 | Hero (`top`) | two-part benefit line, one sentence naming inputs, App Store button, Listen | phone with the real Ocean screen, standing inside the breathing ring | the portal breathes, lit like a sunset lamp |
| 2 | How it works (`how`) | four verb cards: Capture · Gather · Resurface · Ask, each linking to its chapter | a small live vignette per card | four large pools of light drift at the edges |
| 3 | Capture (`capture`) | chapter: label, headline, intro, 5 sentence-titled items, **Try it** release demo | real Capture screen | your released thought sinks inside a large soft light, and the water opens in wide rings, with the chime |
| 4 | Currents (`currents`) | chapter, 3 items | real screen inside one current (its stream) | the pools gather around the phone as you scroll; scrolling back loosens them |
| 5 | Resurfacing (`resurface`) | chapter, 3 items | HTML rendition of the Resurfacing widget | one warm sun rises from the depth behind the widgets and comes into focus |
| 6 | Ask (`ask`) | chapter, four mode tiles | real Ask screen (answer + source chips) | the pools sink low; the glows cool |
| 7 | Grow and find (`grow`) | two side-by-side panels: Branch, Library | real node-detail and Library screens | the pools settle, faint |
| 8 | Use cases (`use-cases`) | tabs by role, each panel a moment + example thought cards | HTML thought cards (glass, like `NodeCard`) | ambient, deeper |
| 9 | Why Oryne (`why`) | "Not another notes app." comparison table | two-column table | ambient |
| 10 | Privacy (`privacy`) | promise list + link to the policy | icons | ambient, darker |
| 11 | And more (`more`) | icon tile grid of secondary features | inline SVG icons | ambient |
| 12 | FAQ (`faq`) | `<details>` accordion, 6 to 7 questions | none | still |
| 13 | Final CTA (`download`) | one line, App Store button | phone (Capture screen), faint ring | still and deep |
| — | Footer | Privacy · Support · language · © 2026 Oryne | | |

### Privacy page and Support page

Same bar, footer, type, and water, but the water is **still** (no choreography,
one render) and the text column is long-form and readable (max 68ch English,
38em Chinese).

---

## 2. Copy (English draft; final wording may be polished in implementation)

Voice: confident and clear like Apple, calm like Oryne. Short sentences.
**No em or en dashes anywhere in site copy** (house rule). No hype words
("supercharge", "revolutionary", "10x"), no streak or count framing. Every
claim appears in the claims ledger (§9). Lines reused from the app are marked
**(app)**; their Chinese comes from `Localizable.xcstrings`.

**Meta.** Title: "Oryne: catch ideas before they drift away". Description:
"Oryne is a calm home for your thoughts, voice notes, screenshots, and links.
Related ideas gather on their own, and forgotten ones come back. For iPhone
and iPad."

**1 · Hero.** Eyebrow "For iPhone and iPad". H1 **"Catch ideas before they
drift away."** Sub "Oryne is a calm home for your thoughts, voice notes,
screenshots, and links. Related ideas gather on their own, and forgotten ones
come back when they matter." Buttons: "Download on the App Store", "Listen".

**2 · How it works.** Cards (label, benefit line, one sentence, "Learn more"):
- Capture · "Catch it in seconds." · Voice, text, screenshots, and links, from anywhere on your iPhone.
- Gather · "Watch it find its place." · Related thoughts drift together into currents. No folders, no tags.
- Resurface · "Get it back." · One forgotten idea returns each day, right when it might matter.
- Ask · "Ask what it all means." · Question your own ideas and see the thoughts behind every answer.

**3 · Capture.** Label "Capture". H2 **"Catch it the moment it arrives."**
Intro "Speak, type, snap, or share. Oryne takes the thought exactly as it
comes and never asks you to file it first." Items:
1. **Press and speak.** Set the Action Button or the Control Center button to Fast Capture. Oryne opens already listening.
2. **Talk in the language you think in.** Your words appear as you speak. If your iPhone is set up for two languages, Oryne listens for both.
3. **Screenshot it, then say why.** Screenshot + voice keeps what was on your screen together with a spoken note.
4. **Share from any app.** Send links, images, and text to Oryne from the share sheet. Links arrive with their title and preview.
5. **Or just ask Siri.** "Hey Siri, add an inspiration to Oryne." Your thought is saved without opening the app.

(Siri phrases ship in English only, so the Chinese page points to the localized Shortcuts action 记录灵感 instead of promising a Chinese Siri phrase.)

Try it: small label "Try it here". Input placeholder **"What just drifted
by?" (app)**, button **"Release" (app)**, confirmation **"Drifted into the
Ocean" (app)**, note "This demo stays on this page. Nothing is sent anywhere."

**4 · Currents.** Label "Currents". H2 **"Your ideas organize themselves."**
Intro "Oryne reads what each thought is about and gathers related ones into
currents. You never make a folder, pick a tag, or decide where something
goes." Items:
1. **Grouped by meaning, not keywords.** A sunset photo and a note about warm light end up together, even when they share no words.
2. **One thought, many currents.** Ideas overlap, so a thought can belong to more than one current. Folders can't do that.
3. **Titled for you.** Every thought gets a short title, written on your device. Change it, and it stays yours.

No words are drawn in the water (Revision 1): the current's name is on the
phone screen, and the four pools around it carry the colors of the
screenshot seed's currents.

**5 · Resurfacing.** Label "Resurfacing". H2 **"The ideas you forgot come
back."** Intro "Every day, one thought you haven't seen in a while rises to
the surface. Not a reminder, not a task. Just a good idea, back in view."
Items:
1. **One a day, on your Home Screen.** The Resurfacing widget shows the day's thought on your Home Screen or Lock Screen.
2. **Connected to what you're exploring now.** Older thoughts that share a current with your latest ones get a gentle lift.
3. **Never the same one on repeat.** A thought you just revisited rests for a while before it can rise again.

The rising sun carries no label; the widgets in front of it show the thought, "Ideas arrive in the shower" (the app's own example).

**6 · Ask.** Label "Ask". H2 **"Ask your ideas anything."** Intro "Oryne
answers from the thoughts you've caught and shows which ones it used, so
every answer leads back to your own words." Mode tiles:
- **Search.** Find the thought you half remember.
- **Synthesis.** See what a pile of notes adds up to.
- **Expansion.** Take an idea somewhere new.
- **Research.** Look beyond your notes, clearly marked as outside your Ocean.

Footnote line: "Answers are composed on your device, with Apple Intelligence
on supported models."

**7 · Grow and find.** Two panels.
- Label "Branch". H3 **"Grow an idea without losing the original."** Branch any thought into a question, a concept, research, or a project. The original stays exactly as you wrote it.
- Label "Library". H3 **"Everything, in order, when you want it."** Search every thought, filter by kind, and switch between Recent and Related.

**8 · Use cases.** Label "Use cases". H2 **"Made for the way ideas really
arrive."** Tabs and panels (moment line, then 2 to 3 example thought cards,
each with kind and current):
- **Designers.** Screenshot a palette on the bus and say what caught your eye. Your color studies gather into one current, ready when the project starts. Cards: "Sunset gradient study" (Image · light and color), "Warm to cool, not a filter" (Thought · light and color), "Desk at 6pm" (Image · light and color).
- **Writers.** Half a sentence on the train, a line overheard in a café. Oryne keeps the fragments until they are ready to become paragraphs. Cards: "The house kept its summer smell" (Whisper · writing: "Opening line? The house kept its summer smell long after we closed it up."), "Overheard at the café" (Thought · writing: "I only lie about small things. Character, not dialogue.").
- **Founders and makers.** The 2 a.m. product idea, the link worth keeping, the thing a customer said. Later, ask what you keep circling. Cards: "Half a sentence from the train", "A button that doesn't need a label", link "Apple Design Principles".
- **Students and researchers.** Quotes, articles, and questions. Branch any of them into research and ask what your sources share. Cards: link "Are.na Editorial", and its Research branch "What makes a collection useful?".
- **Everyday life.** Recipes, gift ideas, places to try. The small things you would otherwise lose. Cards: "Weeknight noodles" (Thought · cooking), "Fix the old radio for Dad" (Thought · gifts), "The dumpling place by the station" (Photo · places).

No music use case: confirmed-transcript audio expires after 30 days
(`expireConfirmedAudio`), so promising kept melodies would mislead.

**9 · Why Oryne.** H2 **"Not another notes app." (app)** Intro "Notes apps
help you write things down. Oryne helps you keep ideas alive." Table,
"A typical notes app" vs "Oryne":
- Saving an idea · Open the app, make a note, name it, pick a folder. · Press a button and speak.
- Staying organized · Up to you, forever. · Related ideas gather on their own.
- Old ideas · Sink out of sight. · Come back, one a day.
- Finding something · Guess the right keyword. · Ask in your own words and see the sources.
- Growing an idea · Edit over the original. · Branch it. The original stays.

**10 · Privacy.** Label "Privacy". H2 **"Your ideas stay yours."** Intro
"Oryne is built so your thoughts never have to leave your devices, and
there's no account to create." Promises:
- **Understood on your device.** Titles, themes, currents, and answers are worked out on your iPhone or iPad.
- **Synced with your own iCloud.** Your Ocean moves between your devices through your private iCloud.
- **No ads, no tracking, no analytics.** Not in the app, and not on this website.
- **Export everything, any time.** Take your whole Ocean with you as Markdown files.

Link: "Read the privacy policy".

**11 · And more.** H2 **"And there's more."** Tiles: Home Screen and Lock
Screen widgets · Control Center button · Siri and Shortcuts · Share from any
app · Link previews · iPhone and iPad, in sync · English and 简体中文 ·
Calm Accessibility Mode · Undo right after you capture · Export to Markdown ·
Apple Intelligence on supported models.

**12 · FAQ.** (no price question at launch)
- **Which devices does Oryne run on?** iPhone with iOS 18 or later, and iPad with iPadOS 18 or later. Answers written by Apple Intelligence need a model that supports it.
- **Do I need an account?** No. Oryne syncs through your iCloud, and works fully without it.
- **Where are my ideas stored?** On your devices, and in your private iCloud if you use it. We can't see them.
- **Does it work offline?** Yes. Capturing, currents, resurfacing, and Ask all work without a connection. Link previews need one, and so does voice transcription in languages your device can't transcribe on its own.
- **Can I use Oryne in Chinese?** Yes. Oryne speaks English and 简体中文. Choose in Settings › Oryne › Language.
- **Can I get my ideas out?** Yes. Settings › Export the Ocean saves everything as Markdown files, one per current.

**13 · Final CTA.** H2 **"Enter the Ocean." (app)** Sub "Your next idea is
on its way. Be ready for it." Button "Download on the App Store".

### Chinese

Parallel pages under `/zh/`. Lines marked (app) use the catalog Chinese:
不是又一个笔记应用。 · 刚刚闪过什么？ · 汇入 · 已汇入海洋 · 潜入海洋
New lines are written by meaning per `docs/localization-glossary.md`
(海洋, 灵感, 语音, 库, 提问, 延展, 汇入, 捕捉, 碎片, 再次浮现; "drift" by sense,
not 漂), full-width punctuation, no 「——」. Every new Chinese line is listed in
the handoff for Malik's review.

---

## 3. Architecture

```
website/
  index.html  privacy.html  support.html          English
  zh/index.html  zh/privacy.html  zh/support.html  简体中文
  assets/
    css/site.css          tokens, layout, components (one stylesheet)
    js/breath.js          shared breathing clock (pure)
    js/choreo.js          chapter + progress → light targets and glows (pure)
    js/lamps.js           the sunset-lamp disc and out-of-focus pool, shared by the water and vignettes
    js/ocean.js           the fixed water: WebGL body + glows, 2D portal, waves, lamps
    js/vignettes.js       the four small "How it works" card visuals
    js/sound.js           Web Audio: ambient ocean + chime
    js/site.js            wiring: scroll, language, sound toggle, tabs, release demo
    audio/ocean-received.m4a
    fonts/  Instrument Serif (roman, italic), Inter (variable 300 to 600), OFL.txt
    img/  icon, favicons, og image, screens/*.webp (+ .png fallback)
  tests/                  node --test suites for breath.js and choreo.js
  tools/check.py          static checks (stdlib only)
  README.md               preview, deploy, placeholders, how assets were made
```

### Module contracts

- **`breath.js`** — `breathAt(t) → { level 0..1, index }` and
  `wavesBetween(t0, t1) → [{ start, rise, fall, peak, pan }]`. Deterministic
  from a fixed seed: wave *i* lasts 8.5 to 11 s (rise ≈ 40%), peak 0.75 to 1.
  One clock for sight and sound, so the ring, the wave lines, and the audio
  swells rise together. Individual lamps keep their own breathing (as in the
  app, no two in step).
- **`choreo.js`** — `layout({ chapter, progress, next, blend }, lamps, view) → targets[]`
  where a target is `{ x, y, r, alpha, soft, warmth }`; `glowsFor(state, view)`
  gives the four water glows; `ringsFor(view)` the portals. Pure; knows
  chapters by name; `view.anchors` are DOM rects passed in by `site.js`
  (phones, widgets) and `view.calm` the text blocks a light only whispers over.
- **`lamps.js`** — `drawLamp(ctx, { x, y, r, alpha, soft, palette, warmth })`:
  in focus a flat disc with a soft edge and a halo glowing around that edge;
  out of focus a gaussian pool with no edge or ring. Palettes moon, dusk,
  lilac, amber. (Replaces the orb sprites and the "no halos" rule; Revision 1.)
- **`ocean.js`** — `createOcean({ water, field, grain, policy }) → { setScene, setPolicy, release, resize, refresh, start, stop, stats }`.
  Owns all drawing; knows nothing of scroll, language, or DOM beyond its
  canvases and the rects it is handed.
- **`vignettes.js`** — `mountVignette(canvas, kind)` for capture, gather,
  resurface, ask (the onboarding mini-visual language). Runs only while
  visible (IntersectionObserver).
- **`sound.js`** — `createSound({ breath }) → { enable, disable, isOn, chime, setDepth }`.
- **`site.js`** — computes chapter and progress from scroll (rAF-throttled),
  passes anchors, handles language routing, the sound toggle, use-case tabs,
  and the release form. The only module that touches the DOM broadly.

---

## 4. Visual system

**Tokens** (from `OceanTheme`): abyss `#050508`, deep `#0d0e11`, mid
`#17181c`, current `#26282d`, surface `#3d3e45`; foam white 0.92, mist 0.50,
hint 0.58, faint 0.26 (decoration only); accent `#d1d6e0`; glowWarm `#f2ede0`.
The ring adds the icon's cool rim light (≈ `#9fb2d6` fading to white).

**Type** (Revision 1). Display: `"Instrument Serif", "Songti SC", "STSong",
"Noto Serif CJK SC", "Source Han Serif SC", "Noto Serif SC", Georgia, serif`
at weight 400 (H1 clamp 52 to 112px, H2 clamp 40 to 76px, leading about 1),
italic `em` accents in English. Text: `"Inter", -apple-system,
BlinkMacSystemFont, "Helvetica Neue", "PingFang SC", "Hiragino Sans GB",
"Noto Sans SC", "Microsoft YaHei", system-ui, sans-serif`; leads and body
copy at 300, labels and buttons at 500, never 600. Both web fonts are
self-hosted woff2 with a Latin `unicode-range`, so Chinese text uses Songti
and PingFang. Chinese: body leading 1.8, headline tracking 0.02em.

**Wordmark** (Revision 2, 2026-09-20). A lockup, not letterspaced text: the
icon's portal drawn as inline SVG (a ring lit brighter on its lower right, a
wave across its lower third, `currentColor`) next to `Oryne` in the display
serif at 25px, tracking 0.005em, 21px in the footer. It replaces the old SF
Medium at 0.18em, which read as plain and carried none of the brand.

**Surfaces.** Glass cards per `GlassCard`: white 0.04 to 0.06 fill,
`backdrop-filter: blur(20px)`, 0.5px white 0.08 hairline, 20px radius.
Buttons: primary is a capsule in accent with abyss text (the app's "Enter the
Ocean" button); secondary is a hairline capsule.

**Phone frame** (Revision 3, 2026-09-20). A silver iPhone mockup Malik
supplied (`assets/img/phone-frame.webp`), with the screen showing through its
opening: the CSS frames that came before it, in silver and then in black, both
got the buttons and the rail subtly wrong. The opening is inset 5.333% at the
sides and 2.5% top and bottom, and its aspect matches the screens exactly, so
nothing is cropped. The frame carries the island and the camera, so a
screenshot's own island sits behind it. The figure scales from one `--w` and
casts a `drop-shadow`, which follows the device's outline rather than a box.

**The water** (one fixed canvas pair behind every page):
- *Body:* WebGL fragment shader following `OceanBackground`'s grid (deep, mid,
  current; lit toward the upper center; abyss corners), the lit region roaming
  slowly (0.03 to 0.05 rad/s), gentle domain-warped noise for light through
  water, depth vignette. Rendered at 0.5 scale. A static grain overlay
  (runtime-generated tile, opacity ≈ 0.016) prevents banding. No WebGL: CSS
  gradient fallback.
- *Ring:* the icon's portal drawn in 2D, centered on the hero phone with a
  diameter of about 0.95× the phone's height, so the device stands inside it. Lit like a sunset lamp
  (Revision 1): a disc of light shading from moonlit lilac at the top to dusk
  at the waterline, its edge glowing and a halo spilling past it, painted once
  per size; the icon's hairline wave across the lower third. Breathes with `breath.level`
  (alpha 0.85 to 1, radius ±0.6%). Scroll lifts and fades it after the hero;
  it returns faintly at the final CTA.
- *Wave lines:* none (Revision 4, 2026-09-21). The hairline swells across the
  hero, the two inside the portal, and the ripple rings of the release demo and
  the Capture card read as thin, fussy lines against the soft lights, so they
  are gone. Waterlines in the cards are soft bands of light instead.
- *Lamps* (Revision 1): five in all. Four currents as large out-of-focus
  pools (radius 118 to 150 pt, scaled to as little as 0.62 on phones) and one
  warm sun (120 pt). No visible light under 60 pt. Wander on shared simplex
  noise (8 to 15 s periods), breathe ±2% on 6 to 10 s, ease to targets on a
  critically damped spring (ω ≈ 2.2).
- *Glows:* four huge blurred pools of light inside the water shader per
  chapter (radius 0.4 to 0.7 of the viewport's larger side, strength at most
  0.25), blended across chapter handovers.
- *Descent:* page depth 0 → 1 darkens and slightly cools the body, dims the
  lamps, and lowers their energy. Privacy and Support render depth 0.6, still.

**The release demo.** Submitting a non-empty thought (max 140 chars): chime
(if sound is on); a large soft light appears below the card with the words
set inside it (Instrument Serif italic; Songti for Chinese), sinks over about
2.4 s as it softens, the words let go at about 4 s, and two wide, flat rings
open on the water; the light is gone by 9 s. The input clears; an `aria-live="polite"` line reads
"Drifted into the Ocean". Nothing is stored or sent. Button disabled while
empty; Enter submits.

---

## 5. Sound

- **Off until turned on.** Browsers require a gesture, and calm means never
  startling anyone. Controls: the bar's Sound toggle (`<button aria-pressed>`)
  and "Listen" in the hero.
- **Ambient ocean, generated live** (no audio files): three layers into a
  master gain.
  - *Deep:* brown noise → lowpass 220 to 420 Hz (lower as depth rises), gain ≈ 0.22.
  - *Swell:* pink noise → lowpass swept about 380 → 1600 Hz and back, gain
    about 0.02 → 0.28 → 0.02 per breath wave, stereo pan per wave.
  - *Wash:* white noise → highpass 2.5 kHz, a short hiss at each crest
    decaying over 2 to 3 s, scaled by (1 − depth).
  - Envelopes scheduled about 4 s ahead from `breath.wavesBetween`, so the
    sound and the visuals swell together; each wave differs, so it never loops.
- **The chime** is the app's real `OceanReceived`: rendered with
  `python3 tools/generate_ocean_received.py --wav-out <tmp>.wav --out <tmp>.caf`
  (never the default `--out`, which is the app bundle), then
  `afconvert -f m4af -d aac` into `assets/audio/ocean-received.m4a`. Decoded
  lazily on first enable; played on release.
- **Manners:** master fades in over 2.5 s and out over 1.2 s; the context
  suspends while the tab is hidden and resumes on return; ambient peaks sit
  around −20 dBFS. The choice persists in `localStorage` (`oryne.sound`); a
  stored "on" resumes at the visitor's first tap or key press. iOS's silent
  switch may mute Web Audio, which is acceptable.

---

## 6. Languages and routing

- `<html lang="en">` and `<html lang="zh-Hans">`; each page carries
  `hreflang` alternates (`en`, `zh-Hans`, `x-default` → English) and a canonical.
- Relative asset paths (`assets/…`, `../assets/…`) so the site works from any
  host root or a local preview.
- Routing, in a tiny inline head script (no flash): a stored `oryne.lang`
  that differs from the page's language redirects to the counterpart. With
  nothing stored, the English page redirects to `/zh/` when the browser's first
  language is Simplified Chinese (`zh`, `zh-CN`, `zh-SG`, `zh-Hans*`; not
  `zh-TW`, `zh-HK`, `zh-MO`, `zh-Hant*`). The `EN | 中` toggle stores the choice.

---

## 7. Real app screens

Six screens, captured in English from a Debug build in the simulator
(iPhone 16 Pro class) with the existing marketing seed:

1. Ocean field (hero)
2. One current's stream, "light and color" (Currents)
3. Capture (Capture, final CTA)
4. Ask with an answer and source chips (Ask)
5. Thought detail with branches (Grow)
6. Library, Related arrangement (Grow)

Recipe (per `oryne-build-run` notes): `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`,
`xcodegen generate`, build the `Oryne` scheme, skip onboarding by writing
`fastCapture.onboardingCompleted` into the App Group plist before first
launch, clean status bar (`simctl status_bar … override --time 9:41`), launch
with `SIMCTL_CHILD_OCEAN_SCREENSHOT_SEED=1`, `SIMCTL_CHILD_OCEAN_START_TAB=…`,
`-AppleLanguages '(en)'`, drive to each screen with the simulator tool, and
`simctl io booted screenshot`. Export WebP (`cwebp -q 82`) at 2× the
displayed width, with PNG fallback. The app's code, seed, and assets are not
modified. Chinese pages reuse these screens at launch; localized screens need
a Chinese screenshot seed in the app (follow-up).

**Fallback** if the build or UI driving fails: ship the chapters with their
water choreography and HTML thought cards in place of screens, and report it.

---

## 8. Privacy and Support pages

**Privacy** (draft for Malik's review, not legal advice), built only from
facts verified in code at `0af9bf0`:
- Captures (text, voice, images, links) live in the app's on-device store,
  shared with its own extension and widgets.
- Sync: CloudKit **private** database, if iCloud is on; Apple stores it; we
  can't access it. Without iCloud, data stays on the device.
- Intelligence: titles, themes, related thoughts, resurfacing, and Ask run on
  device (NaturalLanguage; Apple's on-device model where eligible). The
  Release build sends nothing to any Oryne server
  (`CloudOceanAIService.Configuration.fromEnvironment()` is nil in Release).
- Voice: Apple Speech, on-device when the device supports it for that
  language; otherwise Apple's recognition service may process it. Once a
  whisper has a transcript, its recording is deleted 30 days after capture
  (a whisper without a transcript keeps its audio).
- Link previews: saving a link fetches that page for its title, description,
  and image; the request goes to that website.
- Siri: Apple processes the spoken request under Apple's policy.
- Permissions: microphone, speech recognition, photo library (only images you
  pick or share).
- Export and deletion: export to Markdown plus a JSON backup; deleting the app
  removes local data; iCloud data is managed in iOS Settings.
- The website: static pages, no cookies, no analytics; `localStorage` keeps
  only the language and sound choices; the release demo never leaves the
  page; the web host may keep standard request logs.
- A commitment: if Oryne ever adds a feature that sends content off the
  device, this policy will say so before it ships. **Update this page before
  the cloud proxy is wired into Release.**
- Contact: support email (placeholder until supplied).

**Support:** short FAQ with verified answers (setting up Fast Capture on the
Action Button, Camera Control, and Control Center; the Siri phrase; sync;
export; deleting and undo; Reduce Motion and Calm Accessibility Mode;
language; clearing the examples) plus the contact email.

---

## 9. Claims ledger

Every product claim on the site maps to code. Verified at `0af9bf0`:

| Claim | Source |
|---|---|
| Fast Capture on Action Button and Control Center; opens listening | `CaptureIntents.swift` (StartFastCapture), `FastCaptureControl.swift`, `FastCaptureSessionView` voiceFirst. Camera Control only runs a Context Capture shortcut "where available" (`FastCapturePreferences.setupSteps`), so it is described on Support, not claimed as a button |
| Live transcript; listens for two languages | `LiveTranscriber`, `LanguageResolver` (main + alternate) |
| On-device speech where supported | `requiresOnDeviceRecognition` in `LiveTranscriber`, `DriftTranscriber` |
| Screenshot + voice | `StartContextCaptureIntent`, "Screenshot + voice" |
| Share sheet: links, images, text; link title and preview | `ShareExtension/`, `LinkEnrichmentService`, `LinkCard` |
| Siri phrase | `AddInspirationIntent`, `AppShortcut` phrases |
| Currents by meaning; one thought in several currents; tap to open | `SemanticThemes`, `ClusterStreamView` |
| Titles on device; user edits never overwritten | `TitleDistiller`, `*EditedByUser`, `NodeComposer.applyUnderstanding` |
| One resurfacing a day; echoes; rest | `Resurfacing.swift` |
| Resurfacing widget on Home Screen and Lock Screen | `ResurfacingWidget` (systemSmall/Medium, accessoryRectangular) |
| Quick Capture widget on Lock Screen | `QuickCaptureWidget` (accessoryCircular) |
| Ask modes; sources; Beyond your Ocean | `DialogueMode`, `AskView` outward block, `LocalOceanAIService` |
| Answers on device, Apple Intelligence where available | README AI layer, Release config nil |
| Branch types; original never overwritten | `BranchComposer`, `BranchType` |
| Library search, kind filter, Recent/Related | `LibraryView` |
| iCloud private sync | `Persistence.swift` (`.private(cloudKitContainerID)`) |
| Export to Markdown + JSON | `OceanExport.swift`, Settings "Export the Ocean" |
| Undo after capture | `PostCaptureMoment` |
| Calm Accessibility Mode; Reduce Motion stills | `OceanTheme.swift` (`CalmAccessibility`) |
| iPhone and iPad; iOS 18+ | `project.yml` (device family 1,2; iOS 18.0) |
| English and 简体中文 | `CFBundleLocalizations` |
| No analytics or tracking SDKs | repo search 2026-09-18 |

Not claimed: Apple Watch, kept melodies, price, any cloud
feature, any delete-undo beyond what the Support page verifies.

---

## 10. Accessibility, motion, performance, resilience

- All content is real HTML in reading order; canvases are `aria-hidden`.
  Skip link; visible focus (2px white 0.7 outline, 3px offset). Tabs follow
  the WAI-ARIA tabs pattern (arrow keys) and render as stacked sections
  without JS. The sound toggle is a real button with `aria-pressed`.
- Contrast: body text ≥ 4.5:1 over the darkest water (white ≥ 0.58); faint
  0.26 only for decoration.
- **Motion policy** mirrors the app's `MotionPolicy`: `full` or `still`.
  `prefers-reduced-motion: reduce` (live) or `?motion=still` gives `still`:
  no wander, breathing, dust, or ring pulse; chapter changes crossfade; the
  field renders once per change, then stops. A stilled Ocean is the same Ocean.
- Performance: DPR capped at 2 (2D) and 0.5 scale (water); rendering pauses
  while the tab is hidden; vignettes run only when visible; auto-degrade if
  the average frame exceeds 20 ms for 2 s (water scale 0.35).
  Budget: HTML + CSS + JS under 150 KB uncompressed; each screen under 150 KB;
  first load under 1.2 MB. `?debug=perf` shows fps and frame time.
- Resilience: without JS, all text, links, screens, and the FAQ remain (the
  release demo and sound controls hide); without WebGL, the CSS gradient
  stands in.
- Meta: title, description, canonical, hreflang, Open Graph and Twitter card
  (1200×630 image rendered from the hero), `theme-color #050508`,
  `color-scheme: dark`, favicons from the app icon, `robots.txt`, and
  `apple-itunes-app` once the App Store id is known. `sitemap.xml`, canonical
  links, and absolute `og:image` wait for the domain (README deploy checklist).

---

## 11. Verification

- **`website/tools/check.py`** (stdlib): English and Chinese trees have the
  same sections (ids, `data-chapter` order), links, and assets; no U+2014 or
  U+2013 in any page's text or attributes; every relative link and asset
  resolves; `lang` and `hreflang` present; remaining placeholders listed as
  warnings (App Store URL, support email).
- **`node --test website/tests`** (Node's built-in runner, no packages):
  `breath.js` determinism, range, and continuity; `choreo.js` targets inside
  the viewport, no cluster overlaps, continuous across chapter boundaries,
  still-policy targets equal to settled states.
- **Browser pass** (built-in browser pane): widths 375, 768, 1280, 1440; both
  languages; `?motion=still`; sound on and off (AudioContext state and an
  analyser RMS in range); the release demo; keyboard-only pass; the
  `?debug=perf` frame time on desktop.
- The app is untouched: `git status` shows changes only under `website/` and
  this spec.

## 12. Inputs needed from Malik (placeholders until then)

1. App Store URL (and so the app id for the Smart App Banner).
2. Support email.
3. Later: host and domain.

Resolved: price is left off the site (free for now, may change); the official
Apple badge is approved for download and use.

## 13. Risks

- Performance on low-end laptops and Android: mitigated by adaptive counts,
  half-scale water, and auto-degrade.
- Screen capture may stall on build or UI driving: fallback in §7.
- Chinese copy quality: every new line goes to Malik for review.
- Scroll choreography behind full-width text on phones: lights stay low
  alpha and use the gaps between blocks; text always wins.
