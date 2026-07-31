# theme-reconcile-eval — the "burger bug" co-location test

**What it proves.** Thoughts that obviously belong together get scattered into
different currents because the cloud `understand()` call gives them different
free-text themes ("taste", "food curiosity", ...) and currents group by *exact
theme-string equality* (`OceanLayout.swift`). This harness measures that
fragmentation and whether **Fix C** removes it.

**Fix C.** Pass the ocean's existing themes into the `understand()` prompt with
a reuse-or-coin instruction and a bias toward broad, reusable labels ("prefer
`food` over `food curiosity`"), so related thoughts converge on one theme string
instead of each inventing a near-synonym.

## Why a live harness (not an XCTest)

Fix C is a *prompt* change — its effect is in what the model returns, so it can
only be proven by real model calls. On-device embeddings were measured and are
too weak/inseparable to make this deterministic (see the probe notes in the PR
discussion); the reliable signal is the cloud model. Hence: live API, your key.

## Run it

One-time key setup (with your key on the clipboard from console.anthropic.com):

```bash
mkdir -p ~/.config/oryne && pbpaste > ~/.config/oryne/anthropic.key
```

The keyfile lives outside any repo and `run.sh` strips stray whitespace from
it, so paste artifacts can't invalidate the key. (Exporting
`ANTHROPIC_API_KEY` still works too.) Then:

```bash
./run.sh
```

A preflight call verifies the key before the eval spends anything; a rejected
key fails fast with guidance and prints no scores.

One run makes **both** passes over `eval-set.json`:

- **OLD** — the shipping prompt, each thought interpreted in isolation → expect **RED**
  (within-group co-location well below 100%, food group fragmented).
- **NEW** — Fix C, existing themes passed in → expect **GREEN**
  (within-group at/near 100%, **0** false merges across concepts, and the
  `food-zh` group unifying on its own = bilingual proof).

Optional env: `OCEAN_CLOUD_MODEL` (default `claude-opus-4-8`),
`OCEAN_CLOUD_BASE_URL`.

## What it scores

- **within-group co-location** — same concept + same language must land on a
  shared theme (want 100%). This is the red→green signal.
- **false merges across concepts** — food vs career vs nature must NOT share a
  theme (want 0). Guards against the fix over-merging.
- **cross-language same concept** (food-en vs food-zh) — informational; either
  merging or staying separate is acceptable.

## Files

- `eval-set.json` — 9 interleaved thoughts, tagged with expected group/concept.
  `expectedTheme` is a readout label only; scoring is purely structural.
- `eval.swift` — the harness (mirrors `CloudOceanAIService.understand()` and
  `SemanticThemes.tidyThemeList`). The **NEW** prompt here is exactly what gets
  adopted into `CloudOceanAIService` once the run is green.
- `run.sh` — compiles and runs. No build artifacts are committed.
