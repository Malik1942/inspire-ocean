# Oryne Launch Film Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A ~56 s, 2560×1440/60 fps launch film for Oryne, captured fresh from the iPhone 17 Pro simulator and composed entirely in HyperFrames on the website's own ocean, with the website's ocean ambience and the app's chime.

**Architecture:** Simulator takes are recorded, converted to a constant 60 fps and measured, and the measurements go into one data file (`takes/cuts.json`). A small generator (`tools/film/assemble.mjs`) turns that file and the measured phone frame into HyperFrames compositions: 5 cards, 4 beats, an end card and a root `index.html`. The root draws the website's ocean with the site's lamp, breath and water code, driven by a pure function of film time (`film/src/film-ocean.js`, bundled to a classic script). An offline port of the site's sound engine (`audio/ocean-bed.mjs`) renders the ambience on the same breath clock.

**Tech Stack:** Xcode + `xcrun simctl`, the iOS Simulator control tool, ffmpeg 8.1, Python 3 (numpy, Pillow), Node 26 (`node:test`), esbuild (via `npx`), HyperFrames CLI 0.8.62 (GSAP 3.14.2).

**Spec:** `docs/films/2026-09-22-launch-film.md` (same branch). Read it first.

## Global Constraints

- Canvas **2560×1440, 60 fps**; target length **~56 s (window 45–60 s)**. Cards run 2.4 s (not ~2 s) so the words read for ~0.9 s; the total must still land in 45–60 s.
- Surface: iOS app, **iPhone 17 Pro simulator** (`0EBF66EE-3E7D-48F9-9D44-E7B1A58DACF1`), **English**, Debug build of inspire-ocean @ **f4f698e**.
- **App code, seed and assets are not modified.**
- Words (exact; `*…*` = italic accent, sentence case):
  - Opening: "Catch ideas before they *drift away.*"
  - Cards: "Catch it *in seconds.*" · "Watch it *find its place.*" · "*Get it back.*" · "Ask what it *all means.*"
  - End: Oryne mark → "Oryne" → "Now on the App Store" → official black badge `website/assets/img/badge-en.svg`, unmodified. No price.
- Scene 1 typed line: **"The room feels slower when the light turns warm."** (Task 4 may reword it only if it fails to join "light and color", and must record the change in the audit).
- Type: **Instrument Serif 400** for display, with italic accents in `#d9e1f0`; **Inter 300–500** for small text. Foam text `rgba(255,255,255,0.92)`, abyss `#050508`.
- Avoid: small dots/motes (every light radius ≥ 60 pt), all caps, pixel fonts, cross-dissolves, side pushes, music, idle camera drift.
- Sound: website ocean ambience + the app's `OceanReceived` chime on the release frame. **No music.** Never run `generate_ocean_received.py` with its default `--out` (that writes into the app bundle).
- Ask answer engine: **on-device only**. Never pass `ANTHROPIC_API_KEY`.
- Every readable payoff is held **≥ 2 s**. Every reveal is preceded by a visible touch cue (appear → press → ripple).
- Working folder `~/Desktop/oryne-launch/` is its own local git repo. Commits there and on `am/oryne-launch-film` are authored by **Malik Zhang <auditore1942@gmail.com>, solo, no co-author trailers**.
- Engineering gates that never bend: measure before trimming, splice only whole animations, verify frames, gap audit.

## File Structure

Working folder `~/Desktop/oryne-launch/` (call it `$L`):

| Path | Responsibility |
|---|---|
| `tools/rec.sh` | Start/stop a simulator recording safely |
| `tools/conform.sh` | Raw `.mov` → constant 60 fps H.264 `.mp4` |
| `tools/scan.py` (+ `test_scan.py`) | Frame-change spans and centroids for a take |
| `tools/measure_frame.py` (+ `test_measure_frame.py`) | Screen cutout + corner radius of a device frame PNG |
| `tools/ink_centre.py` (+ `test_ink_centre.py`) | Bounding box/centre of bright ink in a still |
| `tools/grain.py` | Seeded grain tile PNG |
| `tools/film/templates.mjs` | HTML for card / beat / end / index compositions |
| `tools/film/assemble.mjs` (+ `test-assemble.mjs`) | cuts.json + frame.json → slots, release time, all composition files |
| `tools/film/stills.mjs` | Pull verification stills from a render |
| `takes/raw/*.mov`, `takes/*.mp4`, `takes/scans/*.json`, `takes/cuts.json` | Footage, measurements, the one timing source |
| `film/` | HyperFrames project (`hyperframes init`) |
| `film/src/{breath,lamps,noise,choreo}.js` | Verbatim copies of the site modules @ f4f698e |
| `film/src/water.js` | Site `ocean.js` @ f4f698e with 3 exact edits (exports + preserveDrawingBuffer) |
| `film/src/film-ocean.js` (+ `test-film-ocean.mjs`) | Pure film-time ocean: chapters, rings, release light, renderer |
| `film/assets/…` | fonts, phone frame, frame.json, badge, grain, takes, audio, ocean bundle |
| `audio/ocean-bed.mjs` (+ `test-ocean-bed.mjs`) | Offline, seeded port of the site's surf |
| `renders/` | Renders, stills, audit |

Repo branch `am/oryne-launch-film` (worktree `/Users/malik/Documents/inspire-ocean/.claude/worktrees/oryne-launch-film`, call it `$R`): the spec, this plan, the final audit.

---

### Task 1: Workspace and take scanner

**Files:**
- Create: `$L/.gitignore`, `$L/tools/rec.sh`, `$L/tools/conform.sh`, `$L/tools/scan.py`, `$L/tools/test_scan.py`

**Interfaces:**
- Produces: `scan(path, width=180, threshold=1.5, gap=6) -> dict` with keys `fps`, `frames`, `spans` (list of `{start, end, start_frame, end_frame, peak, centroid}`; `centroid` is `[x, y]` as 0..1 fractions of the frame, or `None`), `diffs`. CLI: `python3 tools/scan.py <video> [--out file.json] [--threshold f]`.
- Produces: `tools/rec.sh start <NAME>` / `tools/rec.sh stop` writing `takes/raw/<NAME>.mov`; `tools/conform.sh <in.mov> <out.mp4>`.

- [ ] **Step 1: Create the workspace repo**

```bash
mkdir -p ~/Desktop/oryne-launch/{tools/film,takes/raw,takes/scans,audio,renders}
cd ~/Desktop/oryne-launch
git init -q
git config user.name "Malik Zhang"
git config user.email "auditore1942@gmail.com"
cat > .gitignore <<'EOF'
takes/raw/
takes/*.mp4
takes/*.png
renders/
build/
audio/*.wav
film/assets/takes/
film/assets/audio/
film/renders/
node_modules/
__pycache__/
.DS_Store
EOF
```

- [ ] **Step 2: Write the failing scanner test**

`$L/tools/test_scan.py`:

```python
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from scan import scan  # noqa: E402


def make(path, *args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *args, "-c:v", "libx264", "-pix_fmt", "yuv420p", path], check=True)


class ScanTest(unittest.TestCase):
    def test_finds_the_cut(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "cut.mp4")
            make(p, "-f", "lavfi", "-i", "color=c=black:s=180x390:r=60:d=1",
                 "-f", "lavfi", "-i", "color=c=white:s=180x390:r=60:d=1",
                 "-filter_complex", "[0][1]concat=n=2:v=1:a=0")
            r = scan(p)
            self.assertEqual(r["fps"], 60)
            self.assertEqual(len(r["spans"]), 1)
            self.assertAlmostEqual(r["spans"][0]["start"], 1.0, delta=1 / 60 + 1e-6)

    def test_still_has_no_spans(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "still.mp4")
            make(p, "-f", "lavfi", "-i", "color=c=black:s=180x390:r=60:d=2")
            self.assertEqual(scan(p)["spans"], [])

    def test_centroid_points_at_the_change(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "corner.mp4")
            # A white box appears in the top-left quarter at t=1s.
            make(p, "-f", "lavfi", "-i", "color=c=black:s=180x390:r=60:d=2",
                 "-vf", "drawbox=x=0:y=0:w=60:h=100:color=white:t=fill:enable='gte(t,1)'")
            span = scan(p)["spans"][0]
            self.assertLess(span["centroid"][0], 0.5)
            self.assertLess(span["centroid"][1], 0.5)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run it and watch it fail**

Run: `cd ~/Desktop/oryne-launch && python3 tools/test_scan.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'scan'`.

- [ ] **Step 4: Write the scanner**

`$L/tools/scan.py`:

```python
#!/usr/bin/env python3
"""Where a take actually moves: frame-to-frame change spans, measured, never assumed.

Trims, cue times and camera keyframes come from these spans (product-film law:
input latency makes planned timings fiction).
"""
import argparse
import json
import subprocess

import numpy as np


def probe(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height,r_frame_rate", "-of", "json", path],
        capture_output=True, text=True, check=True)
    s = json.loads(out.stdout)["streams"][0]
    num, den = map(int, s["r_frame_rate"].split("/"))
    return s["width"], s["height"], num / den


def frames(path, width):
    w0, h0, _ = probe(path)
    height = max(2, round(h0 * width / w0 / 2) * 2)
    proc = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-i", path, "-vf", f"scale={width}:{height},format=gray",
         "-f", "rawvideo", "-"], stdout=subprocess.PIPE)
    size = width * height
    while True:
        buf = proc.stdout.read(size)
        if len(buf) < size:
            break
        yield np.frombuffer(buf, np.uint8).reshape(height, width).astype(np.int16)
    proc.wait()


