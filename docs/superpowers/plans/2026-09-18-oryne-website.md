# Oryne Official Website Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Oryne's official product website: a static, bilingual (English + 简体中文) landing page plus Privacy and Support pages, with one living ocean behind every page (breathing water, the icon's portal ring, choreographed motes, generated surf sound, and the app's own chime).

**Architecture:** Plain HTML pages under `website/` share one stylesheet and a handful of ES modules. Pure modules (`noise`, `breath`, `choreo`) decide *what* the water should do and are unit tested with Node's built-in runner; DOM modules (`ocean`, `vignettes`, `sound`) draw and play it; `site.js` is the only module that reads the page and wires scroll, sound, language, tabs, and the release demo together. A standard-library Python checker guards copy rules, links, assets, and English/Chinese parity.

**Tech Stack:** HTML, CSS, JavaScript ES modules, WebGL 1, Canvas 2D, Web Audio. Node 26 (`node --test`) and Python 3 (`unittest`) for tests only. macOS `sips`, `afconvert`, `cwebp`, Xcode simulator, and headless Chrome for assets.

**Spec:** `docs/superpowers/specs/2026-09-18-oryne-website-design.md` (approved 2026-09-18).

## Global Constraints

- Everything new lives in `website/`. Never modify app code, `Oryne/Resources/OceanReceived.caf`, `project.yml`, or anything under `Oryne/`, `Shared/`, `OceanWidgets/`, `ShareExtension/`.
- No dependencies, no build step, no web fonts. The only network request a page makes is the App Store link the visitor clicks.
- No em dash (U+2014) or en dash (U+2013) anywhere in a site page, in either language. `tools/check.py` enforces it.
- Tokens (from `OceanTheme`): abyss `#050508`, deep `#0d0e11`, mid `#17181c`, current `#26282d`, surface `#3d3e45`; foam white 0.92, text white 0.66, mist white 0.50, hint white 0.58, faint white 0.26 (decoration only); accent `#d1d6e0`; warm `#f2ede0`; rim `#9fb2d6`.
- Motes follow `OrbTextures`: body white 0.08 + tint 0.13, one 0.75px rim (white 0.16, warm `#f2ede0` 0.45). No halos, no luminous cores.
- Motion policy is `full` or `still`. `prefers-reduced-motion: reduce`, `?motion=still`, or a long page (Privacy, Support) gives `still`.
- Sound is off until the visitor turns it on. `localStorage` keys: `oryne.sound` (`on`/`off`), `oryne.lang` (`en`/`zh-Hans`). Nothing else is stored.
- Placeholders until Malik supplies them: App Store URL `https://apps.apple.com/app/id0000000000`, support email `support@example.com`.
- Price is never mentioned. No testimonials, logos, or usage numbers. Siri phrases exist in English only.
- Chinese copy follows `docs/localization-glossary.md` (海洋, 灵感, 语音, 库, 提问, 延展, 汇入, 捕捉, 碎片, 再次浮现), full-width punctuation, no 「——」.
- Breakpoints: 720px (section links appear in the bar), 900px (two-column chapters; `choreo.js` treats `vw >= 900` as wide).
- Browser support: current Safari (macOS and iOS), Chrome, Edge, Firefox.
- Commits: none unless Malik asks (repo rule in `CLAUDE.md`). Each task ends with a checkpoint instead. The pre-existing untracked `default.profraw` is never touched or committed.

## Conventions for this plan

- `WT` is the worktree root: `/Users/malik/Documents/inspire-ocean/.claude/worktrees/oryne-official-website-08655b`. Commands run from `WT` unless a step says otherwise.
- `SCRATCH` is the session scratchpad: `/private/tmp/claude-501/-Users-malik-Documents-inspire-ocean--claude-worktrees-oryne-official-website-08655b/fede2667-1588-47b9-a03b-c1e078c2f031/scratchpad`.
- Every file this plan creates appears exactly once, in full, directly under a line of the form **File:** `path`. Executors may create the file by copying that block verbatim.

## File Map

| File | Responsibility |
|---|---|
| `website/package.json` | Marks the JS as ES modules; `npm test` / `npm run check` shortcuts. No dependencies |
| `website/tools/check.py` | Static checks: dashes, links, assets, `lang`/`hreflang`, English/Chinese parity, placeholder warnings |
| `website/tools/test_check.py` | Unit tests for the checker |
| `website/assets/js/noise.js` | Seeded 2D simplex noise (the shared drift field) |
| `website/assets/js/breath.js` | The shared breathing clock: waves, envelope, scheduling window |
| `website/assets/js/choreo.js` | Pure choreography: chapter + progress + anchors → mote targets; rings |
| `website/assets/js/orbs.js` | Mote sprite recipe and cache |
| `website/assets/js/ocean.js` | The fixed water: WebGL body + 2D stars, ring, waves, motes, links, labels, released thoughts |
| `website/assets/js/vignettes.js` | The four small How-it-works visuals |
| `website/assets/js/sound.js` | Web Audio surf on the breath + the OceanReceived chime |
| `website/assets/js/site.js` | Page wiring: scroll, sound toggles, language, tabs, release demo, perf overlay |
| `website/assets/css/site.css` | All styles |
| `website/index.html`, `privacy.html`, `support.html` | English pages |
| `website/zh/index.html`, `zh/privacy.html`, `zh/support.html` | Chinese pages |
| `website/robots.txt` | Crawl rules |
| `website/assets/img/*`, `assets/audio/*` | Icons, badges, screens, social image, chime |
| `website/tests/*.test.mjs` | Node tests for the pure modules and helpers |
| `website/README.md` | Preview, checks, asset recipes, go-live checklist |
| `.claude/launch.json` (untracked) | Preview server for the in-app browser |

---

### Task 1: Tooling and the static checker

**Files:**
- Create: `website/tools/test_check.py`
- Create: `website/tools/check.py`
- Create: `website/package.json`
- Create: `.claude/launch.json` (untracked dev convenience)

**Interfaces:**
- Produces: `python3 website/tools/check.py [--only en|zh]` → exit 0 when clean, 1 on errors; prints `warning:` and `error:` lines and a final `N error(s), M warning(s)` line. `check.run(site, only=None) -> (errors, warnings)`; `check.PAGES = ("index.html", "privacy.html", "support.html")`.
- Produces: markup contract for later tasks: `data-lang-switch="<lang>"` marks language-switch links and `data-lang-asset` marks per-language assets (both excluded from parity); `id` attributes and `data-chapter` values must match between the two trees.

- [ ] **Step 1: Write the failing tests**

**File:** `website/tools/test_check.py`
```python
"""Tests for tools/check.py.

Run: python3 -m unittest discover -s website/tools -p 'test_*.py' -v
"""

import tempfile
import unittest
from pathlib import Path

import check

PAGE = """<!doctype html>
<html lang="{lang}">
<head>
<link rel="alternate" hreflang="en" href="{en}">
<link rel="alternate" hreflang="zh-Hans" href="{zh}">
<link rel="alternate" hreflang="x-default" href="{en}">
<link rel="stylesheet" href="{prefix}assets/site.css">
</head>
<body>
<section id="top" data-chapter="top">
<p>{copy}</p>
<a href="privacy.html">Privacy</a>
<a href="#faq">FAQ</a>
<a href="https://apps.apple.com/app/id123">App Store</a>
<a href="{switch}" data-lang-switch="{other}">{other}</a>
</section>
{extra}
</body>
</html>
"""


def build(root, en_copy="Catch ideas.", zh_copy="留住灵感。", zh_extra=""):
    (root / "assets").mkdir()
    (root / "assets" / "site.css").write_text("", encoding="utf-8")
    (root / "zh").mkdir()
    for name in check.PAGES:
        (root / name).write_text(PAGE.format(
            lang="en", en="./", zh="zh/", prefix="", copy=en_copy,
            switch="zh/", other="zh-Hans", extra=""), encoding="utf-8")
        (root / "zh" / name).write_text(PAGE.format(
            lang="zh-Hans", en="../", zh="./", prefix="../", copy=zh_copy,
            switch="../", other="en", extra=zh_extra), encoding="utf-8")


class CheckTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name).resolve()

    def tearDown(self):
        self._tmp.cleanup()

    def test_a_clean_site_passes(self):
        build(self.root)
        errors, warnings = check.run(self.root)
        self.assertEqual(errors, [])
        self.assertEqual(warnings, [])

    def test_an_em_dash_in_copy_is_an_error(self):
        build(self.root, en_copy="Catch ideas — now.")
        errors, _ = check.run(self.root)
        self.assertTrue(any("em dash" in e for e in errors), errors)

    def test_an_en_dash_in_copy_is_an_error(self):
        build(self.root, zh_copy="iOS 18–26")
        errors, _ = check.run(self.root)
        self.assertTrue(any("en dash" in e for e in errors), errors)

    def test_a_missing_asset_is_an_error(self):
        build(self.root)
        (self.root / "assets" / "site.css").unlink()
        errors, _ = check.run(self.root)
        self.assertTrue(any("missing file" in e and "site.css" in e for e in errors), errors)

    def test_structural_drift_between_languages_is_an_error(self):
        build(self.root, zh_extra='<section id="extra" data-chapter="deep"></section>')
        errors, _ = check.run(self.root)
        self.assertTrue(any("differ in ids" in e for e in errors), errors)
        self.assertTrue(any("differ in data-chapter" in e for e in errors), errors)

    def test_language_switches_are_not_compared(self):
        build(self.root)  # the switches point in opposite directions by design
        errors, _ = check.run(self.root)
        self.assertEqual(errors, [])

    def test_localized_assets_are_not_compared(self):
        build(self.root)
        (self.root / "assets" / "badge-en.svg").write_text("<svg/>", encoding="utf-8")
        (self.root / "assets" / "badge-zh.svg").write_text("<svg/>", encoding="utf-8")
        for name in check.PAGES:
            for page, badge in ((self.root / name, "assets/badge-en.svg"),
                                (self.root / "zh" / name, "../assets/badge-zh.svg")):
                html = page.read_text(encoding="utf-8").replace(
                    "</section>", f'<img src="{badge}" data-lang-asset alt=""></section>', 1)
                page.write_text(html, encoding="utf-8")
        errors, _ = check.run(self.root)
        self.assertEqual(errors, [])

    def test_placeholders_warn_but_do_not_fail(self):
        build(self.root, en_copy="Get it at id0000000000 or write support@example.com")
        errors, warnings = check.run(self.root)
        self.assertEqual(errors, [])
        self.assertEqual(len(warnings), 2 * len(check.PAGES), warnings)

    def test_only_skips_parity(self):
        build(self.root, zh_extra='<section id="extra" data-chapter="deep"></section>')
        errors, _ = check.run(self.root, only="en")
        self.assertEqual(errors, [])

    def test_missing_alternates_are_an_error(self):
        build(self.root)
        page = self.root / "index.html"
        page.write_text(page.read_text(encoding="utf-8").replace(
            'hreflang="x-default"', 'hreflang="fr"'), encoding="utf-8")
        errors, _ = check.run(self.root)
        self.assertTrue(any("x-default" in e for e in errors), errors)

    def test_a_missing_counterpart_page_is_an_error(self):
        build(self.root)
        (self.root / "zh" / "support.html").unlink()
        errors, _ = check.run(self.root)
        self.assertTrue(any("zh/support.html" in e for e in errors), errors)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest discover -s website/tools -p 'test_*.py' -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'check'`.

- [ ] **Step 3: Write the checker**

**File:** `website/tools/check.py`
```python
#!/usr/bin/env python3
"""Static checks for the Oryne website. Standard library only.

    python3 website/tools/check.py            # both languages, with parity
    python3 website/tools/check.py --only en  # one tree, no parity

Errors fail the run (exit 1):
  - an em or en dash anywhere in a page (house rule: none in UI copy)
  - a relative link or asset that does not resolve to a file
  - <html lang> missing, or hreflang alternates for en, zh-Hans, x-default missing
  - a page missing from either language tree
  - an English page and its Chinese counterpart differing in structure:
    element ids (in order), the data-chapter sequence, or links and assets
    (language switches, per-language assets, and hreflang alternates excluded)
Warnings do not fail the run:
  - placeholders still in place (App Store URL, support email)
"""

import argparse
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit

SITE = Path(__file__).resolve().parent.parent
PAGES = ("index.html", "privacy.html", "support.html")
DASHES = {"—": "em dash", "–": "en dash"}
PLACEHOLDERS = {
    "id0000000000": "the App Store URL is still the placeholder",
    "support@example.com": "the support email is still the placeholder",
}
REF_ATTRS = {"a": "href", "link": "href", "img": "src", "script": "src", "source": "srcset"}


class PageScan(HTMLParser):
    """Collects what the checks compare: lang, alternates, ids, chapters, refs."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.lang = None
        self.hreflangs = set()
        self.ids = []
        self.chapters = []
        self.refs = []  # (tag, url, excluded_from_parity)

    def handle_starttag(self, tag, attrs):
        a = {name: value or "" for name, value in attrs}
        if tag == "html":
            self.lang = a.get("lang")
        alternate = tag == "link" and a.get("rel") == "alternate" and "hreflang" in a
        if alternate:
            self.hreflangs.add(a["hreflang"])
        if a.get("id"):
            self.ids.append(a["id"])
        if "data-chapter" in a:
            self.chapters.append(a["data-chapter"])
        attr = REF_ATTRS.get(tag)
        if attr and a.get(attr):
            excluded = alternate or "data-lang-switch" in a or "data-lang-asset" in a
            if attr == "srcset":
                urls = [part.strip().split(" ")[0] for part in a[attr].split(",")]
            else:
                urls = [a[attr]]
            self.refs.extend((tag, url, excluded) for url in urls if url)


def is_local(url):
    parts = urlsplit(url)
    return not parts.scheme and not parts.netloc and bool(parts.path)


def resolve(page, url):
    path = urlsplit(url).path
    target = (page.parent / path).resolve()
    if path.endswith("/") or target.is_dir():
        target = target / "index.html"
    return target


def scan_page(site, page, errors, warnings):
    text = page.read_text(encoding="utf-8")
    rel = page.relative_to(site).as_posix()
    for lineno, line in enumerate(text.splitlines(), 1):
        for char, name in DASHES.items():
            if char in line:
                errors.append(f"{rel}:{lineno}: {name} (copy rule: use a comma, colon, or period)")
    for token, message in PLACEHOLDERS.items():
        if token in text:
            warnings.append(f"{rel}: {message}")
    scan = PageScan()
    scan.feed(text)
    if scan.lang not in ("en", "zh-Hans"):
        errors.append(f"{rel}: <html lang> must be en or zh-Hans, found {scan.lang!r}")
    missing = {"en", "zh-Hans", "x-default"} - scan.hreflangs
    if missing:
        errors.append(f"{rel}: missing hreflang alternates: {', '.join(sorted(missing))}")
    for tag, url, _ in scan.refs:
        if is_local(url) and not resolve(page, url).exists():
            errors.append(f"{rel}: <{tag}> points at a missing file: {url}")
    return scan


def structure_refs(site, page, scan, strip_zh):
    """Links and assets in order, normalized so both language trees compare equal."""
    out = []
    for tag, url, excluded in scan.refs:
        if excluded:
            continue
        if not is_local(url):
            out.append((tag, url))
            continue
        try:
            key = resolve(page, url).relative_to(site).as_posix()
        except ValueError:
            key = f"outside-site:{url}"
        if strip_zh and key.startswith("zh/"):
            key = key[len("zh/"):]
        fragment = urlsplit(url).fragment
        out.append((tag, key + (f"#{fragment}" if fragment else "")))
    return out


def first_difference(a, b):
    for index, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return f"item {index}: {x!r} vs {y!r}"
    return f"lengths {len(a)} vs {len(b)}"


def run(site, only=None):
    site = Path(site).resolve()
    errors, warnings = [], []
    trees = {"en": site, "zh": site / "zh"}
    found = {}
    for lang in ([only] if only else ["en", "zh"]):
        for name in PAGES:
            page = trees[lang] / name
            if not page.exists():
                errors.append(f"missing page: {page.relative_to(site).as_posix()}")
                continue
            scan = scan_page(site, page, errors, warnings)
            found[(lang, name)] = {
                "ids": scan.ids,
                "data-chapter": scan.chapters,
                "links and assets": structure_refs(site, page, scan, strip_zh=(lang == "zh")),
            }
    if not only:
        for name in PAGES:
            en, zh = found.get(("en", name)), found.get(("zh", name))
            if not (en and zh):
                continue
            for label in ("ids", "data-chapter", "links and assets"):
                if en[label] != zh[label]:
                    errors.append(f"{name}: English and Chinese differ in {label}: "
                                  f"{first_difference(en[label], zh[label])}")
    return errors, warnings


def main(argv=None):
    parser = argparse.ArgumentParser(description="Static checks for the Oryne website.")
    parser.add_argument("--only", choices=("en", "zh"), help="check one language tree and skip parity")
    parser.add_argument("--site", type=Path, default=SITE, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    errors, warnings = run(args.site, args.only)
    for warning in warnings:
        print(f"warning: {warning}")
    for error in errors:
        print(f"error: {error}")
    print(f"{len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s website/tools -p 'test_*.py' -v`
Expected: `Ran 11 tests` … `OK`.

- [ ] **Step 5: Add the package manifest and the preview server config**

**File:** `website/package.json`
```json
{
  "name": "oryne-website",
  "private": true,
  "type": "module",
  "description": "The Oryne product website: static pages, no dependencies, no build step.",
  "scripts": {
    "test": "node --test tests/*.test.mjs && python3 -m unittest discover -s tools -p 'test_*.py'",
    "check": "python3 tools/check.py",
    "serve": "python3 -m http.server 8765 --bind 127.0.0.1"
  }
}
```

**File:** `.claude/launch.json`
```json
{
  "version": "0.0.1",
  "configurations": [
    {
      "name": "oryne-website",
      "runtimeExecutable": "python3",
      "runtimeArgs": ["-m", "http.server", "8765", "--bind", "127.0.0.1", "--directory", "website"],
      "port": 8765
    }
  ]
}
```

- [ ] **Step 6: Checkpoint**

Run: `git status --short`
Expected: `?? website/` (plus the pre-existing `?? default.profraw`, and `docs/superpowers/` entries). `.claude/launch.json` does not appear (the folder is ignored). No commit (repo rule).

---

### Task 2: The drift field and the breathing clock

**Files:**
- Create: `website/tests/noise.test.mjs`
- Create: `website/tests/breath.test.mjs`
- Create: `website/assets/js/noise.js`
- Create: `website/assets/js/breath.js`

**Interfaces:**
- Produces: `createNoise2D(seed = 0x0cea) → (x, y) => number` in [-1, 1], smooth, deterministic per seed.
- Produces: `wave(index) → { index, start, duration, rise, peak, pan }` (seconds; duration 8.5..11, rise 36..44% of duration, peak 0.75..1, pan -0.3..0.3); `envelope(wave, phase 0..1) → level`; `breathAt(t) → { level, index, phase }` with level in [`BREATH_BASE`, 1]; `wavesBetween(t0, t1) → wave[]` (waves starting in [t0, t1)); `now() → seconds` (performance.now()/1000); `BREATH_BASE = 0.08`.

- [ ] **Step 1: Write the failing tests**

**File:** `website/tests/noise.test.mjs`
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createNoise2D } from '../assets/js/noise.js';

test('the same seed gives the same water', () => {
  const a = createNoise2D(7);
  const b = createNoise2D(7);
  for (let i = 0; i < 200; i++) assert.equal(a(i * 0.37, i * 0.11), b(i * 0.37, i * 0.11));
});

test('different seeds give different water', () => {
  const a = createNoise2D(7);
  const b = createNoise2D(8);
  let same = 0;
  for (let i = 0; i < 200; i++) if (a(i * 0.37, 1.5) === b(i * 0.37, 1.5)) same++;
  assert.ok(same < 20, `${same} identical samples`);
});

test('values stay within -1..1 and actually vary', () => {
  const n = createNoise2D();
  let sum = 0;
  let squares = 0;
  let count = 0;
  for (let x = -20; x < 20; x += 0.173) {
    for (let y = -3; y < 3; y += 0.61) {
      const v = n(x, y);
      assert.ok(v >= -1 && v <= 1, `out of range: ${v}`);
      sum += v;
      squares += v * v;
      count++;
    }
  }
  const sd = Math.sqrt(squares / count - (sum / count) ** 2);
  assert.ok(sd > 0.1, `too flat: sd ${sd}`);
});

test('the field is smooth', () => {
  const n = createNoise2D();
  for (let x = 0; x < 30; x += 0.05) {
    assert.ok(Math.abs(n(x + 0.001, 2.2) - n(x, 2.2)) < 0.02);
  }
});
```

**File:** `website/tests/breath.test.mjs`
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BREATH_BASE, breathAt, envelope, wave, wavesBetween } from '../assets/js/breath.js';

test('waves last 8.5 to 11 seconds and peak between 0.75 and 1', () => {
  for (let i = 0; i < 500; i++) {
    const w = wave(i);
    assert.ok(w.duration >= 8.5 && w.duration <= 11, `duration ${w.duration}`);
    assert.ok(w.peak >= 0.75 && w.peak <= 1, `peak ${w.peak}`);
    assert.ok(w.rise > 0 && w.rise < w.duration);
    assert.ok(Math.abs(w.pan) <= 0.3);
  }
});

test('waves follow each other without gaps', () => {
  for (let i = 0; i < 200; i++) {
    const a = wave(i);
    const b = wave(i + 1);
    assert.ok(Math.abs(a.start + a.duration - b.start) < 1e-9);
  }
});

test('the breath is deterministic', () => {
  const first = breathAt(123.456);
  breathAt(9999);
  assert.deepEqual(breathAt(123.456), first);
});

test('the level stays between the base and 1', () => {
  for (let t = 0; t < 900; t += 0.37) {
    const { level } = breathAt(t);
    assert.ok(level >= BREATH_BASE - 1e-9 && level <= 1 + 1e-9, `level ${level} at ${t}`);
  }
});

test('the level is continuous, including across wave boundaries', () => {
  for (let t = 0; t < 600; t += 0.05) {
    const jump = Math.abs(breathAt(t + 0.01).level - breathAt(t).level);
    assert.ok(jump < 0.02, `jump ${jump} at ${t}`);
  }
  for (let i = 1; i < 50; i++) {
    const s = wave(i).start;
    assert.ok(Math.abs(breathAt(s - 1e-6).level - breathAt(s + 1e-6).level) < 1e-3);
  }
});

test('each wave reaches its peak at the crest', () => {
  const w = wave(7);
  assert.ok(Math.abs(envelope(w, w.rise / w.duration) - w.peak) < 1e-9);
});

test('wavesBetween lists the waves that begin inside the window, in order', () => {
  const list = wavesBetween(10, 70);
  assert.ok(list.length >= 5 && list.length <= 8, `${list.length} waves`);
  for (const w of list) assert.ok(w.start >= 10 && w.start < 70);
  for (let i = 1; i < list.length; i++) assert.ok(list[i].start > list[i - 1].start);
});

test('negative time is treated as the first moment', () => {
  assert.deepEqual(breathAt(-5), breathAt(0));
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd website && node --test tests/noise.test.mjs tests/breath.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `assets/js/noise.js` and `assets/js/breath.js`.

- [ ] **Step 3: Write the noise field**

**File:** `website/assets/js/noise.js`
```js
// Seeded 2D simplex noise, after Stefan Gustavson's public-domain reference.
// The Ocean samples one shared field, so every mote moves as part of one body
// of water instead of jittering on its own (the app's DriftField, in small).

const F2 = 0.5 * (Math.sqrt(3) - 1);
const G2 = (3 - Math.sqrt(3)) / 6;
const GRADIENTS = [
  [1, 1], [-1, 1], [1, -1], [-1, -1],
  [1, 0], [-1, 0], [0, 1], [0, -1],
];

function permutation(seed) {
  const p = new Uint8Array(256);
  for (let i = 0; i < 256; i++) p[i] = i;
  let s = seed >>> 0 || 1;
  for (let i = 255; i > 0; i--) {
    s ^= s << 13;
    s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5;
    s >>>= 0;
    const j = s % (i + 1);
    const swap = p[i];
    p[i] = p[j];
    p[j] = swap;
  }
  const perm = new Uint8Array(512);
  for (let i = 0; i < 512; i++) perm[i] = p[i & 255];
  return perm;
}

function corner(gradient, x, y) {
  let t = 0.5 - x * x - y * y;
  if (t < 0) return 0;
  const g = GRADIENTS[gradient & 7];
  t *= t;
  return t * t * (g[0] * x + g[1] * y);
}

/** A smooth field in -1..1. The same seed always gives the same water. */
export function createNoise2D(seed = 0x0cea) {
  const perm = permutation(seed);
  return function noise2D(xin, yin) {
    const s = (xin + yin) * F2;
    const i = Math.floor(xin + s);
    const j = Math.floor(yin + s);
    const t = (i + j) * G2;
    const x0 = xin - (i - t);
    const y0 = yin - (j - t);
    const i1 = x0 > y0 ? 1 : 0;
    const j1 = x0 > y0 ? 0 : 1;
    const x1 = x0 - i1 + G2;
    const y1 = y0 - j1 + G2;
    const x2 = x0 - 1 + 2 * G2;
    const y2 = y0 - 1 + 2 * G2;
    const ii = i & 255;
    const jj = j & 255;
    const n = corner(perm[ii + perm[jj]], x0, y0)
      + corner(perm[ii + i1 + perm[jj + j1]], x1, y1)
      + corner(perm[ii + 1 + perm[jj + 1]], x2, y2);
    return Math.max(-1, Math.min(1, 70 * n));
  };
}
```

- [ ] **Step 4: Write the breathing clock**

**File:** `website/assets/js/breath.js`
```js
// One breathing clock for the whole site. The ring, the wave lines, and the
// ambient sound rise and fall on the same waves, so what you see and what you
// hear always agree. Deterministic: a wave's length, height, and pan come from
// its index, so any moment can be asked about at any time.

export const BREATH_BASE = 0.08;   // the water never goes completely flat

const starts = [0];                // start time of wave i, grown on demand

function unit(index, salt) {
  let h = Math.imul(index + 1, 0x27d4eb2d) ^ Math.imul(salt, 0x165667b1);
  h = Math.imul(h ^ (h >>> 15), 0x85ebca6b);
  h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

function durationOf(index) {
  return 8.5 + 2.5 * unit(index, 1);
}

function startOf(index) {
  while (starts.length <= index) {
    const last = starts.length - 1;
    starts.push(starts[last] + durationOf(last));
  }
  return starts[index];
}

function indexAt(t) {
  const time = Math.max(0, t);
  while (starts[starts.length - 1] <= time) startOf(starts.length);
  let lo = 0;
  let hi = starts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (starts[mid] <= time) lo = mid;
    else hi = mid - 1;
  }
  return lo;
}

/** The shape of wave `index`, in seconds. */
export function wave(index) {
  const duration = durationOf(index);
  return {
    index,
    start: startOf(index),
    duration,
    rise: duration * (0.36 + 0.08 * unit(index, 2)),
    peak: 0.75 + 0.25 * unit(index, 3),
    pan: (unit(index, 4) - 0.5) * 0.6,
  };
}

/** Wave height at `phase` (0..1) through it: an easy rise, a long fall back. */
export function envelope(w, phase) {
  const r = w.rise / w.duration;
  const p = Math.min(1, Math.max(0, phase));
  const lift = p < r
    ? 0.5 - 0.5 * Math.cos(Math.PI * (p / r))
    : 0.5 + 0.5 * Math.cos(Math.PI * ((p - r) / (1 - r)));
  return BREATH_BASE + (w.peak - BREATH_BASE) * lift;
}

/** The breath at `t` seconds: level BREATH_BASE..1, the wave, and its phase. */
export function breathAt(t) {
  const index = indexAt(t);
  const w = wave(index);
  const phase = Math.min(1, Math.max(0, (t - w.start) / w.duration));
  return { level: envelope(w, phase), index, phase };
}

/** Waves that begin in [t0, t1), for scheduling sound ahead of the clock. */
export function wavesBetween(t0, t1) {
  const out = [];
  let i = indexAt(t0);
  if (startOf(i) < t0) i += 1;
  for (; startOf(i) < t1; i++) out.push(wave(i));
  return out;
}

/** Seconds since the page started: the one clock sight and sound share. */
export function now() {
  return performance.now() / 1000;
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd website && node --test tests/noise.test.mjs tests/breath.test.mjs`
Expected: `# pass 12`, `# fail 0`.

- [ ] **Step 6: Checkpoint**

Run: `cd website && node --test tests/*.test.mjs`
Expected: all pass. No commit.

---

### Task 3: Choreography

**Files:**
- Create: `website/tests/choreo.test.mjs`
- Create: `website/assets/js/choreo.js`

**Interfaces:**
- Consumes: nothing (pure).
- Produces:
  - `CHAPTERS = ['top','how','capture','currents','resurface','ask','grow','ambient','deep']`; `FOREGROUND = 5`; `ENERGY` map.
  - `createMotes(count) → Mote[]` where `Mote = { id, home: {u, v}, z, r, hue, cluster (0..3), rank, role ('warm'|'source'|null), sourceIndex (-1|0|1|2), seed }`. Mote 5 is `warm`; motes 0, 4, 8 are `source` 0, 1, 2. Minimum 12 motes.
  - `layout(state, motes, view) → Target[]` where `state = { chapter, progress 0..1, next?, blend 0..1 }`, `view = { vw, vh, anchors: { [name]: {x, y, w, h} }, labels: { currents: string[4], resurface: string } }` and `Target = { x, y, r, z, alpha, warm, label, labelAlpha, link: {x, y}|null, linkAlpha }`, clamped on screen (8px margin).
  - Anchor names read: `hero-phone`, `currents-phone`, `resurface-widget`, `ask-phone`, `final-phone`.
  - `ringsFor(view) → [{ x, y, R, alpha }]` (hero ring alpha 1, final ring 0.45; skipped when off screen); `ringRadius(rect) = rect.h * 0.475`.
  - `energyFor(state) → number`; helpers `mix`, `clamp`, `smoothstep`.

- [ ] **Step 1: Write the failing tests**

**File:** `website/tests/choreo.test.mjs`
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  CHAPTERS, FOREGROUND, createMotes, energyFor, layout, ringRadius, ringsFor,
} from '../assets/js/choreo.js';

const DESKTOP = { vw: 1440, vh: 900 };
const PHONE_D = { x: 900, y: 140, w: 300, h: 652 };
const MOBILE = { vw: 390, vh: 844 };
const PHONE_M = { x: 65, y: 300, w: 260, h: 565 };
const LABELS = {
  currents: ['light and color', 'product ideas', 'cooking', 'reading'],
  resurface: 'Ideas arrive in the shower',
};

function viewFor(size, phone) {
  return {
    ...size,
    labels: LABELS,
    anchors: {
      'hero-phone': phone,
      'currents-phone': phone,
      'ask-phone': phone,
      'final-phone': phone,
      'resurface-widget': { x: phone.x, y: phone.y + 200, w: 300, h: 150 },
    },
  };
}

const CASES = [
  { name: 'desktop', view: viewFor(DESKTOP, PHONE_D), phone: PHONE_D, motes: createMotes(56) },
  { name: 'mobile', view: viewFor(MOBILE, PHONE_M), phone: PHONE_M, motes: createMotes(28) },
];
const NUMERIC = ['x', 'y', 'r', 'z', 'alpha', 'warm', 'labelAlpha', 'linkAlpha'];

test('createMotes is stable and casts the story once', () => {
  const a = createMotes(48);
  assert.deepEqual(createMotes(48), a);
  assert.equal(a.filter((m) => m.role === 'warm').length, 1);
  const sources = a.filter((m) => m.role === 'source');
  assert.equal(sources.length, 3);
  assert.deepEqual(sources.map((m) => m.sourceIndex).sort(), [0, 1, 2]);
  for (const m of a) {
    assert.ok(m.home.u > 0 && m.home.u < 1 && m.home.v > 0 && m.home.v < 1);
    assert.ok(m.r >= 3 && m.r <= 13, `radius ${m.r}`);
    assert.ok(m.z >= 0 && m.z <= 1);
  }
  assert.equal(createMotes(3).length, 12);
});

