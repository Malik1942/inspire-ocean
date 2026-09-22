# Oryne website

The official product site for Oryne, in English and 简体中文. Static pages with
plain HTML, CSS, and JavaScript modules: no dependencies, no build step.
Design and decisions: `docs/superpowers/specs/2026-09-18-oryne-website-design.md`.

## Preview

```bash
cd website
python3 -m http.server 8765 --bind 127.0.0.1
```

Then open http://127.0.0.1:8765/ (ES modules need http, not `file://`).

| URL switch | What it does |
| --- | --- |
| `?motion=still` | the stilled Ocean, as with Reduce Motion |
| `?debug=perf` | frame rate and frame time, bottom right |
| `?debug` | exposes `window.__oryne` (`ocean`, `sound`) for console checks |

## Checks

```bash
cd website
node --test tests/*.test.mjs                           # noise, breath, choreography, ocean and sound helpers
python3 -m unittest discover -s tools -p 'test_*.py'   # the checker's own tests
python3 tools/check.py                                 # dashes, links, assets, en/zh parity, placeholders
```

`check.py` must report `0 error(s)` before anything ships.

## How it fits together

| File | Job |
| --- | --- |
| `assets/js/breath.js` | one breathing clock for the ring, the waves, and the sound |
| `assets/js/noise.js` | the shared drift field |
| `assets/js/choreo.js` | where each light wants to be, and the water's glows, per chapter and scroll progress (pure) |
| `assets/js/lamps.js` | the sunset-lamp disc and the out-of-focus pool, shared by the water and the vignettes |
| `assets/js/ocean.js` | the fixed water: WebGL body and glows, the portal, waves, lamps, released thoughts |
| `assets/js/vignettes.js` | the four How it works visuals |
| `assets/js/sound.js` | surf on the breath, plus the app's chime |
| `assets/js/site.js` | page wiring: scroll, sound, language, tabs, release demo |
| `assets/css/site.css` | all styles; tokens from `OceanTheme` |
| `assets/fonts/` | Instrument Serif and Inter, self-hosted (SIL Open Font License, `OFL.txt`) |

Sections declare `data-chapter` and anchors declare `data-anchor`; `site.js`
reads them and hands `choreo.js` plain numbers. Motion is atmosphere: every
fact the water shows is also written on the page, and Reduce Motion (or
`?motion=still`) stills all of it. The water only ever holds large lights:
`choreo.test.mjs` fails if any visible light is smaller than `MIN_LAMP`.

## Editing copy

- No em or en dashes: use a comma, colon, or period. `check.py` fails on them.
- Headline accents: wrap the closing phrase of an English headline in `<em>`
  for the Instrument Serif italic. Chinese headlines stay upright, without `<em>`.
- Change English and Chinese together. Both trees must keep the same ids,
  `data-chapter` order, links, and assets; `check.py` compares them.
- Chinese follows `docs/localization-glossary.md`, reusing the app's catalog
  wording where the sentence exists.
- Every product claim must be true of the current Release build. The spec's
  claims ledger lists the code behind each one.
- The Privacy page follows the published policy at malikzhang.com/oryne/privacy.
  Change that policy and this page together, and keep the effective date in step.

## How the assets were made

- Icons: `sips` from `Oryne/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.
- Fonts: the Latin woff2 files Google Fonts serves for Instrument Serif (regular
  and italic) and Inter (variable, 300 to 600), self-hosted under the SIL Open
  Font License 1.1. The `@font-face` rules carry the same Latin `unicode-range`,
  so Chinese falls through to Songti SC for headlines and PingFang for text.
- Chime: `python3 tools/generate_ocean_received.py --wav-out <tmp>.wav --out <tmp>.caf`,
  then `afconvert -f m4af -d aac -b 96000 <tmp>.wav assets/audio/ocean-received.m4a`.
  Never run the generator without `--out`: its default overwrites the app's sound.
- Badges: Apple's official black Download on the App Store badges (en-us and
  zh-cn) from Apple Marketing Tools, used unmodified.
- Phone frame: `assets/img/phone-frame.webp`, the silver iPhone mockup Malik
  supplied, converted from PNG to WebP with Pillow (quality 93, alpha kept), 222 KB
  down to 27 KB. Its screen opening is inset 5.333% at the sides and 2.5% top and
  bottom, and its aspect matches the screens exactly, so `.phone__screen` sits in the
  opening without cropping. Measure the opening again if the file is ever replaced.
- Screens: Debug build on the iPhone 17 Pro simulator, launched with
  `SIMCTL_CHILD_OCEAN_SCREENSHOT_SEED=1` and `SIMCTL_CHILD_OCEAN_START_TAB=…`, status bar
  set to 9:41, captured with `simctl io … screenshot`, resized to 640 px, WebP q82.
  `fast-capture.webp` is the same build opened with `simctl openurl … oryne://capture/whisper`
  after granting the microphone and answering the speech prompt; its source line reads
  "Widget" because that is how the URL route is labelled.
- Social image: a headless Chrome capture of the stilled hero (`?motion=still`) at
  1200×630 (driven through the DevTools protocol), with the bar, lead, and Listen
  button hidden and the headline set at 92px, so the headline, badge, and phone in
  its ring fill the card.

## Deploy

Hosted on Vercel as the `oryne` project (team malik1942s-projects), a plain static
deployment with no build step, at https://oryne.malikzhang.com and
https://oryne-zeta.vercel.app. `malikzhang.com` itself belongs to the separate
`malik-portfolio` project.

The project is connected to the GitHub repo, with **Root Directory set to `website`**:
every push to `main` deploys this folder automatically, and nothing outside it is
served. Keep that setting. When it was briefly unset (2026-09-21), Vercel deployed the
repository root instead: the site 404ed and the app's source was served as static files
until the setting was restored.

```bash
git push origin main        # deploys; check https://oryne.malikzhang.com a minute later
```

`.vercelignore` keeps `tests/`, `tools/`, `package.json`, and this README out of the
deployment. `website/.vercel/` and `.env.local` are the CLI's local link files,
git-ignored. Vercel Authentication is off for this project, so the site is public.

## Before going live

1. The App Store link (id6778995892) and the support address are in place; `check.py`
   warns if a placeholder ever comes back.
2. Once the domain is known: make `og:image` absolute, add `<link rel="canonical">`,
   make the `hreflang` URLs absolute, add `sitemap.xml` with a `Sitemap:` line in
   `robots.txt`, and add `<meta name="apple-itunes-app" content="app-id=…">`.
4. If a feature that sends content off the device ships in Release, update the
   Privacy page first.
5. Run the checks: `0 error(s), 0 warning(s)`.