def scan(path, width=180, threshold=1.5, gap=6):
    _, _, fps = probe(path)
    diffs, cents, prev = [], [], None
    for f in frames(path, width):
        if prev is None:
            diffs.append(0.0)
            cents.append(None)
        else:
            d = np.abs(f - prev)
            diffs.append(float(d.mean()))
            ys, xs = np.nonzero(d > 24)
            cents.append([round(float(xs.mean()) / f.shape[1], 3), round(float(ys.mean()) / f.shape[0], 3)]
                         if len(xs) else None)
        prev = f
    raw, start, last = [], None, None
    for i, m in enumerate(diffs):
        if m > threshold:
            if start is None:
                start = i
            last = i
        elif start is not None and i - last > gap:
            raw.append((start, last))
            start = None
    if start is not None:
        raw.append((start, last))
    spans = []
    for a, b in raw:
        k = a + int(np.argmax(diffs[a:b + 1]))
        spans.append({"start": round(a / fps, 3), "end": round(b / fps, 3), "start_frame": a,
                      "end_frame": b, "peak": round(max(diffs[a:b + 1]), 2), "centroid": cents[k]})
    return {"fps": round(fps, 3), "frames": len(diffs), "spans": spans, "diffs": [round(d, 3) for d in diffs]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--out")
    ap.add_argument("--threshold", type=float, default=1.5)
    a = ap.parse_args()
    r = scan(a.video, threshold=a.threshold)
    if a.out:
        with open(a.out, "w") as fh:
            json.dump(r, fh, indent=1)
    for s in r["spans"]:
        print(f"{s['start']:8.3f}–{s['end']:8.3f}s  peak {s['peak']:6.2f}  at {s['centroid']}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Run the test and watch it pass**

Run: `cd ~/Desktop/oryne-launch && python3 tools/test_scan.py`
Expected: `Ran 3 tests … OK`.

- [ ] **Step 6: Write the recording and conform helpers**

`$L/tools/rec.sh`:

```bash
#!/bin/bash
# Start or stop a simulator recording without truncating it.
#   tools/rec.sh start A   → takes/raw/A.mov
#   tools/rec.sh stop      → SIGINT to the real recorder, then wait for it to finalize
set -euo pipefail
DIR="$HOME/Desktop/oryne-launch/takes/raw"
pause() { python3 -c "import time; time.sleep($1)"; }
case "${1:-}" in
  start)
    mkdir -p "$DIR"
    nohup xcrun simctl io booted recordVideo --codec h264 --force "$DIR/$2.mov" >"$DIR/$2.log" 2>&1 &
    pause 1.5
    echo "recording $DIR/$2.mov"
    ;;
  stop)
    PID=$(pgrep -f "simctl io booted recordVideo" | head -1)
    [ -n "$PID" ] || { echo "no recorder running" >&2; exit 1; }
    kill -INT "$PID"
    while kill -0 "$PID" 2>/dev/null; do pause 0.2; done
    ls -la "$DIR"/*.mov
    ;;
  *) echo "usage: rec.sh start NAME | rec.sh stop" >&2; exit 2 ;;
esac
```

`$L/tools/conform.sh`:

```bash
#!/bin/bash
# Constant 60 fps before anything else touches a take (product-film law: conform VFR at ingest).
set -euo pipefail
ffmpeg -v error -y -i "$1" -vf "fps=60" -c:v libx264 -preset slow -crf 12 -pix_fmt yuv420p -an "$2"
ffprobe -v error -show_entries stream=width,height,r_frame_rate:format=duration -of compact "$2"
```

```bash
chmod +x ~/Desktop/oryne-launch/tools/*.sh
```

- [ ] **Step 7: Commit**

```bash
cd ~/Desktop/oryne-launch && git add .gitignore tools/rec.sh tools/conform.sh tools/scan.py tools/test_scan.py
git commit -qm "Tools: take scanner, recorder and conform helpers"
```

---

### Task 2: Frame, ink and grain tools

**Files:**
- Create: `$L/tools/measure_frame.py`, `$L/tools/test_measure_frame.py`, `$L/tools/ink_centre.py`, `$L/tools/test_ink_centre.py`, `$L/tools/grain.py`

**Interfaces:**
- Produces: `measure(path) -> {"w", "h", "screen": {"x","y","w","h"}, "radius"}` (frame pixels). CLI: `python3 tools/measure_frame.py <frame.png> > film/assets/frame.json`.
- Produces: `ink(path, threshold=40) -> {"bbox": [x0,y0,x1,y1], "centre": [cx,cy], "offset": [dx,dy]}` where offset is the centre minus the image centre. CLI prints JSON.
- Produces: `python3 tools/grain.py <out.png>`, a 256×256 seeded grain tile (grey noise, alpha 14).

- [ ] **Step 1: Write the failing tests**

`$L/tools/test_measure_frame.py`:

```python
import os
import sys
import tempfile
import unittest

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
from measure_frame import measure  # noqa: E402


class MeasureFrameTest(unittest.TestCase):
    def test_measures_cutout_and_radius(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "frame.png")
            img = Image.new("RGBA", (400, 800), (0, 0, 0, 0))
            draw = ImageDraw.Draw(img)
            draw.rounded_rectangle((0, 0, 399, 799), radius=90, fill=(30, 30, 30, 255))          # device body
            draw.rounded_rectangle((40, 50, 359, 749), radius=60, fill=(0, 0, 0, 0))            # screen hole
            draw.rounded_rectangle((160, 62, 239, 84), radius=11, fill=(0, 0, 0, 255))         # island inside it
            img.save(p)
            m = measure(p)
            self.assertEqual((m["w"], m["h"]), (400, 800))
            self.assertEqual(m["screen"], {"x": 40, "y": 50, "w": 320, "h": 700})
            self.assertAlmostEqual(m["radius"], 60, delta=2)


if __name__ == "__main__":
    unittest.main()
```

`$L/tools/test_ink_centre.py`:

```python
import os
import sys
import tempfile
import unittest

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
from ink_centre import ink  # noqa: E402


class InkTest(unittest.TestCase):
    def test_reports_offset_from_centre(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "card.png")
            img = Image.new("RGB", (2560, 1440), (5, 5, 8))
            ImageDraw.Draw(img).rectangle((1000, 600, 1600, 900), fill=(240, 240, 240))
            img.save(p)
            r = ink(p)
            self.assertEqual(r["bbox"], [1000, 600, 1600, 900])
            self.assertEqual(r["offset"], [20.0, 30.0])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them and watch them fail**

Run: `cd ~/Desktop/oryne-launch && python3 tools/test_measure_frame.py; python3 tools/test_ink_centre.py`
Expected: both FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Write the tools**

`$L/tools/measure_frame.py`:

```python
#!/usr/bin/env python3
"""A device frame's screen cutout and corner radius, measured from its alpha.

Transparent pixels connected to the border are outside the device; the other
transparent pixels are the screen. The corner radius comes from the area the
rounded corner removes from the cutout's top-left square: r²(1 − π/4).
The clip and the frame must use this one radius (product-film law 16).
"""
import json
import math
import sys
from collections import deque

import numpy as np
from PIL import Image


def measure(path):
    alpha = np.array(Image.open(path).convert("RGBA"))[:, :, 3]
    h, w = alpha.shape
    clear = alpha < 8
    outside = np.zeros_like(clear)
    queue = deque()
    for x in range(w):
        for y in (0, h - 1):
            if clear[y, x] and not outside[y, x]:
                outside[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if clear[y, x] and not outside[y, x]:
                outside[y, x] = True
                queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= ny < h and 0 <= nx < w and clear[ny, nx] and not outside[ny, nx]:
                outside[ny, nx] = True
                queue.append((ny, nx))
    hole = clear & ~outside
    ys, xs = np.nonzero(hole)
    x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    box = max(4, int(0.2 * (x1 - x0)))
    missing = int((~hole[y0:y0 + box, x0:x0 + box]).sum())
    radius = math.sqrt(missing / (1 - math.pi / 4))
    return {"w": w, "h": h, "screen": {"x": x0, "y": y0, "w": x1 - x0 + 1, "h": y1 - y0 + 1},
            "radius": round(radius, 1)}


if __name__ == "__main__":
    print(json.dumps(measure(sys.argv[1]), indent=1))
```

`$L/tools/ink_centre.py`:

```python
#!/usr/bin/env python3
"""Where a card's ink sits. Run it on stills from the ink pass (ocean hidden), so
only type is bright. A card is centred only when its ink is centred."""
import json
import sys

import numpy as np
from PIL import Image


def ink(path, threshold=40):
    g = np.array(Image.open(path).convert("L")).astype(np.int16)
    h, w = g.shape
    ys, xs = np.nonzero(g > threshold)
    x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    return {"bbox": [x0, y0, x1, y1], "centre": [cx, cy], "offset": [cx - w / 2, cy - h / 2]}


if __name__ == "__main__":
    print(json.dumps(ink(sys.argv[1])))
```

`$L/tools/grain.py`:

```python
#!/usr/bin/env python3
"""The site's grain tile, seeded so every render gets the same grain (alpha 14, as site ocean.js)."""
import sys

import numpy as np
from PIL import Image

rng = np.random.default_rng(0x0CEA)
v = rng.integers(0, 256, size=(256, 256), dtype=np.uint8)
rgba = np.dstack([v, v, v, np.full_like(v, 14)])
Image.fromarray(rgba, "RGBA").save(sys.argv[1])
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `cd ~/Desktop/oryne-launch && python3 tools/test_measure_frame.py && python3 tools/test_ink_centre.py`
Expected: both `OK`.

- [ ] **Step 5: Commit**

```bash
cd ~/Desktop/oryne-launch && git add tools/measure_frame.py tools/test_measure_frame.py tools/ink_centre.py tools/test_ink_centre.py tools/grain.py
git commit -qm "Tools: frame cutout, ink centre and grain"
```

---

### Task 3: Capture rig (build, simulator, widgets)

No code; the deliverable is a simulator whose state has been verified from screenshots.

**Files:**
- Create: `$L/takes/rig-home.png`, `$L/takes/rig-ocean.png` (evidence, not committed)

**Interfaces:**
- Produces: the app `com.inspireocean.app` installed on the booted iPhone 17 Pro (`0EBF66EE-3E7D-48F9-9D44-E7B1A58DACF1`), the 9:41 status bar, and the Home Screen holding **Quick Capture (medium)** and **Resurfacing (medium)**.
- Produces: the launch commands every take uses:
  - Seeded: `SIMCTL_CHILD_OCEAN_SCREENSHOT_SEED=1 xcrun simctl launch --terminate-running-process booted com.inspireocean.app -AppleLanguages "(en)" -AppleLocale en_US`
  - Seeded, starting on Ask: prefix the same command with `SIMCTL_CHILD_OCEAN_START_TAB=ask`.

- [ ] **Step 1: Build Debug from the pinned commit (the branch worktree is at f4f698e plus docs only)**

```bash
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/oryne-launch-film
git log -1 --format=%h -- Oryne OceanWidgets Shared project.yml   # expect f4f698e or older
xcodegen generate
xcodebuild -scheme Oryne -configuration Debug \
  -destination 'platform=iOS Simulator,id=0EBF66EE-3E7D-48F9-9D44-E7B1A58DACF1' \
  -derivedDataPath ~/Desktop/oryne-launch/build build | tail -3
```
Expected: `** BUILD SUCCEEDED **`. Then `git status --short`: if `xcodegen generate` modified tracked files, restore exactly those paths with `git checkout -- <path>` (no app change may be committed on this branch).

- [ ] **Step 2: Boot, clean status bar, install**

```bash
xcrun simctl boot 0EBF66EE-3E7D-48F9-9D44-E7B1A58DACF1 || true
open -a Simulator
xcrun simctl status_bar booted override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install booted ~/Desktop/oryne-launch/build/Build/Products/Debug-iphonesimulator/Oryne.app
```

Then call the simulator control tool with `attach`, so Malik can watch.

- [ ] **Step 3: Seeded launch and Ocean check**

Run the seeded launch command from Interfaces. Wait for the Ocean to settle, then:

```bash
xcrun simctl io booted screenshot ~/Desktop/oryne-launch/takes/rig-ocean.png
```
Look at the screenshot (Read tool). Expected: the Ocean field in English with the "light and color" current and no onboarding sheet. Confirm with control `inspect` using marker `light and color`: an element with id `oceanCurrent.light and color` exists. If onboarding shows, stop and report (the seed should have skipped it).

- [ ] **Step 4: Place both widgets on the Home Screen**

Drive the simulator with the control tool, one action per call, and `inspect` before every tap:
1. `button HOME`.
2. Long-press an empty area of the Home Screen (`tap`, `duration: 1.2`) until the icons jiggle.
3. Tap the **Edit** control at the top left, then **Add Widget**.
4. Tap the gallery search field and type `Oryne`, then tap the Oryne result.
5. Swipe to the **Quick Capture** medium size (the one with separate Thought and Whisper buttons) and tap **Add Widget**.
6. Repeat 2–5 for **Resurfacing**, medium size.
7. Drag Resurfacing below Quick Capture on the first page if it landed elsewhere, then tap **Done**.

```bash
xcrun simctl io booted screenshot ~/Desktop/oryne-launch/takes/rig-home.png
```
Look at it. Expected: both widgets are on page 1, and Resurfacing shows a thought title, not "The Ocean is still". If it shows "The Ocean is still", run the seeded launch, press `HOME`, and screenshot again. If it still shows no thought after two tries, record that as a capture gap and use the spec fallback for scene 3 (the in-app Resurfacing banner). If widgets can't be placed at all, use the spec fallback for scene 1 (`xcrun simctl openurl booted oryne://capture/thought`, with a tap cue on the Oryne icon), and report it.

- [ ] **Step 5: Record the rig in the workspace log**

```bash
cd ~/Desktop/oryne-launch && cat >> takes/RIG.md <<'EOF'
# Capture rig
- Device: iPhone 17 Pro sim 0EBF66EE-3E7D-48F9-9D44-E7B1A58DACF1, status bar 9:41
- Build: Debug @ f4f698e, derived data ~/Desktop/oryne-launch/build
- Widgets: Quick Capture (medium) + Resurfacing (medium), Home Screen page 1
EOF
git add takes/RIG.md && git commit -qm "Capture rig ready"
```
(If Step 4 used a fallback, add a line naming it.)

---

### Task 4: Takes A, B, C

**Files:**
- Create: `$L/takes/raw/{A,B,C}.mov`, `$L/takes/{A,B,C}.mp4`, `$L/takes/TAKES.md`

**Interfaces:**
- Consumes: the Task 3 launch commands, `tools/rec.sh`, `tools/conform.sh`.
- Produces: `takes/A.mp4` (scenes 1 and 2, one launch), `takes/B.mp4` (scene 3), `takes/C.mp4` (scene 4), all at 60 fps CFR. `TAKES.md` records the final typed line, the final Ask question and the Resurfacing pick.

Simulator-driving rules for every take: `inspect` for a control's frame before tapping it and tap the frame centre; type in chunks of 2–3 words, one `text` call each, so typing shows word by word; start each take on a still screen and hold 1.5 s before the first tap; hold ≥ 3 s on the final state before stopping.

- [ ] **Step 1: Take A, catch and gather**

1. Run the seeded launch. When the Ocean settles, press `button HOME`.
2. `tools/rec.sh start A`
3. Tap the Quick Capture widget's **Thought** button.
4. When the Fast Capture sheet is up, type `The room ` · `feels slower ` · `when the light ` · `turns warm.`
5. Hold 1.2 s, then tap **Release**.
6. Hold 2.5 s. If the app is not on the Ocean tab, tap the **Ocean** tab.
7. `inspect` with marker `light and color`, then tap that current's frame centre.
8. Hold 4 s on the sheet, then `tools/rec.sh stop`.

- [ ] **Step 2: First-take check, the line joined "light and color"**

```bash
cd ~/Desktop/oryne-launch && tools/conform.sh takes/raw/A.mov takes/A.mp4
ffmpeg -v error -y -sseof -1 -i takes/A.mp4 -frames:v 1 takes/A-end.png
```
Read `takes/A-end.png`. Expected: the "light and color" sheet lists "The room feels slower when the light turns warm." alongside Sunset gradient study, Golden hour on the walk home, Warm to cool, not a filter, and Desk at 6pm.
If the line isn't there: `inspect` all `oceanCurrent.*` to see where it went, then redo Step 1 with the next line, trying at most these two in order:
- "Warm light at dusk makes the room feel slower."
- "Sunset light turns the whole room warm and slow."

If all three fail, stop and report. Never fake the grouping.

- [ ] **Step 3: Take B, get it back**

1. Run the seeded launch (fresh store, the seed's own pick). Press `button HOME` and confirm with a screenshot that Resurfacing shows a title.
2. `tools/rec.sh start B`, then hold 1.5 s.
3. Tap the Resurfacing widget.
4. Hold 4 s on the opened thought (its age and nearby thoughts should be visible).
5. `tools/rec.sh stop`, then `tools/conform.sh takes/raw/B.mov takes/B.mp4`.

Check: read the last frame (same `-sseof -1` command, `takes/B-end.png`). Expected: a thought detail showing an age such as "12 days ago" and a "Nearby thoughts" list. Write the pick's title into `TAKES.md`. If the pick reads badly on its own, say so there. Don't change the seed.

- [ ] **Step 4: Take C, ask**

1. Run the seeded launch starting on Ask.
2. `tools/rec.sh start C`, then hold 1.5 s.
3. If **Synthesis** isn't selected, tap it.
4. Tap the input field and type `What keeps ` · `pulling me ` · `toward warm light?`
5. Tap send.
6. Every 2 s, take `xcrun simctl io booted screenshot /tmp/c-poll.png` and compare it with the previous one using `cmp`. When two in a row are identical, hold 3 s more and run `tools/rec.sh stop`.
7. `tools/conform.sh takes/raw/C.mov takes/C.mp4`

Check: read the last frame (`takes/C-end.png`). Expected: a composed answer with its sources, not "nothing matches". If it says nothing matches, retake with these questions, in order: "What do my notes about light have in common?" and then "What keeps coming back about warm light and color?". If all three fail, stop and report.

- [ ] **Step 5: Log the takes and commit**

```bash
cd ~/Desktop/oryne-launch && for t in A B C; do echo "$t: $(ffprobe -v error -show_entries format=duration -of csv=p=0 takes/$t.mp4)s"; done
```
Write `takes/TAKES.md` with the three lines above plus the final typed line, the final question, the Resurfacing pick title, and any retakes with their reasons.

```bash
git add takes/TAKES.md && git commit -qm "Takes A, B, C recorded and conformed"
```

---

### Task 5: Measure takes and author `cuts.json`

**Files:**
- Create: `$L/takes/scans/{A,B,C}.json`, `$L/takes/cuts.json`

**Interfaces:**
- Consumes: `tools/scan.py`, `takes/{A,B,C}.mp4`.
- Produces: `takes/cuts.json`, the only timing source for the film. Its shape is below; `tools/film/assemble.mjs` (Task 9) validates it.

```json
{
  "beats": {
    "catch":     { "take": "A", "segments": [{ "in": 0.0, "out": 0.0 }], "release": 0.0,
                   "cues":   [{ "t": 0.0, "x": 0.0, "y": 0.0, "what": "Thought button" }],
                   "camera": [{ "t": 0, "s": 1, "x": 0.5, "y": 0.5 }] },
    "currents":  { "take": "A", "segments": [], "cues": [], "camera": [] },
    "resurface": { "take": "B", "segments": [], "cues": [], "camera": [] },
    "ask":       { "take": "C", "segments": [], "cues": [], "camera": [] }
  }
}
```

Field rules (every number comes from a scan span or a still, never from a plan):
- `segments` (amendment 2026-09-22, Malik): a beat is 1–3 pieces of its take, played back to back. Capture-tool latency left long static pauses inside takes; a pause may be removed ONLY where the screen is completely still across the cut: the low-threshold scan's diffs must be < 0.05 for the 3 frames either side of both cut points, and the frames at `out` of one segment and `in` of the next must be pixel-identical except for the text caret (check with a still pair). Never cut inside an animation, typing burst or readable hold. Each removed pause keeps ≥ 0.4 s of stillness on both sides of the cut. The first segment's `in` and the last segment's `out` follow the `in`/`out` rules below. Beat duration = sum of segment lengths.
- `in` / `out` are seconds in the take. `in = first cue's absolute tap time − 0.9`. `out = last payoff settle time + 2.4` (settle time is the `end` of the last span, when the screen stops changing). The `catch` beat ends where the Ocean is back after the release, and the `currents` beat starts there (same take A: `currents.in = catch.out`).
- All beat-local times (`cues[].t`, `camera[].t`, `release`) count in the EDITED beat (segments concatenated), not in the take. Convert: local = (take time − segment.in) + sum of earlier segment lengths.
- `cues[].t` is beat-local: the absolute time of the first frame the screen responds to the tap (that span's `start`), minus `in`. `cues[].x` / `y` are fractions of the **screen**, measured from the control's own geometry on a still from just before the tap. Don't use the change centroid, which marks where pixels redrew. `what` names the control.
- `catch.release` is beat-local: the span `start` right after the Release tap, which is when the app's release animation begins.
- `camera[]` is a list of keys `{t, s, x, y, move}`. `t` is when the camera arrives (beat-local), `s` is the scale (1–1.8), and `x`/`y` are the screen fraction placed at the canvas centre. `move` is the length of the move, default 0.6 s, starting at `t − move`. Key 0 is the state at `t: 0` and has no `move`. A move may not start before the previous key's `t`. The camera moves only to show something:
  - **catch:** wide (`s 1, 0.5, 0.5`) → punch `s 1.4` on the Thought button, arriving at cue.t − 0.1 → `s 1.25` centred on the text field while the line is typed, so the whole line is readable → hold through the Release tap → `s 1.0` wide, arriving at release + 0.4 (so the rings on the water show).
  - **currents:** wide → `s 1.35` on the current's orb, arriving at cue.t − 0.1 → `s 1.2` centred on the sheet's list, arriving when the sheet settles.
  - **resurface:** wide → `s 1.35` on the widget, arriving at cue.t − 0.1 → `s 1.2` centred on the age line and the first nearby thoughts.
  - **ask:** `s 1.2` on the input from `t 0` → hold through typing and the send tap → `s 1.15` centred on the answer body, arriving when the answer starts composing.

- [ ] **Step 1: Scan every take**

```bash
cd ~/Desktop/oryne-launch && for t in A B C; do echo "== $t"; python3 tools/scan.py takes/$t.mp4 --out takes/scans/$t.json; done
```
Expected: a span list per take. In take A that means the widget tap, the sheet opening, 4 typing bursts, the release, the Ocean returning, the orb tap and the sheet.

- [ ] **Step 2: Pull a still before every tap and at every settle, and read them**

For each candidate tap span, extract the frame 3 frames before its start and the frame at its end:

```bash
f() { ffmpeg -v error -y -ss "$2" -i "takes/$1.mp4" -frames:v 1 "takes/$1-$2.png"; }
# example: f A 3.117
```
Read each still. Match every span to what happened (tap, typing burst, animation, settle). Measure each control's centre as a screen fraction: `x = px / width`, `y = py / height` on the conformed take (the take *is* the screen).

- [ ] **Step 3: Write `takes/cuts.json`**

Fill every field by the rules above. Every value needs a source: the span or still it came from.

- [ ] **Step 4: Check the payoff holds**

For each beat, the time from its last settle to the end of its last segment must be ≥ 2.0 s (waived for `catch`, which flows straight into the scene-2 card while the release rings open on the water). The typed line in catch must be fully readable for ≥ 1.0 s before the Release tap: check the still at `release − 1.0`.

- [ ] **Step 5: Commit**

```bash
git add takes/scans takes/cuts.json && git commit -qm "Measured cuts for all four beats"
```

---

### Task 6: HyperFrames project and assets

**Files:**
- Create: `$L/film/` (via `hyperframes init`), `$L/film/assets/{fonts/*,phone-frame.png,frame.json,badge-en.svg,grain.png,takes/*.mp4}`
- Create: `$L/film/src/{breath,lamps,noise,choreo,water}.js`

**Interfaces:**
- Produces: `film/assets/frame.json` (the `measure()` shape from Task 2). Site modules exporting `breathAt`, `BREATH_BASE`, `wave` (breath.js); `drawLamp` (lamps.js); `createLamps`, `layout`, `glowsFor`, `energyFor`, `ringRadius`, `smoothstep`, `clamp`, `mix` (choreo.js); and `createWater`, `drawRing`, `wanderOffset`, `breathing` (water.js).

- [ ] **Step 1: Scaffold**

```bash
cd ~/Desktop/oryne-launch
HYPERFRAMES_SKIP_SKILLS=1 npx -y hyperframes@0.8.62 init film --example blank --non-interactive
mkdir -p film/src film/assets/{fonts,takes,audio}
```

- [ ] **Step 2: Copy the site's modules and assets from the pinned commit**

```bash
cd ~/Desktop/oryne-launch
REPO=/Users/malik/Documents/inspire-ocean
for f in breath lamps noise choreo; do git -C $REPO show f4f698e:website/assets/js/$f.js > film/src/$f.js; done
git -C $REPO show f4f698e:website/assets/js/ocean.js > film/src/water.js
for f in instrument-serif.woff2 instrument-serif-italic.woff2 inter.woff2 OFL.txt; do git -C $REPO show f4f698e:website/assets/fonts/$f > film/assets/fonts/$f; done
git -C $REPO show f4f698e:website/assets/img/badge-en.svg > film/assets/badge-en.svg
git -C $REPO show f4f698e:website/assets/img/phone-frame.webp > /tmp/phone-frame.webp
sips -s format png /tmp/phone-frame.webp --out film/assets/phone-frame.png >/dev/null
python3 tools/grain.py film/assets/grain.png
cp takes/A.mp4 takes/B.mp4 takes/C.mp4 film/assets/takes/
```

- [ ] **Step 3: Apply the three exact edits to `water.js`**

```bash
cd ~/Desktop/oryne-launch/film/src
sed -i '' \
  -e 's/^function createWater(canvas) {/export function createWater(canvas) {/' \
  -e 's/^function drawRing(ctx, ring, level, t) {/export function drawRing(ctx, ring, level, t) {/' \
  -e "s/premultipliedAlpha: false, powerPreference: 'low-power',/premultipliedAlpha: false, powerPreference: 'high-performance', preserveDrawingBuffer: true,/" \
  water.js
grep -c "^export function createWater\|^export function drawRing\|preserveDrawingBuffer: true" water.js
```
Expected: `3`. (`preserveDrawingBuffer` keeps the WebGL water in the captured frame.)

- [ ] **Step 4: Measure the phone frame**

```bash
cd ~/Desktop/oryne-launch && python3 tools/measure_frame.py film/assets/phone-frame.png | tee film/assets/frame.json
```
Expected: `w 900, h 1840`, a screen box inside it, and a radius. Sanity check: overlay the box on the PNG and look at it:

```bash
python3 - <<'EOF'
import json
from PIL import Image, ImageDraw
m = json.load(open("film/assets/frame.json")); s = m["screen"]
im = Image.open("film/assets/phone-frame.png").convert("RGBA")
ImageDraw.Draw(im).rounded_rectangle((s["x"], s["y"], s["x"]+s["w"]-1, s["y"]+s["h"]-1), radius=m["radius"], outline=(255,0,0,255), width=3)
im.save("/tmp/frame-check.png")
EOF
```
Read `/tmp/frame-check.png`. Expected: the red outline follows the screen edge, corners included.

- [ ] **Step 5: Commit**

```bash
cd ~/Desktop/oryne-launch && git add film/package.json film/hyperframes.json film/meta.json film/CLAUDE.md film/AGENTS.md film/src film/assets/fonts film/assets/badge-en.svg film/assets/phone-frame.png film/assets/frame.json film/assets/grain.png
git commit -qm "Film project: site modules, fonts, frame, badge, grain"
```

---

### Task 7: The ocean in film time

**Files:**
- Create: `$L/film/src/film-ocean.js`, `$L/film/src/test-film-ocean.mjs`
- Create (build output): `$L/film/assets/ocean.bundle.js`

**Interfaces:**
- Consumes: the Task 6 site modules.
- Produces (global `OryneOcean` in the bundle): `createFilmOcean({ water, field, slots, release }) -> { draw(t) }`. `slots` is `[{ id, kind, start, dur }]` (kind is `opening|card|beat|end`), and `release` is `{ t, text }`. Also exported for tests: `VIEW`, `DPR`, `PHONE_H`, `BLEND`, `phoneRect`, `chapterSegments`, `stateAt`, `ringAlphaAt`, `releaseLight`, `openRings`.

- [ ] **Step 1: Write the failing tests**

`$L/film/src/test-film-ocean.mjs`:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { createLamps, layout, MIN_LAMP } from './choreo.js';
import {
  VIEW, BLEND, phoneRect, chapterSegments, stateAt, ringAlphaAt, releaseLight, openRings,
} from './film-ocean.js';

// A fixture timeline (the real one comes from assemble.mjs); these tests only need consistent slots.
const SLOTS = [
  { id: 'opening', kind: 'opening', start: 0, dur: 3.5 },
  { id: 'card-catch', kind: 'card', start: 3.5, dur: 2 },
  { id: 'catch', kind: 'beat', start: 5.5, dur: 11 },
  { id: 'card-currents', kind: 'card', start: 16.5, dur: 2 },
  { id: 'currents', kind: 'beat', start: 18.5, dur: 9 },
  { id: 'card-resurface', kind: 'card', start: 27.5, dur: 2 },
  { id: 'resurface', kind: 'beat', start: 29.5, dur: 9 },
  { id: 'card-ask', kind: 'card', start: 38.5, dur: 2 },
  { id: 'ask', kind: 'beat', start: 40.5, dur: 11 },
  { id: 'end', kind: 'end', start: 51.5, dur: 5 },
];
const TOTAL = 56.5;
const RELEASE = { t: 14.2, text: 'The room feels slower when the light turns warm.' };

function view() {
  const phone = phoneRect();
  return { ...VIEW, anchors: { 'currents-phone': phone, 'resurface-widget': { x: phone.x, y: phone.y + 0.12 * phone.h, w: phone.w, h: 0.2 * phone.h } }, calm: [] };
}

test('a card and its beat share one chapter', () => {
  const segs = chapterSegments(SLOTS);
  assert.deepEqual(segs.map((s) => s.chapter), ['top', 'fast', 'currents', 'resurface', 'ask', 'top']);
  assert.equal(segs[2].beatStart, 18.5);
  assert.equal(segs[2].end, 27.5);
});

test('progress runs across the beat only', () => {
  const segs = chapterSegments(SLOTS);
  assert.equal(stateAt(17, segs).progress, 0);
  assert.equal(stateAt(23, segs).progress, (23 - 18.5) / 9);
});

test('lights never jump between frames', () => {
  const segs = chapterSegments(SLOTS);
  const lamps = createLamps();
  let prev = null;
  for (let t = 0; t <= TOTAL; t += 1 / 60) {
    const now = layout(stateAt(t, segs), lamps, view());
    if (prev) {
      now.forEach((g, i) => {
        assert.ok(Math.abs(g.alpha - prev[i].alpha) < 0.05, `alpha jump at t=${t.toFixed(3)} lamp ${i}`);
        if (g.alpha < 0.05 && prev[i].alpha < 0.05) return;   // an unseen light may move freely
        assert.ok(Math.abs(g.x - prev[i].x) < 12, `x jump at t=${t.toFixed(3)} lamp ${i}`);
        assert.ok(Math.abs(g.y - prev[i].y) < 12, `y jump at t=${t.toFixed(3)} lamp ${i}`);
      });
    }
    prev = now;
  }
});

test('no small lights', () => {
  const segs = chapterSegments(SLOTS);
  const lamps = createLamps();
  for (let t = 0; t <= TOTAL; t += 0.25) {
    for (const g of layout(stateAt(t, segs), lamps, view())) {
      if (g.alpha > 0.02) assert.ok(g.r >= MIN_LAMP, `r=${g.r} at t=${t}`);
    }
  }
});

test('the portal glows fully on the opening and the end, faintly behind a beat', () => {
  assert.equal(ringAlphaAt(1, SLOTS), 1);
  assert.equal(ringAlphaAt(54, SLOTS), 1);
  assert.equal(ringAlphaAt(10, SLOTS), 0.35);
  assert.equal(ringAlphaAt(4.5, SLOTS), 0.55);
});

test('the released thought sinks, its words let go, then two rings open', () => {
  assert.equal(releaseLight(RELEASE.t - 0.01, RELEASE), null);
  const early = releaseLight(RELEASE.t + 0.5, RELEASE);
  assert.ok(early.wordsAlpha > 0.9);
  assert.equal(releaseLight(RELEASE.t + 4.2, RELEASE).wordsAlpha, 0);
  assert.equal(releaseLight(RELEASE.t + 10.01, RELEASE), null);
  assert.equal(openRings(RELEASE.t + 0.05, RELEASE).length, 0);
  assert.equal(openRings(RELEASE.t + 0.6, RELEASE).length, 2);
  for (const r of openRings(RELEASE.t + 0.6, RELEASE)) assert.ok(r.r >= 60);
});

test('handover blend is BLEND seconds', () => {
  const segs = chapterSegments(SLOTS);
  // 'fast' covers 3.5–16.5 (card-catch + catch), so it hands over to 'currents' from 16.5 − BLEND.
  assert.equal(stateAt(16.5 - BLEND - 0.01, segs).next, undefined);
  assert.equal(stateAt(16.5 - BLEND + 0.01, segs).next, 'currents');
});
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `cd ~/Desktop/oryne-launch/film && node --test src/test-film-ocean.mjs`
Expected: FAIL with `Cannot find module … film-ocean.js`.

- [ ] **Step 3: Write `film-ocean.js`**

`$L/film/src/film-ocean.js`:

```js
// The website's Ocean, driven by film time. Everything is a pure function of
// t: the site's lamps, glows, water and portal (copied from the site @ f4f698e),
// the chapter each moment belongs to, and the released thought. No springs, no
// clock, no Math.random, so HyperFrames can render any frame on its own.

import { breathAt } from './breath.js';
import { drawLamp } from './lamps.js';
import { createLamps, layout, glowsFor, energyFor, ringRadius, smoothstep, clamp, mix } from './choreo.js';
import { createWater, drawRing, wanderOffset, breathing } from './water.js';

/** The film is drawn in points, like a 1280×720 page at 2x, so the lights keep the site's scale. */
export const VIEW = { vw: 1280, vh: 720 };
export const DPR = 2;
/** The phone stands 575 pt (1150 px) tall, centred. */
export const PHONE_H = 575;
const FRAME_ASPECT = 900 / 1840;
/** Seconds a chapter takes to hand its lights to the next. The site eases lights with
 *  springs; 1.6 s keeps the fastest handover (the warm sun sinking after Resurface)
 *  under ~8 pt a frame at 60 fps. */
export const BLEND = 1.6;
const RING_FADE = 0.8;

const CHAPTER = {
  opening: 'top', 'card-catch': 'fast', catch: 'fast', 'card-currents': 'currents', currents: 'currents',
  'card-resurface': 'resurface', resurface: 'resurface', 'card-ask': 'ask', ask: 'ask', end: 'top',
};
const RING_ALPHA = { opening: 1, end: 1, card: 0.55, beat: 0.35 };

/** Where the released thought's light travels, and where the rings open, in points. */
const RELEASE_PATH = { from: { x: 520, y: 470 }, to: { x: 330, y: 560 }, drift: -1, seed: 0.42, rings: { x: 640, y: 660 } };

const easeInOut = (p) => (p < 0.5 ? 2 * p * p : 1 - (-2 * p + 2) ** 2 / 2);
const easeOut = (p) => 1 - (1 - p) ** 3;

export function phoneRect() {
  const h = PHONE_H;
  const w = h * FRAME_ASPECT;
  return { x: (VIEW.vw - w) / 2, y: (VIEW.vh - h) / 2, w, h };
}

/** Consecutive slots that share a chapter become one segment; a beat inside it sets the progress window. */
export function chapterSegments(slots) {
  const segs = [];
  for (const s of slots) {
    const chapter = CHAPTER[s.id];
    const last = segs[segs.length - 1];
    const seg = last && last.chapter === chapter ? last : null;
    const target = seg ?? { chapter, start: s.start, end: s.start + s.dur, beatStart: null, beatEnd: null };
    target.end = s.start + s.dur;
    if (s.kind === 'beat') {
      target.beatStart = s.start;
      target.beatEnd = s.start + s.dur;
    }
    if (!seg) segs.push(target);
  }
  return segs;
}

/** The choreography state at t, in the shape site choreo.js expects. */
export function stateAt(t, segments) {
  let i = segments.findIndex((s) => t < s.end);
  if (i < 0) i = segments.length - 1;
  const seg = segments[i];
  const progress = seg.beatStart == null ? 0 : clamp((t - seg.beatStart) / (seg.beatEnd - seg.beatStart), 0, 1);
  const next = segments[i + 1];
  if (next && t > seg.end - BLEND) {
    return { chapter: seg.chapter, progress, next: next.chapter, blend: smoothstep(seg.end - BLEND, seg.end, t) };
  }
  return { chapter: seg.chapter, progress };
}

const ringOf = (s) => RING_ALPHA[s.id] ?? RING_ALPHA[s.kind];

/** The portal behind the phone: full on the opening and the end, faint behind a beat. */
export function ringAlphaAt(t, slots) {
  let i = slots.findIndex((s) => t < s.start + s.dur);
  if (i < 0) i = slots.length - 1;
  const s = slots[i];
  const next = slots[i + 1];
  if (!next) return ringOf(s);
  const end = s.start + s.dur;
  return mix(ringOf(s), ringOf(next), smoothstep(end - RING_FADE, end, t));
}

/** The released thought (site ocean.js drawReleased, in film time): sinks 2.4 s, drifts, lets go by 10 s. */
export function releaseLight(t, release) {
  const age = t - release.t;
  if (age < 0 || age > 10) return null;
  const p = Math.min(1, age / 2.4);
  const e = easeInOut(p);
  const { from, to, drift, seed } = RELEASE_PATH;
  let x = from.x + (to.x - from.x) * e;
  let y = from.y + (to.y - from.y) * e;
  const settled = Math.max(0, age - 2.4);
  if (p >= 1) {
    const [wx, wy] = wanderOffset(seed, t, 3);
    x += wx + settled * 9 * drift;
    y += wy + settled * 4;
  }
  return {
    x, y,
    alpha: 0.55 * clamp((10 - age) / 4.5, 0, 1),
    soft: Math.min(1, 0.35 + 0.45 * e + settled * 0.06),
    wordsAlpha: clamp(4.1 - age, 0, 1),
  };
}

/** Two wide, flat rings opening on the water with the chime. Never smaller than 80 pt. */
export function openRings(t, release) {
  const out = [];
  for (const delay of [0.1, 0.45]) {
    const a = t - release.t - delay;
    if (a < 0 || a > 3.2) continue;
    const p = a / 3.2;
    out.push({ x: RELEASE_PATH.rings.x, y: RELEASE_PATH.rings.y, r: mix(80, 460, easeOut(p)), alpha: 0.4 * (1 - p) ** 1.5 });
  }
  return out;
}

export function createFilmOcean({ water, field, slots, release }) {
  const gl = createWater(water);
  gl?.resize(VIEW.vw, VIEW.vh, 1);
  field.width = VIEW.vw * DPR;
  field.height = VIEW.vh * DPR;
  const ctx = field.getContext('2d');
  const lamps = createLamps();
  const segments = chapterSegments(slots);
  const phone = phoneRect();
  const view = {
    ...VIEW,
    anchors: {
      'currents-phone': phone,
      'resurface-widget': { x: phone.x, y: phone.y + 0.12 * phone.h, w: phone.w, h: 0.2 * phone.h },
    },
    calm: [],
  };
  const portal = { x: VIEW.vw / 2, y: VIEW.vh / 2, R: ringRadius(phone) };

  function draw(t) {
    const state = stateAt(t, segments);
    const level = breathAt(t).level;
    const energy = energyFor(state);
    gl?.draw(t, 0, level, { w: VIEW.vw, h: VIEW.vh }, glowsFor(state, view));

    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    ctx.clearRect(0, 0, VIEW.vw, VIEW.vh);
    drawRing(ctx, { ...portal, alpha: ringAlphaAt(t, slots) }, level, t);

    const targets = layout(state, lamps, view);
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    const order = targets.map((_, i) => i).sort((a, b) => targets[b].soft - targets[a].soft);
    for (const i of order) {
      const g = targets[i];
      const l = lamps[i];
      if (g.alpha < 0.004) continue;
      const [wx, wy] = wanderOffset(l.seed, t, (3 + 3 * (1 - g.soft)) * energy);
      drawLamp(ctx, {
        x: g.x + wx, y: g.y + wy, r: g.r, scale: breathing(l.seed, t, 0.02 * energy),
        alpha: g.alpha, soft: g.soft, palette: l.palette, warmth: g.warmth,
      });
    }
    const light = releaseLight(t, release);
    if (light) drawLamp(ctx, { x: light.x, y: light.y, r: 64, alpha: light.alpha, soft: light.soft });
    for (const r of openRings(t, release)) {
      ctx.save();
      ctx.strokeStyle = `rgba(160,180,226,${r.alpha.toFixed(3)})`;
      ctx.lineWidth = 2;
      ctx.shadowColor = 'rgba(160,180,226,0.8)';
      ctx.shadowBlur = 10;
      ctx.beginPath();
      ctx.ellipse(r.x, r.y, r.r, r.r * 0.2, 0, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    }
    ctx.restore();

    if (light && light.wordsAlpha > 0) {
      ctx.font = 'italic 400 21px "Instrument Serif", Georgia, serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      const half = ctx.measureText(release.text).width / 2;
      const x = Math.min(VIEW.vw - 16 - half, Math.max(16 + half, light.x));
      ctx.fillStyle = `rgba(255,255,255,${(0.92 * light.wordsAlpha).toFixed(3)})`;
      ctx.fillText(release.text, x, light.y);
    }
  }

  return { draw };
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `cd ~/Desktop/oryne-launch/film && node --test src/test-film-ocean.mjs`
Expected: `# pass 7`, `# fail 0`. If "lights never jump" fails, the fix belongs in `stateAt`/`chapterSegments`, never in the threshold.

- [ ] **Step 5: Bundle to a classic script**

```bash
cd ~/Desktop/oryne-launch/film && npx -y esbuild@0.25.0 src/film-ocean.js --bundle --format=iife --global-name=OryneOcean --outfile=assets/ocean.bundle.js
grep -c "createFilmOcean" assets/ocean.bundle.js
```
Expected: a count ≥ 1. The bundle must contain no `Math.random` call that `draw` can reach: site `ocean.js`'s `createOcean`/`grainTile` use it and are unused. Confirm with `grep -n "Math.random" assets/ocean.bundle.js` and check that every hit sits inside `createOcean`, `grainTile` or `seamless` code that `createFilmOcean` never calls.

- [ ] **Step 6: Commit**

```bash
cd ~/Desktop/oryne-launch && git add film/src/film-ocean.js film/src/test-film-ocean.mjs film/assets/ocean.bundle.js
git commit -qm "Ocean: the site's lights and water as a pure function of film time"
```

---

### Task 8: Sound (ocean bed and chime)

**Files:**
- Create: `$L/audio/ocean-bed.mjs`, `$L/audio/test-ocean-bed.mjs`
- Create (outputs): `$L/audio/chime.wav`, `$L/audio/chime.caf`, then copies at `film/assets/audio/{ocean-bed,chime}.wav`

**Interfaces:**
- Consumes: `film/src/breath.js` (`BREATH_BASE`, `breathAt`, `wave`), so the sound breathes on the same clock as the lights.
- Produces: `renderBed(seconds, { fadeIn = 2.5, fadeOut = 2.5, rmsDb = -24 }) -> { L: Float32Array, R: Float32Array }`, `wav16(L, R) -> Buffer`, `swellAt(t) -> { gain, cutoff }`, `washGain(t) -> number`, `mulberry32(seed) -> () => number`. CLI: `node audio/ocean-bed.mjs --duration <s> --out <file.wav>`.

- [ ] **Step 1: Write the failing tests**

`$L/audio/test-ocean-bed.mjs`:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { wave } from '../film/src/breath.js';
import { renderBed, wav16, swellAt, washGain, SR } from './ocean-bed.mjs';

const hash = (buf) => createHash('sha256').update(buf).digest('hex');

test('the same length renders the same bytes', () => {
  const a = renderBed(4);
  const b = renderBed(4);
  assert.equal(hash(wav16(a.L, a.R)), hash(wav16(b.L, b.R)));
});

test('length is exact and the level lands on the target', () => {
  const { L, R } = renderBed(12, { rmsDb: -24 });
  assert.equal(L.length, 12 * SR);
  let sum = 0;
  for (let i = 0; i < L.length; i++) sum += L[i] * L[i] + R[i] * R[i];
  const db = 10 * Math.log10(sum / (2 * L.length));
  assert.ok(Math.abs(db + 24) < 0.1, `rms ${db.toFixed(2)} dB`);
});

test('no clipping and no NaN', () => {
  const { L, R } = renderBed(12);
  for (const ch of [L, R]) for (const v of ch) { assert.ok(Number.isFinite(v)); assert.ok(Math.abs(v) < 0.9); }
});

test('the swell opens with the breath', () => {
  const w = wave(0);
  const crest = swellAt(w.start + w.rise);
  const trough = swellAt(w.start + 0.05);
  assert.ok(crest.gain > trough.gain * 3);
  assert.ok(crest.cutoff > trough.cutoff * 2);
});

test('the wash hisses just after a crest and dies away', () => {
  const w = wave(1);
  const crest = w.start + w.rise;
  assert.ok(Math.abs(washGain(crest + 0.35) - 0.05 * w.peak) < 1e-9);
  assert.ok(washGain(crest + 3) < 0.05 * w.peak * 0.1);
  assert.equal(washGain(0.1), 0);   // nothing before the first crest
});

test('fades in from silence and out to silence', () => {
  const { L } = renderBed(8);
  assert.ok(Math.abs(L[0]) < 1e-12);
  assert.ok(Math.abs(L[L.length - 1]) < 1e-4);
});
```

- [ ] **Step 2: Run them and watch them fail**

Run: `cd ~/Desktop/oryne-launch && node --test audio/test-ocean-bed.mjs`
Expected: FAIL with `Cannot find module … ocean-bed.mjs`.

- [ ] **Step 3: Write `ocean-bed.mjs`**

`$L/audio/ocean-bed.mjs`:

```js
#!/usr/bin/env node
// The Ocean's surf, rendered offline. A port of website/assets/js/sound.js @ f4f698e:
// brown-noise deep bed → lowpass 420 Hz; pink-noise swell opened and closed by
// the shared breath (gain 0.03→0.5, cutoff 380→1600 Hz) and panned per wave;
// white-noise wash through a 2.5 kHz highpass, a short hiss at each crest.
// Seeded noise instead of Math.random, so the same length is the same file.

import { writeFileSync } from 'node:fs';
import { BREATH_BASE, breathAt, wave } from '../film/src/breath.js';

export const SR = 48000;
const BLOCK = 128;
const MASTER = 0.9;

export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function noiseSource(kind, seed) {
  const rand = mulberry32(seed);
  let b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0, brown = 0;
  return () => {
    const white = rand() * 2 - 1;
    if (kind === 'white') return white * 0.5;
    if (kind === 'pink') {
      b0 = 0.99886 * b0 + white * 0.0555179;
      b1 = 0.99332 * b1 + white * 0.0750759;
      b2 = 0.969 * b2 + white * 0.153852;
      b3 = 0.8665 * b3 + white * 0.3104856;
      b4 = 0.55 * b4 + white * 0.5329522;
      b5 = -0.7616 * b5 - white * 0.016898;
      const out = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.11;
      b6 = white * 0.115926;
      return out;
    }
    brown = (brown + 0.02 * white) / 1.02;
    return brown * 3.5;
  };
}

/** RBJ biquad, as Web Audio's BiquadFilterNode computes it. */
function biquad(type) {
  let b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0, x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  return {
    set(frequency, q) {
      const w = (2 * Math.PI * frequency) / SR;
      const c = Math.cos(w);
      const alpha = Math.sin(w) / (2 * q);
      const a0 = 1 + alpha;
      const n = type === 'lowpass' ? [(1 - c) / 2, 1 - c, (1 - c) / 2] : [(1 + c) / 2, -(1 + c), (1 + c) / 2];
      b0 = n[0] / a0; b1 = n[1] / a0; b2 = n[2] / a0; a1 = (-2 * c) / a0; a2 = (1 - alpha) / a0;
    },
    run(x) {
      const y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      x2 = x1; x1 = x; y2 = y1; y1 = y;
      return y;
    },
  };
}

/** sound.js swellCurve at depth 0: loudness and brightness follow the breath. */
export function swellAt(t) {
  const lift = (breathAt(t).level - BREATH_BASE) / (1 - BREATH_BASE);
  return { gain: 0.03 + 0.47 * lift, cutoff: 380 + 1220 * lift ** 1.5 };
}

/** sound.js scheduleWave's wash: 0 at crest−0.3 s, up to 0.05·peak at crest+0.35 s, then decays (τ 0.9 s). */
export function washGain(t) {
  for (let i = breathAt(t + 0.3).index; i >= 0; i--) {
    const w = wave(i);
    const crest = w.start + w.rise;
    if (crest - 0.3 > t) continue;
    const top = 0.05 * w.peak;
    if (t < crest + 0.35) return (top * (t - (crest - 0.3))) / 0.65;
    return top * Math.exp(-(t - (crest + 0.35)) / 0.9);
  }
  return 0;
}

export function renderBed(seconds, { fadeIn = 2.5, fadeOut = 2.5, rmsDb = -24 } = {}) {
  const n = Math.round(seconds * SR);
  const L = new Float32Array(n);
  const R = new Float32Array(n);
  const deep = [noiseSource('brown', 11), noiseSource('brown', 12)];
  const swell = [noiseSource('pink', 21), noiseSource('pink', 22)];
  const wash = [noiseSource('white', 31), noiseSource('white', 32)];
  const deepF = [biquad('lowpass'), biquad('lowpass')];
  const swellF = [biquad('lowpass'), biquad('lowpass')];
  const washF = [biquad('highpass'), biquad('highpass')];
  deepF.forEach((f) => f.set(420, 0.4));
  washF.forEach((f) => f.set(2500, 0.7));
  let pan = wave(0).pan;
  const panStep = 1 - Math.exp(-BLOCK / SR / 1.5);   // setTargetAtTime(pan, …, 1.5)

  for (let s0 = 0; s0 < n; s0 += BLOCK) {
    const t = s0 / SR;
    const { gain, cutoff } = swellAt(t);
    swellF.forEach((f) => f.set(cutoff, 0.6));
    pan += (wave(breathAt(t).index).pan - pan) * panStep;
    const gl = Math.cos(((pan + 1) * Math.PI) / 4) * Math.SQRT2;
    const gr = Math.sin(((pan + 1) * Math.PI) / 4) * Math.SQRT2;
    const wg = washGain(t);
    const end = Math.min(n, s0 + BLOCK);
    for (let s = s0; s < end; s++) {
      const tt = s / SR;
      const env = Math.max(0, Math.min(1, tt / fadeIn, (seconds - tt) / fadeOut));
      const body = [0, 1].map((c) => deepF[c].run(deep[c]()) * 0.1);
      const surf = [0, 1].map((c) => swellF[c].run(swell[c]()) * gain + washF[c].run(wash[c]()) * wg);
      L[s] = MASTER * env * (body[0] + surf[0] * gl);
      R[s] = MASTER * env * (body[1] + surf[1] * gr);
    }
  }

  let sum = 0;
  for (let i = 0; i < n; i++) sum += L[i] * L[i] + R[i] * R[i];
  const k = 10 ** (rmsDb / 20) / Math.sqrt(sum / (2 * n));
  for (let i = 0; i < n; i++) { L[i] *= k; R[i] *= k; }
  return { L, R };
}

export function wav16(L, R) {
  const n = L.length;
  const buf = Buffer.alloc(44 + n * 4);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 4, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22);
  buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(n * 4, 40);
  const q = (v) => Math.max(-32768, Math.min(32767, Math.round(v * 32767)));
  for (let i = 0; i < n; i++) { buf.writeInt16LE(q(L[i]), 44 + i * 4); buf.writeInt16LE(q(R[i]), 46 + i * 4); }
  return buf;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const arg = (name) => process.argv[process.argv.indexOf(name) + 1];
  const seconds = Number(arg('--duration'));
  const out = arg('--out');
  if (!(seconds > 0) || !out) { console.error('usage: ocean-bed.mjs --duration <s> --out <file.wav>'); process.exit(2); }
  const { L, R } = renderBed(seconds);
  writeFileSync(out, wav16(L, R));
  let peak = 0;
  for (const ch of [L, R]) for (const v of ch) peak = Math.max(peak, Math.abs(v));
  console.log(`${out}: ${seconds}s, peak ${(20 * Math.log10(peak)).toFixed(1)} dBFS, rms -24.0 dBFS`);
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `cd ~/Desktop/oryne-launch && node --test audio/test-ocean-bed.mjs`
Expected: `# pass 6`, `# fail 0`.

- [ ] **Step 5: Render the chime without touching the app bundle**

```bash
cd ~/Desktop/oryne-launch
python3 /Users/malik/Documents/inspire-ocean/tools/generate_ocean_received.py --peak-db -6 \
  --wav-out ~/Desktop/oryne-launch/audio/chime.wav --out ~/Desktop/oryne-launch/audio/chime.caf
git -C /Users/malik/Documents/inspire-ocean status --short Oryne/Resources/OceanReceived.caf
```
Expected: `audio/chime.wav` exists, and the `git status` line is **empty** (the bundled asset is untouched). `--peak-db -6` makes the film chime sit 6 dB above the app's in-UI level. Keep the notes and reverb the same.

- [ ] **Step 6: Commit**

```bash
git add audio/ocean-bed.mjs audio/test-ocean-bed.mjs && git commit -qm "Sound: offline, seeded port of the site's ocean"
```
(The bed itself is rendered in Task 9, once the film's length is known.)

---

### Task 9: Compositions from measurements

**Files:**
- Create: `$L/tools/film/templates.mjs`, `$L/tools/film/assemble.mjs`, `$L/tools/film/test-assemble.mjs`
- Create (generated): `$L/film/index.html`, `$L/film/compositions/{opening,card-catch,catch,card-currents,currents,card-resurface,resurface,card-ask,ask,end}.html`, `$L/film/film.json`

**Interfaces:**
- Consumes: `takes/cuts.json` (Task 5 shape), `film/assets/frame.json` (Task 2 shape), and `OryneOcean.createFilmOcean` from the Task 7 bundle.
- Produces: `validateCuts(cuts)` (throws `Error('cuts.<beat>: <reason>')`), `plan(cuts) -> { total, slots: [{id, kind, start, dur}], release: {t, text} }`, and `build(dir, cuts, frame) -> plan`, which writes all composition files plus `film.json` (the plan). CLI: `node tools/film/assemble.mjs` (paths are relative to `$L`).

- [ ] **Step 1: Write the failing tests**

`$L/tools/film/test-assemble.mjs`:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { validateCuts, plan, build, ORDER, RELEASE_TEXT } from './assemble.mjs';

const beat = (take, dur, extra = {}) => ({
  take, segments: [{ in: 2, out: 2 + dur }],
  cues: [{ t: 1.2, x: 0.5, y: 0.8, what: 'button' }],
  camera: [{ t: 0, s: 1, x: 0.5, y: 0.5 }, { t: 1.1, s: 1.4, x: 0.5, y: 0.8, move: 0.6 }],
  ...extra,
});
const CUTS = { beats: { catch: beat('A', 11, { release: 8.5 }), currents: beat('A', 9), resurface: beat('B', 9), ask: beat('C', 11) } };
const FRAME = { w: 900, h: 1840, screen: { x: 40, y: 38, w: 820, h: 1764 }, radius: 110 };

test('slots follow the script order and add up', () => {
  const p = plan(CUTS);
  assert.deepEqual(p.slots.map((s) => s.id), ORDER);
  assert.equal(p.total, 58.1);   // 3.5 + 4 × 2.4 + 11 + 9 + 9 + 11 + 5
  assert.equal(p.slots.find((s) => s.id === 'currents').start, 19.3);
});

test('the chime lands on the release frame', () => {
  const p = plan(CUTS);
  assert.equal(p.release.t, 14.4);
  assert.equal(p.release.text, RELEASE_TEXT);
});

test('segments add up and play back to back', () => {
  const split = structuredClone(CUTS);
  split.beats.catch.segments = [{ in: 2, out: 8 }, { in: 15, out: 20 }];   // 6 + 5 = 11 s, 7 s pause removed
  const p = plan(split);
  assert.equal(p.slots.find((s) => s.id === 'catch').dur, 11);
  const dir = mkdtempSync(join(tmpdir(), 'film-'));
  build(dir, split, FRAME);
  const html = readFileSync(join(dir, 'compositions', 'catch.html'), 'utf8');
  assert.match(html, /id="catch-video-0"[^>]*data-start="0" data-duration="6" data-media-start="2"/);
  assert.match(html, /id="catch-video-1"[^>]*data-start="6" data-duration="5" data-media-start="15"/);
});

test('bad cuts are refused with the beat named', () => {
  const overlap = structuredClone(CUTS);
  overlap.beats.currents.segments = [{ in: 2, out: 8 }, { in: 7, out: 12 }];
  assert.throws(() => validateCuts(overlap), /cuts\.currents: /);
  const bad = structuredClone(CUTS);
  bad.beats.ask.cues = [];
  assert.throws(() => validateCuts(bad), /cuts\.ask: /);
  const late = structuredClone(CUTS);
  late.beats.catch.camera[1].move = 2;
  assert.throws(() => validateCuts(late), /cuts\.catch: /);
  const noRelease = structuredClone(CUTS);
  delete noRelease.beats.catch.release;
  assert.throws(() => validateCuts(noRelease), /cuts\.catch: /);
});

test('build writes every composition with the exact words and the measured trim', () => {
  const dir = mkdtempSync(join(tmpdir(), 'film-'));
  mkdirSync(join(dir, 'compositions'));
  build(dir, CUTS, FRAME);
  const html = (id) => readFileSync(join(dir, 'compositions', `${id}.html`), 'utf8');
  assert.match(html('opening'), /<span class="w">Catch<\/span>.*<em><span class="w">drift<\/span> <span class="w">away\.<\/span><\/em>/s);
  assert.match(html('card-resurface'), /<em><span class="w">Get<\/span> <span class="w">it<\/span> <span class="w">back\.<\/span><\/em>/);
  assert.match(html('catch'), /id="catch-video-0"[^>]*data-media-start="2"/);
  assert.match(html('catch'), /src="assets\/takes\/A\.mp4"/);
  assert.match(html('end'), /Now on the App Store/);
  const index = readFileSync(join(dir, 'index.html'), 'utf8');
  assert.match(index, /id="root"[^>]*data-duration="58.1"/);
  assert.match(index, /id="chime"[^>]*data-start="14.4"/);
  for (const id of ORDER) assert.match(index, new RegExp(`id="slot-${id}"[^>]*data-composition-src="compositions/${id}\\.html"`));
});
```

- [ ] **Step 2: Run them and watch them fail**

Run: `cd ~/Desktop/oryne-launch && node --test tools/film/test-assemble.mjs`
Expected: FAIL with `Cannot find module … assemble.mjs`.

- [ ] **Step 3: Write `templates.mjs`**

`$L/tools/film/templates.mjs`:

```js
// HTML for every composition, from measured numbers. Layout math only; the
// numbers come from takes/cuts.json and film/assets/frame.json.

export const W = 2560;
export const H = 1440;
export const PHONE_H = 1150;
const FOAM = 'rgba(255,255,255,0.92)';
const ITALIC = '#d9e1f0';
const TEXT = 'rgba(255,255,255,0.66)';

const spans = (s) => s.split(' ').filter(Boolean).map((w) => `<span class="w">${w}</span>`).join(' ');

export function words(lead, accent) {
  return [lead ? spans(lead) : '', accent ? `<em>${spans(accent)}</em>` : ''].filter(Boolean).join(' ');
}

export function card({ id, lead, accent, dur }) {
  return `<template id="${id}-template">
<div id="${id}" data-composition-id="${id}" data-width="${W}" data-height="${H}" data-duration="${dur}">
  <style>
    #${id} { position: relative; width: 100%; height: 100%; display: flex; align-items: center; justify-content: center; }
    #${id} h1 { margin: 0; max-width: 2000px; text-align: center; text-wrap: balance; font-family: "Instrument Serif", Georgia, serif; font-weight: 400; font-size: 200px; line-height: 0.98; letter-spacing: -0.012em; color: ${FOAM}; }
    #${id} em { font-style: italic; color: ${ITALIC}; }
    #${id} .w { display: inline-block; }
  </style>
  <h1>${words(lead, accent)}</h1>
  <script>
    (function () {
      const tl = gsap.timeline({ paused: true });
      tl.from("#${id} .w", { y: 48, opacity: 0, duration: 0.8, ease: "power3.out", stagger: 0.06 }, 0.15);
      window.__timelines["${id}"] = tl;
    })();
  </script>
</div>
</template>
`;
}

export function end({ dur }) {
  return `<template id="end-template">
<div id="end" data-composition-id="end" data-width="${W}" data-height="${H}" data-duration="${dur}">
  <style>
    #end { position: relative; width: 100%; height: 100%; display: flex; align-items: center; justify-content: center; }
    #end .lock { display: flex; flex-direction: column; align-items: center; }
    #end .mark { width: 120px; height: 120px; fill: none; stroke: ${FOAM}; stroke-width: 1.4; stroke-linecap: round; display: block; }
    #end .name { margin-top: 28px; font-family: "Instrument Serif", Georgia, serif; font-weight: 400; font-size: 150px; line-height: 1; letter-spacing: 0.02em; color: ${FOAM}; }
    #end .line { margin: 36px 0 0; font-family: "Inter", sans-serif; font-weight: 300; font-size: 40px; letter-spacing: 0.01em; color: ${TEXT}; }
    #end .badge { display: block; height: 104px; width: auto; margin-top: 44px; }
  </style>
  <div class="lock">
    <svg class="mark" viewBox="0 0 28 28" aria-hidden="true"><circle cx="14" cy="14" r="11.2" opacity="0.4"/><path d="M21.2 5.4A11.2 11.2 0 0 1 6.8 22.6"/><path d="M5.8 17.1c1.38-1.5 2.76-1.5 4.14 0s2.76 1.5 4.14 0 2.76-1.5 4.14 0 2.76 1.5 4.14 0" opacity="0.7"/></svg>
    <div class="name">Oryne</div>
    <p class="line">Now on the App Store</p>
    <img class="badge" src="assets/badge-en.svg" alt="Download on the App Store">
  </div>
  <script>
    (function () {
      const tl = gsap.timeline({ paused: true });
      tl.from("#end .mark", { y: 24, opacity: 0, duration: 0.9, ease: "power3.out" }, 0.1)
        .from("#end .name", { y: 32, opacity: 0, duration: 0.9, ease: "power3.out" }, 0.45)
        .from("#end .line", { y: 20, opacity: 0, duration: 0.8, ease: "power2.out" }, 1.1)
        .from("#end .badge", { y: 16, opacity: 0, duration: 0.8, ease: "power2.out" }, 1.5);
      window.__timelines["end"] = tl;
    })();
  </script>
</div>
</template>
`;
}

/** Phone geometry on the canvas, from the measured frame. */
export function phone(frame) {
  const k = PHONE_H / frame.h;
  return {
    k, pw: frame.w * k, ph: PHONE_H,
    screen: { x: frame.screen.x * k, y: frame.screen.y * k, w: frame.screen.w * k, h: frame.screen.h * k },
    radius: frame.radius * k,
  };
}

/** A camera key {t, s, x, y, move} → GSAP transform that puts screen point (x, y) at the canvas centre at scale s. */
export function cameraTransforms(cut, geo) {
  return cut.camera.map((c) => {
    const px = geo.screen.x + c.x * geo.screen.w - geo.pw / 2;
    const py = geo.screen.y + c.y * geo.screen.h - geo.ph / 2;
    return { t: c.t, move: c.move ?? 0.6, scale: c.s, x: +(-c.s * px).toFixed(2), y: +(-c.s * py).toFixed(2) };
  });
}

export function beat({ id, cut, frame }) {
  const geo = phone(frame);
  const s = geo.screen;
  let at = 0;
  const pieces = cut.segments.map((g, i) => {
    const len = +(g.out - g.in).toFixed(3);
    const piece = { i, start: +at.toFixed(3), len, from: g.in };
    at += len;
    return piece;
  });
  const dur = +at.toFixed(3);
  const cues = cut.cues.map((c, i) => ({ i, t: c.t, left: +(s.x + c.x * s.w).toFixed(1), top: +(s.y + c.y * s.h).toFixed(1) }));
  const cam = cameraTransforms(cut, geo);
  return `<template id="${id}-template">
<div id="${id}" data-composition-id="${id}" data-width="${W}" data-height="${H}" data-duration="${dur}">
  <style>
    #${id} { position: relative; width: 100%; height: 100%; }
    #${id} .cam { position: absolute; left: ${((W - geo.pw) / 2).toFixed(1)}px; top: ${((H - geo.ph) / 2).toFixed(1)}px; width: ${geo.pw.toFixed(1)}px; height: ${geo.ph}px; transform-origin: 50% 50%; }
    #${id} .screen { position: absolute; left: ${s.x.toFixed(1)}px; top: ${s.y.toFixed(1)}px; width: ${s.w.toFixed(1)}px; height: ${s.h.toFixed(1)}px; border-radius: ${geo.radius.toFixed(1)}px; overflow: hidden; background: #000; }
    #${id} .screen video { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }
    #${id} .frame { position: absolute; inset: 0; width: 100%; height: 100%; }
    #${id} .dot, #${id} .ripple { position: absolute; width: 64px; height: 64px; margin: -32px 0 0 -32px; border-radius: 50%; opacity: 0; }
    #${id} .dot { background: rgba(255,255,255,0.82); box-shadow: 0 0 0 1px rgba(0,0,0,0.18), 0 6px 24px rgba(0,0,0,0.35); }
    #${id} .ripple { border: 3px solid rgba(255,255,255,0.9); }
  </style>
  <div class="cam">
    <div class="screen">
${pieces.map((p) => `      <video id="${id}-video-${p.i}" class="clip" src="assets/takes/${cut.take}.mp4" data-start="${p.start}" data-duration="${p.len}" data-media-start="${p.from}" muted playsinline></video>`).join('\n')}
    </div>
    <img class="frame" src="assets/phone-frame.png" alt="">
${cues.map((c) => `    <div class="ripple" id="${id}-ripple-${c.i}" style="left:${c.left}px;top:${c.top}px"></div>
    <div class="dot" id="${id}-dot-${c.i}" style="left:${c.left}px;top:${c.top}px"></div>`).join('\n')}
  </div>
  <script>
    (function () {
      const tl = gsap.timeline({ paused: true });
      const cam = "#${id} .cam";
      const keys = ${JSON.stringify(cam)};
      tl.set(cam, { x: keys[0].x, y: keys[0].y, scale: keys[0].scale }, 0);
      for (let i = 1; i < keys.length; i++) {
        const k = keys[i];
        tl.to(cam, { x: k.x, y: k.y, scale: k.scale, duration: k.move, ease: "power2.inOut" }, k.t - k.move);
      }
      for (const c of ${JSON.stringify(cues.map(({ i, t }) => ({ i, t })))}) {
        const dot = "#${id}-dot-" + c.i;
        const ripple = "#${id}-ripple-" + c.i;
        tl.fromTo(dot, { opacity: 0, scale: 1.15 }, { opacity: 1, scale: 1, duration: 0.25, ease: "power2.out" }, c.t - 0.45)
          .to(dot, { scale: 0.82, duration: 0.1, ease: "power2.in" }, c.t - 0.1)
          .to(dot, { scale: 1, duration: 0.15, ease: "power2.out" }, c.t)
          .fromTo(ripple, { opacity: 0.9, scale: 1 }, { opacity: 0, scale: 2.6, duration: 0.45, ease: "power2.out" }, c.t)
          .to(dot, { opacity: 0, duration: 0.25, ease: "power1.out" }, c.t + 0.25);
      }
      window.__timelines["${id}"] = tl;
    })();
  </script>
</div>
</template>
`;
}

export function index({ total, slots, release }) {
  const film = JSON.stringify({ total, slots, release });
  return `<!doctype html>
<html lang="en" data-composition-variables='[{"id":"oceanOff","type":"boolean","label":"Hide the ocean (ink pass)","default":false}]'>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=${W}, height=${H}">
  <script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
  <style>
    @font-face { font-family: "Instrument Serif"; src: url(assets/fonts/instrument-serif.woff2) format("woff2"); font-weight: 400; font-style: normal; }
    @font-face { font-family: "Instrument Serif"; src: url(assets/fonts/instrument-serif-italic.woff2) format("woff2"); font-weight: 400; font-style: italic; }
    @font-face { font-family: "Inter"; src: url(assets/fonts/inter.woff2) format("woff2"); font-weight: 100 900; font-style: normal; }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { background: #050508; overflow: hidden; }
    #root { position: relative; width: 100%; height: 100%; overflow: hidden; background: #050508; }
    #water, #field, #grain { position: absolute; inset: 0; width: 100%; height: 100%; }
    #grain { background: url(assets/grain.png) repeat; background-size: 256px 256px; }
    .slot { position: absolute; inset: 0; }
  </style>
</head>
<body>
  <div id="root" data-composition-id="main" data-start="0" data-duration="${total}" data-width="${W}" data-height="${H}" data-fps="60">
    <canvas id="water"></canvas>
    <canvas id="field"></canvas>
    <div id="grain"></div>
${slots.map((s, i) => `    <div id="slot-${s.id}" class="slot" data-composition-id="${s.id}" data-composition-src="compositions/${s.id}.html" data-start="${s.start}" data-duration="${s.dur}" data-track-index="${1 + (i % 2)}"></div>`).join('\n')}
    <audio id="bed" src="assets/audio/ocean-bed.wav" data-start="0" data-duration="${total}" data-track-index="20" data-volume="1"></audio>
    <audio id="chime" src="assets/audio/chime.wav" data-start="${release.t}" data-track-index="21" data-volume="1"></audio>
  </div>
  <script src="assets/ocean.bundle.js"></script>
  <script>
    (function () {
      const FILM = ${film};
      const off = window.__hyperframes && window.__hyperframes.getVariables().oceanOff;
      if (off) for (const id of ["water", "field", "grain"]) document.getElementById(id).style.display = "none";
      document.fonts.load('italic 400 21px "Instrument Serif"').then(function () {
        const ocean = OryneOcean.createFilmOcean({ water: document.getElementById("water"), field: document.getElementById("field"), slots: FILM.slots, release: FILM.release });
        const tl = gsap.timeline({ paused: true });
        const clock = { t: 0 };
        tl.fromTo(clock, { t: 0 }, { t: FILM.total, duration: FILM.total, ease: "none", onUpdate: function () { if (!off) ocean.draw(clock.t); } }, 0);
        FILM.slots.forEach(function (s, i) {
          const el = "#slot-" + s.id;
          tl.fromTo(el, { opacity: 0, scale: 0.94 }, { opacity: 1, scale: 1, duration: 0.45, ease: "power2.out" }, s.start);
          if (i < FILM.slots.length - 1) tl.to(el, { opacity: 0, scale: 1.06, duration: 0.4, ease: "power2.in" }, s.start + s.dur - 0.4);
        });
        if (!off) ocean.draw(0);
        window.__timelines["main"] = tl;
      });
    })();
  </script>
</body>
</html>
`;
}
```

- [ ] **Step 4: Write `assemble.mjs`**

`$L/tools/film/assemble.mjs`:

```js
#!/usr/bin/env node
// cuts.json + frame.json → every composition in film/. The one place slot times are decided.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { card, end, beat, index } from './templates.mjs';

export const ORDER = ['opening', 'card-catch', 'catch', 'card-currents', 'currents', 'card-resurface', 'resurface', 'card-ask', 'ask', 'end'];
export const CARDS = {
  opening: { lead: 'Catch ideas before they', accent: 'drift away.' },
  'card-catch': { lead: 'Catch it', accent: 'in seconds.' },
  'card-currents': { lead: 'Watch it', accent: 'find its place.' },
  'card-resurface': { lead: '', accent: 'Get it back.' },
  'card-ask': { lead: 'Ask what it', accent: 'all means.' },
};
// Cards run 2.4 s, not the spec's ~2 s: the words settle at ~1.1 s and exit from 2.0 s, so
// they read for ~0.9 s. At 2.0 s they would read for ~0.3 s.
export const LENGTH = { opening: 3.5, card: 2.4, end: 5.0 };
export const RELEASE_TEXT = 'The room feels slower when the light turns warm.';
const BEATS = ['catch', 'currents', 'resurface', 'ask'];
const r3 = (v) => Math.round(v * 1000) / 1000;
/** A beat's length on screen: its segments played back to back. */
export const beatLength = (b) => r3(b.segments.reduce((sum, g) => sum + (g.out - g.in), 0));
const kindOf = (id) => (id === 'opening' || id === 'end' ? id : id.startsWith('card-') ? 'card' : 'beat');

export function validateCuts(cuts) {
  for (const id of BEATS) {
    const b = cuts?.beats?.[id];
    const fail = (why) => { throw new Error(`cuts.${id}: ${why}`); };
    if (!b) fail('missing');
    if (!['A', 'B', 'C'].includes(b.take)) fail('take must be A, B or C');
    if (!Array.isArray(b.segments) || b.segments.length < 1 || b.segments.length > 3) fail('needs 1–3 segments');
    b.segments.forEach((g, i) => {
      if (!(Number.isFinite(g.in) && Number.isFinite(g.out) && g.out > g.in)) fail(`segment ${i} needs in < out`);
      if (i > 0 && g.in < b.segments[i - 1].out) fail(`segment ${i} starts before segment ${i - 1} ends`);
    });
    const dur = beatLength(b);
    if (!Array.isArray(b.cues) || b.cues.length === 0) fail('needs at least one cue');
    for (const c of b.cues) {
      if (!(c.t > 0.45 && c.t < dur)) fail(`cue t ${c.t} outside (0.45, ${dur})`);
      if (!(c.x >= 0 && c.x <= 1 && c.y >= 0 && c.y <= 1)) fail('cue x/y must be screen fractions');
    }
    if (!Array.isArray(b.camera) || b.camera.length === 0 || b.camera[0].t !== 0) fail('camera must start with a key at t 0');
    b.camera.forEach((k, i) => {
      if (!(k.s >= 1 && k.s <= 1.8)) fail(`camera key ${i} scale ${k.s} outside 1–1.8`);
      if (i > 0 && k.t - (k.move ?? 0.6) < b.camera[i - 1].t - 1e-6) fail(`camera key ${i} starts moving before key ${i - 1} arrives`);
      if (k.t > dur) fail(`camera key ${i} after the beat ends`);
    });
    if (id === 'catch' && !(b.release > 0 && b.release < dur)) fail('release must be inside the beat');
  }
}

export function plan(cuts) {
  let t = 0;
  const slots = ORDER.map((id) => {
    const kind = kindOf(id);
    const dur = kind === 'beat' ? beatLength(cuts.beats[id]) : LENGTH[kind];
    const slot = { id, kind, start: r3(t), dur };
    t += dur;
    return slot;
  });
  const catchSlot = slots.find((s) => s.id === 'catch');
  return { total: r3(t), slots, release: { t: r3(catchSlot.start + cuts.beats.catch.release), text: RELEASE_TEXT } };
}

export function build(dir, cuts, frame) {
  validateCuts(cuts);
  const p = plan(cuts);
  mkdirSync(join(dir, 'compositions'), { recursive: true });
  for (const s of p.slots) {
    const html = s.kind === 'beat' ? beat({ id: s.id, cut: cuts.beats[s.id], frame })
      : s.kind === 'end' ? end({ dur: s.dur })
      : card({ id: s.id, ...CARDS[s.id], dur: s.dur });
    writeFileSync(join(dir, 'compositions', `${s.id}.html`), html);
  }
  writeFileSync(join(dir, 'index.html'), index(p));
  writeFileSync(join(dir, 'film.json'), JSON.stringify(p, null, 1));
  return p;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const cuts = JSON.parse(readFileSync('takes/cuts.json', 'utf8'));
  const frame = JSON.parse(readFileSync('film/assets/frame.json', 'utf8'));
  const p = build('film', cuts, frame);
  console.log(`film: ${p.total}s, release at ${p.release.t}s`);
  for (const s of p.slots) console.log(`  ${s.start.toFixed(3).padStart(7)}  ${s.dur.toFixed(3).padStart(6)}  ${s.id}`);
}
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `cd ~/Desktop/oryne-launch && node --test tools/film/test-assemble.mjs`
Expected: `# pass 5`, `# fail 0`.

- [ ] **Step 6: Generate the real film, then the bed at its exact length**

```bash
cd ~/Desktop/oryne-launch
node tools/film/assemble.mjs
TOTAL=$(node -e "console.log(require('./film/film.json').total)")
node audio/ocean-bed.mjs --duration "$TOTAL" --out audio/ocean-bed.wav
cp audio/ocean-bed.wav audio/chime.wav film/assets/audio/
```
Expected: `film: <total>s` with a total between 45 and 60, and a slot table in script order. If the total is outside 45–60, go back to Task 5: tighten `in`/`out` without cutting any payoff below its 2 s hold, or report.

- [ ] **Step 7: Check the composition**

Run: `cd ~/Desktop/oryne-launch/film && npx -y hyperframes@0.8.62 check 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -30`
Expected: `Check passed` with 0 errors. Fix any error at its source: in `templates.mjs` if it's structural, or in `cuts.json` if it's a timing problem. Then regenerate (Step 6) and recheck. Read every warning and note it for the audit.

- [ ] **Step 8: Commit**

```bash
cd ~/Desktop/oryne-launch && git add tools/film film/index.html film/compositions film/film.json
git commit -qm "Film: compositions generated from measured cuts"
```

---

### Task 10: Draft render and verification

**Files:**
- Create: `$L/tools/film/stills.mjs`
- Create (outputs): `$L/renders/draft-v1.mp4`, `$L/renders/draft-v1b.mp4`, `$L/renders/ink-v1.mp4`, `$L/renders/stills/*.png`

**Interfaces:**
- Consumes: `film/film.json`, `takes/cuts.json`, `tools/ink_centre.py`.
- Produces: `node tools/film/stills.mjs <video> <outdir>` writes `card-<id>.png` (at slot start + 1.4 s), `cue-<beat>-<i>.png` (at the cue's film time), `payoff-<beat>.png` (at slot end − 1.0 s), `release.png` (release + 0.6 s) and `end.png` (end start + 3.0 s), and prints each file with its film time.

- [ ] **Step 1: Write the stills tool**

`$L/tools/film/stills.mjs`:

```js
#!/usr/bin/env node
// Verification stills at the moments the script promises something.
import { readFileSync, mkdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';

const [video, out] = process.argv.slice(2);
const film = JSON.parse(readFileSync('film/film.json', 'utf8'));
const cuts = JSON.parse(readFileSync('takes/cuts.json', 'utf8'));
mkdirSync(out, { recursive: true });
const shots = [];
for (const s of film.slots) {
  if (s.kind === 'card' || s.kind === 'opening') shots.push([`card-${s.id}`, s.start + 1.4]);
  if (s.kind === 'beat') {
    cuts.beats[s.id].cues.forEach((c, i) => shots.push([`cue-${s.id}-${i}`, s.start + c.t - 0.12]));
    shots.push([`payoff-${s.id}`, s.start + s.dur - 1.0]);
  }
  if (s.kind === 'end') shots.push(['end', s.start + 3.0]);
}
shots.push(['release', film.release.t + 0.6]);
for (const [name, t] of shots) {
  const file = join(out, `${name}.png`);
  spawnSync('ffmpeg', ['-v', 'error', '-y', '-ss', t.toFixed(3), '-i', video, '-frames:v', '1', file], { stdio: 'inherit' });
  console.log(`${t.toFixed(3).padStart(8)}s  ${file}`);
}
```

- [ ] **Step 2: Draft render, twice, to prove determinism**

```bash
cd ~/Desktop/oryne-launch
npx -y hyperframes@0.8.62 render film -o renders/draft-v1.mp4 --fps 30 --quality draft --strict
npx -y hyperframes@0.8.62 render film -o renders/draft-v1b.mp4 --fps 30 --quality draft --strict
for t in 2 14.8 33; do ffmpeg -v error -ss $t -i renders/draft-v1.mp4 -ss $t -i renders/draft-v1b.mp4 -frames:v 1 -lavfi psnr -f null - 2>&1 | grep -o "average:[^ ]*"; done
```
Expected: both renders succeed and all three PSNR lines read `average:inf`. Any finite value means something draws from something other than film time. Find it in `film-ocean.js` or `index.html` and fix it there, not by accepting it. If the WebGL water itself proves non-deterministic in the headless renderer (the lamps' 2D canvas matches but the water layer doesn't), use the spec fallback: skip `gl` in `createFilmOcean` (`const gl = null`), paint the water as a static CSS gradient on `#root` (`radial-gradient(ellipse at 50% 36%, #17181c 0%, #0d0e11 45%, #050508 100%)`), keep the lamps, and record the fallback in the audit.

- [ ] **Step 3: Pull the stills and read every one**

```bash
cd ~/Desktop/oryne-launch && node tools/film/stills.mjs renders/draft-v1.mp4 renders/stills
```
Read each PNG at full resolution (Read tool) and check:
- `card-*.png`: the words match the Global Constraints exactly (case, punctuation, which words are italic), in Instrument Serif, with nothing clipped.
- `cue-*`: the touch dot sits on the control named in `cuts.json` `what`, and never on the typed line.
- `payoff-*`: the proof is readable. For catch it's the full typed line before release; for currents, the sheet with 5 thoughts, the new one among them; for resurface, the age plus nearby thoughts; for ask, the answer body.
- `release.png`: the release light with the words sinking left of the phone and the rings opening under it.
- `end.png`: mark, "Oryne", "Now on the App Store", badge.
- Everywhere: no lights smaller than a lamp, no grey outline around the phone, and screen corners that match the frame's corners.
- The deepest punch (the highest `s` in `cuts.json`): zoom into the phone bezel at full resolution. If the bezel's edge or buttons look soft, switch to the product-film frame: `cp ~/.claude/skills/product-film/assets/iphone-17-pro-silver.png film/assets/phone-frame.png`, re-run `python3 tools/measure_frame.py film/assets/phone-frame.png > film/assets/frame.json` (expect about 1120×2289, cutout 60,58,999×2173, radius ≈174), then `node tools/film/assemble.mjs` and re-render. `FRAME_ASPECT` in `film-ocean.js` becomes `1120 / 2289`; rebundle (Task 7 Step 5).

- [ ] **Step 4: Ink pass, to check card centring**

```bash
cd ~/Desktop/oryne-launch
npx -y hyperframes@0.8.62 render film -o renders/ink-v1.mp4 --fps 30 --quality draft --variables '{"oceanOff":true}'
node tools/film/stills.mjs renders/ink-v1.mp4 renders/stills-ink
for f in renders/stills-ink/card-*.png renders/stills-ink/end.png; do echo "$f $(python3 tools/ink_centre.py $f)"; done
```
Expected: every `offset` is within ±6 px on both axes. If a card is off, fix the layout in `templates.mjs` (never nudge by eye), regenerate, and re-run Steps 2–4.

- [ ] **Step 5: Send the draft to Malik**

Send `renders/draft-v1.mp4` with SendUserFile and a one-line caption naming anything still open from Steps 3–4. Wait for notes. Sort each note: a vibe-level note cascades to the cards, edit, camera and sound together; a scoped note touches only that element.

- [ ] **Step 6: Commit**

```bash
cd ~/Desktop/oryne-launch && git add tools/film/stills.mjs && git commit -qm "Verification: stills, determinism, ink centring"
```

---

### Task 11: Delivery render and gap audit

**Files:**
- Create: `$L/renders/Oryne Launch v1.mp4`, `$L/renders/audit-v1.md`
- Create: `$R/docs/films/2026-09-22-launch-film-audit-v1.md` (the same audit, in the repo)

**Interfaces:**
- Consumes: everything above; `~/.claude/skills/product-film/references/gap-audit.md` (the grading rules).

- [ ] **Step 1: Delivery render**

```bash
cd ~/Desktop/oryne-launch
npx -y hyperframes@0.8.62 render film -o "renders/Oryne Launch v1.mp4" --fps 60 --quality delivery --strict
ffprobe -v error -show_entries stream=codec_type,width,height,r_frame_rate:format=duration -of compact "renders/Oryne Launch v1.mp4"
ffmpeg -i "renders/Oryne Launch v1.mp4" -af ebur128=peak=true -f null - 2>&1 | grep -E "I:|Peak:" | tail -2
```
Expected: video `2560x1440`, `60/1`; one audio stream; duration equal to `film.json` total (±0.02 s) and inside 45–60 s; true peak ≤ −1 dBTP. If the peak is higher, lower `data-volume` on `#chime` in `templates.mjs` (`index`), regenerate, and re-render.

- [ ] **Step 2: Listen for the chime on the release frame**

```bash
cd ~/Desktop/oryne-launch
REL=$(node -e "console.log(require('./film/film.json').release.t)")
ffmpeg -v error -ss $(echo "$REL - 0.5" | bc) -t 1.5 -i "renders/Oryne Launch v1.mp4" -af "astats=metadata=1:reset=6,ametadata=print:key=lavfi.astats.Overall.Peak_level" -f null - 2>&1 | grep -E "pts_time|Peak_level" | paste - - | head -30
```
Expected: the peak level jumps within 0.05 s after `pts_time` ≈ 0.5, which is the release time.

- [ ] **Step 3: Stills from the delivery file, then the gap audit**

```bash
cd ~/Desktop/oryne-launch && node tools/film/stills.mjs "renders/Oryne Launch v1.mp4" renders/stills-v1
```
Read `~/.claude/skills/product-film/references/gap-audit.md`, then write `renders/audit-v1.md`:
- One row per scene (opening, 4 beats, 4 cards, end card), graded MET / PARTIAL / CONTRADICTED / MISSING / DEVIATES. Base each grade on the named still, never on the build plan.
- Split findings into editing gaps (fixable now) and capture gaps (need a retake or an app change), stated plainly.
- List every deviation from the spec: a reworded typed line or question, a fallback used, the Resurfacing pick, whether Ask used Apple's model or the composed answer.
- Record the file facts from Step 1 (size, duration, loudness, true peak).

- [ ] **Step 4: Copy the audit into the repo and commit both sides**

```bash
cp ~/Desktop/oryne-launch/renders/audit-v1.md /Users/malik/Documents/inspire-ocean/.claude/worktrees/oryne-launch-film/docs/films/2026-09-22-launch-film-audit-v1.md
cd /Users/malik/Documents/inspire-ocean/.claude/worktrees/oryne-launch-film && git add docs/films/2026-09-22-launch-film-audit-v1.md && git commit -qm "Film: launch film v1 gap audit"
cd ~/Desktop/oryne-launch && git add -A tools film/index.html film/compositions film/film.json takes/cuts.json && git commit -qm "Launch film v1 delivered" || true
```

- [ ] **Step 5: Deliver**

Send `renders/Oryne Launch v1.mp4` and `renders/audit-v1.md` to Malik with SendUserFile. Report in chat: length, what met the script, every gap and deviation, and where the files are. Don't post anything anywhere.
