# The eval harness

One fixture, four evals, several runs, thresholds. `Fixture.swift` is a
bilingual Ocean of twenty-seven thoughts with the understanding record
phase 1 writes; every eval reads it, so a change to the fixture moves them
together. Each eval prints one `RESULT <eval> k=v …` line per run, and
`run.sh` compiles each once, runs it N times and reports the worst run and
the mean per metric against `report.py`'s thresholds. Thresholds are per
run: a flaky case fails the harness instead of hiding in a mean.

```bash
Scripts/eval/run.sh          # three runs of everything
Scripts/eval/run.sh 1 ask    # one run of one eval
```

Runs on this Mac's Apple Intelligence model (macOS 26+); each full pass
takes a few minutes. The logs stay in the temp folder the report names.

## What each eval checks

- **understanding** (`Scripts/understanding-eval`): the reader's category
  against the fixture's (and the alternatives an honest reader could pick),
  the gist landing in the other language, the title staying in the entry's
  language by words, no refusals.
- **snap** (`Scripts/current-snap-eval`): related entries join a right
  current (`missed`), near misses and unrelated entries join none
  (`false_merges`); a join the fixture allows but does not require is `may`.
- **ask** (`Scripts/ask-agent-eval`): answered, sources right, language
  right, no translation that echoes the original, how often the model had
  to be re-asked with find results in the prompt (`no_tool`).
- **memory** (`Scripts/memory-eval`): records kept only on two or more
  grounded thoughts, no claim of repetition on fewer than three
  (`overstated`), and current summaries that are not a preamble, not first
  person, not a quoted thought, not a definition of the name.

## The cases it was built from (2026-10-22)

| case | what the model did | what caught it, what fixed it |
|---|---|---|
| title language | rejected a Chinese title that kept "Tide" and "resurfacing" in Latin, so the entry's own words stood in | the check and `TitleDistiller.speaksLike` judge by words, not letters |
| false merges | filed a run under a one-thought "Night train to Lisbon", a job worry under a one-thought "Why strangers' opinions"; word vectors scored the wrong join 0.69 against true joins from 0.53 | a one-thought current is offered only when the entry shares a word with it; two thoughts earn the right to attract |
| anchoring | instruction examples ("a run is not travel, worry is not self-worth") made the model pick exactly those labels | the examples left the instruction |
| overstated memory | "You frequently mention Oryne" on two thoughts | `MemoryRules.softened` drops the claim below three grounded thoughts |
| invented evidence | cited a run for a curtain preference, an unrelated bug for an app project | `MemoryRules.groundedEvidence`: each cited thought must touch the observation |
| missed patterns | proposed two single-entry observations and missed a person named in three entries | counted hints in the prompt: names in more than one entry, entries by kind |
| summaries | a preamble ending in a colon, a thought quoted verbatim, first person | `MemoryRules.summaryProblem` and one retry naming the problem; a second miss is no summary |
| pictures | a picture-only thought had no record at all (the model takes no images); asked for pictures, the agent searched by meaning, then listed "the last 7 days" for a question that named no time | pictures are read into words first (`PictureReading`, Vision OCR and scene labels) and the fixture carries two picture-only thoughts; a named form leads the search; a `withinDays` the model invents is dropped unless the question names a time (`AskAgent.namesTime`) |

## Baseline (2026-10-22, macOS 26.6, Xcode 27.1, three runs)

| eval | metric | worst run | threshold |
|---|---|---|---|
| understanding | category | 27 of 30 | ≥ 24 |
| understanding | gist in the other language | 27 of 30 | ≥ 23 |
| understanding | title in its language | 29 of 30 | ≥ 28 |
| snap | missed joins | 0 of 12 | 0 |
| snap | false merges | 0 of 7 | 0 |
| ask | answered | 12 of 12 | ≥ 11 |
| ask | sources right | 12 of 12 | ≥ 10 |
| ask | language right | 12 of 12 | ≥ 10 |
| ask | translation echoes | 0 | 0 |
| memory | records kept | 2 | ≥ 1 |
| memory | overstated | 0 | 0 |
| memory | summaries: preamble, first person, echo, definition | 0 | 0 |

The understanding and Ask rows are from the picture pass later that day
(two picture-only thoughts added to the fixture, two Ask cases for them;
understanding one run, Ask two). Current summaries go missing one run in
three or so (the model declines twice for "Light and Color" or 家, both
currents without pictures); the threshold allows one a run.

Where it started the same day, before the fixes above: understanding 23
and 23 of 26 with 24 titles; snap 2 to 5 false merges a run; ask 7 to 9
answered; memory 0 kept and 1 overstated. Rerun after any change to a
prompt, a schema, a budget, the fixture, or the model.
