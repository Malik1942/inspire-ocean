# Current snap eval

Measures whether a new thought joins the existing current it belongs to.
Currents group by exact theme strings, and the on-device model themes each
thought in isolation, so without help it almost never reuses an existing
label. `FoundationCurrentPicker` asks the model one constrained question
(which of these currents is this entry about, or none), and `CurrentSnap`
decides what's offered and how a pick lands in the thought's themes.

This script runs that pick on this Mac's Apple Intelligence model against a
fixed Ocean (the screenshot seed's currents, a few extra ones, and two Chinese
currents). It compiles `Shared/Services/CurrentSnap.swift` and
`Oryne/Services/FoundationCurrentPicker.swift` as they ship, so the prompt and
schema under test are always the app's own.

## What it reports

- **Joined**: clearly related thoughts that landed in an acceptable current.
- **False merges**: near-miss thoughts (a shared word or mood, a different
  subject: "Collecting unpaid invoices" vs. the *collecting* current of saved
  articles) and unrelated thoughts that were put into a current anyway. A miss
  only keeps the old behavior; a false merge hides a thought, so this is the
  number that must stay at zero.
- **No answer**: errors or guardrail refusals. These resolve to no snap.
- **Mean pick latency**.

## How to run

```bash
Scripts/current-snap-eval/run.sh
```

Pass a number for runs per case (default 3). Sampling is greedy, so repeat
runs mostly confirm determinism. Rerun after any change to
`CurrentSnap.instructions`, `CurrentSnap.prompt`, the candidate cap or examples,
or `FoundationCurrentPicker`, and after macOS updates the model.

## Baseline (2026-09-22, macOS 26.6)

Joined 27/27, false merges 0/27, no answer 0, mean pick latency 0.58s. Before
the pick, 0 of 21 related thoughts led with their current's exact label.