test('every chapter gives one finite, on-screen target per mote', () => {
  for (const { name, view, motes } of CASES) {
    for (const chapter of CHAPTERS) {
      for (const progress of [0, 0.25, 0.5, 0.75, 1]) {
        const targets = layout({ chapter, progress }, motes, view);
        assert.equal(targets.length, motes.length);
        for (const t of targets) {
          for (const key of NUMERIC) assert.ok(Number.isFinite(t[key]), `${name} ${chapter} ${key}`);
          assert.ok(t.x >= 0 && t.x <= view.vw && t.y >= 0 && t.y <= view.vh, `${name} ${chapter} off screen`);
          assert.ok(t.alpha >= 0 && t.alpha <= 1 && t.z >= 0 && t.z <= 1 && t.r > 0);
        }
      }
    }
  }
});

test('chapters hand over without a jump', () => {
  for (const { name, view, motes } of CASES) {
    for (let i = 0; i < CHAPTERS.length - 1; i++) {
      const [a, b] = [CHAPTERS[i], CHAPTERS[i + 1]];
      const end = layout({ chapter: a, progress: 1, next: b, blend: 1 }, motes, view);
      const start = layout({ chapter: b, progress: 0 }, motes, view);
      end.forEach((t, k) => {
        for (const key of NUMERIC) {
          assert.ok(Math.abs(t[key] - start[k][key]) < 1e-9, `${name} ${a}→${b} ${key}`);
        }
        if (start[k].labelAlpha > 0) assert.equal(t.label, start[k].label);
      });
    }
  }
});

test('the hero keeps the phone clear', () => {
  for (const { view, phone, motes } of CASES) {
    for (const t of layout({ chapter: 'top', progress: 0 }, motes, view)) {
      if (t.alpha <= 0.05) continue;
      const inside = t.x > phone.x && t.x < phone.x + phone.w && t.y > phone.y && t.y < phone.y + phone.h;
      assert.ok(!inside, `visible mote at ${t.x},${t.y} over the phone`);
    }
  }
});

test('currents gather into four labeled groups that never overlap', () => {
  for (const { name, view, motes } of CASES) {
    const targets = layout({ chapter: 'currents', progress: 1 }, motes, view);
    const labeled = targets.filter((t) => t.labelAlpha > 0.99).map((t) => t.label).sort();
    assert.deepEqual(labeled, [...LABELS.currents].sort(), name);
    const gathered = targets.filter((_, i) => motes[i].rank < FOREGROUND);
    for (let i = 0; i < gathered.length; i++) {
      for (let j = i + 1; j < gathered.length; j++) {
        const [a, b] = [gathered[i], gathered[j]];
        const gap = Math.hypot(a.x - b.x, a.y - b.y) - a.r - b.r;
        assert.ok(gap >= 4, `${name}: motes ${i} and ${j} overlap (gap ${gap.toFixed(1)})`);
      }
    }
  }
});

test('the warm thought rises and warms through resurfacing', () => {
  for (const { view, motes } of CASES) {
    const i = motes.findIndex((m) => m.role === 'warm');
    const before = layout({ chapter: 'resurface', progress: 0 }, motes, view)[i];
    const after = layout({ chapter: 'resurface', progress: 1 }, motes, view)[i];
    assert.ok(after.y < before.y - 200, `${before.y} → ${after.y}`);
    assert.equal(after.warm, 1);
    assert.equal(after.z, 0);
    assert.equal(after.labelAlpha, 1);
    assert.equal(after.label, LABELS.resurface);
  }
});

test('ask links its three sources to the phone', () => {
  const { view, motes } = CASES[0];
  const targets = layout({ chapter: 'ask', progress: 1 }, motes, view);
  const sources = targets.filter((_, i) => motes[i].role === 'source');
  assert.equal(sources.length, 3);
  for (const t of sources) {
    assert.equal(t.linkAlpha, 1);
    assert.ok(t.link);
    assert.ok(Math.abs(t.link.x - (PHONE_D.x - 2)) < 1e-9);
  }
});

test('rings follow the hero and final phones, and leave when they scroll away', () => {
  const rings = ringsFor({ ...DESKTOP, anchors: { 'hero-phone': PHONE_D } });
  assert.equal(rings.length, 1);
  assert.equal(rings[0].R, ringRadius(PHONE_D));
  assert.equal(rings[0].x, PHONE_D.x + PHONE_D.w / 2);
  assert.equal(rings[0].alpha, 1);
  const away = ringsFor({ ...DESKTOP, anchors: { 'hero-phone': { ...PHONE_D, y: -3000 } } });
  assert.equal(away.length, 0);
  const final = ringsFor({ ...DESKTOP, anchors: { 'final-phone': PHONE_D } });
  assert.equal(final[0].alpha, 0.45);
});

