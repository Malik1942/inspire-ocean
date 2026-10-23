# Understanding eval

Measures the on-device thought reader (`FoundationThoughtReader`, cleaned by
`ThoughtReading`): does one guided call give the right category, a gist in
the other language, usable theme keys and entities, and how long it takes.
It compiles the shipping sources, so the prompt and schema under test are
always the app's own.

## What it reports

- **Category**: entries whose category is one the fixture accepts.
- **Gist in the other language**: a gist is kept only when it is in the
  other language (`ThoughtReading.tidyGist`), since that is the whole point.
- **No answer**: errors or guardrail refusals; the app falls back to the
  older free-text title and themes calls for these.
- **Mean latency** per reading.

## How to run

```bash
Scripts/understanding-eval/run.sh
```

Pass a number for runs per entry (default 1). Sampling is greedy. Rerun
after any change to `ThoughtReading.instructions`, the `Reading` schema, or
`ThoughtReading.version`, and after macOS updates the model.

## Baseline (2026-10-22, macOS 26.6, Xcode 27.1)

Category 19/19, gist in the other language 18/19 (the miss: an English gist
for an English entry, dropped by `tidyGist`), no answer 0, mean latency
1.9s. Before the prompt named the entry's language and the formal
categories were decided in code: category 15/19, gist 13/19.