test('energy blends between chapters', () => {
  assert.equal(energyFor({ chapter: 'deep' }), 0.25);
  assert.ok(Math.abs(energyFor({ chapter: 'top', next: 'how', blend: 0.5 }) - 0.95) < 1e-9);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd website && node --test tests/choreo.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `assets/js/choreo.js`.

- [ ] **Step 3: Write the choreography**

**File:** `website/assets/js/choreo.js`
```js
// Choreography: where each mote wants to be at a given moment of the page.
// Pure functions of (chapter, progress, viewport, anchors, labels): no DOM, no
// clock. The renderer eases motes toward these targets, so scrolling either
// way plays the story either way. Motion is atmosphere: every fact the water
// shows is also written on the page (PHILOSOPHY §4).

export const CHAPTERS = ['top', 'how', 'capture', 'currents', 'resurface', 'ask', 'grow', 'ambient', 'deep'];

/** How lively the water is per chapter; wander and breathing scale with it. */
export const ENERGY = {
  top: 1, how: 0.9, capture: 0.9, currents: 0.8, resurface: 0.8,
  ask: 0.7, grow: 0.5, ambient: 0.6, deep: 0.25,
};

/** Motes per current that gather in the foreground; the rest stay in the depth. */
export const FOREGROUND = 5;

const GOLDEN = 0.6180339887498949;
const PLASTIC = 0.7548776662466927;
const GOLDEN_ANGLE = 2.399963229728653;
const CLUSTER_HUES = [0.12, 0.58, 0.34, 0.82];
const EDGE = 8;

export const mix = (a, b, t) => a + (b - a) * t;
export const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

export function smoothstep(edge0, edge1, x) {
  const t = clamp((x - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

const fract = (v) => v - Math.floor(v);
const center = (rect) => ({ x: rect.x + rect.w / 2, y: rect.y + rect.h / 2 });

function unit(index, salt) {
  let h = Math.imul(index + 1, 0x9e3779b1) ^ Math.imul(salt + 7, 0x85ebca6b);
  h = Math.imul(h ^ (h >>> 16), 0x7feb352d);
  h = Math.imul(h ^ (h >>> 15), 0x846ca68b);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

/** The mote population. The same count always gives the same water. */
export function createMotes(count) {
  const n = Math.max(12, Math.round(count));
  const motes = [];
  for (let i = 0; i < n; i++) {
    const z = 0.12 + 0.88 * unit(i, 1);
    motes.push({
      id: i,
      home: { u: 0.04 + 0.92 * fract(0.5 + i * GOLDEN), v: 0.04 + 0.92 * fract(0.5 + i * PLASTIC) },
      z,
      r: 3 + 10 * (1 - z) * (0.6 + 0.4 * unit(i, 2)),
      hue: CLUSTER_HUES[i % 4],
      cluster: i % 4,
      rank: Math.floor(i / 4),
      role: null,
      sourceIndex: -1,
      seed: unit(i, 3),
    });
  }
  // The story's cast: the resurfacing thought, and three sources drawn from
  // the light and color current the Ask chapter asks about.
  motes[5].role = 'warm';
  [0, 4, 8].forEach((id, k) => {
    motes[id].role = 'source';
    motes[id].sourceIndex = k;
  });
  return motes;
}

function scatter(m, ctx, lower = 1) {
  const top = ctx.vh * (1 - lower);
  return { x: m.home.u * ctx.vw, y: top + m.home.v * (ctx.vh - top) };
}

function target(m, pos, extra = {}) {
  return {
    x: pos.x, y: pos.y, r: m.r, z: m.z, alpha: 1 - 0.55 * m.z, warm: 0,
    label: null, labelAlpha: 0, link: null, linkAlpha: 0, ...extra,
  };
}

function receded(m, ctx, depth, dim, lower = 1) {
  return target(m, scatter(m, ctx, lower), {
    z: Math.min(1, m.z + depth),
    alpha: (1 - 0.55 * m.z) * dim,
  });
}

function inside(point, rect, pad) {
  return point.x > rect.x - pad && point.x < rect.x + rect.w + pad
    && point.y > rect.y - pad && point.y < rect.y + rect.h + pad;
}

function clusterCenter(cluster, phone, ctx) {
  if (ctx.vw < 900 || !phone) {
    const spots = [[0.25, 0.22], [0.75, 0.3], [0.28, 0.72], [0.74, 0.8]];
    return { x: spots[cluster][0] * ctx.vw, y: spots[cluster][1] * ctx.vh };
  }
  // Wide screens: two currents on each side of the phone, clear of the text column.
  const c = center(phone);
  const side = cluster % 2 === 0 ? -1 : 1;
  const rows = [-0.28, -0.1, 0.2, 0.34];
  return {
    x: clamp(c.x + side * (phone.w / 2 + 80), 70, ctx.vw - 70),
    y: clamp(c.y + rows[cluster] * phone.h, 70, ctx.vh - 70),
  };
}

const LAYOUTS = {
  top(m, ctx) {
    const t = target(m, scatter(m, ctx, 0.8));
    const phone = ctx.anchors['hero-phone'];
    if (phone && inside(t, phone, 14)) t.alpha = 0;
    return t;
  },

  how: (m, ctx) => receded(m, ctx, 0.15, 0.8),

  capture: (m, ctx) => receded(m, ctx, 0.05, 0.85),

  currents(m, ctx) {
    const phone = ctx.anchors['currents-phone'];
    const g = smoothstep(0.08, 0.55, ctx.progress);
    const from = scatter(m, ctx);
    if (m.rank >= FOREGROUND) {
      return target(m, from, { z: Math.min(1, m.z + 0.25 * g), alpha: (1 - 0.55 * m.z) * (1 - 0.45 * g) });
    }
    const c = clusterCenter(m.cluster, phone, ctx);
    const k = m.rank;
    const rho = k === 0 ? 0 : 22 * Math.sqrt(k + 0.35);
    const angle = k * GOLDEN_ANGLE + m.cluster * 1.3;
    const size = k === 0 ? 11 : 6 + 2 * ((k * 7) % 3);
    return target(m, {
      x: mix(from.x, c.x + rho * Math.cos(angle), g),
      y: mix(from.y, c.y + rho * Math.sin(angle), g),
    }, {
      r: mix(m.r, size, g),
      z: mix(m.z, 0.04 * k, g),
      alpha: mix(1 - 0.55 * m.z, 1, g),
      label: k === 0 ? (ctx.labels.currents?.[m.cluster] ?? null) : null,
      labelAlpha: k === 0 ? smoothstep(0.5, 0.8, ctx.progress) : 0,
    });
  },

  resurface(m, ctx) {
    const widget = ctx.anchors['resurface-widget'];
    if (m.role !== 'warm' || !widget) return receded(m, ctx, 0.2, 0.7);
    const p = ctx.progress;
    const rise = smoothstep(0.05, 0.7, p);
    return target(m, {
      x: widget.x + widget.w / 2,
      y: mix(ctx.vh * 0.96, widget.y - 52, rise),
    }, {
      r: mix(4, 12, rise),
      z: mix(0.9, 0, rise),
      alpha: mix(0.35, 1, rise),
      warm: smoothstep(0.3, 0.8, p),
      label: ctx.labels.resurface ?? null,
      labelAlpha: smoothstep(0.6, 0.85, p),
    });
  },

  ask(m, ctx) {
    const phone = ctx.anchors['ask-phone'];
    if (m.role !== 'source' || !phone) return receded(m, ctx, 0.2, 0.6);
    const p = ctx.progress;
    const k = m.sourceIndex;
    const show = smoothstep(0.1, 0.5, p);
    const wide = ctx.vw >= 900;
    const to = wide
      ? { x: phone.x - 70 - 24 * (k % 2), y: phone.y + phone.h * (0.3 + 0.15 * k) }
      : { x: phone.x + phone.w * (0.2 + 0.3 * k), y: phone.y - 56 - 16 * (k % 2) };
    const link = wide
      ? { x: phone.x - 2, y: phone.y + phone.h * (0.56 + 0.07 * k) }
      : { x: to.x, y: phone.y + 2 };
    const from = scatter(m, ctx);
    return target(m, { x: mix(from.x, to.x, show), y: mix(from.y, to.y, show) }, {
      r: mix(m.r, 9, show),
      z: mix(m.z, 0, show),
      alpha: mix(1 - 0.55 * m.z, 1, show),
      link,
      linkAlpha: smoothstep(0.35, 0.7, p),
    });
  },

  grow(m, ctx) {
    // After the open water, motes settle into three quiet shelves along the
    // bottom of the view: the Library's calm, in miniature.
    const settle = smoothstep(0, 0.6, ctx.progress);
    const row = m.id % 3;
    const perRow = Math.ceil(ctx.count / 3);
    const col = Math.floor(m.id / 3);
    const from = scatter(m, ctx);
    return target(m, {
      x: mix(from.x, ctx.vw * (0.06 + (0.88 * (col + 0.5)) / perRow), settle),
      y: mix(from.y, ctx.vh * (0.8 + 0.06 * row), settle),
    }, {
      r: mix(m.r, row === 0 ? 5 : 3.5, settle),
      z: mix(m.z, 0.45 + 0.15 * row, settle),
      alpha: mix(1 - 0.55 * m.z, 0.5, settle),
    });
  },

  ambient: (m, ctx) => receded(m, ctx, 0.3, 0.55),

  deep: (m, ctx) => receded(m, ctx, 0.4, 0.35, 0.45),
};

function blendTargets(a, b, t) {
  const weightA = a.labelAlpha * (1 - t);
  const weightB = b.labelAlpha * t;
  let link = a.link ?? b.link;
  if (a.link && b.link) link = { x: mix(a.link.x, b.link.x, t), y: mix(a.link.y, b.link.y, t) };
  return {
    x: mix(a.x, b.x, t), y: mix(a.y, b.y, t), r: mix(a.r, b.r, t), z: mix(a.z, b.z, t),
    alpha: mix(a.alpha, b.alpha, t), warm: mix(a.warm, b.warm, t),
    label: weightA >= weightB ? a.label : b.label,
    labelAlpha: Math.max(weightA, weightB),
    link,
    linkAlpha: mix(a.linkAlpha, b.linkAlpha, t),
  };
}

function finish(t, ctx) {
  t.x = clamp(t.x, EDGE, ctx.vw - EDGE);
  t.y = clamp(t.y, EDGE, ctx.vh - EDGE);
  t.alpha = clamp(t.alpha, 0, 1);
  t.z = clamp(t.z, 0, 1);
  return t;
}

/** Targets for every mote. Near a chapter's end, `next` and `blend` hand over to the next one. */
export function layout(state, motes, view) {
  const ctx = {
    vw: view.vw, vh: view.vh, anchors: view.anchors ?? {}, labels: view.labels ?? {}, count: motes.length,
  };
  const first = LAYOUTS[state.chapter] ?? LAYOUTS.ambient;
  const second = state.next ? (LAYOUTS[state.next] ?? LAYOUTS.ambient) : null;
  const blend = second ? clamp(state.blend ?? 0, 0, 1) : 0;
  const here = { ...ctx, progress: clamp(state.progress ?? 0, 0, 1) };
  const ahead = { ...ctx, progress: 0 };
  return motes.map((m) => {
    const a = first(m, here);
    return finish(blend > 0 ? blendTargets(a, second(m, ahead), blend) : a, ctx);
  });
}

export function energyFor(state) {
  const a = ENERGY[state.chapter] ?? ENERGY.ambient;
  if (!state.next) return a;
  return mix(a, ENERGY[state.next] ?? ENERGY.ambient, clamp(state.blend ?? 0, 0, 1));
}

/** The portal ring's radius: the phone stands inside it (diameter 0.95 of its height). */
export function ringRadius(rect) {
  return rect.h * 0.475;
}

/** Rings around the hero phone (full) and the final phone (faint), while on screen. */
export function ringsFor(view) {
  const rings = [];
  for (const [name, alpha] of [['hero-phone', 1], ['final-phone', 0.45]]) {
    const rect = view.anchors?.[name];
    if (!rect) continue;
    const R = ringRadius(rect);
    const c = center(rect);
    if (c.y + R * 1.3 < 0 || c.y - R * 1.3 > view.vh) continue;
    rings.push({ x: c.x, y: c.y, R, alpha });
  }
  return rings;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd website && node --test tests/choreo.test.mjs`
Expected: `# pass 9`, `# fail 0`.

- [ ] **Step 5: Checkpoint**

Run: `cd website && node --test tests/*.test.mjs`
Expected: all pass (21 tests). No commit.

---

### Task 4: Brand assets and real app screens

**Files:**
- Create: `website/assets/img/apple-touch-icon.png`, `favicon-32.png`, `favicon-16.png`, `icon-192.webp`
- Create: `website/assets/audio/ocean-received.m4a`
- Create: `website/assets/img/badge-en.svg`, `website/assets/img/badge-zh.svg` (download approved by Malik on 2026-09-18)
- Create: `website/assets/img/screens/ocean.webp`, `current.webp`, `capture.webp`, `ask.webp`, `detail.webp`, `library.webp`

**Interfaces:**
- Produces: the asset paths the pages reference. Screens are 640 px wide; record their height in Step 8 (the pages assume `height="1391"` for a 1206×2622 simulator capture).
- Touches nothing in the app. The Xcode project is generated (gitignored) and DerivedData goes to `SCRATCH`.

- [ ] **Step 1: Icons from the app icon**

```bash
SCRATCH=/private/tmp/claude-501/-Users-malik-Documents-inspire-ocean--claude-worktrees-oryne-official-website-08655b/fede2667-1588-47b9-a03b-c1e078c2f031/scratchpad
mkdir -p website/assets/img/screens website/assets/audio "$SCRATCH/raw"
ICON=Oryne/Assets.xcassets/AppIcon.appiconset/icon-1024.png
sips -z 180 180 "$ICON" --out website/assets/img/apple-touch-icon.png >/dev/null
sips -z 32 32 "$ICON" --out website/assets/img/favicon-32.png >/dev/null
sips -z 16 16 "$ICON" --out website/assets/img/favicon-16.png >/dev/null
sips -z 192 192 "$ICON" --out "$SCRATCH/icon-192.png" >/dev/null
cwebp -quiet -q 90 "$SCRATCH/icon-192.png" -o website/assets/img/icon-192.webp
ls -l website/assets/img
```

Expected: four icon files; `icon-192.webp` under 20 KB.

- [ ] **Step 2: The chime, rendered by the app's own generator**

```bash
SCRATCH=/private/tmp/claude-501/-Users-malik-Documents-inspire-ocean--claude-worktrees-oryne-official-website-08655b/fede2667-1588-47b9-a03b-c1e078c2f031/scratchpad
python3 tools/generate_ocean_received.py --wav-out "$SCRATCH/ocean-received.wav" --out "$SCRATCH/ocean-received.caf"
afconvert -f m4af -d aac -b 96000 "$SCRATCH/ocean-received.wav" website/assets/audio/ocean-received.m4a
afinfo website/assets/audio/ocean-received.m4a | grep -E "format|duration"
ls -l website/assets/audio/ocean-received.m4a
git status --short Oryne
```

Expected: `wrote …/scratchpad/ocean-received.caf`; an AAC file of about 1.4 s, under 30 KB; `git status --short Oryne` prints nothing (the app's `OceanReceived.caf` is untouched). Never run the generator without `--out`: its default overwrites the app's bundled sound.

- [ ] **Step 3: Apple's official App Store badges (black, English and Simplified Chinese)**

```bash
curl -fsSL -o website/assets/img/badge-en.svg "https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83"
curl -fsSL -o website/assets/img/badge-zh.svg "https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/zh-cn?size=250x83"
head -c 80 website/assets/img/badge-en.svg; echo
head -c 80 website/assets/img/badge-zh.svg; echo
ls -l website/assets/img/badge-*.svg
```

Expected: both files begin with `<svg` (or an XML prolog then `<svg`) and are under 40 KB. Use them unmodified (Apple's badge guidelines). If the endpoint returns anything other than SVG, open `https://tools.applemediaservices.com/app-store/` in the browser pane, use the download link it shows for the black badge in each language, and tell Malik which files were used.

- [ ] **Step 4: Look up the live App Store listing (read only)**

```bash
curl -fsSL "https://itunes.apple.com/search?term=Oryne&entity=software&limit=10" \
  | python3 -c "import json,sys; [print(r['trackName'], '|', r['sellerName'], '|', r['trackViewUrl']) for r in json.load(sys.stdin)['results']]"
```

Expected: a line whose name is Oryne. Record its `trackViewUrl` (strip any `?uo=` query) and its numeric id, and ask Malik to confirm it in the Task 7 checkpoint message. Until he confirms, pages keep the placeholder `https://apps.apple.com/app/id0000000000`.

- [ ] **Step 5: Build the app for the simulator**

```bash
SCRATCH=/private/tmp/claude-501/-Users-malik-Documents-inspire-ocean--claude-worktrees-oryne-official-website-08655b/fede2667-1588-47b9-a03b-c1e078c2f031/scratchpad
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=0EBF66EE-3E7D-48F9-9D44-E7B1A58DACF1   # iPhone 17 Pro
xcodegen generate
xcodebuild -project Oryne.xcodeproj -scheme Oryne -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$SCRATCH/dd" build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`. If the build fails, stop and report to Malik with the error. Do not change app code to make it build. The spec's fallback (HTML thought cards in place of screens) needs his go-ahead.

- [ ] **Step 6: Boot, clean status bar, install, skip onboarding**

```bash
SCRATCH=/private/tmp/claude-501/-Users-malik-Documents-inspire-ocean--claude-worktrees-oryne-official-website-08655b/fede2667-1588-47b9-a03b-c1e078c2f031/scratchpad
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=0EBF66EE-3E7D-48F9-9D44-E7B1A58DACF1
xcrun simctl boot $UDID 2>/dev/null; xcrun simctl bootstatus $UDID -b
xcrun simctl status_bar $UDID override --time 9:41 --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
APP=$(find "$SCRATCH/dd/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name 'Oryne.app')
xcrun simctl uninstall $UDID com.inspireocean.app 2>/dev/null
xcrun simctl install $UDID "$APP"
GROUP=$(xcrun simctl get_app_container $UDID com.inspireocean.app groups | awk '/group.com.inspireocean.shared/ {print $2}')
xcrun simctl spawn $UDID defaults write "$GROUP/Library/Preferences/group.com.inspireocean.shared" fastCapture.onboardingCompleted -bool true
echo "$GROUP"
```

Expected: a group container path is printed. Writing the preference before the first launch skips onboarding (see the `oryne-build-run` notes).

- [ ] **Step 7: Capture the six screens**

Launch helper for each screen (English, marketing seed):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=0EBF66EE-3E7D-48F9-9D44-E7B1A58DACF1
TAB=ocean   # set per screen: ocean | capture | ask | library
xcrun simctl terminate $UDID com.inspireocean.app 2>/dev/null
SIMCTL_CHILD_OCEAN_SCREENSHOT_SEED=1 SIMCTL_CHILD_OCEAN_START_TAB=$TAB \
  xcrun simctl launch $UDID com.inspireocean.app -AppleLanguages '(en)' -AppleLocale en_US
```

Then drive each screen with the iOS Simulator tool (`inspect` before every `tap`; wait by re-inspecting until the expected element is present), and save a clean capture with `xcrun simctl io $UDID screenshot "$SCRATCH/raw/<name>.png"`:

1. `ocean.png`: `TAB=ocean`. Wait until the field shows its currents. Capture.
2. `current.png`: from the Ocean, `inspect` for the element labeled `light and color`, tap the center of its frame. The current's stream opens (every thought about light and color). Capture.
3. `capture.png`: `TAB=capture`. The empty capture screen with `What just drifted by?`. Capture.
4. `ask.png`: `TAB=ask`. Tap the question field, type `What have I been noticing about light?`, send. Wait until the answer and its source chips (for example `Sunset gradient study`) are present. Capture.
5. `detail.png`: `TAB=library`. Open `Sunset gradient study`. Choose `Grow a branch`, pick `Question`, type `What palette would dusk suggest for the app?`, save. Back on the thought, scroll until the branch is visible with the original above it. Capture.
6. `library.png`: `TAB=library`. The DEBUG seed switches the Library to Related. Wait for the masonry grid with images. Capture.

- [ ] **Step 8: Encode to WebP and record the size**

```bash
SCRATCH=/private/tmp/claude-501/-Users-malik-Documents-inspire-ocean--claude-worktrees-oryne-official-website-08655b/fede2667-1588-47b9-a03b-c1e078c2f031/scratchpad
for n in ocean current capture ask detail library; do
  sips --resampleWidth 640 "$SCRATCH/raw/$n.png" --out "$SCRATCH/raw/$n-640.png" >/dev/null
  cwebp -quiet -q 82 "$SCRATCH/raw/$n-640.png" -o "website/assets/img/screens/$n.webp"
done
sips -g pixelWidth -g pixelHeight "$SCRATCH/raw/ocean-640.png" | tail -2
ls -l website/assets/img/screens
```

Expected: six WebP files, each under 150 KB, 640 px wide. Note the printed height. If it is not 1391, use that number wherever Task 7, 8, and 9 write `height="1391"`, and in the `.phone` `aspect-ratio` in `site.css`.

- [ ] **Step 9: Review every screen**

Open each `$SCRATCH/raw/<name>-640.png` with the Read tool. Each must show: the 9:41 status bar with full battery, no onboarding sheet, no debug overlay, only seed content (no personal data), and the state named in Step 7. Recapture any that fail.

- [ ] **Step 10: Release the simulator and checkpoint**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun simctl status_bar 0EBF66EE-3E7D-48F9-9D44-E7B1A58DACF1 clear
xcrun simctl shutdown 0EBF66EE-3E7D-48F9-9D44-E7B1A58DACF1
git status --short
```

Expected: only `website/` and `docs/superpowers/` entries plus the pre-existing `default.profraw`. `Oryne.xcodeproj` is ignored. No commit.

---

### Task 5: The Ocean renderer

**Files:**
- Create: `website/tests/ocean.test.mjs`
- Create: `website/assets/js/orbs.js`
- Create: `website/assets/js/ocean.js`

**Interfaces:**
- Consumes: `breathAt`, `now` (breath.js); `createNoise2D` (noise.js); `Target` and `Mote` shapes (choreo.js).
- Produces:
  - `orbs.js`: `tint(hue, brightness = 0.85) → [r, g, b]`; `WARM = [242, 237, 224]`; `orbSprite(radius, depth, warm, hue, dpr) → { canvas, size }` (size in CSS px, cached by bucket).
  - `ocean.js`: `springStep(position, velocity, target, dt, omega = 2.2) → [position, velocity]`; `wanderOffset(seed, t, amplitude) → [dx, dy]`; `breathing(seed, t, depth) → scale`; `createOcean({ water, field, grain, policy }) → { setScene({ depth, motes, targets, rings, energy }), setPolicy('full'|'still'), release({ text, x, y }), resize(), start(), stop(), stats() → { fps, ms, motes, degraded } }`.

- [ ] **Step 1: Write the failing tests**

**File:** `website/tests/ocean.test.mjs`
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { breathing, springStep, wanderOffset } from '../assets/js/ocean.js';
import { tint } from '../assets/js/orbs.js';

test('the spring arrives without overshooting', () => {
  let x = 0;
  let v = 0;
  let peak = 0;
  for (let i = 0; i < 600; i++) {
    [x, v] = springStep(x, v, 100, 1 / 60);
    peak = Math.max(peak, x);
  }
  assert.ok(peak <= 100 + 1e-9, `overshoot to ${peak}`);
  assert.ok(Math.abs(x - 100) < 0.05, `ended at ${x}`);
});

test('the spring stays calm through long frames', () => {
  let x = 0;
  let v = 0;
  for (let i = 0; i < 100; i++) [x, v] = springStep(x, v, 100, 0.05);
  assert.ok(x > 99 && x <= 100 + 1e-9, `ended at ${x}`);
});

test('wander stays within its amplitude and is deterministic', () => {
  for (let t = 0; t < 120; t += 0.7) {
    const [x, y] = wanderOffset(0.37, t, 4);
    assert.ok(Math.abs(x) <= 4 && Math.abs(y) <= 4);
    assert.deepEqual(wanderOffset(0.37, t, 4), [x, y]);
  }
});

test('wander is smooth from frame to frame', () => {
  for (let t = 0; t < 60; t += 0.1) {
    const [a] = wanderOffset(0.8, t, 4);
    const [b] = wanderOffset(0.8, t + 1 / 60, 4);
    assert.ok(Math.abs(a - b) < 0.1);
  }
});

test('breathing stays within its depth', () => {
  for (let t = 0; t < 60; t += 0.3) {
    const s = breathing(0.42, t, 0.02);
    assert.ok(s >= 0.98 - 1e-9 && s <= 1.02 + 1e-9);
  }
});

test('mote tint nudges temperature, never saturation', () => {
  assert.deepEqual(tint(0.5), [217, 217, 217]);
  const [r, g, b] = tint(1);
  assert.ok(r > g && g > b);
  assert.ok(r - b <= 13);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd website && node --test tests/ocean.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `assets/js/ocean.js`.

- [ ] **Step 3: Write the mote sprites**

**File:** `website/assets/js/orbs.js`
```js
// Mote sprites, after the app's OrbTextures: a faint white glass body, a
// whisper of hue, one restrained rim (warm for the resurfacing thought). No
// halos and no luminous cores (PHILOSOPHY §4). Depth softens a mote by
// widening a radial falloff rather than a blur filter, which every browser
// draws the same way. Sprites are cached by bucket so drawing stays cheap.

const cache = new Map();

export const WARM = [242, 237, 224];

/** OceanTheme.color(forHue:): brightness carries hierarchy, the hue only nudges temperature. */
export function tint(hue, brightness = 0.85) {
  const shift = (hue - 0.5) * 0.05;
  const channel = (v) => Math.round(Math.max(0, Math.min(1, v)) * 255);
  return [channel(brightness + shift), channel(brightness), channel(brightness - shift)];
}

function draw(radius, soft, warm, hue, scale) {
  const spread = soft * 3;
  const shadow = radius >= 9 && soft < 0.5;
  const pad = 3 + spread + (shadow ? 10 : 0);
  const size = Math.ceil((radius + pad) * 2);
  const canvas = document.createElement('canvas');
  canvas.width = Math.ceil(size * scale);
  canvas.height = canvas.width;
  const ctx = canvas.getContext('2d');
  ctx.scale(scale, scale);
  const c = size / 2;
  const [tr, tg, tb] = tint(hue);
  const circle = (r, dy = 0) => {
    ctx.beginPath();
    ctx.arc(c, c + dy, r, 0, Math.PI * 2);
  };

  if (shadow) {
    // A soft depth shadow: a dark pool sitting slightly low, outside the body.
    const pool = ctx.createRadialGradient(c, c + 5, radius * 0.8, c, c + 5, radius + 9);
    pool.addColorStop(0, 'rgba(0,0,0,0.22)');
    pool.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = pool;
    circle(radius + 9, 5);
    ctx.fill();
  }

  // Glass body: a faint lift off the dark water, then the hue's whisper.
  const fill = (color) => {
    if (spread === 0) {
      ctx.fillStyle = color(1);
      circle(radius);
      ctx.fill();
      return;
    }
    const falloff = ctx.createRadialGradient(c, c, Math.max(0, radius - spread), c, c, radius + spread);
    falloff.addColorStop(0, color(1));
    falloff.addColorStop(1, color(0));
    ctx.fillStyle = falloff;
    circle(radius + spread);
    ctx.fill();
  };
  fill((k) => `rgba(255,255,255,${0.08 * k})`);
  fill((k) => `rgba(${tr},${tg},${tb},${0.13 * k})`);

  if (radius >= 9 && soft === 0) {
    // Soft light from above, fading out by the middle of the orb.
    ctx.save();
    circle(radius);
    ctx.clip();
    const light = ctx.createLinearGradient(0, c - radius, 0, c);
    light.addColorStop(0, 'rgba(255,255,255,0.14)');
    light.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = light;
    ctx.fillRect(c - radius, c - radius, radius * 2, radius);
    ctx.restore();
  }

  const rim = 1 - soft;
  if (rim > 0) {
    ctx.lineWidth = 0.75;
    ctx.strokeStyle = warm
      ? `rgba(${WARM.join(',')},${0.45 * rim})`
      : `rgba(255,255,255,${0.16 * rim})`;
    circle(radius - 0.375);
    ctx.stroke();
  }
  return { canvas, size };
}

/** A cached sprite for a mote of this radius (px), depth (0 near, 1 far), warmth, and hue. */
export function orbSprite(radius, depth, warm, hue, dpr) {
  const r = Math.max(1.5, Math.round(radius * 2) / 2);
  const soft = Math.round(Math.max(0, Math.min(1, depth)) * 4) / 4;
  const hueBucket = Math.round(hue * 8);
  const scale = Math.min(2, Math.max(1, dpr));
  const key = `${r}|${soft}|${warm ? 1 : 0}|${hueBucket}|${scale}`;
  let sprite = cache.get(key);
  if (!sprite) {
    sprite = draw(r, soft, warm, hueBucket / 8, scale);
    cache.set(key, sprite);
  }
  return sprite;
}
```

- [ ] **Step 4: Write the renderer**

**File:** `website/assets/js/ocean.js`
```js
// The Ocean behind every page. A WebGL water body after the app's
// OceanBackground (near-black, lit toward the upper centre, the light roaming
// slowly), and above it a 2D field: stars, the portal ring from the app icon,
// hairline waves, and the motes. It knows nothing about scrolling or language:
// site.js hands it a scene, and it eases the water toward it.

import { breathAt, now } from './breath.js';
import { createNoise2D } from './noise.js';
import { WARM, orbSprite } from './orbs.js';

const TAU = Math.PI * 2;
const noise = createNoise2D(0x0cea);
const LABEL_FONT = '500 12px -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", system-ui, sans-serif';
const RING_STARS = [[-0.72, -0.3], [-0.6, 0.18], [0.62, -0.42], [0.78, 0.1], [0.66, 0.4], [-0.8, 0.02]];

function fract(v) {
  return v - Math.floor(v);
}

// ------------------------------------------------------------ pure helpers

/** One exact step of a critically damped spring: a calm arrival that never overshoots from rest. */
export function springStep(position, velocity, target, dt, omega = 2.2) {
  const offset = position - target;
  const carry = (velocity + omega * offset) * dt;
  const decay = Math.exp(-omega * dt);
  return [target + (offset + carry) * decay, (velocity - omega * carry) * decay];
}

/** A mote's wander on the shared field, in points: 8 to 15 s a cycle, as in the app. */
export function wanderOffset(seed, t, amplitude) {
  const progress = t / (8 + 7 * seed);
  return [
    noise(progress + seed * 16, seed * 7.3) * amplitude,
    noise(progress + 5.2 + seed * 11, seed * 3.1 + 9) * amplitude,
  ];
}

/** Breathing scale around 1: 6 to 10 s a breath, never in step with a neighbour. */
export function breathing(seed, t, depth) {
  const period = 6 + 4 * fract(seed * 7.919);
  return 1 + depth * Math.sin((t * TAU) / period + seed * TAU);
}

// ------------------------------------------------------------------ water

const VERTEX = `
attribute vec2 aPosition;
void main() { gl_Position = vec4(aPosition, 0.0, 1.0); }
`;

const FRAGMENT = `
precision mediump float;
uniform vec2 uResolution;
uniform float uTime;
uniform float uDepth;
uniform float uBreath;

const vec3 ABYSS = vec3(0.020, 0.020, 0.030);
const vec3 DEEP = vec3(0.050, 0.055, 0.065);
const vec3 MID = vec3(0.090, 0.095, 0.110);
const vec3 CURRENT = vec3(0.150, 0.155, 0.175);

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float valueNoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * valueNoise(p);
    p = p * 2.03 + 11.7;
    a *= 0.5;
  }
  return v;
}

void main() {
  vec2 uv = gl_FragCoord.xy / uResolution;
  float aspect = uResolution.x / uResolution.y;
  vec2 p = vec2(uv.x * aspect, uv.y);
  float t = uTime;

  // The lit region roams like light through water (OceanBackground's centre wander).
  vec2 light = vec2((0.5 + 0.10 * sin(t * 0.037)) * aspect, 0.64 + 0.08 * cos(t * 0.032));
  vec2 q = vec2(fbm(p * 1.4 + vec2(0.0, t * 0.020)), fbm(p * 1.4 + vec2(5.2, -t * 0.017)));
  float caustic = fbm(p * 2.2 + 1.8 * q + vec2(t * 0.012, 0.0));
  float lit = (1.0 - smoothstep(0.0, 1.05, distance(p, light))) * (0.72 + 0.28 * caustic);
  lit *= (1.0 - 0.78 * uDepth) * (0.93 + 0.07 * uBreath);

  vec3 color = mix(ABYSS, DEEP, smoothstep(0.0, 1.0, uv.y) * (1.0 - 0.6 * uDepth));
  color = mix(color, MID, clamp(lit, 0.0, 1.0) * 0.9);
  color = mix(color, CURRENT, clamp(lit * lit, 0.0, 1.0) * 0.75);
  color += vec3(-0.004, 0.0, 0.006) * uDepth;

  // Depth vignette: darker toward the edges, focus held in the middle.
  float vignette = smoothstep(0.35, 1.05, distance(uv, vec2(0.5, 0.55)));
  color = mix(color, ABYSS * 0.45, vignette * 0.55);

  color += (hash(gl_FragCoord.xy + fract(t)) - 0.5) / 255.0;
  gl_FragColor = vec4(color, 1.0);
}
`;

function createWater(canvas) {
  const gl = canvas.getContext('webgl', {
    alpha: false, antialias: false, depth: false, stencil: false,
    premultipliedAlpha: false, powerPreference: 'low-power',
  });
  if (!gl) return null;
  const compile = (type, source) => {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader) || 'shader');
    return shader;
  };
  const program = gl.createProgram();
  try {
    gl.attachShader(program, compile(gl.VERTEX_SHADER, VERTEX));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAGMENT));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program) || 'link');
  } catch (error) {
    console.warn('Oryne: the WebGL water failed; the CSS water stands in.', error);
    return null;
  }
  gl.useProgram(program);
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const position = gl.getAttribLocation(program, 'aPosition');
  gl.enableVertexAttribArray(position);
  gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
  const uniform = (name) => gl.getUniformLocation(program, name);
  const u = {
    resolution: uniform('uResolution'), time: uniform('uTime'),
    depth: uniform('uDepth'), breath: uniform('uBreath'),
  };
  let lost = false;
  canvas.addEventListener('webglcontextlost', (event) => {
    event.preventDefault();
    lost = true;
    canvas.hidden = true;
  });
  return {
    resize(width, height, scale) {
      canvas.width = Math.max(1, Math.round(width * scale));
      canvas.height = Math.max(1, Math.round(height * scale));
      gl.viewport(0, 0, canvas.width, canvas.height);
    },
    draw(time, depth, breath) {
      if (lost) return;
      gl.uniform2f(u.resolution, canvas.width, canvas.height);
      gl.uniform1f(u.time, time);
      gl.uniform1f(u.depth, depth);
      gl.uniform1f(u.breath, breath);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    },
  };
}

// ------------------------------------------------------------ field pieces

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function makeStars(count) {
  const rand = mulberry32(0x5eed);
  return Array.from({ length: count }, () => ({
    u: rand(), v: rand() * 0.55, r: 0.4 + rand() * 0.7, a: 0.12 + rand() * 0.33, phase: rand() * TAU,
  }));
}

function grainTile() {
  const tile = document.createElement('canvas');
  tile.width = 128;
  tile.height = 128;
  const context = tile.getContext('2d');
  const image = context.createImageData(128, 128);
  for (let i = 0; i < image.data.length; i += 4) {
    const v = Math.random() * 255;
    image.data[i] = v;
    image.data[i + 1] = v;
    image.data[i + 2] = v;
    image.data[i + 3] = 22;
  }
  context.putImageData(image, 0, 0);
  return tile.toDataURL('image/png');
}

function drawRing(ctx, ring, level, t, dpr) {
  const { x, y, R, alpha: A } = ring;
  if (A <= 0.01) return;
  const lift = 0.85 + 0.15 * level;
  const r = R * (1 + 0.006 * level);

  // The frosted band around the portal, with its faint outer hairline.
  const band = ctx.createRadialGradient(x, y, r * 0.98, x, y, r * 1.24);
  band.addColorStop(0, `rgba(170,186,220,${(0.07 * A).toFixed(3)})`);
  band.addColorStop(1, 'rgba(170,186,220,0)');
  ctx.fillStyle = band;
  ctx.beginPath();
  ctx.arc(x, y, r * 1.24, 0, TAU);
  ctx.arc(x, y, r * 0.98, 0, TAU);
  ctx.fill('evenodd');
  ctx.lineWidth = 1;
  ctx.strokeStyle = `rgba(255,255,255,${(0.05 * A).toFixed(3)})`;
  ctx.beginPath();
  ctx.arc(x, y, r * 1.24, 0, TAU);
  ctx.stroke();

  // The dark interior, and the paler lens along its upper left.
  ctx.fillStyle = `rgba(2,3,7,${(0.5 * A).toFixed(3)})`;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, TAU);
  ctx.fill();
  const lens = ctx.createLinearGradient(x - r, y - r, x + r * 0.3, y + r * 0.3);
  lens.addColorStop(0, `rgba(120,142,190,${(0.16 * A).toFixed(3)})`);
  lens.addColorStop(1, 'rgba(120,142,190,0)');
  ctx.fillStyle = lens;
  ctx.beginPath();
  ctx.arc(x - r * 0.05, y - r * 0.04, r * 0.99, 0, TAU);
  ctx.arc(x + r * 0.03, y + r * 0.03, r * 0.9, 0, TAU);
  ctx.fill('evenodd');

  // A few stars and the icon's wave, inside the portal.
  ctx.save();
  ctx.beginPath();
  ctx.arc(x, y, r * 0.985, 0, TAU);
  ctx.clip();
  ctx.fillStyle = `rgba(255,255,255,${(0.5 * A).toFixed(3)})`;
  for (const [u, v] of RING_STARS) {
    ctx.beginPath();
    ctx.arc(x + u * r, y + v * r, 0.8, 0, TAU);
    ctx.fill();
  }
  ctx.lineWidth = 1;
  for (let k = 0; k < 2; k++) {
    ctx.strokeStyle = `rgba(170,190,230,${((k === 0 ? 0.3 : 0.14) * A * lift).toFixed(3)})`;
    ctx.beginPath();
    const base = y + r * (0.52 + 0.1 * k);
    for (let px = -r; px <= r; px += 6) {
      const wy = base
        + Math.sin((px / r) * 3.1 + t * 0.35 + k) * r * 0.035
        - Math.cos((px / r) * 1.4 - t * 0.2) * r * 0.02;
      if (px === -r) ctx.moveTo(x + px, wy);
      else ctx.lineTo(x + px, wy);
    }
    ctx.stroke();
  }
  ctx.restore();

  // The rim: lit from the lower right as in the icon, fading around the top.
  const a = (v) => (v * A * lift).toFixed(3);
  let rim;
  if (typeof ctx.createConicGradient === 'function') {
    rim = ctx.createConicGradient(Math.PI / 4, x, y);
    rim.addColorStop(0, `rgba(255,255,255,${a(0.95)})`);
    rim.addColorStop(0.12, `rgba(206,218,242,${a(0.7)})`);
    rim.addColorStop(0.3, `rgba(150,168,206,${a(0.28)})`);
    rim.addColorStop(0.5, `rgba(130,148,190,${a(0.08)})`);
    rim.addColorStop(0.7, `rgba(150,168,206,${a(0.24)})`);
    rim.addColorStop(0.88, `rgba(206,218,242,${a(0.65)})`);
    rim.addColorStop(1, `rgba(255,255,255,${a(0.95)})`);
  } else {
    rim = ctx.createLinearGradient(x - r, y - r, x + r, y + r);
    rim.addColorStop(0, `rgba(130,148,190,${a(0.1)})`);
    rim.addColorStop(1, `rgba(255,255,255,${a(0.9)})`);
  }
  ctx.save();
  ctx.shadowColor = `rgba(159,178,214,${a(0.35)})`;
  ctx.shadowBlur = (18 + 12 * level) * dpr;
  ctx.lineWidth = 1.6;
  ctx.strokeStyle = rim;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, TAU);
  ctx.stroke();
  ctx.restore();
}

function drawWaves(ctx, width, baseline, alpha, level, t) {
  if (alpha <= 0.01) return;
  const fade = ctx.createLinearGradient(0, 0, width, 0);
  fade.addColorStop(0, 'rgba(190,205,235,0)');
  fade.addColorStop(0.2, 'rgba(190,205,235,1)');
  fade.addColorStop(0.8, 'rgba(190,205,235,1)');
  fade.addColorStop(1, 'rgba(190,205,235,0)');
  ctx.strokeStyle = fade;
  ctx.lineWidth = 1;
  const amplitude = 5 + 5 * level;
  [0.1, 0.07, 0.045].forEach((strength, k) => {
    ctx.globalAlpha = strength * alpha * (0.8 + 0.2 * level);
    ctx.beginPath();
    for (let x = 0; x <= width + 8; x += 8) {
      const y = baseline + k * 13 + amplitude * (
        0.6 * Math.sin(x * 0.006 + t * 0.4 + k) + 0.4 * noise(x * 0.004 + k * 3, t * 0.05));
      if (x === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();
  });
  ctx.globalAlpha = 1;
}

// ------------------------------------------------------------------ Ocean

export function createOcean({ water: waterCanvas, field, grain, policy = 'full' }) {
  const ctx = field.getContext('2d');
  const water = waterCanvas ? createWater(waterCanvas) : null;
  if (waterCanvas && !water) waterCanvas.hidden = true;
  if (grain) grain.style.backgroundImage = `url(${grainTile()})`;

  const stars = makeStars(44);
  const released = [];
  let mode = policy;
  let scene = { depth: 0, motes: [], targets: [], rings: [], energy: 1 };
  let states = [];
  let vw = 1;
  let vh = 1;
  let dpr = 1;
  let waterScale = 0.5;
  let raf = 0;
  let running = false;
  let dirty = true;
  let last = now();
  let previous = 0;
  let frame = 0;
  let slowFor = 0;
  let degraded = false;
  let fps = 60;
  let ms = 0;

  function kick() {
    if (running && !raf) raf = window.requestAnimationFrame(tick);
  }

  function resize() {
    vw = window.innerWidth;
    vh = window.innerHeight;
    dpr = Math.min(2, window.devicePixelRatio || 1);
    field.width = Math.round(vw * dpr);
    field.height = Math.round(vh * dpr);
    water?.resize(vw, vh, waterScale);
    dirty = true;
    kick();
  }

  function setScene(next) {
    if (states.length !== next.targets.length) {
      states = next.targets.map((t) => ({ ...t, vx: 0, vy: 0, drawX: t.x, drawY: t.y, scale: 1 }));
    }
    scene = next;
    dirty = true;
    kick();
  }

  function setPolicy(next) {
    mode = next;
    dirty = true;
    kick();
  }

  function release({ text, x, y }) {
    released.push({
      text,
      born: now(),
      from: { x, y },
      to: {
        x: Math.min(vw - 40, x + 30 + Math.random() * 90),
        y: Math.min(vh - 60, y + 150 + Math.random() * 70),
      },
      seed: Math.random(),
    });
    if (released.length > 6) released.shift();
    dirty = true;
    kick();
    // A stilled Ocean does not animate: wake once more to let the label go.
    if (mode === 'still') {
      window.setTimeout(() => {
        dirty = true;
        kick();
      }, 4700);
    }
  }

  function update(dt) {
    const still = mode === 'still';
    const ease = still ? 1 : 1 - Math.exp(-dt * 3.2);
    states.forEach((s, i) => {
      const g = scene.targets[i];
      if (!g) return;
      if (still) {
        s.x = g.x;
        s.y = g.y;
        s.vx = 0;
        s.vy = 0;
      } else {
        [s.x, s.vx] = springStep(s.x, s.vx, g.x, dt);
        [s.y, s.vy] = springStep(s.y, s.vy, g.y, dt);
      }
      for (const key of ['r', 'z', 'alpha', 'warm', 'labelAlpha', 'linkAlpha']) {
        s[key] += (g[key] - s[key]) * ease;
      }
      if (g.label && g.labelAlpha > 0.01) s.label = g.label;
      if (g.link) s.link = g.link;
    });
  }

  function place(t, energy) {
    states.forEach((s, i) => {
      const m = scene.motes[i];
      if (!m) return;
      const [wx, wy] = wanderOffset(m.seed, t, (1.5 + 2.5 * (1 - s.z)) * energy);
      s.drawX = s.x + wx;
      s.drawY = s.y + wy;
      s.scale = breathing(m.seed, t, 0.02 * energy);
    });
  }

  function sprite(image, x, y, scale, alpha) {
    if (alpha <= 0.005) return;
    const size = image.size * scale;
    ctx.globalAlpha = Math.min(1, alpha);
    ctx.drawImage(image.canvas, x - size / 2, y - size / 2, size, size);
  }

  function drawStars(t) {
    const fade = Math.max(0, 1 - scene.depth * 1.6);
    if (fade <= 0) return;
    ctx.fillStyle = '#ffffff';
    for (const star of stars) {
      ctx.globalAlpha = star.a * fade * (0.85 + 0.15 * Math.sin(t * 0.3 + star.phase));
      ctx.beginPath();
      ctx.arc(star.u * vw, star.v * vh, star.r, 0, TAU);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  function drawLinks() {
    ctx.lineWidth = 1;
    for (const s of states) {
      if (!s.link || s.linkAlpha < 0.01) continue;
      ctx.strokeStyle = `rgba(200,214,240,${(0.3 * s.linkAlpha).toFixed(3)})`;
      ctx.beginPath();
      ctx.moveTo(s.drawX, s.drawY);
      ctx.quadraticCurveTo((s.drawX + s.link.x) / 2, (s.drawY + s.link.y) / 2 - 18, s.link.x, s.link.y);
      ctx.stroke();
    }
  }

  function drawMotes() {
    const order = states.map((_, i) => i).sort((a, b) => states[b].z - states[a].z);
    const dim = 1 - 0.25 * scene.depth;
    for (const i of order) {
      const s = states[i];
      const m = scene.motes[i];
      if (!m || s.alpha < 0.01) continue;
      if (degraded && m.id % 10 >= 7 && !m.role && s.labelAlpha < 0.01) continue;
      const alpha = s.alpha * dim;
      sprite(orbSprite(s.r, s.z, false, m.hue, dpr), s.drawX, s.drawY, s.scale, alpha * (1 - s.warm));
      if (s.warm > 0.01) sprite(orbSprite(s.r, s.z, true, m.hue, dpr), s.drawX, s.drawY, s.scale, alpha * s.warm);
    }
    ctx.globalAlpha = 1;
  }

  function drawLabels() {
    ctx.font = LABEL_FONT;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    for (const s of states) {
      if (!s.label || s.labelAlpha < 0.02) continue;
      ctx.fillStyle = s.warm > 0.5
        ? `rgba(${WARM.join(',')},${(0.85 * s.labelAlpha).toFixed(3)})`
        : `rgba(255,255,255,${(0.66 * s.labelAlpha).toFixed(3)})`;
      ctx.fillText(s.label, s.drawX, s.drawY + s.r * s.scale + 8);
    }
  }

  function drawReleased() {
    const t = now();
    const still = mode === 'still';
    const easeInOut = (p) => (p < 0.5 ? 2 * p * p : 1 - (-2 * p + 2) ** 2 / 2);
    ctx.font = LABEL_FONT;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    for (const r of released) {
      const age = t - r.born;
      const p = still ? 1 : Math.min(1, age / 2.4);
      const along = (q) => ({
        x: r.from.x + (r.to.x - r.from.x) * easeInOut(q),
        y: r.from.y + (r.to.y - r.from.y) * easeInOut(q),
      });
      const at = along(p);
      if (!still && p >= 1) {
        const [wx, wy] = wanderOffset(r.seed, t, 3);
        at.x += wx;
        at.y += wy;
      }
      if (!still && p < 1) {
        // A short trail behind the falling thought, as in the onboarding's capture visual.
        ctx.fillStyle = '#ffffff';
        [0.18, 0.1, 0.05].forEach((strength, k) => {
          const dot = along(Math.max(0, p - (k + 1) * 0.05));
          ctx.globalAlpha = strength;
          ctx.beginPath();
          ctx.arc(dot.x, dot.y, 2, 0, TAU);
          ctx.fill();
        });
      }
      const settle = Math.min(1, Math.max(0, (age - 30) / 60));   // after half a minute it sinks into the field
      sprite(orbSprite(12, 0, false, 0.5, dpr), at.x, at.y, 1, 1 - 0.6 * settle);
      const labelAlpha = Math.min(1, Math.max(0, 4.5 - age));
      if (labelAlpha > 0) {
        const text = r.text.length > 42 ? `${r.text.slice(0, 41)}…` : r.text;
        ctx.globalAlpha = labelAlpha;
        ctx.fillStyle = 'rgba(255,255,255,0.8)';
        ctx.fillText(text, at.x, at.y + 20);
      }
    }
    ctx.globalAlpha = 1;
  }

  function render() {
    const started = performance.now();
    const clock = now();
    const dt = Math.min(0.05, Math.max(0, clock - last));
    last = clock;
    const t = mode === 'still' ? 0 : clock;
    const energy = mode === 'still' ? 0 : scene.energy;
    const level = breathAt(t).level;

    if (water && (dirty || mode === 'still' || frame % 2 === 0)) water.draw(t, scene.depth, level);

    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, vw, vh);
    drawStars(t);
    for (const ring of scene.rings) drawRing(ctx, ring, level, t, dpr);
    const hero = scene.rings.find((ring) => ring.alpha === 1);
    if (hero) drawWaves(ctx, vw, hero.y + hero.R * 0.62, hero.alpha, level, t);
    update(dt);
    place(t, energy);
    drawLinks();
    drawMotes();
    drawReleased();
    drawLabels();

    ms = ms * 0.9 + (performance.now() - started) * 0.1;
    frame += 1;
    dirty = false;
  }

  function watchFrame(interval) {
    if (interval <= 0 || interval > 1) return;          // a paused tab, not a slow frame
    fps = fps * 0.9 + (1 / interval) * 0.1;
    slowFor = interval > 0.021 ? slowFor + interval : Math.max(0, slowFor - interval);
    if (!degraded && slowFor > 2) {
      // Two seconds of long frames: lighten the load (fewer far motes, softer water).
      degraded = true;
      waterScale = 0.35;
      water?.resize(vw, vh, waterScale);
    }
  }

  function tick(timestamp) {
    raf = 0;
    if (!running) return;
    if (previous && mode === 'full') watchFrame((timestamp - previous) / 1000);
    previous = timestamp;
    render();
    if (mode === 'full') kick();
    else previous = 0;
  }

  function start() {
    if (running) return;
    running = true;
    last = now();
    previous = 0;
    dirty = true;
    kick();
  }

  function stop() {
    running = false;
    if (raf) window.cancelAnimationFrame(raf);
    raf = 0;
  }

  function stats() {
    return { fps, ms, motes: states.length, degraded };
  }

  return { setScene, setPolicy, release, resize, start, stop, stats };
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd website && node --test tests/ocean.test.mjs`
Expected: `# pass 6`, `# fail 0`.

- [ ] **Step 6: Syntax-check the DOM module and checkpoint**

Run: `cd website && node --check assets/js/orbs.js && node --check assets/js/ocean.js && node --test tests/*.test.mjs`
Expected: no output from `--check`; all 27 tests pass. The drawing itself is verified in the browser in Task 7. No commit.

---

### Task 6: Card vignettes and the Ocean's sound

**Files:**
- Create: `website/tests/sound.test.mjs`
- Create: `website/assets/js/vignettes.js`
- Create: `website/assets/js/sound.js`

**Interfaces:**
- Consumes: `now` (breath.js), `orbSprite` (orbs.js); `BREATH_BASE`, `breathAt`, `envelope`, `wave`, `wavesBetween` (breath.js).
- Produces:
  - `vignettes.js`: `SCENES` (`capture`, `gather`, `resurface`, `ask`: `(ctx, w, h, t, dpr, still) → void`); `mountVignettes(canvases, getPolicy) → { refresh() } | undefined`. Canvases carry `data-vignette="capture|gather|resurface|ask"`.
  - `sound.js`: `swellCurve(wave, from, depth, steps = 48) → { begin, end, gains: Float32Array, cutoffs: Float32Array }` (gain 0.03..0.5, cutoff 380..1600 Hz scaled by `1 - 0.45 * depth`); `createSound({ chimeUrl }) → { enable() → Promise<boolean>, disable(), chime(), setDepth(0..1), rms() → dBFS, isOn }`.

- [ ] **Step 1: Write the failing tests**

**File:** `website/tests/sound.test.mjs`
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { swellCurve } from '../assets/js/sound.js';
import { BREATH_BASE, envelope, wave } from '../assets/js/breath.js';

test('a whole wave swells from quiet to its crest and back', () => {
  const w = wave(3);
  const { begin, end, gains, cutoffs } = swellCurve(w, w.start, 0);
  assert.equal(begin, w.start);
  assert.ok(Math.abs(end - (w.start + w.duration)) < 1e-9);
  assert.equal(gains.length, 48);
  assert.ok(Math.abs(gains[0] - 0.03) < 1e-6);
  assert.ok(Math.abs(gains[47] - 0.03) < 1e-6);
  for (const g of gains) assert.ok(g >= 0.03 - 1e-6 && g <= 0.5 + 1e-6, `gain ${g}`);
  for (const c of cutoffs) assert.ok(c >= 380 - 1e-3 && c <= 1600 + 1e-3, `cutoff ${c}`);
});

test('the loudest moment is the crest the visuals show', () => {
  const w = wave(11);
  const { gains } = swellCurve(w, w.start, 0);
  const loudest = gains.indexOf(Math.max(...gains));
  const crest = Math.round((w.rise / w.duration) * 47);
  assert.ok(Math.abs(loudest - crest) <= 1, `${loudest} vs ${crest}`);
});

test('joining mid-wave picks up where the breath is', () => {
  const w = wave(5);
  const from = w.start + w.duration * 0.3;
  const { begin, gains } = swellCurve(w, from, 0);
  assert.equal(begin, from);
  const lift = (envelope(w, 0.3) - BREATH_BASE) / (1 - BREATH_BASE);
  assert.ok(Math.abs(gains[0] - (0.03 + 0.47 * lift)) < 1e-6);
});

test('deeper water sounds more muffled', () => {
  const w = wave(2);
  const shallow = swellCurve(w, w.start, 0).cutoffs;
  const deep = swellCurve(w, w.start, 1).cutoffs;
  for (let i = 0; i < shallow.length; i++) assert.ok(deep[i] < shallow[i]);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd website && node --test tests/sound.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `assets/js/sound.js`.

- [ ] **Step 3: Write the sound**

**File:** `website/assets/js/sound.js`
```js
// The Ocean's sound. Surf generated live from filtered noise, swelling on the
// shared breath so it rises with the ring and the waves you see, and the
// app's own chime (OceanReceived) when a thought is released. Silent until
// the visitor asks for it; fades in and out; sleeps while the tab is hidden.

import { BREATH_BASE, breathAt, envelope, now, wave, wavesBetween } from './breath.js';

const LOOKAHEAD = 4;      // seconds of waves scheduled ahead of the clock
const TICK_MS = 1000;
const MASTER = 0.9;

/** The swell of one wave as automation curves: loudness and brightness follow the breath. */
export function swellCurve(w, from, depth, steps = 48) {
  const begin = Math.max(from, w.start);
  const end = w.start + w.duration;
  const gains = new Float32Array(steps);
  const cutoffs = new Float32Array(steps);
  for (let i = 0; i < steps; i++) {
    const time = begin + (i / (steps - 1)) * (end - begin);
    const lift = (envelope(w, (time - w.start) / w.duration) - BREATH_BASE) / (1 - BREATH_BASE);
    gains[i] = 0.03 + 0.47 * lift;
    cutoffs[i] = (380 + 1220 * lift ** 1.5) * (1 - 0.45 * depth);
  }
  return { begin, end, gains, cutoffs };
}

/** Looping noise whose tail is crossfaded into its head, so the loop has no seam. */
function seamlessNoise(ac, kind, seconds) {
  const length = Math.round(ac.sampleRate * seconds);
  const overlap = Math.round(ac.sampleRate * 0.5);
  const buffer = ac.createBuffer(2, length, ac.sampleRate);
  for (let channel = 0; channel < 2; channel++) {
    const raw = new Float32Array(length + overlap);
    let b0 = 0;
    let b1 = 0;
    let b2 = 0;
    let b3 = 0;
    let b4 = 0;
    let b5 = 0;
    let b6 = 0;
    let brown = 0;
    for (let i = 0; i < raw.length; i++) {
      const white = Math.random() * 2 - 1;
      if (kind === 'white') {
        raw[i] = white * 0.5;
      } else if (kind === 'pink') {
        b0 = 0.99886 * b0 + white * 0.0555179;
        b1 = 0.99332 * b1 + white * 0.0750759;
        b2 = 0.969 * b2 + white * 0.153852;
        b3 = 0.8665 * b3 + white * 0.3104856;
        b4 = 0.55 * b4 + white * 0.5329522;
        b5 = -0.7616 * b5 - white * 0.016898;
        raw[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.11;
        b6 = white * 0.115926;
      } else {
        brown = (brown + 0.02 * white) / 1.02;
        raw[i] = brown * 3.5;
      }
    }
    const data = buffer.getChannelData(channel);
    for (let i = 0; i < length; i++) {
      if (i < overlap) {
        const k = i / overlap;
        data[i] = raw[i] * Math.sqrt(k) + raw[length + i] * Math.sqrt(1 - k);
      } else {
        data[i] = raw[i];
      }
    }
  }
  return buffer;
}

export function createSound({ chimeUrl }) {
  let ac = null;
  let nodes = null;
  let on = false;
  let depth = 0;
  let offset = 0;           // audio clock minus page clock
  let scheduledUntil = 0;   // page-clock time already scheduled
  let timer = 0;
  let chimeBuffer = null;
  let chimeLoading = null;

  function build() {
    const master = ac.createGain();
    master.gain.value = 0;
    master.connect(ac.destination);
    const analyser = ac.createAnalyser();
    analyser.fftSize = 2048;
    master.connect(analyser);
    const loop = (buffer) => {
      const source = ac.createBufferSource();
      source.buffer = buffer;
      source.loop = true;
      return source;
    };
    const filter = (type, frequency, q = 0.7) => {
      const node = ac.createBiquadFilter();
      node.type = type;
      node.frequency.value = frequency;
      node.Q.value = q;
      return node;
    };
    const gain = (value) => {
      const node = ac.createGain();
      node.gain.value = value;
      return node;
    };

    // Deep: the low body of the water, darker the further down the page.
    const deepFilter = filter('lowpass', 420, 0.4);
    const deep = loop(seamlessNoise(ac, 'brown', 7.3));
    deep.connect(deepFilter).connect(gain(0.14)).connect(master);

    // Swell: each wave's body, opened and closed by the breath.
    const swellPan = ac.createStereoPanner();
    swellPan.connect(master);
    const swellFilter = filter('lowpass', 380, 0.6);
    const swellGain = gain(0.03);
    const swell = loop(seamlessNoise(ac, 'pink', 8.1));
    swell.connect(swellFilter).connect(swellGain).connect(swellPan);

    // Wash: the fizz as a wave breaks and slides back.
    const washGain = gain(0);
    const wash = loop(seamlessNoise(ac, 'white', 6.7));
    wash.connect(filter('highpass', 2500)).connect(washGain).connect(swellPan);

    [deep, swell, wash].forEach((source) => source.start());
    return { master, analyser, deepFilter, swellFilter, swellGain, swellPan, washGain };
  }

  function ramp(param, value, seconds) {
    const t = ac.currentTime;
    param.cancelScheduledValues(t);
    param.setValueAtTime(param.value, t);
    param.linearRampToValueAtTime(value, t + seconds);
  }

  function scheduleWave(w, from) {
    const { begin, end, gains, cutoffs } = swellCurve(w, from, depth);
    const at = begin + offset;
    if (end - begin < 0.1 || at < ac.currentTime) return;
    const span = end - begin - 0.002;
    try {
      nodes.swellGain.gain.setValueCurveAtTime(gains, at + 0.001, span);
      nodes.swellFilter.frequency.setValueCurveAtTime(cutoffs, at + 0.001, span);
      nodes.swellPan.pan.setTargetAtTime(w.pan, at + 0.001, 1.5);
      const crest = w.start + w.rise + offset;
      if (crest - 0.3 > ac.currentTime) {
        const wash = nodes.washGain.gain;
        wash.setValueAtTime(0, crest - 0.3);
        wash.linearRampToValueAtTime(0.05 * w.peak * (1 - depth), crest + 0.35);
        wash.setTargetAtTime(0, crest + 0.35, 0.9);
      }
    } catch {
      // An overlapping curve means this wave is already scheduled; the water carries on.
    }
  }

  function schedule() {
    if (!on || !ac) return;
    const clock = now();
    const horizon = clock + LOOKAHEAD;
    for (const w of wavesBetween(Math.max(scheduledUntil, clock), horizon)) scheduleWave(w, w.start);
    scheduledUntil = horizon;
  }

  function begin() {
    offset = ac.currentTime - now();
    for (const param of [nodes.swellGain.gain, nodes.swellFilter.frequency, nodes.washGain.gain, nodes.swellPan.pan]) {
      param.cancelScheduledValues(0);
    }
    const clock = now();
    scheduleWave(wave(breathAt(clock).index), clock + 0.05);   // join the wave already under way
    scheduledUntil = clock;
    schedule();
    window.clearInterval(timer);
    timer = window.setInterval(schedule, TICK_MS);
  }

  function loadChime() {
    if (chimeLoading || !chimeUrl) return;
    chimeLoading = fetch(chimeUrl)
      .then((response) => response.arrayBuffer())
      .then((data) => ac.decodeAudioData(data))
      .then((buffer) => { chimeBuffer = buffer; })
      .catch(() => { chimeLoading = null; });
  }

  async function enable() {
    if (on) return true;
    const Context = window.AudioContext || window.webkitAudioContext;
    if (!Context) return false;
    on = true;
    if (!ac) {
      ac = new Context({ latencyHint: 'playback' });
      nodes = build();
    }
    try {
      await ac.resume();
    } catch {
      on = false;
      return false;
    }
    if (!on) return false;   // turned off again while waking
    begin();
    ramp(nodes.master.gain, MASTER, 2.5);
    loadChime();
    return true;
  }

  function disable() {
    if (!on) return;
    on = false;
    window.clearInterval(timer);
    if (!ac) return;
    ramp(nodes.master.gain, 0, 1.2);
    window.setTimeout(() => {
      if (!on && ac.state === 'running') ac.suspend();
    }, 1300);
  }

  function chime() {
    if (!on || !chimeBuffer) return;
    const source = ac.createBufferSource();
    source.buffer = chimeBuffer;
    source.connect(nodes.master);
    source.start();
  }

  function setDepth(value) {
    depth = Math.max(0, Math.min(1, value));
    if (on && nodes) nodes.deepFilter.frequency.setTargetAtTime(420 - 200 * depth, ac.currentTime, 0.8);
  }

  /** Current output level in dBFS, for verification. */
  function rms() {
    if (!nodes) return -Infinity;
    const data = new Float32Array(nodes.analyser.fftSize);
    nodes.analyser.getFloatTimeDomainData(data);
    let sum = 0;
    for (const v of data) sum += v * v;
    return 10 * Math.log10(sum / data.length || 1e-12);
  }

  document.addEventListener('visibilitychange', async () => {
    if (!ac || !on) return;
    if (document.hidden) {
      window.clearInterval(timer);
      ramp(nodes.master.gain, 0, 0.3);
      window.setTimeout(() => {
        if (document.hidden) ac.suspend();
      }, 350);
    } else {
      await ac.resume();
      begin();
      ramp(nodes.master.gain, MASTER, 1);
    }
  });

  return {
    enable,
    disable,
    chime,
    setDepth,
    rms,
    get isOn() {
      return on;
    },
  };
}
```

- [ ] **Step 4: Write the card vignettes**

**File:** `website/assets/js/vignettes.js`
```js
// The four small visuals on the How it works cards, in the onboarding's
// language: soft orbs, hairline rims, one warm accent. Each runs only while
// its card is on screen, and rests in a still frame when motion is off.

import { now } from './breath.js';
import { orbSprite } from './orbs.js';

const TAU = Math.PI * 2;
const ease = (p) => (p < 0.5 ? 2 * p * p : 1 - (-2 * p + 2) ** 2 / 2);

function orb(ctx, dpr, x, y, r, alpha, warm = false) {
  const sprite = orbSprite(r, 0, warm, 0.5, dpr);
  ctx.globalAlpha = Math.max(0, Math.min(1, alpha));
  ctx.drawImage(sprite.canvas, x - sprite.size / 2, y - sprite.size / 2, sprite.size, sprite.size);
  ctx.globalAlpha = 1;
}

function bar(ctx, x, y, width, height) {
  ctx.beginPath();
  if (typeof ctx.roundRect === 'function') ctx.roundRect(x, y, width, height, height / 2);
  else ctx.rect(x, y, width, height);
  ctx.fill();
}

export const SCENES = {
  // A bright fragment arrives from above, its trail behind it (the onboarding's capture visual).
  capture(ctx, w, h, t, dpr, still) {
    for (const [u, v, r] of [[0.28, 0.76, 7], [0.5, 0.86, 6], [0.72, 0.74, 8]]) orb(ctx, dpr, u * w, v * h, r, 0.6);
    const cycle = still ? 0.7 : (t % 4.8) / 4.8;
    const fall = ease(Math.min(1, cycle / 0.7));
    const x = w * 0.5;
    const y = h * (0.02 + 0.4 * fall);
    const fade = cycle > 0.86 ? 1 - (cycle - 0.86) / 0.14 : 1;
    if (!still && cycle < 0.7) {
      ctx.fillStyle = '#ffffff';
      [0.18, 0.1, 0.05].forEach((strength, k) => {
        ctx.globalAlpha = strength * fade;
        ctx.beginPath();
        ctx.arc(x, y - (k + 1) * 11, 1.8, 0, TAU);
        ctx.fill();
      });
      ctx.globalAlpha = 1;
    }
    orb(ctx, dpr, x, y, 11, fade);
  },

  // Scattered fragments drift together into a current, then loosen again.
  gather(ctx, w, h, t, dpr, still) {
    const spots = [[0.12, 0.3], [0.3, 0.8], [0.45, 0.2], [0.62, 0.75], [0.78, 0.28], [0.9, 0.7], [0.2, 0.55]];
    const k = ease(still ? 1 : 0.5 - 0.5 * Math.cos((t / 10) * TAU));
    spots.forEach(([u, v], i) => {
      const rho = i === 0 ? 0 : 13 * Math.sqrt(i + 0.3);
      const cx = w * 0.5 + rho * Math.cos(i * 2.4);
      const cy = h * 0.5 + rho * Math.sin(i * 2.4);
      orb(ctx, dpr, u * w + (cx - u * w) * k, v * h + (cy - v * h) * k, i === 0 ? 9 : 5.5, 0.55 + 0.45 * k);
    });
  },

  // One warm fragment rises out of the depth.
  resurface(ctx, w, h, t, dpr, still) {
    for (const [u, v, r] of [[0.22, 0.84, 6], [0.42, 0.9, 5], [0.62, 0.86, 6], [0.82, 0.8, 4.5]]) {
      orb(ctx, dpr, u * w, v * h, r, 0.4);
    }
    const cycle = t % 9;
    const rise = ease(still ? 1 : Math.min(1, cycle / 6));
    const hold = still || cycle < 8.2 ? 1 : 1 - (cycle - 8.2) / 0.8;
    orb(ctx, dpr, w * 0.52, h * (0.95 - 0.58 * rise), 5 + 6 * rise, (0.35 + 0.65 * rise) * hold, rise > 0.5);
  },

  // Three sources reach toward an answer.
  ask(ctx, w, h, t, dpr, still) {
    const pulse = still ? 1 : 0.7 + 0.3 * Math.sin(t * 1.3);
    const end = { x: w * 0.6, y: h * 0.5 };
    ctx.lineWidth = 1;
    for (const [u, v] of [[0.16, 0.3], [0.24, 0.58], [0.14, 0.82]]) {
      ctx.strokeStyle = `rgba(200,214,240,${(0.28 * pulse).toFixed(3)})`;
      ctx.beginPath();
      ctx.moveTo(u * w, v * h);
      ctx.quadraticCurveTo((u * w + end.x) / 2, (v * h + end.y) / 2 - 10, end.x - 6, end.y);
      ctx.stroke();
      orb(ctx, dpr, u * w, v * h, 7, 0.9);
    }
    ctx.fillStyle = 'rgba(255,255,255,0.22)';
    [[0, 0.62], [14, 0.46], [28, 0.54]].forEach(([dy, length]) => bar(ctx, end.x, end.y - 16 + dy, length * w * 0.6, 5));
  },
};

/** Starts each canvas[data-vignette] while it is on screen. `getPolicy()` returns 'full' or 'still'. */
export function mountVignettes(canvases, getPolicy) {
  const items = [...canvases].map((canvas) => ({
    canvas, draw: SCENES[canvas.dataset.vignette], visible: false, w: 0, h: 0, dpr: 1,
  }));
  if (!items.length) return undefined;
  let raf = 0;

  const size = (item) => {
    item.dpr = Math.min(2, window.devicePixelRatio || 1);
    item.w = item.canvas.clientWidth;
    item.h = item.canvas.clientHeight;
    item.canvas.width = Math.max(1, Math.round(item.w * item.dpr));
    item.canvas.height = Math.max(1, Math.round(item.h * item.dpr));
  };

  const paint = (item, t, still) => {
    const ctx = item.canvas.getContext('2d');
    ctx.setTransform(item.dpr, 0, 0, item.dpr, 0, 0);
    ctx.clearRect(0, 0, item.w, item.h);
    item.draw?.(ctx, item.w, item.h, t, item.dpr, still);
  };

  const loop = () => {
    raf = 0;
    const still = getPolicy() === 'still';
    const t = now();
    let visible = false;
    for (const item of items) {
      if (!item.visible) continue;
      paint(item, t, still);
      visible = true;
    }
    if (visible && !still && !document.hidden) raf = window.requestAnimationFrame(loop);
  };

  const refresh = () => {
    if (!raf) raf = window.requestAnimationFrame(loop);
  };

  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      const item = items.find((candidate) => candidate.canvas === entry.target);
      if (item) item.visible = entry.isIntersecting;
    }
    refresh();
  });
  items.forEach((item) => {
    size(item);
    observer.observe(item.canvas);
  });
  window.addEventListener('resize', () => {
    items.forEach(size);
    refresh();
  });
  document.addEventListener('visibilitychange', refresh);
  return { refresh };
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd website && node --test tests/sound.test.mjs`
Expected: `# pass 4`, `# fail 0`.

- [ ] **Step 6: Syntax-check and checkpoint**

Run: `cd website && node --check assets/js/vignettes.js && node --check assets/js/sound.js && node --test tests/*.test.mjs`
Expected: all 31 tests pass. Audio and drawing are verified in the browser in Task 7. No commit.

---

### Task 7: The English landing page

**Files:**
- Create: `website/assets/css/site.css`
- Create: `website/assets/js/site.js`
- Create: `website/index.html`

**Interfaces:**
- Consumes: `createMotes`, `energyFor`, `layout`, `ringsFor`, `smoothstep` (choreo.js); `createOcean` (ocean.js); `createSound` (sound.js); `mountVignettes` (vignettes.js); all assets from Task 4.
- Produces, for Tasks 8 and 9 (the markup contract):
  - `<html class="no-js" data-en="…" data-zh="…">` with the inline routing script; `<body data-page="long">` on Privacy and Support.
  - `.ocean` with `canvas.ocean__water`, `canvas.ocean__field`, `div.ocean__grain`.
  - Sections carry `data-chapter`; anchors carry `data-anchor` (`hero-phone`, `currents-phone`, `resurface-widget`, `ask-phone`, `final-phone`); `data-currents="a|b|c|d"` and `data-resurface-label` hold the water's labels.
  - `[data-sound-toggle]` buttons (`aria-pressed`), `[data-release]` form (`data-released` holds the confirmation), `[data-tabs]` with `[data-tab-list][data-label]`, `[data-tab-panel]` (with `id`), `[data-tab-title]`.
  - `data-lang-switch="en|zh-Hans"` on language links; `data-lang-asset` on the App Store badge images.
  - Debug switches: `?motion=still`, `?debug=perf`, `?debug` (exposes `window.__oryne = { ocean, sound }`).

- [ ] **Step 1: Write the stylesheet**

**File:** `website/assets/css/site.css`
```css
/* Oryne website.
   Tokens follow OceanTheme (Oryne/DesignSystem/OceanTheme.swift): near-black and
   spatial, brightness carries hierarchy. Surfaces follow GlassCard. No web
   fonts: SF and PingFang on Apple devices, system fonts elsewhere. */

:root {
  --abyss: #050508;
  --deep: #0d0e11;
  --mid: #17181c;
  --current: #26282d;
  --surface: #3d3e45;
  --foam: rgba(255, 255, 255, 0.92);
  --text: rgba(255, 255, 255, 0.66);
  --mist: rgba(255, 255, 255, 0.5);
  --hint: rgba(255, 255, 255, 0.58);
  --faint: rgba(255, 255, 255, 0.26);
  --hairline: rgba(255, 255, 255, 0.08);
  --accent: #d1d6e0;
  --warm: #f2ede0;
  --rim: #9fb2d6;
  --glass: rgba(255, 255, 255, 0.045);
  --glass-strong: rgba(255, 255, 255, 0.07);
  --font: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Helvetica Neue",
    "PingFang SC", "Hiragino Sans GB", "Noto Sans SC", "Microsoft YaHei", system-ui, sans-serif;
  --gutter: clamp(16px, 4vw, 32px);
  --max: 1120px;
  --radius: 20px;
  --bar: 52px;
  --ease: cubic-bezier(0.22, 1, 0.36, 1);
  color-scheme: dark;
}

/* ---------------------------------------------------------------- base */

*, *::before, *::after { box-sizing: border-box; }

html {
  background: var(--abyss);
  -webkit-text-size-adjust: 100%;
  text-size-adjust: 100%;
  scroll-behavior: smooth;
  scroll-padding-top: calc(var(--bar) + 16px);
}

body {
  margin: 0;
  min-height: 100vh;
  background: var(--abyss);
  color: var(--text);
  font: 17px/1.55 var(--font);
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  overflow-x: clip;
}

html:lang(zh-Hans) body { line-height: 1.8; letter-spacing: 0.02em; }

img { display: block; max-width: 100%; height: auto; }
a { color: inherit; }
h1, h2, h3, p, ul, ol, figure, table { margin: 0; }
ul, ol { padding: 0; list-style: none; }
button, input { font: inherit; color: inherit; }
::selection { background: rgba(209, 214, 224, 0.28); }
:focus-visible { outline: 2px solid rgba(255, 255, 255, 0.72); outline-offset: 3px; }

.vh {
  position: absolute !important;
  width: 1px;
  height: 1px;
  margin: -1px;
  padding: 0;
  overflow: hidden;
  clip: rect(0 0 0 0);
  white-space: nowrap;
  border: 0;
}

.no-js .js-only { display: none !important; }

.skip {
  position: absolute;
  left: 12px;
  top: -60px;
  z-index: 40;
  padding: 10px 16px;
  border-radius: 999px;
  background: var(--accent);
  color: var(--abyss);
  font-weight: 600;
  text-decoration: none;
  transition: top 0.2s var(--ease);
}
.skip:focus { top: 12px; }

.i {
  width: 1em;
  height: 1em;
  flex: none;
  fill: none;
  stroke: currentColor;
  stroke-width: 1.6;
  stroke-linecap: round;
  stroke-linejoin: round;
}

/* ----------------------------------------------------------- the Ocean */

.ocean {
  position: fixed;
  inset: 0;
  z-index: 0;
  pointer-events: none;
  background: radial-gradient(120% 80% at 50% 32%, var(--current) 0%, var(--mid) 26%, var(--deep) 55%, var(--abyss) 100%);
}
.ocean__water, .ocean__field { position: absolute; inset: 0; display: block; width: 100%; height: 100%; }
.ocean__grain { position: absolute; inset: 0; opacity: 0.5; background-size: 128px 128px; }
.no-js .ocean__water, .no-js .ocean__field { display: none; }

main, .footer { position: relative; z-index: 1; }

/* -------------------------------------------------------------- layout */

.wrap {
  width: 100%;
  max-width: calc(var(--max) + var(--gutter) * 2);
  margin-inline: auto;
  padding-inline: var(--gutter);
}
.wrap--narrow { max-width: calc(760px + var(--gutter) * 2); }
.section { padding-block: clamp(96px, 14vh, 176px); }

/* ---------------------------------------------------------------- type */

.eyebrow { margin-bottom: 14px; font-size: 15px; font-weight: 600; letter-spacing: 0.01em; color: var(--rim); }

.display {
  font-size: clamp(44px, 7.2vw, 88px);
  line-height: 1.04;
  letter-spacing: -0.028em;
  font-weight: 600;
  color: var(--foam);
}

.headline {
  max-width: 18em;
  font-size: clamp(34px, 5vw, 60px);
  line-height: 1.08;
  letter-spacing: -0.022em;
  font-weight: 600;
  color: var(--foam);
}

.lead { max-width: 34em; margin-top: 20px; font-size: clamp(18px, 1.7vw, 21px); line-height: 1.5; color: var(--text); }

h3 { font-size: 17px; line-height: 1.35; font-weight: 600; color: var(--foam); }

html:lang(zh-Hans) .display,
html:lang(zh-Hans) .headline,
html:lang(zh-Hans) .panel__title,
html:lang(zh-Hans) .prose__title { letter-spacing: 0; line-height: 1.22; }
html:lang(zh-Hans) .lead { line-height: 1.75; }

/* ----------------------------------------------------------------- bar */

.bar {
  position: sticky;
  top: 0;
  z-index: 20;
  height: var(--bar);
  background: rgba(5, 5, 8, 0.55);
  -webkit-backdrop-filter: saturate(140%) blur(20px);
  backdrop-filter: saturate(140%) blur(20px);
  border-bottom: 0.5px solid var(--hairline);
}
.bar__inner { display: flex; align-items: center; gap: 24px; height: 100%; }
.wordmark { font-size: 17px; font-weight: 500; letter-spacing: 0.15em; color: var(--foam); text-decoration: none; }
.bar__nav { display: none; gap: 24px; margin-left: auto; font-size: 13px; }
.bar__nav a, .lang a { color: var(--mist); text-decoration: none; transition: color 0.2s; }
.bar__nav a:hover, .lang a:hover { color: var(--foam); }
.bar__controls { display: flex; align-items: center; gap: 10px; margin-left: auto; }
@media (min-width: 720px) {
  .bar__nav { display: flex; }
  .bar__controls { margin-left: 0; }
}

.lang { display: flex; align-items: center; gap: 2px; font-size: 13px; }
.lang > * { padding: 4px 6px; border-radius: 6px; }
.lang [aria-current] { color: var(--foam); }

.icon-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 30px;
  padding: 0 11px;
  border: 0.5px solid rgba(255, 255, 255, 0.16);
  border-radius: 999px;
  background: transparent;
  color: var(--mist);
  font-size: 13px;
  cursor: pointer;
  transition: color 0.2s, background-color 0.2s;
}
.icon-btn .i { font-size: 16px; }
.icon-btn:hover { color: var(--foam); }
@media (max-width: 480px) {
  .icon-btn__label { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }
}

[data-sound-toggle][aria-pressed="true"] { color: var(--foam); background: var(--glass-strong); }
[data-sound-toggle][aria-pressed="true"] .i path { animation: sway 3.2s ease-in-out infinite; }
[data-sound-toggle][aria-pressed="true"] .i path + path { animation-delay: -1.6s; }
@keyframes sway { 50% { transform: translateX(1.5px); } }

/* ------------------------------------------------------------- buttons */

.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  height: 44px;
  padding: 0 20px;
  border: 0;
  border-radius: 999px;
  font-size: 15px;
  font-weight: 600;
  text-decoration: none;
  cursor: pointer;
  transition: background-color 0.2s, opacity 0.2s, transform 0.2s var(--ease);
}
.btn:active { transform: scale(0.98); }
.btn .i { font-size: 18px; }
.btn--primary { background: var(--accent); color: var(--abyss); }
.btn--primary:hover { background: #e4e8ef; }
.btn--primary:disabled { opacity: 0.4; cursor: default; transform: none; }
.btn--ghost { border: 0.5px solid rgba(255, 255, 255, 0.24); background: transparent; color: var(--foam); }
.btn--ghost:hover { background: var(--glass); }
.btn--small { height: 30px; padding: 0 14px; font-size: 13px; }

.badge { display: inline-block; border-radius: 10px; line-height: 0; }
.badge img { width: auto; height: 48px; }

/* --------------------------------------------------------------- phone */

.phone {
  position: relative;
  width: clamp(240px, 24vw, 300px);
  aspect-ratio: 640 / 1391;
  border-radius: 13.5% / 6.2%;
  overflow: hidden;
  background: #000;
  box-shadow:
    0 0 0 1px rgba(255, 255, 255, 0.14),
    0 0 0 7px rgba(16, 17, 21, 0.92),
    0 0 0 8px rgba(255, 255, 255, 0.08),
    0 40px 90px -30px rgba(0, 0, 0, 0.9);
}
.phone img { width: 100%; height: 100%; object-fit: cover; }
.phone--small { width: clamp(200px, 19vw, 240px); }

/* ---------------------------------------------------------------- hero */

.hero { padding-top: clamp(64px, 11vh, 128px); padding-bottom: clamp(40px, 8vh, 96px); text-align: center; }
.hero__copy { display: flex; flex-direction: column; align-items: center; }
.hero .display { max-width: 12em; }
.hero .lead { margin-inline: auto; }
.hero__actions { display: flex; flex-wrap: wrap; align-items: center; justify-content: center; gap: 14px; margin-top: 32px; }
.hero__stage { display: flex; justify-content: center; margin-top: clamp(72px, 12vh, 128px); }

/* ---------------------------------------------------------- how cards */

.cards { display: grid; grid-template-columns: 1fr; gap: 16px; margin-top: 48px; }
@media (min-width: 640px) { .cards { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
@media (min-width: 1024px) { .cards { grid-template-columns: repeat(4, minmax(0, 1fr)); } }
.card {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 16px 18px 22px;
  border: 0.5px solid var(--hairline);
  border-radius: var(--radius);
  background: var(--glass);
}
.vignette { display: block; width: 100%; height: 120px; margin-bottom: 8px; }
.card__label { font-size: 13px; font-weight: 600; color: var(--rim); }
.card p:not(.card__label) { font-size: 15px; }
.more { display: inline-flex; align-items: center; margin-top: auto; padding-top: 10px; font-size: 15px; color: var(--accent); text-decoration: none; }
.more:hover { text-decoration: underline; text-underline-offset: 4px; }

/* ------------------------------------------------------------ chapters */

.chapter__grid { display: grid; gap: 64px; align-items: center; }
@media (min-width: 900px) { .chapter__grid { grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 48px; } }
.chapter__visual { display: flex; justify-content: center; }
.features { display: grid; gap: 22px; margin-top: 36px; }
.features li { padding-left: 18px; border-left: 1px solid rgba(255, 255, 255, 0.12); }
.features p { margin-top: 4px; font-size: 16px; }

/* --------------------------------------------------------- release demo */

.release {
  margin-top: 40px;
  padding: 18px;
  border: 0.5px solid var(--hairline);
  border-radius: var(--radius);
  background: var(--glass-strong);
  -webkit-backdrop-filter: blur(16px);
  backdrop-filter: blur(16px);
}
.release__label { display: block; margin-bottom: 10px; font-size: 13px; font-weight: 600; color: var(--rim); }
.release__row { display: flex; gap: 10px; }
.release input {
  flex: 1;
  min-width: 0;
  height: 44px;
  padding: 0 16px;
  border: 0.5px solid rgba(255, 255, 255, 0.16);
  border-radius: 999px;
  background: rgba(0, 0, 0, 0.35);
  color: var(--foam);
}
.release input::placeholder { color: var(--hint); }
.release__status { min-height: 1.6em; margin-top: 10px; font-size: 14px; color: var(--warm); }
.release__note { font-size: 13px; color: var(--hint); }

/* ------------------------------------------------------------- widgets */

.widgets { display: flex; flex-wrap: wrap; align-items: flex-start; justify-content: center; gap: 16px; }
.widget {
  display: flex;
  flex-direction: column;
  padding: 16px;
  border: 0.5px solid var(--hairline);
  border-radius: 22px;
  background: linear-gradient(180deg, var(--abyss), var(--deep) 55%, var(--mid));
  box-shadow: 0 30px 60px -30px rgba(0, 0, 0, 0.9);
}
.widget--small { width: 158px; height: 158px; }
.widget--medium { width: 338px; max-width: 100%; height: 158px; }
.widget__head { display: flex; align-items: center; gap: 5px; font-size: 11px; font-weight: 600; color: var(--warm); }
.widget__head .i { font-size: 12px; }
.widget__title { margin-top: auto; font-size: 15px; font-weight: 500; line-height: 1.3; color: var(--foam); }
.widget--medium .widget__title { margin-top: 8px; font-size: 17px; }
.widget__snippet {
  display: -webkit-box;
  margin-top: 4px;
  overflow: hidden;
  font-size: 12px;
  line-height: 1.4;
  color: var(--mist);
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
}
.widget__age { margin-top: 4px; font-size: 11px; color: var(--faint); }
.widget--medium .widget__age { margin-top: auto; }

/* ---------------------------------------------------------------- ask */

.modes { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; margin-top: 36px; }
.modes li { padding: 16px; border: 0.5px solid var(--hairline); border-radius: 16px; background: var(--glass); }
.modes h3 { font-size: 15px; }
.modes p { margin-top: 4px; font-size: 14px; line-height: 1.45; }
.footnote { margin-top: 18px; font-size: 13px; color: var(--hint); }

/* ------------------------------------------------------ grow and find */

.grow__grid { display: grid; gap: 24px; }
@media (min-width: 900px) { .grow__grid { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
.panel {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  padding: 44px 24px 0;
  overflow: hidden;
  border: 0.5px solid var(--hairline);
  border-radius: 28px;
  background: var(--glass);
  text-align: center;
}
.panel .eyebrow { margin-bottom: 0; }
.panel__title {
  max-width: 14em;
  font-size: clamp(26px, 3vw, 36px);
  line-height: 1.15;
  letter-spacing: -0.015em;
  font-weight: 600;
  color: var(--foam);
}
.panel p { max-width: 28em; }
.panel .phone { margin-top: 28px; margin-bottom: -30%; }

/* ----------------------------------------------------------- use cases */

.tabs { margin-top: 40px; }
.tabs__list { display: flex; gap: 8px; padding: 2px 2px 8px; overflow-x: auto; scrollbar-width: none; }
.tabs__list::-webkit-scrollbar { display: none; }
.tabs__tab {
  flex: none;
  height: 36px;
  padding: 0 16px;
  border: 0.5px solid rgba(255, 255, 255, 0.18);
  border-radius: 999px;
  background: transparent;
  color: var(--mist);
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
}
.tabs__tab:hover { color: var(--foam); }
.tabs__tab[aria-selected="true"] { border-color: transparent; background: var(--accent); color: var(--abyss); }
.tabs__panel { margin-top: 28px; }
.tabs__panel + .tabs__panel { margin-top: 64px; }
.tabs--ready .tabs__panel + .tabs__panel { margin-top: 28px; }
.tabs__title { margin-bottom: 12px; font-size: 22px; }
.moment { max-width: 32em; font-size: clamp(19px, 2vw, 24px); line-height: 1.45; color: var(--foam); }
.thoughts { display: grid; gap: 14px; margin-top: 28px; }
@media (min-width: 720px) { .thoughts { grid-template-columns: repeat(3, minmax(0, 1fr)); } }
.thought {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 16px;
  border: 0.5px solid var(--hairline);
  border-radius: 18px;
  background: var(--glass);
}
.thought__image { height: 128px; margin: -4px -4px 6px; border-radius: 12px; }
.thought__image--sunset { background: linear-gradient(180deg, #232447 0%, #5b3a6b 36%, #c9694a 70%, #f0ad68 100%); }
.thought__image--dusk { background: linear-gradient(180deg, #e7b392 0%, #b88675 40%, #5c6072 78%, #3a3f4c 100%); }
.thought__image--dumplings { background: radial-gradient(60% 50% at 50% 60%, #efe5d3 0%, #cbb89a 45%, #3a3129 100%); }
.thought__kind { display: flex; align-items: center; gap: 6px; font-size: 12px; font-weight: 600; color: var(--mist); }
.thought__kind .i { font-size: 14px; }
.thought__title { font-size: 16px; font-weight: 600; line-height: 1.35; color: var(--foam); }
.thought__text { font-size: 14px; line-height: 1.5; }
.thought__source { font-size: 12px; color: var(--hint); }
.thought__current {
  align-self: flex-start;
  margin-top: auto;
  padding: 3px 9px;
  border: 0.5px solid rgba(255, 255, 255, 0.14);
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.07);
  font-size: 12px;
  color: var(--foam);
}

/* ---------------------------------------------------------- comparison */

.compare { width: 100%; margin-top: 44px; border-collapse: separate; border-spacing: 0; font-size: 16px; }
.compare th, .compare td { padding: 18px 16px; border-bottom: 0.5px solid var(--hairline); text-align: left; vertical-align: top; }
.compare thead th { font-size: 14px; font-weight: 600; color: var(--mist); }
.compare tbody th { width: 24%; font-weight: 600; color: var(--foam); }
.compare td { color: var(--mist); }
.compare .is-oryne { background: rgba(255, 255, 255, 0.04); color: var(--foam); }
.compare thead .is-oryne { border-radius: 14px 14px 0 0; }
@media (max-width: 719px) {
  .compare thead { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); }
  .compare, .compare tbody, .compare tr, .compare th, .compare td { display: block; width: auto; }
  .compare tr { padding: 18px 0; border-bottom: 0.5px solid var(--hairline); }
  .compare th, .compare td { padding: 4px 0; border: 0; }
  .compare tbody th { margin-bottom: 6px; font-size: 17px; }
  .compare td::before { content: attr(data-label); display: block; font-size: 12px; font-weight: 600; color: var(--hint); }
  .compare .is-oryne { margin-top: 8px; background: none; }
}

/* ------------------------------------------------------------- privacy */

.promises { display: grid; gap: 32px; margin-top: 48px; }
@media (min-width: 720px) { .promises { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
@media (min-width: 1024px) { .promises { grid-template-columns: repeat(4, minmax(0, 1fr)); } }
.promises .i { margin-bottom: 14px; font-size: 28px; color: var(--rim); }
.promises p { margin-top: 6px; font-size: 15px; }
.privacy .more { margin-top: 40px; }

/* ----------------------------------------------------------- and more */

.tiles { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; margin-top: 40px; }
@media (min-width: 720px) { .tiles { grid-template-columns: repeat(3, minmax(0, 1fr)); } }
@media (min-width: 1024px) { .tiles { grid-template-columns: repeat(4, minmax(0, 1fr)); } }
.tiles li {
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  gap: 14px;
  min-height: 124px;
  padding: 18px;
  border: 0.5px solid var(--hairline);
  border-radius: 18px;
  background: var(--glass);
  font-size: 15px;
  font-weight: 500;
  line-height: 1.35;
  color: var(--foam);
}
.tiles .i { font-size: 24px; color: var(--accent); }

/* ----------------------------------------------------------------- faq */

.faq .headline { margin-bottom: 24px; }
.qa { border-bottom: 0.5px solid var(--hairline); }
.qa summary {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 22px 0;
  list-style: none;
  font-size: 18px;
  font-weight: 600;
  color: var(--foam);
  cursor: pointer;
}
.qa summary::-webkit-details-marker { display: none; }
.qa summary::after {
  content: "";
  flex: none;
  width: 14px;
  height: 14px;
  color: var(--mist);
  background:
    linear-gradient(currentColor, currentColor) center / 14px 1.5px no-repeat,
    linear-gradient(currentColor, currentColor) center / 1.5px 14px no-repeat;
  transition: transform 0.25s var(--ease);
}
.qa[open] summary::after { transform: rotate(45deg); }
.qa p { max-width: 44em; padding-bottom: 22px; }

/* --------------------------------------------------------------- final */

.final { padding-bottom: 0; text-align: center; }
.final__inner { display: flex; flex-direction: column; align-items: center; }
.final__icon {
  width: 96px;
  height: 96px;
  margin-bottom: 28px;
  border-radius: 22%;
  box-shadow: 0 0 0 0.5px rgba(255, 255, 255, 0.14), 0 24px 50px -12px rgba(0, 0, 0, 0.8);
}
.final .lead { margin-inline: auto; }
.final__actions { margin-top: 32px; }
.final__stage { display: flex; justify-content: center; height: clamp(280px, 38vw, 420px); margin-top: 72px; overflow: hidden; }

/* -------------------------------------------------------------- footer */

.footer {
  padding-block: 44px 60px;
  border-top: 0.5px solid var(--hairline);
  background: rgba(5, 5, 8, 0.72);
  font-size: 13px;
  color: var(--hint);
}
.footer__inner { display: grid; gap: 14px; }
.footer .wordmark { font-size: 15px; }
.footer nav, .footer__lang { display: flex; flex-wrap: wrap; gap: 8px 20px; }
.footer a { color: var(--mist); text-decoration: none; }
.footer a:hover { color: var(--foam); }
.footer [aria-current] { color: var(--foam); }

/* ----------------------------------------------- privacy and support */

.prose { max-width: calc(68ch + var(--gutter) * 2); padding-block: clamp(72px, 12vh, 132px) 112px; }
html:lang(zh-Hans) .prose { max-width: calc(38em + var(--gutter) * 2); }
.prose__title {
  font-size: clamp(40px, 6vw, 64px);
  line-height: 1.08;
  letter-spacing: -0.022em;
  font-weight: 600;
  color: var(--foam);
}
.prose .updated { margin-top: 14px; font-size: 14px; color: var(--hint); }
.prose .summary {
  margin-top: 36px;
  padding: 22px 24px;
  border: 0.5px solid var(--hairline);
  border-radius: var(--radius);
  background: var(--glass-strong);
  color: var(--foam);
}
.prose h2 { margin-top: 56px; font-size: 24px; line-height: 1.25; letter-spacing: -0.01em; font-weight: 600; color: var(--foam); }
.prose h3 { margin-top: 28px; }
.prose p, .prose ul { margin-top: 14px; }
.prose ul { padding-left: 1.2em; list-style: disc; }
.prose li + li { margin-top: 8px; }
.prose strong { font-weight: 600; color: var(--foam); }
.prose a { color: var(--accent); text-underline-offset: 3px; }
.prose .qa summary { font-size: 17px; }
.prose .qa p { margin-top: 0; }

/* ----------------------------------------------------------- utilities */

.perf {
  position: fixed;
  right: 12px;
  bottom: 12px;
  z-index: 50;
  padding: 6px 10px;
  border-radius: 8px;
  background: rgba(0, 0, 0, 0.72);
  color: #a8f0b4;
  font: 12px/1.2 ui-monospace, Menlo, monospace;
}

@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

- [ ] **Step 2: Write the page wiring**

**File:** `website/assets/js/site.js`
```js
// Wires the page together: scroll position to choreography to the Ocean, the
// sound toggles, the language choice, the use-case tabs, and the release
// demo. The only module that reads the DOM broadly; everything it drives is
// DOM-free or tested on its own.

import { createMotes, energyFor, layout, ringsFor, smoothstep } from './choreo.js';
import { createOcean } from './ocean.js';
import { createSound } from './sound.js';
import { mountVignettes } from './vignettes.js';

const params = new URLSearchParams(window.location.search);
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const longPage = document.body.dataset.page === 'long';

const store = {
  get(key) {
    try {
      return window.localStorage.getItem(key);
    } catch {
      return null;
    }
  },
  set(key, value) {
    try {
      window.localStorage.setItem(key, value);
    } catch {
      // Private browsing: the choice lasts for this page only.
    }
  },
};

function motionPolicy() {
  return reduceMotion.matches || params.get('motion') === 'still' || longPage ? 'still' : 'full';
}

function moteCount() {
  return Math.round(Math.min(64, Math.max(28, (window.innerWidth * window.innerHeight) / 22000)));
}

function readLabels() {
  const currents = document.querySelector('[data-currents]');
  const resurface = document.querySelector('[data-resurface-label]');
  return {
    currents: currents ? currents.dataset.currents.split('|') : [],
    resurface: resurface ? resurface.dataset.resurfaceLabel : null,
  };
}

/** Which chapter holds the middle of the viewport, how far through it we are, and the handover to the next. */
function chapterState(sections, viewportHeight) {
  if (!sections.length) return { chapter: 'deep', progress: 0, next: null, blend: 0 };
  const middle = viewportHeight / 2;
  let index = sections.findIndex((section) => {
    const rect = section.getBoundingClientRect();
    return rect.top <= middle && rect.bottom > middle;
  });
  if (index === -1) index = sections[0].getBoundingClientRect().top > middle ? 0 : sections.length - 1;
  const rect = sections[index].getBoundingClientRect();
  const progress = Math.min(1, Math.max(0, (middle - rect.top) / Math.max(1, rect.height)));
  const following = sections[index + 1];
  const blend = following ? smoothstep(0.75, 1, progress) : 0;
  return {
    chapter: sections[index].dataset.chapter,
    progress,
    next: blend > 0 ? following.dataset.chapter : null,
    blend,
  };
}

function setupOcean(sound) {
  const field = document.querySelector('.ocean__field');
  if (!field) return null;
  const ocean = createOcean({
    water: document.querySelector('.ocean__water'),
    field,
    grain: document.querySelector('.ocean__grain'),
    policy: motionPolicy(),
  });
  const sections = [...document.querySelectorAll('[data-chapter]')];
  const anchors = [...document.querySelectorAll('[data-anchor]')];
  const labels = readLabels();
  let count = moteCount();
  let motes = createMotes(count);
  let queued = false;

  function update() {
    queued = false;
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const rects = {};
    for (const element of anchors) {
      const rect = element.getBoundingClientRect();
      rects[element.dataset.anchor] = { x: rect.left, y: rect.top, w: rect.width, h: rect.height };
    }
    const view = { vw, vh, anchors: rects, labels };
    const state = chapterState(sections, vh);
    const scrollable = document.documentElement.scrollHeight - vh;
    const depth = longPage ? 0.6 : scrollable > 0 ? Math.min(1, window.scrollY / scrollable) : 0;
    ocean.setScene({
      depth,
      motes,
      targets: layout(state, motes, view),
      rings: ringsFor(view),
      energy: energyFor(state),
    });
    sound?.setDepth(depth);
  }

  const refresh = () => {
    if (queued) return;
    queued = true;
    window.requestAnimationFrame(update);
  };

  window.addEventListener('scroll', refresh, { passive: true });
  window.addEventListener('resize', () => {
    const next = moteCount();
    if (next !== count) {
      count = next;
      motes = createMotes(count);
    }
    ocean.resize();
    refresh();
  });
  document.addEventListener('visibilitychange', () => (document.hidden ? ocean.stop() : ocean.start()));
  ocean.start();
  ocean.resize();
  update();
  return { ocean, refresh };
}

function setupSound() {
  const toggles = [...document.querySelectorAll('[data-sound-toggle]')];
  if (!toggles.length) return null;
  const sound = createSound({ chimeUrl: new URL('../audio/ocean-received.m4a', import.meta.url).href });
  const show = (on) => {
    for (const toggle of toggles) toggle.setAttribute('aria-pressed', String(on));
  };
  const turn = async (on) => {
    if (on) {
      const ok = await sound.enable();
      show(ok);
      store.set('oryne.sound', ok ? 'on' : 'off');
    } else {
      sound.disable();
      show(false);
      store.set('oryne.sound', 'off');
    }
  };
  for (const toggle of toggles) toggle.addEventListener('click', () => turn(!sound.isOn));
  if (store.get('oryne.sound') === 'on') {
    // Browsers start audio only from a gesture, so resume on the visitor's first one.
    const resume = (event) => {
      window.removeEventListener('pointerdown', resume, true);
      window.removeEventListener('keydown', resume, true);
      if (event.target instanceof Element && event.target.closest('[data-sound-toggle]')) return;
      turn(true);
    };
    window.addEventListener('pointerdown', resume, true);
    window.addEventListener('keydown', resume, true);
  }
  return sound;
}

function setupRelease(ocean, sound) {
  const form = document.querySelector('[data-release]');
  if (!form) return;
  const input = form.querySelector('input');
  const button = form.querySelector('button[type="submit"]');
  const status = form.querySelector('[role="status"]');
  let clearTimer = 0;
  const sync = () => {
    button.disabled = input.value.trim() === '';
  };
  input.addEventListener('input', sync);
  sync();
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const text = input.value.trim();
    if (!text) return;
    const rect = input.getBoundingClientRect();
    ocean?.release({ text, x: rect.left + 28, y: rect.top + rect.height / 2 });
    sound?.chime();
    input.value = '';
    sync();
    input.focus();
    status.textContent = '';
    window.requestAnimationFrame(() => {
      status.textContent = form.dataset.released;
    });
    window.clearTimeout(clearTimer);
    clearTimer = window.setTimeout(() => {
      status.textContent = '';
    }, 4000);
  });
}

/** WAI-ARIA tabs, built from panels that read fine as plain sections without JS. */
function setupTabs() {
  for (const root of document.querySelectorAll('[data-tabs]')) {
    const list = root.querySelector('[data-tab-list]');
    const panels = [...root.querySelectorAll('[data-tab-panel]')];
    if (!list || panels.length < 2) continue;
    list.setAttribute('role', 'tablist');
    if (list.dataset.label) list.setAttribute('aria-label', list.dataset.label);
    const tabs = panels.map((panel) => {
      const title = panel.querySelector('[data-tab-title]');
      const tab = document.createElement('button');
      tab.type = 'button';
      tab.className = 'tabs__tab';
      tab.id = `${panel.id}-tab`;
      tab.setAttribute('role', 'tab');
      tab.setAttribute('aria-controls', panel.id);
      tab.textContent = title.textContent;
      title.classList.add('vh');
      panel.setAttribute('role', 'tabpanel');
      panel.setAttribute('aria-labelledby', tab.id);
      panel.tabIndex = 0;
      list.append(tab);
      return tab;
    });
    const select = (index, focus) => {
      tabs.forEach((tab, i) => {
        const selected = i === index;
        tab.setAttribute('aria-selected', String(selected));
        tab.tabIndex = selected ? 0 : -1;
        panels[i].hidden = !selected;
      });
      if (focus) tabs[index].focus();
    };
    tabs.forEach((tab, i) => {
      tab.addEventListener('click', () => select(i, false));
      tab.addEventListener('keydown', (event) => {
        const last = tabs.length - 1;
        const target = { ArrowRight: i === last ? 0 : i + 1, ArrowLeft: i === 0 ? last : i - 1, Home: 0, End: last }[event.key];
        if (target === undefined) return;
        event.preventDefault();
        select(target, true);
      });
    });
    root.classList.add('tabs--ready');
    select(0, false);
  }
}

function setupLanguage() {
  for (const link of document.querySelectorAll('[data-lang-switch]')) {
    link.addEventListener('click', () => store.set('oryne.lang', link.dataset.langSwitch));
  }
}

function setupPerf(ocean) {
  if (params.get('debug') !== 'perf' || !ocean) return;
  const readout = document.createElement('div');
  readout.className = 'perf';
  document.body.append(readout);
  window.setInterval(() => {
    const s = ocean.stats();
    readout.textContent = `${s.fps.toFixed(0)} fps · ${s.ms.toFixed(1)} ms · ${s.motes} motes${s.degraded ? ' · degraded' : ''}`;
  }, 500);
}

const sound = setupSound();
const water = setupOcean(sound);
const vignettes = mountVignettes(document.querySelectorAll('canvas[data-vignette]'), motionPolicy);
setupRelease(water?.ocean, sound);
setupTabs();
setupLanguage();
setupPerf(water?.ocean);

reduceMotion.addEventListener('change', () => {
  water?.ocean.setPolicy(motionPolicy());
  water?.refresh();
  vignettes?.refresh();
});

if (params.has('debug')) window.__oryne = { ocean: water?.ocean, sound };
```

- [ ] **Step 3: Write the landing page**

If Task 4 Step 8 recorded a screen height other than 1391, use it for every `height="1391"` below.

**File:** `website/index.html`
```html
<!doctype html>
<html lang="en" class="no-js" data-en="./" data-zh="zh/">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>Oryne: catch ideas before they drift away</title>
  <meta name="description" content="Oryne is a calm home for your thoughts, voice notes, screenshots, and links. Related ideas gather on their own, and forgotten ones come back. For iPhone and iPad.">
  <meta name="theme-color" content="#050508">
  <meta name="color-scheme" content="dark">
  <link rel="alternate" hreflang="en" href="./">
  <link rel="alternate" hreflang="zh-Hans" href="zh/">
  <link rel="alternate" hreflang="x-default" href="./">
  <link rel="icon" href="assets/img/favicon-32.png" sizes="32x32" type="image/png">
  <link rel="icon" href="assets/img/favicon-16.png" sizes="16x16" type="image/png">
  <link rel="apple-touch-icon" href="assets/img/apple-touch-icon.png">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Oryne">
  <meta property="og:title" content="Oryne: catch ideas before they drift away">
  <meta property="og:description" content="A calm home for your thoughts, voice notes, screenshots, and links. For iPhone and iPad.">
  <meta property="og:image" content="assets/img/og.png">
  <meta property="og:locale" content="en_US">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="stylesheet" href="assets/css/site.css">
  <script>
    (function () {
      var root = document.documentElement;
      root.className = root.className.replace('no-js', 'js');
      var here = root.lang === 'zh-Hans' ? 'zh-Hans' : 'en';
      var want = null;
      try { want = window.localStorage.getItem('oryne.lang'); } catch (e) {}
      if (!want && here === 'en') {
        var first = ((navigator.languages && navigator.languages[0]) || navigator.language || '').toLowerCase();
        if (/^zh(?:-(?:hans|cn|sg)(?:-|$)|$)/.test(first)) want = 'zh-Hans';
      }
      if (want && want !== here) {
        var target = root.getAttribute(want === 'zh-Hans' ? 'data-zh' : 'data-en');
        if (target) window.location.replace(target + window.location.search + window.location.hash);
      }
    })();
  </script>
  <script type="module" src="assets/js/site.js"></script>
</head>
<body>
  <a class="skip" href="#main">Skip to content</a>

  <div class="ocean" aria-hidden="true">
    <canvas class="ocean__water"></canvas>
    <canvas class="ocean__field"></canvas>
    <div class="ocean__grain"></div>
  </div>

  <header class="bar">
    <div class="wrap bar__inner">
      <a class="wordmark" href="#top">Oryne</a>
      <nav class="bar__nav" aria-label="Sections">
        <a href="#how">Features</a>
        <a href="#use-cases">Use cases</a>
        <a href="#privacy">Privacy</a>
        <a href="#faq">FAQ</a>
      </nav>
      <div class="bar__controls">
        <div class="lang"><span aria-current="true">EN</span><a href="zh/" hreflang="zh-Hans" lang="zh-Hans" data-lang-switch="zh-Hans">中文</a></div>
        <button class="icon-btn js-only" type="button" data-sound-toggle aria-pressed="false">
          <svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 9c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/><path d="M3 15c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/></svg>
          <span class="icon-btn__label">Sound</span>
        </button>
        <a class="btn btn--primary btn--small" href="https://apps.apple.com/app/id0000000000">Download</a>
      </div>
    </div>
  </header>

  <main id="main">
    <section class="section hero" id="top" data-chapter="top">
      <div class="wrap hero__copy">
        <p class="eyebrow">For iPhone and iPad</p>
        <h1 class="display">Catch ideas before they drift away.</h1>
        <p class="lead">Oryne is a calm home for your thoughts, voice notes, screenshots, and links. Related ideas gather on their own, and forgotten ones come back when they matter.</p>
        <div class="hero__actions">
          <a class="badge" href="https://apps.apple.com/app/id0000000000"><img src="assets/img/badge-en.svg" alt="Download on the App Store" height="48" data-lang-asset></a>
          <button class="btn btn--ghost js-only" type="button" data-sound-toggle aria-pressed="false">
            <svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 9c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/><path d="M3 15c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/></svg>
            Listen
          </button>
        </div>
      </div>
      <div class="hero__stage">
        <figure class="phone" data-anchor="hero-phone">
          <img src="assets/img/screens/ocean.webp" width="640" height="1391" alt="The Oryne Ocean: thoughts drift as soft orbs and gather into currents." fetchpriority="high">
        </figure>
      </div>
    </section>

    <section class="section how" id="how" data-chapter="how">
      <div class="wrap">
        <p class="eyebrow">How it works</p>
        <h2 class="headline">Catch it once. Oryne does the rest.</h2>
        <ol class="cards">
          <li class="card">
            <canvas class="vignette js-only" data-vignette="capture" aria-hidden="true"></canvas>
            <p class="card__label">Capture</p>
            <h3>Catch it in seconds.</h3>
            <p>Voice, text, screenshots, and links, from anywhere on your iPhone.</p>
            <a class="more" href="#capture">Learn more<span class="vh"> about capture</span><span aria-hidden="true">&nbsp;›</span></a>
          </li>
          <li class="card">
            <canvas class="vignette js-only" data-vignette="gather" aria-hidden="true"></canvas>
            <p class="card__label">Gather</p>
            <h3>Watch it find its place.</h3>
            <p>Related thoughts drift together into currents. No folders, no tags.</p>
            <a class="more" href="#currents">Learn more<span class="vh"> about currents</span><span aria-hidden="true">&nbsp;›</span></a>
          </li>
          <li class="card">
            <canvas class="vignette js-only" data-vignette="resurface" aria-hidden="true"></canvas>
            <p class="card__label">Resurface</p>
            <h3>Get it back.</h3>
            <p>One forgotten idea returns each day, right when it might matter.</p>
            <a class="more" href="#resurface">Learn more<span class="vh"> about resurfacing</span><span aria-hidden="true">&nbsp;›</span></a>
          </li>
          <li class="card">
            <canvas class="vignette js-only" data-vignette="ask" aria-hidden="true"></canvas>
            <p class="card__label">Ask</p>
            <h3>Ask what it all means.</h3>
            <p>Question your own ideas and see the thoughts behind every answer.</p>
            <a class="more" href="#ask">Learn more<span class="vh"> about Ask</span><span aria-hidden="true">&nbsp;›</span></a>
          </li>
        </ol>
      </div>
    </section>

    <section class="section chapter" id="capture" data-chapter="capture">
      <div class="wrap chapter__grid">
        <div class="chapter__copy">
          <p class="eyebrow">Capture</p>
          <h2 class="headline">Catch it the moment it arrives.</h2>
          <p class="lead">Speak, type, snap, or share. Oryne takes the thought exactly as it comes and never asks you to file it first.</p>
          <ul class="features">
            <li><h3>Press and speak.</h3><p>Set the Action Button or the Control Center button to Fast Capture. Oryne opens already listening.</p></li>
            <li><h3>Talk in the language you think in.</h3><p>Your words appear as you speak. If your iPhone is set up for two languages, Oryne listens for both.</p></li>
            <li><h3>Screenshot it, then say why.</h3><p>Screenshot + voice keeps what was on your screen together with a spoken note.</p></li>
            <li><h3>Share from any app.</h3><p>Send links, images, and text to Oryne from the share sheet. Links arrive with their title and preview.</p></li>
            <li><h3>Or just ask Siri.</h3><p>“Hey Siri, add an inspiration to Oryne.” Your thought is saved without opening the app.</p></li>
          </ul>
          <form class="release js-only" data-release data-released="Drifted into the Ocean" autocomplete="off">
            <label class="release__label" for="release-input">Try it here</label>
            <div class="release__row">
              <input id="release-input" name="thought" type="text" maxlength="140" placeholder="What just drifted by?" enterkeyhint="send">
              <button class="btn btn--primary" type="submit">Release</button>
            </div>
            <p class="release__status" role="status" aria-live="polite"></p>
            <p class="release__note">This demo stays on this page. Nothing is sent anywhere.</p>
          </form>
        </div>
        <div class="chapter__visual">
          <figure class="phone" data-anchor="capture-phone">
            <img src="assets/img/screens/capture.webp" width="640" height="1391" alt="Oryne's capture screen, asking what just drifted by." loading="lazy" decoding="async">
          </figure>
        </div>
      </div>
    </section>

    <section class="section chapter" id="currents" data-chapter="currents" data-currents="light and color|product ideas|cooking|reading">
      <div class="wrap chapter__grid">
        <div class="chapter__copy">
          <p class="eyebrow">Currents</p>
          <h2 class="headline">Your ideas organize themselves.</h2>
          <p class="lead">Oryne reads what each thought is about and gathers related ones into currents. You never make a folder, pick a tag, or decide where something goes.</p>
          <ul class="features">
            <li><h3>Grouped by meaning, not keywords.</h3><p>A sunset photo and a note about warm light end up together, even when they share no words.</p></li>
            <li><h3>One thought, many currents.</h3><p>Ideas overlap, so a thought can belong to more than one current. Folders can't do that.</p></li>
            <li><h3>Titled for you.</h3><p>Every thought gets a short title, written on your device. Change it, and it stays yours.</p></li>
          </ul>
        </div>
        <div class="chapter__visual">
          <figure class="phone" data-anchor="currents-phone">
            <img src="assets/img/screens/current.webp" width="640" height="1391" alt="Inside one current in Oryne: every thought about light and color, newest first." loading="lazy" decoding="async">
          </figure>
        </div>
      </div>
    </section>

    <section class="section chapter" id="resurface" data-chapter="resurface" data-resurface-label="Ideas arrive in the shower">
      <div class="wrap chapter__grid">
        <div class="chapter__copy">
          <p class="eyebrow">Resurfacing</p>
          <h2 class="headline">The ideas you forgot come back.</h2>
          <p class="lead">Every day, one thought you haven't seen in a while rises to the surface. Not a reminder, not a task. Just a good idea, back in view.</p>
          <ul class="features">
            <li><h3>One a day, on your Home Screen.</h3><p>The Resurfacing widget shows the day's thought on your Home Screen or Lock Screen.</p></li>
            <li><h3>Connected to what you're exploring now.</h3><p>Older thoughts that share a current with your latest ones get a gentle lift.</p></li>
            <li><h3>Never the same one on repeat.</h3><p>A thought you just revisited rests for a while before it can rise again.</p></li>
          </ul>
        </div>
        <div class="chapter__visual">
          <div class="widgets" data-anchor="resurface-widget">
            <div class="widget widget--small" role="img" aria-label="Resurfacing widget, small size: Ideas arrive in the shower, from 3 weeks ago.">
              <p class="widget__head"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 19.5s-7.5-4.6-7.5-9.8A4 4 0 0 1 12 7.6a4 4 0 0 1 7.5 2.1c0 5.2-7.5 9.8-7.5 9.8z"/><path d="M12 15.5v-5M9.8 12.6 12 10.4l2.2 2.2"/></svg>Resurfacing</p>
              <p class="widget__title">Ideas arrive in the shower</p>
              <p class="widget__age">3 weeks ago</p>
            </div>
            <div class="widget widget--medium" role="img" aria-label="Resurfacing widget, medium size: Ideas arrive in the shower. Why do my best ideas arrive in the shower and never at the desk?">
              <p class="widget__head"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 19.5s-7.5-4.6-7.5-9.8A4 4 0 0 1 12 7.6a4 4 0 0 1 7.5 2.1c0 5.2-7.5 9.8-7.5 9.8z"/><path d="M12 15.5v-5M9.8 12.6 12 10.4l2.2 2.2"/></svg>Resurfacing</p>
              <p class="widget__title">Ideas arrive in the shower</p>
              <p class="widget__snippet">Why do my best ideas arrive in the shower and never at the desk? Something about not gripping them too hard.</p>
              <p class="widget__age">3 weeks ago</p>
            </div>
          </div>
        </div>
      </div>
    </section>

    <section class="section chapter" id="ask" data-chapter="ask">
      <div class="wrap chapter__grid">
        <div class="chapter__copy">
          <p class="eyebrow">Ask</p>
          <h2 class="headline">Ask your ideas anything.</h2>
          <p class="lead">Oryne answers from the thoughts you've caught and shows which ones it used, so every answer leads back to your own words.</p>
          <ul class="modes">
            <li><h3>Search</h3><p>Find the thought you half remember.</p></li>
            <li><h3>Synthesis</h3><p>See what a pile of notes adds up to.</p></li>
            <li><h3>Expansion</h3><p>Take an idea somewhere new.</p></li>
            <li><h3>Research</h3><p>Look beyond your notes, clearly marked as outside your Ocean.</p></li>
          </ul>
          <p class="footnote">Answers are composed on your device, with Apple Intelligence on supported models.</p>
        </div>
        <div class="chapter__visual">
          <figure class="phone" data-anchor="ask-phone">
            <img src="assets/img/screens/ask.webp" width="640" height="1391" alt="Asking the Ocean about light: the answer names the thoughts it drew from." loading="lazy" decoding="async">
          </figure>
        </div>
      </div>
    </section>

    <section class="section grow" id="grow" data-chapter="grow">
      <div class="wrap grow__grid">
        <article class="panel">
          <p class="eyebrow">Branch</p>
          <h2 class="panel__title">Grow an idea without losing the original.</h2>
          <p>Branch any thought into a question, a concept, research, or a project. The original stays exactly as you wrote it.</p>
          <figure class="phone phone--small">
            <img src="assets/img/screens/detail.webp" width="640" height="1391" alt="A thought in Oryne with a question branching from it." loading="lazy" decoding="async">
          </figure>
        </article>
        <article class="panel">
          <p class="eyebrow">Library</p>
          <h2 class="panel__title">Everything, in order, when you want it.</h2>
          <p>Search every thought, filter by kind, and switch between Recent and Related.</p>
          <figure class="phone phone--small">
            <img src="assets/img/screens/library.webp" width="640" height="1391" alt="The Oryne Library, with related thoughts laid out side by side." loading="lazy" decoding="async">
          </figure>
        </article>
      </div>
    </section>

    <section class="section usecases" id="use-cases" data-chapter="ambient">
      <div class="wrap">
        <p class="eyebrow">Use cases</p>
        <h2 class="headline">Made for the way ideas really arrive.</h2>
        <div class="tabs" data-tabs>
          <div class="tabs__list js-only" data-tab-list data-label="Use cases"></div>

          <div class="tabs__panel" id="use-designers" data-tab-panel>
            <h3 class="tabs__title" data-tab-title>Designers</h3>
            <p class="moment">Screenshot a palette on the bus and say what caught your eye. Your color studies gather into one current, ready when the project starts.</p>
            <ul class="thoughts">
              <li class="thought">
                <div class="thought__image thought__image--sunset" aria-hidden="true"></div>
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="5.5" width="17" height="13" rx="2.5"/><path d="M3.5 15.5l4.5-4.5 4 4 3-3 5.5 5.5"/><circle cx="16" cy="9.5" r="1.3"/></svg>Image</p>
                <p class="thought__title">Sunset gradient study</p>
                <p class="thought__text">The orange does not end. It cools into violet before the horizon eats it.</p>
                <p class="thought__current">light and color</p>
              </li>
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14M5 12h14M5 17h9"/></svg>Thought</p>
                <p class="thought__title">Warm to cool, not a filter</p>
                <p class="thought__text">Stop adding an orange overlay. The sunset is already a temperature shift: 3500K down into blue. Match that, don't fake it.</p>
                <p class="thought__current">light and color</p>
              </li>
              <li class="thought">
                <div class="thought__image thought__image--dusk" aria-hidden="true"></div>
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="5.5" width="17" height="13" rx="2.5"/><path d="M3.5 15.5l4.5-4.5 4 4 3-3 5.5 5.5"/><circle cx="16" cy="9.5" r="1.3"/></svg>Image</p>
                <p class="thought__title">Desk at 6pm</p>
                <p class="thought__text">The wall goes peach, then slate, as the sun drops. Worth sampling before picking the app background.</p>
                <p class="thought__current">light and color</p>
              </li>
            </ul>
          </div>

          <div class="tabs__panel" id="use-writers" data-tab-panel>
            <h3 class="tabs__title" data-tab-title>Writers</h3>
            <p class="moment">Half a sentence on the train, a line overheard in a café. Oryne keeps the fragments until they are ready to become paragraphs.</p>
            <ul class="thoughts">
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 11v2M7.5 8.5v7M11 5v14M14.5 8v8M18 10v4"/></svg>Whisper</p>
                <p class="thought__title">The house kept its summer smell</p>
                <p class="thought__text">Opening line? The house kept its summer smell long after we closed it up.</p>
                <p class="thought__current">writing</p>
              </li>
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14M5 12h14M5 17h9"/></svg>Thought</p>
                <p class="thought__title">Overheard at the café</p>
                <p class="thought__text">“I only lie about small things.” Character, not dialogue.</p>
                <p class="thought__current">writing</p>
              </li>
            </ul>
          </div>

          <div class="tabs__panel" id="use-founders" data-tab-panel>
            <h3 class="tabs__title" data-tab-title>Founders and makers</h3>
            <p class="moment">The 2 a.m. product idea, the link worth keeping, the thing a customer said. Later, ask what you keep circling.</p>
            <ul class="thoughts">
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14M5 12h14M5 17h9"/></svg>Thought</p>
                <p class="thought__title">Half a sentence from the train</p>
                <p class="thought__text">What if the home screen was just one thought, not a grid.</p>
                <p class="thought__current">product ideas</p>
              </li>
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14M5 12h14M5 17h9"/></svg>Thought</p>
                <p class="thought__title">A button that doesn't need a label</p>
                <p class="thought__text">If the icon is the action, the word next to it is noise. Cut the word first.</p>
                <p class="thought__current">interface design</p>
              </li>
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M10 14a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66L11.5 6.8"/><path d="M14 10a4 4 0 0 0-5.66 0l-3 3a4 4 0 0 0 5.66 5.66l1.5-1.46"/></svg>Link</p>
                <p class="thought__title">Apple Design Principles</p>
                <p class="thought__source">developer.apple.com</p>
                <p class="thought__text">Guidance that keeps an interface feeling like it belongs on the phone.</p>
                <p class="thought__current">user experience</p>
              </li>
            </ul>
          </div>

          <div class="tabs__panel" id="use-students" data-tab-panel>
            <h3 class="tabs__title" data-tab-title>Students and researchers</h3>
            <p class="moment">Quotes, articles, and questions. Branch any of them into research, then ask what your sources have in common.</p>
            <ul class="thoughts">
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M10 14a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66L11.5 6.8"/><path d="M14 10a4 4 0 0 0-5.66 0l-3 3a4 4 0 0 0 5.66 5.66l1.5-1.46"/></svg>Link</p>
                <p class="thought__title">Are.na Editorial</p>
                <p class="thought__source">are.na</p>
                <p class="thought__text">Notes on attention, collecting, and slow software. Saving is not the same as seeing.</p>
                <p class="thought__current">reading</p>
              </li>
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6"/><path d="M15 15l5 5"/></svg>Research</p>
                <p class="thought__title">What makes a collection useful?</p>
                <p class="thought__source">Branch of Are.na Editorial</p>
                <p class="thought__text">Look at what the best collections leave out.</p>
                <p class="thought__current">reading</p>
              </li>
            </ul>
          </div>

          <div class="tabs__panel" id="use-everyday" data-tab-panel>
            <h3 class="tabs__title" data-tab-title>Everyday life</h3>
            <p class="moment">Recipes, gift ideas, places to try. The small things you would otherwise lose.</p>
            <ul class="thoughts">
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14M5 12h14M5 17h9"/></svg>Thought</p>
                <p class="thought__title">Weeknight noodles</p>
                <p class="thought__text">Chili oil, garlic, leftover greens. Ten minutes. Don't lose this one.</p>
                <p class="thought__current">cooking</p>
              </li>
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14M5 12h14M5 17h9"/></svg>Thought</p>
                <p class="thought__title">Fix the old radio for Dad</p>
                <p class="thought__text">He still talks about the one from the old kitchen. Find someone who repairs valve radios.</p>
                <p class="thought__current">gifts</p>
              </li>
              <li class="thought">
                <div class="thought__image thought__image--dumplings" aria-hidden="true"></div>
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="5.5" width="17" height="13" rx="2.5"/><path d="M3.5 15.5l4.5-4.5 4 4 3-3 5.5 5.5"/><circle cx="16" cy="9.5" r="1.3"/></svg>Image</p>
                <p class="thought__title">The dumpling place by the station</p>
                <p class="thought__text">Pork and chive, a queue out the door at seven. Go on a weekday.</p>
                <p class="thought__current">places</p>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </section>

    <section class="section why" id="why" data-chapter="ambient">
      <div class="wrap">
        <h2 class="headline">Not another notes app.</h2>
        <p class="lead">Notes apps help you write things down. Oryne helps you keep ideas alive.</p>
        <table class="compare">
          <caption class="vh">How Oryne compares with a typical notes app</caption>
          <thead>
            <tr><td></td><th scope="col">A typical notes app</th><th scope="col" class="is-oryne">Oryne</th></tr>
          </thead>
          <tbody>
            <tr><th scope="row">Saving an idea</th><td data-label="A typical notes app">Open the app, make a note, name it, pick a folder.</td><td class="is-oryne" data-label="Oryne">Press a button and speak.</td></tr>
            <tr><th scope="row">Staying organized</th><td data-label="A typical notes app">Up to you, forever.</td><td class="is-oryne" data-label="Oryne">Related ideas gather on their own.</td></tr>
            <tr><th scope="row">Old ideas</th><td data-label="A typical notes app">Sink out of sight.</td><td class="is-oryne" data-label="Oryne">Come back, one a day.</td></tr>
            <tr><th scope="row">Finding something</th><td data-label="A typical notes app">Guess the right keyword.</td><td class="is-oryne" data-label="Oryne">Ask in your own words and see the sources.</td></tr>
            <tr><th scope="row">Growing an idea</th><td data-label="A typical notes app">Edit over the original.</td><td class="is-oryne" data-label="Oryne">Branch it. The original stays.</td></tr>
          </tbody>
        </table>
      </div>
    </section>

    <section class="section privacy" id="privacy" data-chapter="ambient">
      <div class="wrap">
        <p class="eyebrow">Privacy</p>
        <h2 class="headline">Your ideas stay yours.</h2>
        <p class="lead">Oryne is built so your thoughts never have to leave your devices, and there's no account to create.</p>
        <ul class="promises">
          <li>
            <svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="7" y="3" width="10" height="18" rx="2.5"/><path d="M11 18h2"/></svg>
            <h3>Understood on your device.</h3>
            <p>Titles, themes, currents, and answers are worked out on your iPhone or iPad.</p>
          </li>
          <li>
            <svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M7 18h10a4 4 0 0 0 .6-7.95 5.5 5.5 0 0 0-10.7 1.2A3.5 3.5 0 0 0 7 18z"/></svg>
            <h3>Synced with your own iCloud.</h3>
            <p>Your Ocean moves between your devices through your private iCloud.</p>
          </li>
          <li>
            <svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 12s3.5-6 9-6 9 6 9 6-3.5 6-9 6-9-6-9-6z"/><circle cx="12" cy="12" r="2.5"/><path d="M4 4l16 16"/></svg>
            <h3>No ads, no tracking, no analytics.</h3>
            <p>Not in the app, and not on this website.</p>
          </li>
          <li>
            <svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 14V4M8 8l4-4 4 4"/><path d="M5 12v6.5A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5V12"/></svg>
            <h3>Export everything, any time.</h3>
            <p>Take your whole Ocean with you as Markdown files.</p>
          </li>
        </ul>
        <a class="more" href="privacy.html">Read the privacy policy<span aria-hidden="true">&nbsp;›</span></a>
      </div>
    </section>

    <section class="section more-section" id="more" data-chapter="ambient">
      <div class="wrap">
        <h2 class="headline">And there's more.</h2>
        <ul class="tiles">
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="4" width="7" height="7" rx="2"/><rect x="13" y="4" width="7" height="7" rx="2"/><rect x="4" y="13" width="16" height="7" rx="2"/></svg>Home Screen and Lock Screen widgets</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="8" width="18" height="8" rx="4"/><circle cx="16.5" cy="12" r="2.2"/></svg>Control Center button</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/></svg>Siri and Shortcuts</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 15V3M8 7l4-4 4 4"/><path d="M7 10H6a1.5 1.5 0 0 0-1.5 1.5v8A1.5 1.5 0 0 0 6 21h12a1.5 1.5 0 0 0 1.5-1.5v-8A1.5 1.5 0 0 0 18 10h-1"/></svg>Share from any app</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M10 14a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66L11.5 6.8"/><path d="M14 10a4 4 0 0 0-5.66 0l-3 3a4 4 0 0 0 5.66 5.66l1.5-1.46"/></svg>Link previews</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="2.5" y="5" width="13" height="15" rx="2"/><rect x="16" y="9" width="5.5" height="11" rx="1.5"/></svg>iPhone and iPad, in sync</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.4 2.3 3.5 5.1 3.5 8.5s-1.1 6.2-3.5 8.5c-2.4-2.3-3.5-5.1-3.5-8.5s1.1-6.2 3.5-8.5z"/></svg>English and <span lang="zh-Hans">简体中文</span></li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9h16M4 13h16M7 17h10"/></svg>Calm Accessibility Mode</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M9 6 5 10l4 4"/><path d="M5 10h9.5a4.5 4.5 0 0 1 0 9H12"/></svg>Undo right after you capture</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M14 3.5H7.5A1.5 1.5 0 0 0 6 5v14a1.5 1.5 0 0 0 1.5 1.5h9A1.5 1.5 0 0 0 18 19V7.5z"/><path d="M14 3.5v4h4M9 12.5h6M9 16h4"/></svg>Export to Markdown</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M11 3.5l1.5 4 4 1.5-4 1.5-1.5 4-1.5-4-4-1.5 4-1.5z"/><path d="M18 14l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z"/></svg>Apple Intelligence on supported models</li>
        </ul>
      </div>
    </section>

    <section class="section faq" id="faq" data-chapter="deep">
      <div class="wrap wrap--narrow">
        <h2 class="headline">Questions and answers</h2>
        <details class="qa"><summary>Which devices does Oryne run on?</summary><p>iPhone with iOS 18 or later, and iPad with iPadOS 18 or later. Answers written by Apple Intelligence need a model that supports it.</p></details>
        <details class="qa"><summary>Do I need an account?</summary><p>No. Oryne syncs through your iCloud, and works fully without it.</p></details>
        <details class="qa"><summary>Where are my ideas stored?</summary><p>On your devices, and in your private iCloud if you use it. We can't see them.</p></details>
        <details class="qa"><summary>Does it work offline?</summary><p>Yes. Capturing, currents, resurfacing, and Ask all work without a connection. Link previews need one, and so does voice transcription in languages your device can't transcribe on its own.</p></details>
        <details class="qa"><summary>Can I use Oryne in Chinese?</summary><p>Yes. Oryne speaks English and <span lang="zh-Hans">简体中文</span>. Choose in Settings › Oryne › Language.</p></details>
        <details class="qa"><summary>Can I get my ideas out?</summary><p>Yes. In Oryne's Settings, Export the Ocean saves everything as Markdown files, one per current, with a JSON backup.</p></details>
      </div>
    </section>

    <section class="section final" id="download" data-chapter="deep">
      <div class="wrap final__inner">
        <img class="final__icon" src="assets/img/icon-192.webp" width="96" height="96" alt="">
        <h2 class="display">Enter the Ocean.</h2>
        <p class="lead">Your next idea is on its way. Be ready for it.</p>
        <div class="final__actions">
          <a class="badge" href="https://apps.apple.com/app/id0000000000"><img src="assets/img/badge-en.svg" alt="Download on the App Store" height="48" data-lang-asset></a>
        </div>
      </div>
      <div class="final__stage">
        <figure class="phone" data-anchor="final-phone">
          <img src="assets/img/screens/capture.webp" width="640" height="1391" alt="Oryne, ready for the next thought." loading="lazy" decoding="async">
        </figure>
      </div>
    </section>
  </main>

  <footer class="footer">
    <div class="wrap footer__inner">
      <a class="wordmark" href="#top">Oryne</a>
      <nav aria-label="Legal and help"><a href="privacy.html">Privacy</a><a href="support.html">Support</a></nav>
      <p class="footer__lang"><span aria-current="true">English</span><a href="zh/" hreflang="zh-Hans" lang="zh-Hans" data-lang-switch="zh-Hans">简体中文</a></p>
      <p>© 2026 Oryne. Apple, iPhone, iPad, and Siri are trademarks of Apple Inc. App Store is a service mark of Apple Inc.</p>
    </div>
  </footer>
</body>
</html>
```

- [ ] **Step 4: Run the static checks for the English tree**

Run: `python3 website/tools/check.py --only en`
Expected: the only errors are `missing page: privacy.html`, `missing page: support.html`, and `index.html: <a> points at a missing file` for `privacy.html` and `support.html` (both pages arrive in Task 8). No dash errors. Exactly one warning: `index.html: the App Store URL is still the placeholder`.

- [ ] **Step 5: Open the page in the browser pane**

Start the preview with `preview_start` (name `oryne-website`) and open `http://127.0.0.1:8765/?debug`. Read console errors (`read_console_messages`, errors only).
Expected: no errors. The module graph loads (site, choreo, ocean, orbs, noise, breath, sound, vignettes).

- [ ] **Step 6: Verify the water, chapter by chapter (desktop 1440×900)**

For each section id in order (`top`, `how`, `capture`, `currents`, `resurface`, `ask`, `grow`, `use-cases`, `why`, `privacy`, `more`, `faq`, `download`), scroll it to the middle of the viewport with `javascript_tool` (`document.getElementById(id).scrollIntoView({block: 'center'})`), wait about a second, and take a screenshot. Check:

1. `top`: the breathing ring stands around the phone, the rim brightest at the lower right, faint stars inside the ring, hairline waves across the width, motes drifting but none over the phone.
2. `how`: all four vignettes animate.
3. `currents`: at the middle of the section, four labeled groups sit beside the phone, clear of the text column.
4. `resurface`: a warm mote with the label "Ideas arrive in the shower" sits above the widgets.
5. `ask`: three motes to the left of the phone, hairlines reaching the phone's edge.
6. `grow`: motes settle into three low shelves.
7. Deeper sections: the water darkens, stars are gone, motion calms. `faq` and `download` are nearly still.

Tune only presentation constants (alphas, offsets, sizes) if something reads wrong. Re-run `node --test tests/*.test.mjs` after touching `choreo.js`.

- [ ] **Step 7: Verify the release demo**

In the Capture section, click the input, type `The tide keeps returning my ideas`, press Return.
Expected: a bright mote leaves the input with a short trail, falls about 150 px into the water carrying the text, the status line reads "Drifted into the Ocean", the input is empty with focus, and the label fades after about 4.5 s. An empty input keeps Release disabled.

- [ ] **Step 8: Verify the sound**

Click the bar's Sound toggle, then with `javascript_tool` read `__oryne.sound.isOn` and sample `__oryne.sound.rms()` six times one second apart (use `await new Promise(r => setTimeout(r, 1000))` between samples inside one script).
Expected: `isOn` is `true`; both toggles have `aria-pressed="true"`; readings rise and fall with the breath and stay between −40 and −14 dBFS. Release a thought: `rms()` briefly rises (the chime). Toggle off: readings fall toward silence within 1.5 s. If the level sits outside the range, adjust the layer gains in `sound.js` (`deep` 0.14, swell `0.03 + 0.47 * lift`, wash 0.05) and re-run `node --test tests/sound.test.mjs` (update its expected ranges together with the formula).

- [ ] **Step 9: Verify stillness, tabs, keyboard, and phone width**

1. `?motion=still&debug`: run `const c = document.querySelector('.ocean__field'); const a = c.toDataURL(); await new Promise(r => setTimeout(r, 2000)); a === c.toDataURL()`. Expected: `true` (the stilled Ocean does not move).
2. Tabs: click each use-case tab; press ArrowRight/ArrowLeft/Home/End on a focused tab. Expected: one panel visible at a time; focus and `aria-selected` follow.
3. Keyboard: from the top, press Tab. Expected: "Skip to content" appears first, then the wordmark, the four section links, 中文, Sound, Download; focus rings are visible everywhere.
4. `resize_window` preset `mobile`, reload. Screenshot the hero, Capture, Currents, the comparison table, and the footer. Expected: no horizontal scroll (`document.documentElement.scrollWidth === innerWidth`), section links hidden, the Sound label visually hidden but the button still named, the comparison table stacked with its column labels. Reset with preset `desktop`.

- [ ] **Step 10: Verify performance**

Open `?debug=perf`, scroll top to bottom and back over about 10 s, then read the readout.
Expected on this Mac: about 60 fps or more, frame work under 6 ms, not degraded.

- [ ] **Step 11: Checkpoint**

Run: `cd website && node --test tests/*.test.mjs && python3 tools/check.py --only en`
Expected: tests pass; the checker reports only the Task 8 pages as missing. Report the App Store URL found in Task 4 Step 4 to Malik for confirmation. No commit.

---

### Task 8: English Privacy and Support pages

**Files:**
- Create: `website/privacy.html`
- Create: `website/support.html`
- Create: `website/robots.txt`

**Interfaces:**
- Consumes: the Task 7 markup contract and stylesheet (`.prose`, `.summary`, `.updated`, `.qa`); `site.js` treats `<body data-page="long">` as still water at depth 0.6.
- Produces: heading and question `id`s that the Chinese pages must repeat exactly (Task 9).
- Facts (verified in code at `0af9bf0`, spec §8): Release builds send nothing to any Oryne server; speech prefers on-device recognition; a transcribed whisper's audio is deleted 30 days after capture; links are fetched for previews; CloudKit private database; export is Markdown per current plus `backup.json`; Delete asks "Delete this thought?"; Settings has Calm Accessibility Mode, Clear examples, and Export the Ocean; Siri phrases are English only.

- [ ] **Step 1: Write the privacy policy**

**File:** `website/privacy.html`
```html
<!doctype html>
<html lang="en" class="no-js" data-en="privacy.html" data-zh="zh/privacy.html">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>Privacy Policy · Oryne</title>
  <meta name="description" content="How Oryne handles your thoughts: on your devices and in your private iCloud, and nowhere else.">
  <meta name="theme-color" content="#050508">
  <meta name="color-scheme" content="dark">
  <link rel="alternate" hreflang="en" href="privacy.html">
  <link rel="alternate" hreflang="zh-Hans" href="zh/privacy.html">
  <link rel="alternate" hreflang="x-default" href="privacy.html">
  <link rel="icon" href="assets/img/favicon-32.png" sizes="32x32" type="image/png">
  <link rel="icon" href="assets/img/favicon-16.png" sizes="16x16" type="image/png">
  <link rel="apple-touch-icon" href="assets/img/apple-touch-icon.png">
  <link rel="stylesheet" href="assets/css/site.css">
  <script>
    (function () {
      var root = document.documentElement;
      root.className = root.className.replace('no-js', 'js');
      var here = root.lang === 'zh-Hans' ? 'zh-Hans' : 'en';
      var want = null;
      try { want = window.localStorage.getItem('oryne.lang'); } catch (e) {}
      if (!want && here === 'en') {
        var first = ((navigator.languages && navigator.languages[0]) || navigator.language || '').toLowerCase();
        if (/^zh(?:-(?:hans|cn|sg)(?:-|$)|$)/.test(first)) want = 'zh-Hans';
      }
      if (want && want !== here) {
        var target = root.getAttribute(want === 'zh-Hans' ? 'data-zh' : 'data-en');
        if (target) window.location.replace(target + window.location.search + window.location.hash);
      }
    })();
  </script>
  <script type="module" src="assets/js/site.js"></script>
</head>
<body data-page="long">
  <a class="skip" href="#main">Skip to content</a>

  <div class="ocean" aria-hidden="true">
    <canvas class="ocean__water"></canvas>
    <canvas class="ocean__field"></canvas>
    <div class="ocean__grain"></div>
  </div>

  <header class="bar">
    <div class="wrap bar__inner">
      <a class="wordmark" href="index.html">Oryne</a>
      <nav class="bar__nav" aria-label="Sections">
        <a href="index.html#how">Features</a>
        <a href="index.html#use-cases">Use cases</a>
        <a href="index.html#privacy">Privacy</a>
        <a href="index.html#faq">FAQ</a>
      </nav>
      <div class="bar__controls">
        <div class="lang"><span aria-current="true">EN</span><a href="zh/privacy.html" hreflang="zh-Hans" lang="zh-Hans" data-lang-switch="zh-Hans">中文</a></div>
        <button class="icon-btn js-only" type="button" data-sound-toggle aria-pressed="false">
          <svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 9c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/><path d="M3 15c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/></svg>
          <span class="icon-btn__label">Sound</span>
        </button>
        <a class="btn btn--primary btn--small" href="https://apps.apple.com/app/id0000000000">Download</a>
      </div>
    </div>
  </header>

  <main id="main">
    <article class="wrap prose">
      <p class="eyebrow">Privacy</p>
      <h1 class="prose__title">Privacy Policy</h1>
      <p class="updated">Last updated September 18, 2026</p>
      <p class="summary">Oryne keeps your thoughts on your devices and in your private iCloud. We don't run any server that receives what you capture, and there are no ads, trackers, or analytics in the app or on this website.</p>

      <h2 id="stores">What Oryne stores</h2>
      <p>Everything you capture: text, voice recordings and their transcripts, images, and links, along with their titles and themes. It lives in Oryne's database on your device, which Oryne's share extension and widgets on the same device can also read.</p>

      <h2 id="icloud">Sync through your iCloud</h2>
      <p>If you're signed in to iCloud, Oryne syncs your Ocean through your private iCloud database, so your iPhone and iPad stay in step. Apple stores this data in your Apple Account, and we can't access it. If you don't use iCloud, your Ocean stays on the device.</p>

      <h2 id="on-device">Understanding happens on your device</h2>
      <p>Titles, themes, currents, related thoughts, resurfacing, and answers in Ask are worked out on your device, using Apple's frameworks and, on supported models, Apple Intelligence. This version of Oryne doesn't send your thoughts to us or to any AI service.</p>
      <p>If a future version adds a feature that sends content off your device, this policy and the feature itself will say so before it ships.</p>

      <h2 id="voice">Voice</h2>
      <p>Oryne transcribes whispers with Apple's speech recognition. When your device can transcribe a language on its own, it does, and the audio stays on the device. For languages it can't, Apple's speech recognition service may process the audio, under Apple's privacy policy.</p>
      <p>Once a whisper has a transcript, Oryne deletes its recording 30 days after it was captured: Oryne keeps your words, not the files. A whisper without a transcript keeps its recording.</p>

      <h2 id="links">Links</h2>
      <p>When you save a link, Oryne fetches that page to show its title, description, and image, the way a browser would. That request goes to the website you saved.</p>

      <h2 id="siri">Siri and Shortcuts</h2>
      <p>When you capture with Siri or a shortcut, Apple handles the request under Apple's privacy policy, then passes the text to Oryne.</p>

      <h2 id="permissions">Permissions</h2>
      <p>Oryne asks for the microphone and speech recognition to catch whispers, and for photos only when you choose images to capture. You can change these in your iPhone's Settings at any time.</p>

      <h2 id="control">Your control</h2>
      <ul>
        <li><strong>Export.</strong> In Oryne's Settings, Export the Ocean saves everything as Markdown files with a JSON backup.</li>
        <li><strong>Delete.</strong> Delete any thought in the app. Deleting Oryne removes its data from that device.</li>
        <li><strong>iCloud.</strong> Data synced to iCloud can be managed in your iPhone's Settings, under your Apple Account.</li>
      </ul>

      <h2 id="website">This website</h2>
      <p>This site is a set of static pages. It uses no cookies and no analytics. It keeps two preferences in your browser, your language and whether sound is on, and nothing else. The Try it demo never leaves the page. Like any website, our host may keep standard request logs, such as IP address and browser type, to deliver and protect the site.</p>

      <h2 id="children">Children</h2>
      <p>Oryne doesn't collect personal information from anyone, including children.</p>

      <h2 id="changes">Changes</h2>
      <p>If this policy changes, we'll update this page and the date at the top.</p>

      <h2 id="contact">Contact</h2>
      <p>Questions about privacy? Email <a href="mailto:support@example.com">support@example.com</a>.</p>
    </article>
  </main>

  <footer class="footer">
    <div class="wrap footer__inner">
      <a class="wordmark" href="index.html">Oryne</a>
      <nav aria-label="Legal and help"><a href="privacy.html" aria-current="page">Privacy</a><a href="support.html">Support</a></nav>
      <p class="footer__lang"><span aria-current="true">English</span><a href="zh/privacy.html" hreflang="zh-Hans" lang="zh-Hans" data-lang-switch="zh-Hans">简体中文</a></p>
      <p>© 2026 Oryne. Apple, iPhone, iPad, and Siri are trademarks of Apple Inc. App Store is a service mark of Apple Inc.</p>
    </div>
  </footer>
</body>
</html>
```

- [ ] **Step 2: Write the support page**

**File:** `website/support.html`
```html
<!doctype html>
<html lang="en" class="no-js" data-en="support.html" data-zh="zh/support.html">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>Support · Oryne</title>
  <meta name="description" content="Answers to common questions about Oryne: fast capture, sync, export, and more.">
  <meta name="theme-color" content="#050508">
  <meta name="color-scheme" content="dark">
  <link rel="alternate" hreflang="en" href="support.html">
  <link rel="alternate" hreflang="zh-Hans" href="zh/support.html">
  <link rel="alternate" hreflang="x-default" href="support.html">
  <link rel="icon" href="assets/img/favicon-32.png" sizes="32x32" type="image/png">
  <link rel="icon" href="assets/img/favicon-16.png" sizes="16x16" type="image/png">
  <link rel="apple-touch-icon" href="assets/img/apple-touch-icon.png">
  <link rel="stylesheet" href="assets/css/site.css">
  <script>
    (function () {
      var root = document.documentElement;
      root.className = root.className.replace('no-js', 'js');
      var here = root.lang === 'zh-Hans' ? 'zh-Hans' : 'en';
      var want = null;
      try { want = window.localStorage.getItem('oryne.lang'); } catch (e) {}
      if (!want && here === 'en') {
        var first = ((navigator.languages && navigator.languages[0]) || navigator.language || '').toLowerCase();
        if (/^zh(?:-(?:hans|cn|sg)(?:-|$)|$)/.test(first)) want = 'zh-Hans';
      }
      if (want && want !== here) {
        var target = root.getAttribute(want === 'zh-Hans' ? 'data-zh' : 'data-en');
        if (target) window.location.replace(target + window.location.search + window.location.hash);
      }
    })();
  </script>
  <script type="module" src="assets/js/site.js"></script>
</head>
<body data-page="long">
  <a class="skip" href="#main">Skip to content</a>

  <div class="ocean" aria-hidden="true">
    <canvas class="ocean__water"></canvas>
    <canvas class="ocean__field"></canvas>
    <div class="ocean__grain"></div>
  </div>

  <header class="bar">
    <div class="wrap bar__inner">
      <a class="wordmark" href="index.html">Oryne</a>
      <nav class="bar__nav" aria-label="Sections">
        <a href="index.html#how">Features</a>
        <a href="index.html#use-cases">Use cases</a>
        <a href="index.html#privacy">Privacy</a>
        <a href="index.html#faq">FAQ</a>
      </nav>
      <div class="bar__controls">
        <div class="lang"><span aria-current="true">EN</span><a href="zh/support.html" hreflang="zh-Hans" lang="zh-Hans" data-lang-switch="zh-Hans">中文</a></div>
        <button class="icon-btn js-only" type="button" data-sound-toggle aria-pressed="false">
          <svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 9c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/><path d="M3 15c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/></svg>
          <span class="icon-btn__label">Sound</span>
        </button>
        <a class="btn btn--primary btn--small" href="https://apps.apple.com/app/id0000000000">Download</a>
      </div>
    </div>
  </header>

  <main id="main">
    <article class="wrap prose">
      <p class="eyebrow">Support</p>
      <h1 class="prose__title">How can we help?</h1>
      <p class="updated">Answers to common questions, and a way to reach us.</p>

      <h2 id="getting-started">Getting started</h2>
      <details class="qa" id="fast-capture"><summary>How do I capture fastest?</summary><p>In your iPhone's Settings, open Action Button, choose Shortcut, then pick Oryne's Start Fast Capture. You can also add Oryne's button to Control Center. Either way, Oryne opens already listening.</p></details>
      <details class="qa" id="context-capture"><summary>How do I keep a screenshot together with a spoken note?</summary><p>In the Shortcuts app, make a shortcut that runs Take Screenshot, then Oryne's Start Context Capture. Run it from the Action Button, from Back Tap in Accessibility settings, or from Camera Control where your iPhone allows it.</p></details>
      <details class="qa" id="share"><summary>Can I capture from other apps?</summary><p>Yes. In any app, tap Share and choose Oryne. Links, images, and text arrive in your Ocean.</p></details>
      <details class="qa" id="siri"><summary>Can I use Siri?</summary><p>Yes. Say “Hey Siri, add an inspiration to Oryne,” then speak your thought. Siri phrases are in English. In any language, you can run Oryne's Add Inspiration action from a shortcut.</p></details>

      <h2 id="your-ocean">Your Ocean</h2>
      <details class="qa" id="sync"><summary>Does Oryne sync between my iPhone and iPad?</summary><p>Yes, through iCloud, when both devices are signed in to the same Apple Account.</p></details>
      <details class="qa" id="export"><summary>How do I export everything?</summary><p>In Oryne's Settings, choose Export the Ocean. You get Markdown files, one per current, plus a JSON backup.</p></details>
      <details class="qa" id="delete"><summary>How do I delete a thought?</summary><p>Open the thought, choose Delete, and confirm. Right after a capture, Undo takes it back.</p></details>
      <details class="qa" id="examples"><summary>What are the example thoughts?</summary><p>Oryne starts with a short introduction current. Once you've read it, choose Clear examples in Oryne's Settings.</p></details>

      <h2 id="comfort">Comfort</h2>
      <details class="qa" id="motion"><summary>The Ocean moves too much for me.</summary><p>Turn on Calm Accessibility Mode in Oryne's Settings, or Reduce Motion in your iPhone's Settings under Accessibility, then Motion. The Ocean holds still.</p></details>
      <details class="qa" id="language"><summary>How do I switch Oryne to Chinese?</summary><p>In Settings › Oryne › Language, choose <span lang="zh-Hans">简体中文</span>.</p></details>

      <h2 id="contact">Contact</h2>
      <p>Still need help? Email <a href="mailto:support@example.com">support@example.com</a>.</p>
    </article>
  </main>

  <footer class="footer">
    <div class="wrap footer__inner">
      <a class="wordmark" href="index.html">Oryne</a>
      <nav aria-label="Legal and help"><a href="privacy.html">Privacy</a><a href="support.html" aria-current="page">Support</a></nav>
      <p class="footer__lang"><span aria-current="true">English</span><a href="zh/support.html" hreflang="zh-Hans" lang="zh-Hans" data-lang-switch="zh-Hans">简体中文</a></p>
      <p>© 2026 Oryne. Apple, iPhone, iPad, and Siri are trademarks of Apple Inc. App Store is a service mark of Apple Inc.</p>
    </div>
  </footer>
</body>
</html>
```

- [ ] **Step 3: Add the crawl rules**

**File:** `website/robots.txt`
```text
User-agent: *
Allow: /
```

- [ ] **Step 4: Run the English checks**

Run: `python3 website/tools/check.py --only en`
Expected: `0 error(s), 5 warning(s)`: the App Store placeholder on all three pages and the support email on Privacy and Support.

- [ ] **Step 5: Verify both pages in the browser**

Open `http://127.0.0.1:8765/privacy.html?debug` and `…/support.html?debug`. For each:
1. Screenshot at 1440×900 and at the `mobile` preset. Expected: the still, darker water; one readable column (about 68 characters wide); headings and lists spaced as in the stylesheet; no horizontal scroll.
2. Stillness: the `toDataURL` comparison from Task 7 Step 9 returns `true`.
3. On Support, open and close two questions with the keyboard (Tab to a summary, press Enter). Expected: the plus turns into a cross and back.
4. Links: the bar's section links go to `index.html#…`; the footer's current page is marked.

Reset the viewport with preset `desktop`.

- [ ] **Step 6: Checkpoint**

Run: `cd website && node --test tests/*.test.mjs && python3 tools/check.py --only en`
Expected: tests pass, `0 error(s)`. No commit.

---

### Task 9: The Chinese pages

**Files:**
- Create: `website/zh/index.html`
- Create: `website/zh/privacy.html`
- Create: `website/zh/support.html`

**Interfaces:**
- Consumes: the English pages as the structural source of truth (same `id`s in the same order, same `data-chapter` sequence, same links and assets after normalization); `badge-zh.svg`.
- Copy rules: glossary terms (海洋, 灵感, 语音, 库, 提问, 延展, 汇入, 捕捉, 碎片, 再次浮现); the app's own catalog Chinese where the sentence exists (不是又一个笔记应用。 · 刚刚闪过什么？ · 汇入 · 已汇入海洋 · 潜入海洋 · 灵感总在洗澡时冒出来 · 记录灵感 · 开始快速捕捉 · 开始情境捕捉 · 导出海洋 · 清空示例 · 宁静无障碍模式); Apple's Simplified Chinese UI names (操作按钮, 控制中心, 相机控制, 快捷指令, 截屏, 轻点背面, 减弱动态效果, 主屏幕, 锁定屏幕, Apple 智能, 共享表单); full-width punctuation; no 「——」; Siri phrases stay English.

- [ ] **Step 1: Write the Chinese landing page**

**File:** `website/zh/index.html`
```html
<!doctype html>
<html lang="zh-Hans" class="no-js" data-en="../" data-zh="./">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>Oryne：在灵感溜走之前，接住它</title>
  <meta name="description" content="Oryne 是安放灵感、语音、截图与链接的宁静之所。相关的灵感会自行汇聚，被遗忘的灵感会再次浮现。适用于 iPhone 与 iPad。">
  <meta name="theme-color" content="#050508">
  <meta name="color-scheme" content="dark">
  <link rel="alternate" hreflang="en" href="../">
  <link rel="alternate" hreflang="zh-Hans" href="./">
  <link rel="alternate" hreflang="x-default" href="../">
  <link rel="icon" href="../assets/img/favicon-32.png" sizes="32x32" type="image/png">
  <link rel="icon" href="../assets/img/favicon-16.png" sizes="16x16" type="image/png">
  <link rel="apple-touch-icon" href="../assets/img/apple-touch-icon.png">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Oryne">
  <meta property="og:title" content="Oryne：在灵感溜走之前，接住它">
  <meta property="og:description" content="安放灵感、语音、截图与链接的宁静之所。适用于 iPhone 与 iPad。">
  <meta property="og:image" content="../assets/img/og.png">
  <meta property="og:locale" content="zh_CN">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="stylesheet" href="../assets/css/site.css">
  <script>
    (function () {
      var root = document.documentElement;
      root.className = root.className.replace('no-js', 'js');
      var here = root.lang === 'zh-Hans' ? 'zh-Hans' : 'en';
      var want = null;
      try { want = window.localStorage.getItem('oryne.lang'); } catch (e) {}
      if (!want && here === 'en') {
        var first = ((navigator.languages && navigator.languages[0]) || navigator.language || '').toLowerCase();
        if (/^zh(?:-(?:hans|cn|sg)(?:-|$)|$)/.test(first)) want = 'zh-Hans';
      }
      if (want && want !== here) {
        var target = root.getAttribute(want === 'zh-Hans' ? 'data-zh' : 'data-en');
        if (target) window.location.replace(target + window.location.search + window.location.hash);
      }
    })();
  </script>
  <script type="module" src="../assets/js/site.js"></script>
</head>
<body>
  <a class="skip" href="#main">跳到正文</a>

  <div class="ocean" aria-hidden="true">
    <canvas class="ocean__water"></canvas>
    <canvas class="ocean__field"></canvas>
    <div class="ocean__grain"></div>
  </div>

  <header class="bar">
    <div class="wrap bar__inner">
      <a class="wordmark" href="#top">Oryne</a>
      <nav class="bar__nav" aria-label="页面导航">
        <a href="#how">功能</a>
        <a href="#use-cases">使用场景</a>
        <a href="#privacy">隐私</a>
        <a href="#faq">常见问题</a>
      </nav>
      <div class="bar__controls">
        <div class="lang"><a href="../" hreflang="en" lang="en" data-lang-switch="en">EN</a><span aria-current="true">中文</span></div>
        <button class="icon-btn js-only" type="button" data-sound-toggle aria-pressed="false">
          <svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 9c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/><path d="M3 15c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/></svg>
          <span class="icon-btn__label">声音</span>
        </button>
        <a class="btn btn--primary btn--small" href="https://apps.apple.com/app/id0000000000">下载</a>
      </div>
    </div>
  </header>

  <main id="main">
    <section class="section hero" id="top" data-chapter="top">
      <div class="wrap hero__copy">
        <p class="eyebrow">适用于 iPhone 与 iPad</p>
        <h1 class="display">在灵感溜走之前，接住它。</h1>
        <p class="lead">Oryne 是安放灵感、语音、截图与链接的宁静之所。相关的灵感会自行汇聚，被遗忘的灵感会在需要时再次浮现。</p>
        <div class="hero__actions">
          <a class="badge" href="https://apps.apple.com/app/id0000000000"><img src="../assets/img/badge-zh.svg" alt="在 App Store 下载" height="48" data-lang-asset></a>
          <button class="btn btn--ghost js-only" type="button" data-sound-toggle aria-pressed="false">
            <svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 9c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/><path d="M3 15c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/></svg>
            聆听
          </button>
        </div>
      </div>
      <div class="hero__stage">
        <figure class="phone" data-anchor="hero-phone">
          <img src="../assets/img/screens/ocean.webp" width="640" height="1391" alt="Oryne 的海洋：每条灵感都是一个柔和的光点，相关的灵感汇成洋流。" fetchpriority="high">
        </figure>
      </div>
    </section>

    <section class="section how" id="how" data-chapter="how">
      <div class="wrap">
        <p class="eyebrow">工作方式</p>
        <h2 class="headline">捕捉一次，其余交给 Oryne。</h2>
        <ol class="cards">
          <li class="card">
            <canvas class="vignette js-only" data-vignette="capture" aria-hidden="true"></canvas>
            <p class="card__label">捕捉</p>
            <h3>几秒就能留住。</h3>
            <p>语音、文字、截图与链接，在 iPhone 上随时随地捕捉。</p>
            <a class="more" href="#capture">了解更多<span class="vh">：捕捉</span><span aria-hidden="true">&nbsp;›</span></a>
          </li>
          <li class="card">
            <canvas class="vignette js-only" data-vignette="gather" aria-hidden="true"></canvas>
            <p class="card__label">汇聚</p>
            <h3>让它自己找到归处。</h3>
            <p>相关的灵感会汇成洋流。无需文件夹，也无需标签。</p>
            <a class="more" href="#currents">了解更多<span class="vh">：洋流</span><span aria-hidden="true">&nbsp;›</span></a>
          </li>
          <li class="card">
            <canvas class="vignette js-only" data-vignette="resurface" aria-hidden="true"></canvas>
            <p class="card__label">浮现</p>
            <h3>把它找回来。</h3>
            <p>每天，一条被遗忘的灵感会在合适的时候回到你面前。</p>
            <a class="more" href="#resurface">了解更多<span class="vh">：再次浮现</span><span aria-hidden="true">&nbsp;›</span></a>
          </li>
          <li class="card">
            <canvas class="vignette js-only" data-vignette="ask" aria-hidden="true"></canvas>
            <p class="card__label">提问</p>
            <h3>问问这一切意味着什么。</h3>
            <p>向你自己的灵感提问，并看到每个回答背后的灵感。</p>
            <a class="more" href="#ask">了解更多<span class="vh">：提问</span><span aria-hidden="true">&nbsp;›</span></a>
          </li>
        </ol>
      </div>
    </section>

    <section class="section chapter" id="capture" data-chapter="capture">
      <div class="wrap chapter__grid">
        <div class="chapter__copy">
          <p class="eyebrow">捕捉</p>
          <h2 class="headline">灵感一来，立刻接住。</h2>
          <p class="lead">说出来、打出来、拍下来，或者分享过来。Oryne 原样接住每一条灵感，从不要求你先归档。</p>
          <ul class="features">
            <li><h3>按下，就说。</h3><p>把操作按钮或控制中心按钮设为「快速捕捉」。Oryne 一打开就在聆听。</p></li>
            <li><h3>用你思考的语言说。</h3><p>说话的同时，文字就会出现。如果你的 iPhone 设置了两种语言，Oryne 会同时聆听这两种语言。</p></li>
            <li><h3>截个图，再说说为什么。</h3><p>「截图 + 语音」会把屏幕上的内容和你的语音备注一起留存。</p></li>
            <li><h3>从任何 App 分享。</h3><p>通过共享表单把链接、图片和文字发送到 Oryne。链接会带着标题和预览一起到来。</p></li>
            <li><h3>或者，交给快捷指令。</h3><p>在「快捷指令」中使用 Oryne 的「记录灵感」操作，无需打开 App 就能留住灵感，也可以用 Siri 运行它。</p></li>
          </ul>
          <form class="release js-only" data-release data-released="已汇入海洋" autocomplete="off">
            <label class="release__label" for="release-input">在这里试试</label>
            <div class="release__row">
              <input id="release-input" name="thought" type="text" maxlength="140" placeholder="刚刚闪过什么？" enterkeyhint="send">
              <button class="btn btn--primary" type="submit">汇入</button>
            </div>
            <p class="release__status" role="status" aria-live="polite"></p>
            <p class="release__note">这个演示只在本页进行，不会发送任何内容。</p>
          </form>
        </div>
        <div class="chapter__visual">
          <figure class="phone" data-anchor="capture-phone">
            <img src="../assets/img/screens/capture.webp" width="640" height="1391" alt="Oryne 的捕捉界面，问你刚刚闪过什么。" loading="lazy" decoding="async">
          </figure>
        </div>
      </div>
    </section>

    <section class="section chapter" id="currents" data-chapter="currents" data-currents="光与色|产品灵感|烹饪|阅读">
      <div class="wrap chapter__grid">
        <div class="chapter__copy">
          <p class="eyebrow">洋流</p>
          <h2 class="headline">你的灵感，会自己整理好。</h2>
          <p class="lead">Oryne 理解每条灵感在说什么，并把相关的灵感汇成洋流。你不必建文件夹、选标签，也不必决定它该放在哪里。</p>
          <ul class="features">
            <li><h3>按含义归类，而非关键词。</h3><p>一张日落照片和一条关于暖光的笔记会汇到一起，即使它们没有一个相同的词。</p></li>
            <li><h3>一条灵感，可属多条洋流。</h3><p>想法本就彼此交叠，所以一条灵感可以同时属于多条洋流。文件夹做不到这一点。</p></li>
            <li><h3>自动起好标题。</h3><p>每条灵感都会在你的设备上得到一个简短的标题。改了它，它就一直是你的。</p></li>
          </ul>
        </div>
        <div class="chapter__visual">
          <figure class="phone" data-anchor="currents-phone">
            <img src="../assets/img/screens/current.webp" width="640" height="1391" alt="Oryne 中的一条洋流：所有关于光与色的灵感，最新的在最上面。" loading="lazy" decoding="async">
          </figure>
        </div>
      </div>
    </section>

    <section class="section chapter" id="resurface" data-chapter="resurface" data-resurface-label="灵感总在洗澡时冒出来">
      <div class="wrap chapter__grid">
        <div class="chapter__copy">
          <p class="eyebrow">再次浮现</p>
          <h2 class="headline">你忘掉的灵感，会回来。</h2>
          <p class="lead">每天，都会有一条你许久未见的灵感浮上水面。它不是提醒，也不是任务，只是一个好念头，重新回到眼前。</p>
          <ul class="features">
            <li><h3>每天一条，就在主屏幕上。</h3><p>「再次浮现」小组件会在主屏幕或锁定屏幕上显示当天的那条灵感。</p></li>
            <li><h3>与你此刻所想相连。</h3><p>与你最近的灵感同属一条洋流的旧灵感，会更容易浮现。</p></li>
            <li><h3>不会一再重复。</h3><p>刚刚重温过的灵感会先歇一阵，之后才可能再次浮现。</p></li>
          </ul>
        </div>
        <div class="chapter__visual">
          <div class="widgets" data-anchor="resurface-widget">
            <div class="widget widget--small" role="img" aria-label="「再次浮现」小组件，小尺寸：灵感总在洗澡时冒出来，3 周前。">
              <p class="widget__head"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 19.5s-7.5-4.6-7.5-9.8A4 4 0 0 1 12 7.6a4 4 0 0 1 7.5 2.1c0 5.2-7.5 9.8-7.5 9.8z"/><path d="M12 15.5v-5M9.8 12.6 12 10.4l2.2 2.2"/></svg>再次浮现</p>
              <p class="widget__title">灵感总在洗澡时冒出来</p>
              <p class="widget__age">3 周前</p>
            </div>
            <div class="widget widget--medium" role="img" aria-label="「再次浮现」小组件，中尺寸：灵感总在洗澡时冒出来。为什么我最好的灵感总在洗澡时冒出来，而从不在书桌前？">
              <p class="widget__head"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 19.5s-7.5-4.6-7.5-9.8A4 4 0 0 1 12 7.6a4 4 0 0 1 7.5 2.1c0 5.2-7.5 9.8-7.5 9.8z"/><path d="M12 15.5v-5M9.8 12.6 12 10.4l2.2 2.2"/></svg>再次浮现</p>
              <p class="widget__title">灵感总在洗澡时冒出来</p>
              <p class="widget__snippet">为什么我最好的灵感总在洗澡时冒出来，而从不在书桌前？大概是因为没有把它们攥得太紧。</p>
              <p class="widget__age">3 周前</p>
            </div>
          </div>
        </div>
      </div>
    </section>

    <section class="section chapter" id="ask" data-chapter="ask">
      <div class="wrap chapter__grid">
        <div class="chapter__copy">
          <p class="eyebrow">提问</p>
          <h2 class="headline">向你的灵感提任何问题。</h2>
          <p class="lead">Oryne 从你捕捉过的灵感中作答，并标明用到了哪些，让每个回答都能追溯到你自己的文字。</p>
          <ul class="modes">
            <li><h3>搜索</h3><p>找到那条你只记得一半的灵感。</p></li>
            <li><h3>综合</h3><p>看清一堆笔记加起来意味着什么。</p></li>
            <li><h3>延展</h3><p>把一个想法带去新的地方。</p></li>
            <li><h3>研究</h3><p>看向笔记之外，并明确标为「海洋之外」。</p></li>
          </ul>
          <p class="footnote">回答在你的设备上生成，在支持的机型上使用 Apple 智能。</p>
        </div>
        <div class="chapter__visual">
          <figure class="phone" data-anchor="ask-phone">
            <img src="../assets/img/screens/ask.webp" width="640" height="1391" alt="向海洋询问关于光的问题：回答标明了它参考的灵感。" loading="lazy" decoding="async">
          </figure>
        </div>
      </div>
    </section>

    <section class="section grow" id="grow" data-chapter="grow">
      <div class="wrap grow__grid">
        <article class="panel">
          <p class="eyebrow">延展</p>
          <h2 class="panel__title">延展一个想法，不丢失原来的它。</h2>
          <p>把任何灵感延展为问题、概念、研究或项目。原始内容会完全保持你写下的样子。</p>
          <figure class="phone phone--small">
            <img src="../assets/img/screens/detail.webp" width="640" height="1391" alt="Oryne 中的一条灵感，以及由它延展出的问题。" loading="lazy" decoding="async">
          </figure>
        </article>
        <article class="panel">
          <p class="eyebrow">库</p>
          <h2 class="panel__title">需要时，一切井然有序。</h2>
          <p>搜索每一条灵感，按类型筛选，还可以按时间或相关性浏览。</p>
          <figure class="phone phone--small">
            <img src="../assets/img/screens/library.webp" width="640" height="1391" alt="Oryne 的库：相关的灵感并排呈现。" loading="lazy" decoding="async">
          </figure>
        </article>
      </div>
    </section>

    <section class="section usecases" id="use-cases" data-chapter="ambient">
      <div class="wrap">
        <p class="eyebrow">使用场景</p>
        <h2 class="headline">为灵感真实的到来方式而设计。</h2>
        <div class="tabs" data-tabs>
          <div class="tabs__list js-only" data-tab-list data-label="使用场景"></div>

          <div class="tabs__panel" id="use-designers" data-tab-panel>
            <h3 class="tabs__title" data-tab-title>设计师</h3>
            <p class="moment">在公交上截下一组配色，说说是什么打动了你。你的色彩研究会汇成一条洋流，项目开始时随时可用。</p>
            <ul class="thoughts">
              <li class="thought">
                <div class="thought__image thought__image--sunset" aria-hidden="true"></div>
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="5.5" width="17" height="13" rx="2.5"/><path d="M3.5 15.5l4.5-4.5 4 4 3-3 5.5 5.5"/><circle cx="16" cy="9.5" r="1.3"/></svg>图片</p>
                <p class="thought__title">日落渐变研究</p>
                <p class="thought__text">橙色并没有结束，它在地平线吞没它之前，冷却成了紫色。</p>
                <p class="thought__current">光与色</p>
              </li>
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14M5 12h14M5 17h9"/></svg>灵感</p>
                <p class="thought__title">由暖到冷，而非滤镜</p>
                <p class="thought__text">别再叠一层橙色了。日落本身就是色温的变化：从 3500K 降到蓝色。去匹配它，而不是伪造它。</p>
                <p class="thought__current">光与色</p>
              </li>
              <li class="thought">
                <div class="thought__image thought__image--dusk" aria-hidden="true"></div>
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="5.5" width="17" height="13" rx="2.5"/><path d="M3.5 15.5l4.5-4.5 4 4 3-3 5.5 5.5"/><circle cx="16" cy="9.5" r="1.3"/></svg>图片</p>
                <p class="thought__title">傍晚 6 点的书桌</p>
                <p class="thought__text">太阳落下时，墙面先变成桃色，再变成石板灰。选 App 背景前值得取个样。</p>
                <p class="thought__current">光与色</p>
              </li>
            </ul>
          </div>

          <div class="tabs__panel" id="use-writers" data-tab-panel>
            <h3 class="tabs__title" data-tab-title>写作者</h3>
            <p class="moment">火车上的半句话，咖啡馆里偶然听到的一句。Oryne 帮你留着这些碎片，直到它们长成段落。</p>
            <ul class="thoughts">
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 11v2M7.5 8.5v7M11 5v14M14.5 8v8M18 10v4"/></svg>语音</p>
                <p class="thought__title">房子留着夏天的气味</p>
                <p class="thought__text">开头一句？我们关上房子很久以后，它还留着夏天的气味。</p>
                <p class="thought__current">写作</p>
              </li>
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14M5 12h14M5 17h9"/></svg>灵感</p>
                <p class="thought__title">咖啡馆里听到的</p>
                <p class="thought__text">「我只在小事上撒谎。」这是人物，不是台词。</p>
                <p class="thought__current">写作</p>
              </li>
            </ul>
          </div>

          <div class="tabs__panel" id="use-founders" data-tab-panel>
            <h3 class="tabs__title" data-tab-title>创始人与创作者</h3>
            <p class="moment">凌晨两点的产品点子，值得留着的链接，客户随口说的一句话。之后问问自己：我一直在绕着什么打转？</p>
            <ul class="thoughts">
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14M5 12h14M5 17h9"/></svg>灵感</p>
                <p class="thought__title">火车上的半句话</p>
                <p class="thought__text">如果主屏幕只是一条灵感，而不是一格格的网格呢。</p>
                <p class="thought__current">产品灵感</p>
              </li>
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14M5 12h14M5 17h9"/></svg>灵感</p>
                <p class="thought__title">不需要文字的按钮</p>
                <p class="thought__text">如果图标本身就是动作，旁边的文字就是噪音。先删掉文字。</p>
                <p class="thought__current">界面设计</p>
              </li>
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M10 14a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66L11.5 6.8"/><path d="M14 10a4 4 0 0 0-5.66 0l-3 3a4 4 0 0 0 5.66 5.66l1.5-1.46"/></svg>链接</p>
                <p class="thought__title">Apple 设计原则</p>
                <p class="thought__source">developer.apple.com</p>
                <p class="thought__text">让界面始终像是属于这台手机的设计指南。</p>
                <p class="thought__current">用户体验</p>
              </li>
            </ul>
          </div>

          <div class="tabs__panel" id="use-students" data-tab-panel>
            <h3 class="tabs__title" data-tab-title>学生与研究者</h3>
            <p class="moment">引文、文章和问题。把任何一条延展为研究，再问问你的资料有什么共同点。</p>
            <ul class="thoughts">
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M10 14a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66L11.5 6.8"/><path d="M14 10a4 4 0 0 0-5.66 0l-3 3a4 4 0 0 0 5.66 5.66l1.5-1.46"/></svg>链接</p>
                <p class="thought__title">Are.na Editorial</p>
                <p class="thought__source">are.na</p>
                <p class="thought__text">关于注意力、收藏与慢软件的笔记。保存不等于看见。</p>
                <p class="thought__current">阅读</p>
              </li>
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6"/><path d="M15 15l5 5"/></svg>研究</p>
                <p class="thought__title">什么让一个收藏变得有用？</p>
                <p class="thought__source">延展自 Are.na Editorial</p>
                <p class="thought__text">看看最好的收藏舍弃了什么。</p>
                <p class="thought__current">阅读</p>
              </li>
            </ul>
          </div>

          <div class="tabs__panel" id="use-everyday" data-tab-panel>
            <h3 class="tabs__title" data-tab-title>日常生活</h3>
            <p class="moment">菜谱、礼物点子、想去的地方。那些不记下来就会丢掉的小事。</p>
            <ul class="thoughts">
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14M5 12h14M5 17h9"/></svg>灵感</p>
                <p class="thought__title">工作日晚上的拌面</p>
                <p class="thought__text">辣椒油、蒜、剩下的青菜。十分钟。别丢了这条。</p>
                <p class="thought__current">烹饪</p>
              </li>
              <li class="thought">
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14M5 12h14M5 17h9"/></svg>灵感</p>
                <p class="thought__title">给爸爸修好那台旧收音机</p>
                <p class="thought__text">他还常说起老厨房里的那台。找个会修电子管收音机的人。</p>
                <p class="thought__current">礼物</p>
              </li>
              <li class="thought">
                <div class="thought__image thought__image--dumplings" aria-hidden="true"></div>
                <p class="thought__kind"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="5.5" width="17" height="13" rx="2.5"/><path d="M3.5 15.5l4.5-4.5 4 4 3-3 5.5 5.5"/><circle cx="16" cy="9.5" r="1.3"/></svg>图片</p>
                <p class="thought__title">车站旁的那家饺子馆</p>
                <p class="thought__text">猪肉韭菜馅，七点门口就排起长队。工作日去。</p>
                <p class="thought__current">地方</p>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </section>

    <section class="section why" id="why" data-chapter="ambient">
      <div class="wrap">
        <h2 class="headline">不是又一个笔记应用。</h2>
        <p class="lead">笔记应用帮你把事情记下来。Oryne 让灵感一直活着。</p>
        <table class="compare">
          <caption class="vh">Oryne 与一般笔记应用的对比</caption>
          <thead>
            <tr><td></td><th scope="col">一般的笔记应用</th><th scope="col" class="is-oryne">Oryne</th></tr>
          </thead>
          <tbody>
            <tr><th scope="row">记下一个想法</th><td data-label="一般的笔记应用">打开 App，新建笔记，起个名字，选个文件夹。</td><td class="is-oryne" data-label="Oryne">按一下按钮，开口就说。</td></tr>
            <tr><th scope="row">保持有序</th><td data-label="一般的笔记应用">永远得靠你自己。</td><td class="is-oryne" data-label="Oryne">相关的灵感会自己汇聚。</td></tr>
            <tr><th scope="row">旧的想法</th><td data-label="一般的笔记应用">沉到看不见的地方。</td><td class="is-oryne" data-label="Oryne">每天回来一条。</td></tr>
            <tr><th scope="row">找东西</th><td data-label="一般的笔记应用">得猜对关键词。</td><td class="is-oryne" data-label="Oryne">用你自己的话提问，并看到出处。</td></tr>
            <tr><th scope="row">发展一个想法</th><td data-label="一般的笔记应用">直接在原稿上改。</td><td class="is-oryne" data-label="Oryne">延展它，原稿保持不变。</td></tr>
          </tbody>
        </table>
      </div>
    </section>

    <section class="section privacy" id="privacy" data-chapter="ambient">
      <div class="wrap">
        <p class="eyebrow">隐私</p>
        <h2 class="headline">你的灵感，只属于你。</h2>
        <p class="lead">Oryne 的设计让你的灵感无需离开你的设备，也无需创建任何账户。</p>
        <ul class="promises">
          <li>
            <svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="7" y="3" width="10" height="18" rx="2.5"/><path d="M11 18h2"/></svg>
            <h3>在你的设备上理解。</h3>
            <p>标题、主题、洋流与回答，都在你的 iPhone 或 iPad 上完成。</p>
          </li>
          <li>
            <svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M7 18h10a4 4 0 0 0 .6-7.95 5.5 5.5 0 0 0-10.7 1.2A3.5 3.5 0 0 0 7 18z"/></svg>
            <h3>通过你自己的 iCloud 同步。</h3>
            <p>你的海洋通过你的私人 iCloud 在设备之间同步。</p>
          </li>
          <li>
            <svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 12s3.5-6 9-6 9 6 9 6-3.5 6-9 6-9-6-9-6z"/><circle cx="12" cy="12" r="2.5"/><path d="M4 4l16 16"/></svg>
            <h3>没有广告，没有追踪，没有分析。</h3>
            <p>App 里没有，这个网站上也没有。</p>
          </li>
          <li>
            <svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 14V4M8 8l4-4 4 4"/><path d="M5 12v6.5A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5V12"/></svg>
            <h3>随时导出全部内容。</h3>
            <p>把整片海洋导出为 Markdown 文件，带着它去任何地方。</p>
          </li>
        </ul>
        <a class="more" href="privacy.html">阅读隐私政策<span aria-hidden="true">&nbsp;›</span></a>
      </div>
    </section>

    <section class="section more-section" id="more" data-chapter="ambient">
      <div class="wrap">
        <h2 class="headline">还有更多。</h2>
        <ul class="tiles">
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="4" width="7" height="7" rx="2"/><rect x="13" y="4" width="7" height="7" rx="2"/><rect x="4" y="13" width="16" height="7" rx="2"/></svg>主屏幕与锁定屏幕小组件</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="8" width="18" height="8" rx="4"/><circle cx="16.5" cy="12" r="2.2"/></svg>控制中心按钮</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/></svg>Siri 与快捷指令</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 15V3M8 7l4-4 4 4"/><path d="M7 10H6a1.5 1.5 0 0 0-1.5 1.5v8A1.5 1.5 0 0 0 6 21h12a1.5 1.5 0 0 0 1.5-1.5v-8A1.5 1.5 0 0 0 18 10h-1"/></svg>从任何 App 分享</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M10 14a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66L11.5 6.8"/><path d="M14 10a4 4 0 0 0-5.66 0l-3 3a4 4 0 0 0 5.66 5.66l1.5-1.46"/></svg>链接预览</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect x="2.5" y="5" width="13" height="15" rx="2"/><rect x="16" y="9" width="5.5" height="11" rx="1.5"/></svg>iPhone 与 iPad 同步</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.4 2.3 3.5 5.1 3.5 8.5s-1.1 6.2-3.5 8.5c-2.4-2.3-3.5-5.1-3.5-8.5s1.1-6.2 3.5-8.5z"/></svg><span lang="en">English</span> 与简体中文</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9h16M4 13h16M7 17h10"/></svg>宁静无障碍模式</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M9 6 5 10l4 4"/><path d="M5 10h9.5a4.5 4.5 0 0 1 0 9H12"/></svg>捕捉后可立即撤销</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M14 3.5H7.5A1.5 1.5 0 0 0 6 5v14a1.5 1.5 0 0 0 1.5 1.5h9A1.5 1.5 0 0 0 18 19V7.5z"/><path d="M14 3.5v4h4M9 12.5h6M9 16h4"/></svg>导出为 Markdown</li>
          <li><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M11 3.5l1.5 4 4 1.5-4 1.5-1.5 4-1.5-4-4-1.5 4-1.5z"/><path d="M18 14l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z"/></svg>在支持的机型上使用 Apple 智能</li>
        </ul>
      </div>
    </section>

    <section class="section faq" id="faq" data-chapter="deep">
      <div class="wrap wrap--narrow">
        <h2 class="headline">常见问题</h2>
        <details class="qa"><summary>Oryne 支持哪些设备？</summary><p>运行 iOS 18 或更高版本的 iPhone，以及运行 iPadOS 18 或更高版本的 iPad。由 Apple 智能生成的回答需要受支持的机型。</p></details>
        <details class="qa"><summary>需要注册账户吗？</summary><p>不需要。Oryne 通过你的 iCloud 同步，不用 iCloud 也能完整使用。</p></details>
        <details class="qa"><summary>我的灵感存在哪里？</summary><p>在你的设备上；如果你使用 iCloud，也会存在你的私人 iCloud 中。我们看不到它们。</p></details>
        <details class="qa"><summary>可以离线使用吗？</summary><p>可以。捕捉、洋流、再次浮现和提问都无需联网。链接预览需要联网；对于设备无法独立转写的语言，语音转写也需要联网。</p></details>
        <details class="qa"><summary>可以用中文使用 Oryne 吗？</summary><p>可以。Oryne 支持 <span lang="en">English</span> 与简体中文。在「设置」›「Oryne」›「语言」中选择。</p></details>
        <details class="qa"><summary>可以把灵感导出吗？</summary><p>可以。在 Oryne 的设置中选择「导出海洋」，所有内容都会保存为 Markdown 文件，每条洋流一个，并附带一份 JSON 备份。</p></details>
      </div>
    </section>

    <section class="section final" id="download" data-chapter="deep">
      <div class="wrap final__inner">
        <img class="final__icon" src="../assets/img/icon-192.webp" width="96" height="96" alt="">
        <h2 class="display">潜入海洋。</h2>
        <p class="lead">下一个灵感正在路上。准备好接住它。</p>
        <div class="final__actions">
          <a class="badge" href="https://apps.apple.com/app/id0000000000"><img src="../assets/img/badge-zh.svg" alt="在 App Store 下载" height="48" data-lang-asset></a>
        </div>
      </div>
      <div class="final__stage">
        <figure class="phone" data-anchor="final-phone">
          <img src="../assets/img/screens/capture.webp" width="640" height="1391" alt="Oryne，准备好接住下一个灵感。" loading="lazy" decoding="async">
        </figure>
      </div>
    </section>
  </main>

  <footer class="footer">
    <div class="wrap footer__inner">
      <a class="wordmark" href="#top">Oryne</a>
      <nav aria-label="法律与帮助"><a href="privacy.html">隐私</a><a href="support.html">支持</a></nav>
      <p class="footer__lang"><a href="../" hreflang="en" lang="en" data-lang-switch="en">English</a><span aria-current="true">简体中文</span></p>
      <p>© 2026 Oryne。Apple、iPhone、iPad 和 Siri 是 Apple Inc. 的商标。App Store 是 Apple Inc. 的服务标记。</p>
    </div>
  </footer>
</body>
</html>
```

- [ ] **Step 2: Write the Chinese privacy policy**

**File:** `website/zh/privacy.html`
```html
<!doctype html>
<html lang="zh-Hans" class="no-js" data-en="../privacy.html" data-zh="privacy.html">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>隐私政策 · Oryne</title>
  <meta name="description" content="Oryne 如何处理你的灵感：只在你的设备和你的私人 iCloud 中。">
  <meta name="theme-color" content="#050508">
  <meta name="color-scheme" content="dark">
  <link rel="alternate" hreflang="en" href="../privacy.html">
  <link rel="alternate" hreflang="zh-Hans" href="privacy.html">
  <link rel="alternate" hreflang="x-default" href="../privacy.html">
  <link rel="icon" href="../assets/img/favicon-32.png" sizes="32x32" type="image/png">
  <link rel="icon" href="../assets/img/favicon-16.png" sizes="16x16" type="image/png">
  <link rel="apple-touch-icon" href="../assets/img/apple-touch-icon.png">
  <link rel="stylesheet" href="../assets/css/site.css">
  <script>
    (function () {
      var root = document.documentElement;
      root.className = root.className.replace('no-js', 'js');
      var here = root.lang === 'zh-Hans' ? 'zh-Hans' : 'en';
      var want = null;
      try { want = window.localStorage.getItem('oryne.lang'); } catch (e) {}
      if (!want && here === 'en') {
        var first = ((navigator.languages && navigator.languages[0]) || navigator.language || '').toLowerCase();
        if (/^zh(?:-(?:hans|cn|sg)(?:-|$)|$)/.test(first)) want = 'zh-Hans';
      }
      if (want && want !== here) {
        var target = root.getAttribute(want === 'zh-Hans' ? 'data-zh' : 'data-en');
        if (target) window.location.replace(target + window.location.search + window.location.hash);
      }
    })();
  </script>
  <script type="module" src="../assets/js/site.js"></script>
</head>
<body data-page="long">
  <a class="skip" href="#main">跳到正文</a>

  <div class="ocean" aria-hidden="true">
    <canvas class="ocean__water"></canvas>
    <canvas class="ocean__field"></canvas>
    <div class="ocean__grain"></div>
  </div>

  <header class="bar">
    <div class="wrap bar__inner">
      <a class="wordmark" href="index.html">Oryne</a>
      <nav class="bar__nav" aria-label="页面导航">
        <a href="index.html#how">功能</a>
        <a href="index.html#use-cases">使用场景</a>
        <a href="index.html#privacy">隐私</a>
        <a href="index.html#faq">常见问题</a>
      </nav>
      <div class="bar__controls">
        <div class="lang"><a href="../privacy.html" hreflang="en" lang="en" data-lang-switch="en">EN</a><span aria-current="true">中文</span></div>
        <button class="icon-btn js-only" type="button" data-sound-toggle aria-pressed="false">
          <svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 9c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/><path d="M3 15c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/></svg>
          <span class="icon-btn__label">声音</span>
        </button>
        <a class="btn btn--primary btn--small" href="https://apps.apple.com/app/id0000000000">下载</a>
      </div>
    </div>
  </header>

  <main id="main">
    <article class="wrap prose">
      <p class="eyebrow">隐私</p>
      <h1 class="prose__title">隐私政策</h1>
      <p class="updated">最后更新：2026 年 9 月 18 日</p>
      <p class="summary">Oryne 把你的灵感保存在你的设备和你的私人 iCloud 中。我们没有任何接收你所捕捉内容的服务器，App 和本网站也都没有广告、追踪器或分析工具。</p>

      <h2 id="stores">Oryne 保存什么</h2>
      <p>你捕捉的一切：文字、语音录音及其文字记录、图片和链接，以及它们的标题和主题。这些内容存放在你设备上的 Oryne 数据库中，同一设备上的 Oryne 共享扩展和小组件也可以读取。</p>

      <h2 id="icloud">通过你的 iCloud 同步</h2>
      <p>如果你登录了 iCloud，Oryne 会通过你的私人 iCloud 数据库同步你的海洋，让 iPhone 和 iPad 保持一致。这些数据由 Apple 存储在你的 Apple 账户中，我们无法访问。如果你不使用 iCloud，你的海洋只会留在设备上。</p>

      <h2 id="on-device">理解在你的设备上完成</h2>
      <p>标题、主题、洋流、相关灵感、再次浮现，以及「提问」中的回答，都在你的设备上完成，使用 Apple 的框架，并在支持的机型上使用 Apple 智能。当前版本的 Oryne 不会把你的灵感发送给我们，也不会发送给任何 AI 服务。</p>
      <p>如果未来的版本加入了会把内容发送到设备之外的功能，本政策和该功能本身都会在它发布之前说明。</p>

      <h2 id="voice">语音</h2>
      <p>Oryne 使用 Apple 的语音识别来转写语音。当你的设备能够独立转写某种语言时，转写在设备上完成，音频不会离开设备。对于设备无法独立转写的语言，Apple 的语音识别服务可能会处理这段音频，适用 Apple 的隐私政策。</p>
      <p>一条语音有了文字记录后，Oryne 会在捕捉 30 天后删除它的录音：Oryne 保留你的文字，而不是文件。没有文字记录的语音会保留录音。</p>

      <h2 id="links">链接</h2>
      <p>保存链接时，Oryne 会像浏览器一样获取该页面，以显示它的标题、描述和图片。这个请求会发送到你保存的网站。</p>

      <h2 id="siri">Siri 与快捷指令</h2>
      <p>当你通过 Siri 或快捷指令捕捉时，Apple 会依据其隐私政策处理这个请求，然后把文字交给 Oryne。</p>

      <h2 id="permissions">权限</h2>
      <p>Oryne 会请求麦克风和语音识别权限来记录语音，并且只在你选择要捕捉的图片时访问照片。你可以随时在 iPhone 的「设置」中更改这些权限。</p>

      <h2 id="control">由你掌控</h2>
      <ul>
        <li><strong>导出。</strong>在 Oryne 的设置中选择「导出海洋」，所有内容都会保存为 Markdown 文件，并附带一份 JSON 备份。</li>
        <li><strong>删除。</strong>你可以在 App 中删除任何灵感。删除 Oryne 会移除它在该设备上的数据。</li>
        <li><strong>iCloud。</strong>同步到 iCloud 的数据，可以在 iPhone 的「设置」中你的 Apple 账户下管理。</li>
      </ul>

      <h2 id="website">本网站</h2>
      <p>本网站由静态页面组成，不使用 Cookie，也没有分析工具。它只会在你的浏览器中保存两项偏好：语言，以及是否开启声音。「在这里试试」演示从不离开本页。和所有网站一样，我们的网站托管服务商可能会保留标准的访问日志（例如 IP 地址和浏览器类型），用于提供和保护网站。</p>

      <h2 id="children">儿童</h2>
      <p>Oryne 不会收集任何人的个人信息，包括儿童。</p>

      <h2 id="changes">变更</h2>
      <p>如果本政策有所变更，我们会更新本页面及页首的日期。</p>

      <h2 id="contact">联系我们</h2>
      <p>关于隐私的问题，请发送邮件至 <a href="mailto:support@example.com">support@example.com</a>。</p>
    </article>
  </main>

  <footer class="footer">
    <div class="wrap footer__inner">
      <a class="wordmark" href="index.html">Oryne</a>
      <nav aria-label="法律与帮助"><a href="privacy.html" aria-current="page">隐私</a><a href="support.html">支持</a></nav>
      <p class="footer__lang"><a href="../privacy.html" hreflang="en" lang="en" data-lang-switch="en">English</a><span aria-current="true">简体中文</span></p>
      <p>© 2026 Oryne。Apple、iPhone、iPad 和 Siri 是 Apple Inc. 的商标。App Store 是 Apple Inc. 的服务标记。</p>
    </div>
  </footer>
</body>
</html>
```

- [ ] **Step 3: Write the Chinese support page**

**File:** `website/zh/support.html`
```html
<!doctype html>
<html lang="zh-Hans" class="no-js" data-en="../support.html" data-zh="support.html">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>支持 · Oryne</title>
  <meta name="description" content="关于 Oryne 的常见问题：快速捕捉、同步、导出等。">
  <meta name="theme-color" content="#050508">
  <meta name="color-scheme" content="dark">
  <link rel="alternate" hreflang="en" href="../support.html">
  <link rel="alternate" hreflang="zh-Hans" href="support.html">
  <link rel="alternate" hreflang="x-default" href="../support.html">
  <link rel="icon" href="../assets/img/favicon-32.png" sizes="32x32" type="image/png">
  <link rel="icon" href="../assets/img/favicon-16.png" sizes="16x16" type="image/png">
  <link rel="apple-touch-icon" href="../assets/img/apple-touch-icon.png">
  <link rel="stylesheet" href="../assets/css/site.css">
  <script>
    (function () {
      var root = document.documentElement;
      root.className = root.className.replace('no-js', 'js');
      var here = root.lang === 'zh-Hans' ? 'zh-Hans' : 'en';
      var want = null;
      try { want = window.localStorage.getItem('oryne.lang'); } catch (e) {}
      if (!want && here === 'en') {
        var first = ((navigator.languages && navigator.languages[0]) || navigator.language || '').toLowerCase();
        if (/^zh(?:-(?:hans|cn|sg)(?:-|$)|$)/.test(first)) want = 'zh-Hans';
      }
      if (want && want !== here) {
        var target = root.getAttribute(want === 'zh-Hans' ? 'data-zh' : 'data-en');
        if (target) window.location.replace(target + window.location.search + window.location.hash);
      }
    })();
  </script>
  <script type="module" src="../assets/js/site.js"></script>
</head>
<body data-page="long">
  <a class="skip" href="#main">跳到正文</a>

  <div class="ocean" aria-hidden="true">
    <canvas class="ocean__water"></canvas>
    <canvas class="ocean__field"></canvas>
    <div class="ocean__grain"></div>
  </div>

  <header class="bar">
    <div class="wrap bar__inner">
      <a class="wordmark" href="index.html">Oryne</a>
      <nav class="bar__nav" aria-label="页面导航">
        <a href="index.html#how">功能</a>
        <a href="index.html#use-cases">使用场景</a>
        <a href="index.html#privacy">隐私</a>
        <a href="index.html#faq">常见问题</a>
      </nav>
      <div class="bar__controls">
        <div class="lang"><a href="../support.html" hreflang="en" lang="en" data-lang-switch="en">EN</a><span aria-current="true">中文</span></div>
        <button class="icon-btn js-only" type="button" data-sound-toggle aria-pressed="false">
          <svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 9c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/><path d="M3 15c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/></svg>
          <span class="icon-btn__label">声音</span>
        </button>
        <a class="btn btn--primary btn--small" href="https://apps.apple.com/app/id0000000000">下载</a>
      </div>
    </div>
  </header>

  <main id="main">
    <article class="wrap prose">
      <p class="eyebrow">支持</p>
      <h1 class="prose__title">需要什么帮助？</h1>
      <p class="updated">常见问题的解答，以及联系我们的方式。</p>

      <h2 id="getting-started">开始使用</h2>
      <details class="qa" id="fast-capture"><summary>怎样捕捉得最快？</summary><p>在 iPhone 的「设置」中打开「操作按钮」，选择「快捷指令」，然后选择 Oryne 的「开始快速捕捉」。你也可以在控制中心添加 Oryne 按钮。无论哪种方式，Oryne 一打开就在聆听。</p></details>
      <details class="qa" id="context-capture"><summary>怎样把截图和一句语音一起留住？</summary><p>在「快捷指令」App 中新建一个快捷指令：先「截屏」，再运行 Oryne 的「开始情境捕捉」。你可以用操作按钮、辅助功能中的「轻点背面」运行它，在机型支持时也可以用相机控制。</p></details>
      <details class="qa" id="share"><summary>能从其他 App 捕捉吗？</summary><p>可以。在任意 App 中轻点「分享」，然后选择 Oryne。链接、图片和文字都会汇入你的海洋。</p></details>
      <details class="qa" id="siri"><summary>能用 Siri 吗？</summary><p>Oryne 的 Siri 短语目前只有英文：<span lang="en">“Hey Siri, add an inspiration to Oryne”</span>。在任何语言下，你都可以在快捷指令中使用 Oryne 的「记录灵感」操作，并用 Siri 运行这个快捷指令。</p></details>

      <h2 id="your-ocean">你的海洋</h2>
      <details class="qa" id="sync"><summary>Oryne 会在 iPhone 和 iPad 之间同步吗？</summary><p>会。只要两台设备登录了同一个 Apple 账户，就会通过 iCloud 同步。</p></details>
      <details class="qa" id="export"><summary>怎样导出全部内容？</summary><p>在 Oryne 的设置中选择「导出海洋」。你会得到 Markdown 文件（每条洋流一个）以及一份 JSON 备份。</p></details>
      <details class="qa" id="delete"><summary>怎样删除一条灵感？</summary><p>打开这条灵感，选择「删除」并确认。刚捕捉完时，也可以轻点「撤销」。</p></details>
      <details class="qa" id="examples"><summary>那些示例灵感是什么？</summary><p>Oryne 一开始会附带一条简短的介绍洋流。读完后，在 Oryne 的设置中选择「清空示例」即可。</p></details>

      <h2 id="comfort">舒适</h2>
      <details class="qa" id="motion"><summary>海洋动得太多了。</summary><p>在 Oryne 的设置中打开「宁静无障碍模式」，或在 iPhone 的「设置」›「辅助功能」›「动态效果」中打开「减弱动态效果」。海洋会静止下来。</p></details>
      <details class="qa" id="language"><summary>怎样把 Oryne 切换成中文？</summary><p>在「设置」›「Oryne」›「语言」中选择「简体中文」。</p></details>

      <h2 id="contact">联系我们</h2>
      <p>还需要帮助？请发送邮件至 <a href="mailto:support@example.com">support@example.com</a>。</p>
    </article>
  </main>

  <footer class="footer">
    <div class="wrap footer__inner">
      <a class="wordmark" href="index.html">Oryne</a>
      <nav aria-label="法律与帮助"><a href="privacy.html">隐私</a><a href="support.html" aria-current="page">支持</a></nav>
      <p class="footer__lang"><a href="../support.html" hreflang="en" lang="en" data-lang-switch="en">English</a><span aria-current="true">简体中文</span></p>
      <p>© 2026 Oryne。Apple、iPhone、iPad 和 Siri 是 Apple Inc. 的商标。App Store 是 Apple Inc. 的服务标记。</p>
    </div>
  </footer>
</body>
</html>
```

- [ ] **Step 4: Run the full checks, with parity**

Run: `python3 website/tools/check.py`
Expected: `0 error(s), 10 warning(s)` (the App Store placeholder on all six pages, the support email on the four Privacy and Support pages). Any "differ in" error means the Chinese markup drifted from the English: fix the Chinese page to match.

- [ ] **Step 5: Verify the Chinese pages and language routing in the browser**

1. Open `http://127.0.0.1:8765/zh/?debug`. Screenshot the hero, Currents (the four labels read 光与色, 产品灵感, 烹饪, 阅读), Resurfacing (the warm label reads 灵感总在洗澡时冒出来), the use-case tabs, and the comparison table, at desktop and at the `mobile` preset. Expected: Chinese headings wrap cleanly with no orphaned single characters on the hero line at 375 px; no horizontal scroll.
2. Routing: run `localStorage.removeItem('oryne.lang')`, then on `/zh/` click `EN`. Expected: lands on `/` and stays there on reload (`oryne.lang` is `en`). Click `中文`: lands on `/zh/`; reload `/`: redirected to `/zh/`.
3. Release demo in Chinese: the confirmation reads 已汇入海洋.

Reset with `localStorage.removeItem('oryne.lang')` and preset `desktop`.

- [ ] **Step 6: Checkpoint**

Run: `cd website && node --test tests/*.test.mjs && python3 tools/check.py`
Expected: tests pass; `0 error(s)`. No commit.

---

### Task 10: Social image, README, and the final pass

**Files:**
- Create: `website/assets/img/og.png`
- Create: `website/README.md`

**Interfaces:**
- Consumes: the running preview server (Task 7 Step 5), every page and module.
- Produces: the handoff to Malik.

- [ ] **Step 1: Render the social image from the hero**

With the preview server running:

```bash
SCRATCH=/private/tmp/claude-501/-Users-malik-Documents-inspire-ocean--claude-worktrees-oryne-official-website-08655b/fede2667-1588-47b9-a03b-c1e078c2f031/scratchpad
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --no-first-run \
  --disable-extensions --user-data-dir="$SCRATCH/chrome-og" --enable-unsafe-swiftshader \
  --hide-scrollbars --force-device-scale-factor=1 --window-size=1200,630 \
  --virtual-time-budget=4000 --screenshot=website/assets/img/og.png "http://127.0.0.1:8765/?motion=still"
sips -g pixelWidth -g pixelHeight website/assets/img/og.png | tail -2
ls -l website/assets/img/og.png
```

Expected: a 1200×630 PNG under 800 KB. Open it with the Read tool: the bar, the headline, the lead, the badge, and the ring's upper arc over dark water, no scrollbars. If the ring or water is missing (no WebGL in headless mode), the CSS water still reads as intended; note it and move on.

- [ ] **Step 2: Write the README**

**File:** `website/README.md`
````markdown
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
| `assets/js/choreo.js` | where each mote wants to be, per chapter and scroll progress (pure) |
| `assets/js/orbs.js` | mote sprites, after the app's `OrbTextures` |
| `assets/js/ocean.js` | the fixed water: WebGL body, ring, waves, motes, released thoughts |
| `assets/js/vignettes.js` | the four How it works visuals |
| `assets/js/sound.js` | surf on the breath, plus the app's chime |
| `assets/js/site.js` | page wiring: scroll, sound, language, tabs, release demo |
| `assets/css/site.css` | all styles; tokens from `OceanTheme` |

Sections declare `data-chapter` and anchors declare `data-anchor`; `site.js`
reads them and hands `choreo.js` plain numbers. Motion is atmosphere: every
fact the water shows is also written on the page, and Reduce Motion (or
`?motion=still`) stills all of it.

## Editing copy

- No em or en dashes: use a comma, colon, or period. `check.py` fails on them.
- Change English and Chinese together. Both trees must keep the same ids,
  `data-chapter` order, links, and assets; `check.py` compares them.
- Chinese follows `docs/localization-glossary.md`, reusing the app's catalog
  wording where the sentence exists.
- Every product claim must be true of the current Release build. The spec's
  claims ledger lists the code behind each one.

## How the assets were made

- Icons: `sips` from `Oryne/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.
- Chime: `python3 tools/generate_ocean_received.py --wav-out <tmp>.wav --out <tmp>.caf`,
  then `afconvert -f m4af -d aac -b 96000 <tmp>.wav assets/audio/ocean-received.m4a`.
  Never run the generator without `--out`: its default overwrites the app's sound.
- Badges: Apple's official black Download on the App Store badges (en-us and
  zh-cn) from Apple Marketing Tools, used unmodified.
- Screens: Debug build on the iPhone 17 Pro simulator, launched with
  `SIMCTL_CHILD_OCEAN_SCREENSHOT_SEED=1` and `SIMCTL_CHILD_OCEAN_START_TAB=…`, status bar
  set to 9:41, captured with `simctl io … screenshot`, resized to 640 px, WebP q82.
- Social image: a headless Chrome screenshot of the hero at 1200×630 with `?motion=still`.

## Before going live

1. Replace the App Store placeholder on all six pages:
   `grep -rl id0000000000 --include='*.html' . | xargs sed -i '' 's#https://apps.apple.com/app/id0000000000#<App Store URL>#g'`
2. Replace `support@example.com` on the Privacy and Support pages, in both languages.
3. Once the domain is known: make `og:image` absolute, add `<link rel="canonical">`,
   make the `hreflang` URLs absolute, add `sitemap.xml` with a `Sitemap:` line in
   `robots.txt`, and add `<meta name="apple-itunes-app" content="app-id=…">`.
4. If a feature that sends content off the device ships in Release, update the
   Privacy page first.
5. Run the checks: `0 error(s), 0 warning(s)`.
````

- [ ] **Step 3: Run every check**

```bash
cd website
node --test tests/*.test.mjs
python3 -m unittest discover -s tools -p 'test_*.py'
python3 tools/check.py
cd .. && git status --short
```

Expected: 31 Node tests pass; 11 Python tests pass; `0 error(s), 10 warning(s)` (placeholders only); `git status` lists `website/`, the spec, the plan, and the pre-existing `default.profraw`, and nothing under `Oryne/`, `Shared/`, `OceanWidgets/`, `ShareExtension/`, or `tools/`.

- [ ] **Step 4: Final browser pass**

In the browser pane, for `/` and `/zh/`, at the default desktop size and at the `mobile` preset:
1. Scroll top to bottom once, taking a screenshot at the hero, Currents, Ask, Use cases, and the final call to action.
2. Turn sound on, release one thought, turn sound off.
3. Load `?motion=still` and confirm nothing moves (Task 7 Step 9.1).
4. Read console errors: none.

Reset the viewport with preset `desktop` and stop the preview server (`preview_stop`).

- [ ] **Step 5: Hand off to Malik**

Send a short report:
- What was built, file by file (a few lines).
- Screenshots of the hero and one chapter in each language (SendUserFile).
- For his review: every Chinese line not taken from the app catalog (all of `zh/*.html` except the reused catalog lines listed in Task 9), and the Privacy page as a draft policy (not legal advice).
- Still needed: confirmation of the App Store URL (from Task 4 Step 4, if found), a support email, and later the host and domain (README go-live checklist).
- Nothing is committed. Offer to commit `website/` plus the spec and plan as one change, listing exactly those paths and leaving `default.profraw` out.

---

## Execution notes (2026-09-19)

Executed inline. Everything above ran as written except the following, each verified afterwards:

- **Preview server.** macOS privacy blocks the in-app preview runner from reading `~/Documents`, so the preview served a synced copy of `website/` from the session scratchpad. The temporary `.claude/launch.json` has since been removed.
- **Branch screen.** `detail.webp` shows the branch composer (Question, Concept, Research, Project) instead of a finished branch, which reads better in the cropped panel; alt text updated in both languages.
- **Choreography retuned after the visual pass.** Currents gather by 40% of the section and name themselves below each group (`labelDy`); resurfacing and Ask play earlier; motes behind the hero headline (`hero-copy` anchor) and over text columns (`data-calm` quiet zones) dim, and no label lands on text; on phones, currents gather along the phone's edges without names. Three tests added (34 total).
- **Release demo.** A released thought drops out of the card's lower edge (it used to start behind the glass) and is drawn brighter than the ambient motes.
- **Layout fixes.** Balanced headline wrapping; Chinese headlines break only at punctuation or `<wbr>`, with a smaller display size on phones; tile words wrap in one span; the final ring circles the visible stage and the phone keeps its proportions; the release field no longer widens the Capture column on phones; the stacked comparison table's row headers use the full width.
- **Sound.** The deep layer dropped from 0.14 to 0.10 so the swells read: measured crests near −23 dBFS and troughs near −35 dBFS, in step with the visual breath; off fades to silence in about 1.2 s.
- **Social image.** Chrome's one-shot `--screenshot` hung on its virtual-time budget; the image was captured through the DevTools protocol instead, with the bar, lead, and Listen button hidden.
- **Expectations corrected.** Task 7 Step 4 and Task 8 Step 4 also listed `zh/` links as missing until Task 9 (the plan missed them). The in-app browser tool cannot trigger a form's implicit Enter submission; a real Enter was verified in headless Chrome.

## Revision after visual review (2026-09-19)

Malik's review of the first build: the English font read "too plain and too bold, not premium", and the small bubbles were trypophobic (密集恐惧症). Keep only large circles, lit like a sunset lamp with a halo at the edge; big blurred glows are welcome in the background; nothing small. He chose Instrument Serif, self-hosted. The spec's Revision 1 records the decisions; the work:

- **Type.** Instrument Serif (regular, italic) and Inter (variable 300 to 600) self-hosted in `assets/fonts/` with `OFL.txt`, Latin `unicode-range` only. Headlines, card, panel, FAQ, and policy titles in the serif at 400; English headlines carry italic `<em>` accents (7 of them); text at 300, labels and buttons at 500, nothing at 600. Chinese falls through to Songti SC headlines and PingFang text. Grain lowered to 0.3.
- **Lights.** `orbs.js` gave way to `lamps.js`: in focus a flat disc with a soft edge and a halo glowing around it, out of focus a gaussian pool with no edge or ring. The cast shrank to five: four currents as large pools that gather around the Currents phone, and one warm sun that rises behind the Resurfacing widgets. No labels, links, stars, trails, or source dots remain. The portal is a cached sunset-lamp sprite (lilac to dusk, glowing edge); four huge shader glows per chapter sit in the water.
- **Release demo.** The words sink inside a large soft light (Instrument Serif italic, Songti in Chinese), let go at about 4 s, then two wide flat rings open on the water. It now drops from the card's center.
- **Vignettes** redrawn with the same large lights and faded edges; the canvas bleeds to the card edges.
- **Tests.** `choreo.test.mjs` rewritten for the new cast: nothing visible under `MIN_LAMP` (60 pt), currents gather and stay out of focus, the sun rises behind the widgets, handovers stay continuous (33 JS tests, 11 checker tests, all passing).
- **Social image** re-rendered from the stilled hero with the new type and portal.
- **Verified** in headless Chrome: desktop and 375 pt screenshots in both languages, the release demo in both languages, still mode, no horizontal overflow on all six pages, 60 fps at about 0.1 ms per frame while scrolling the landing page, no console errors, and `check.py` at 0 errors (10 placeholder warnings for the App Store URL and support email).

## Phone mockup (2026-09-20)

Malik pointed at the Capture phone: "Use the real phone mock-up here." Given the
choice between a hand-drawn CSS frame, Apple's official product image, or a file
of his own, he chose the CSS frame. All five phones (and the two small panel
phones) now render as an iPhone in CSS: a graphite titanium rail with light along
its edges, the black glass border, the screen inset, and the buttons in their real
places, all scaling from `--w`. No downloads, no device artwork, about 2 KB of CSS.
The social image was rendered again, since the hero phone changed.

## Bar and phone, second pass (2026-09-20)

Three notes from Malik, pointing at the page:

- **One language button.** The `EN 中文` pair became a single capsule: a globe
  and the language it switches to, labelled for screen readers in the page's own
  language. `data-lang-switch` stays, so `site.js` still remembers the choice and
  `check.py` still excludes it from parity. The footer keeps both languages as links.
- **Wordmark.** "Too plain, and the word gap doesn't show the branding." It is now
  a lockup: the icon's portal as inline SVG (ring lit on its lower right, wave
  across its lower third) beside `Oryne` in Instrument Serif at 25px with normal
  tracking, 21px in the footer.
- **Phone in Black.** Checked Apple's current iPhone Pro pages: the finishes are
  Burgundy, Glacier, Silver, and Black, and Black is a matte body whose rail only
  catches light on its chamfers. The frame was retuned to that: near-black rail,
  a thicker black glass border, and dark buttons with a lit outer edge.

Caught while verifying: headless Chrome was serving pages from its own cache, so a
screenshot showed old markup with new CSS. The CDP driver now sends
`Network.setCacheDisabled`, and the screenshots were taken again.

## Supplied frame and the real policy (2026-09-20)

- **Phone frame.** Two CSS frames (silver, then black) both had the buttons and
  the rail subtly wrong, so Malik supplied a silver iPhone mockup PNG and asked
  for that. It is now `assets/img/phone-frame.webp` (Pillow, quality 93, alpha
  kept: 222 KB to 27 KB), with the screenshot placed in its opening. The opening
  measured 804x1748 px inside a 900x1840 image, an aspect of 0.4600 against the
  screens' 0.4601, so nothing is cropped: insets are 5.333% at the sides and 2.5%
  top and bottom. All fourteen phone figures (seven per language) carry
  `phone__screen` and `phone__frame`; the CSS rail, its gradients, and the button
  pseudo-elements are gone.
- **Privacy page.** Rewritten from the published policy at
  malikzhang.com/oryne/privacy: its effective date (June 28, 2026), its summary,
  and its sections on storage, on-device AI, microphone and photos, selling and
  advertising, deletion, changes, and contact, in the site's own prose layout, in
  both languages. Three sections the published policy does not cover were kept
  because they are true here: links Oryne fetches, recordings deleted 30 days
  after transcription, and what this website itself stores (two preferences, no
  cookies, no analytics).
- **Microphone wording.** The published policy says voice is transcribed on the
  device. `DriftTranscriber.swift:81` and `LiveTranscriber.swift:471` only set
  `requiresOnDeviceRecognition` when the recognizer supports it, so the page keeps
  the narrower claim: on device whenever it can, and Apple's speech recognition
  under Apple's policy when it cannot. Malik to confirm which wording he wants.
- **Support email.** `malikdes9gn@gmail.com`, taken from the published Privacy and
  Support pages, replaces the placeholder on all four pages that had it.

## Frame fit, support content, and deploy (2026-09-21)

- **Frame fit.** Malik saw the screen spill past the mockup at the corners. The
  opening's corners measure a 130 px radius in the 900 px image (14.4% of the frame's
  width), while the screenshot had a small elliptical `border-radius: 5.5%`, so the page
  showed through the opening's corners. The screen now bleeds a third of a percent past
  the opening on every side (under the frame's opaque bezel) with a radius of 11% of
  `--w`, tighter than the opening's, so the corners are always filled. Checked at 4x on
  all four corners.
- **Support page.** Integrated from malikzhang.com/oryne/support in both languages: the
  capture basics, how thoughts get organized, offline behavior, why a link may not be
  summarized, editing and deleting, a privacy summary linking to the policy, and the
  contact note, merged with the existing setup answers (Fast Capture, Context Capture,
  share, Siri, sync, export, examples, motion, language). New ids match in both trees.
- **Deploy.** The Vercel CLI was already signed in as malik1942. `vercel link` created a
  new `oryne` project (checked first: `malikzhang.com` is attached to `malik-portfolio`,
  so nothing live was touched), then `vercel deploy --prod`. The deployment's file list
  was checked before going public: only site files, no `.env.local`. With Malik's OK,
  Vercel Authentication was switched off for this project only. Live at
  https://oryne-zeta.vercel.app, all pages and assets 200, no console errors.

## Lines out, link in (2026-09-21)

- **No hairlines.** Malik: the thin wave lines are "not elegant, not coherent with the
  overall vibes." Removed every one: the three swells across the hero, the two inside
  the portal, the release demo's ripple rings, and the Capture card's ripples. Card
  waterlines are now soft radial bands of light. Sight and sound still share the breath
  clock through the portal's lift and the lamps.
- **App Store link.** Confirmed by Malik: https://apps.apple.com/app/id6778995892 on all
  six pages. `check.py` now reports 0 warnings.
- Redeployed to https://oryne-zeta.vercel.app.
- **Custom domain.** `oryne.malikzhang.com` added to the `oryne` project and verified. The
  apex's nameservers are the registrar's, so the `oryne` record must be added there; Vercel
  recommends `A 76.76.21.21`.

## Two motion refinements (2026-09-21)

Asked for my own read of the site, I named two soft spots and Malik said do both.

- **Currents gather.** The four pools now tuck in behind the phone (0.42 phone widths
  from its center instead of 0.55) and brighten to 0.9 instead of 0.65, so "related ideas
  drift together" registers without reading the copy. They stay out of focus.
- **Release ending.** After the light settles it drifts off to one side and keeps sinking,
  softening as it goes, and lets go over the last four seconds (gone at 10 s instead of 9).
  Still mode keeps its single frame.
- Redeployed to https://oryne-zeta.vercel.app.

## Microphone wording (2026-09-21)

Malik chose to match the published policy: the microphone paragraph now says the audio is
transcribed on the device, in both languages, with the narrower on-device-when-supported
clause removed. The 30-day recording deletion sentence stays.

## Release into open water (2026-09-21)

Malik: the released light should appear in the empty right part of the page. On wide
screens the thought now leaves the card's right edge and settles in the open water
between the card and the viewport edge, below the phone if the phone is in the way, then
drifts right as it lets go. On phones it still drops out of the card's lower edge.
`release()` takes an optional `to` and `drift`.

## Parked (2026-09-21)

- Chinese copy review: Malik will revise `zh/*.html` himself later. Everything else on the
  site is signed off and live.

## Outage and fix (2026-09-21, evening)

After the worktree was removed, the `oryne` Vercel project turned out to be connected to
the GitHub repo with Root Directory `.`, and a git deployment from `main` had replaced the
CLI deployment: the site 404ed and the repository root, including the app's Swift source,
was served as static files for a few minutes. Fix: Root Directory set to `website`, build
and install commands cleared, and a fresh production deployment created from `main`.
Verified: all pages 200, `/Oryne/...`, `/PHILOSOPHY.md`, `/project.yml`, and `/tests/...`
404. From here on, pushes to `main` deploy the site.

## Fast Capture chapter (2026-09-21)

Malik asked for the Action Button and Fast Capture on the site. A new chapter after
Capture (`#fast-capture`, water chapter `fast`) in both languages: the Action Button setup
path from `FastCapturePreferences.setupSteps`, the Control Center control, voice first or
typing first, the three-second review before auto-release (`scheduleAutoRelease`), and the
widget. Screen captured from the seeded simulator via `oryne://capture/whisper`.
`choreo.js` gained the `fast` chapter (pools pulled back, amber glow); its tests iterate
`CHAPTERS` so they cover it.

## Fast Capture card (2026-09-21)

A fifth How it works card, second in the row: "One press, no app." with a vignette of a
light switching on in an instant and breathing while it listens. The grid is five across
from 1024px (tighter padding, 24px card titles), two columns below that with the odd card
spanning the row.

## Widget screenshot (2026-09-21)

The Fast Capture chapter's visual is now a pair of small phones: the listening session and
the Home Screen with the medium Quick Capture widget (Thought and Whisper buttons), added
in the simulator through the widget gallery. `.chapter__visual--pair` sizes the pair down
to 42vw each so both fit a phone screen. The widget point in the copy now names the two
buttons and the Lock Screen widget (`accessoryCircular`).
