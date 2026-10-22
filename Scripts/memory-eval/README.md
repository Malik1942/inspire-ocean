# Memory eval

Runs the memory extractor (`FoundationMemoryExtractor`) over sixteen
thoughts from three weeks, with one record already kept, and prints what it
proposes to remember: kind, sentence, and the thoughts it rests on. A
proposal counts when `MemoryRules.fresh` keeps it (not a repeat of what is
kept) and it rests on at least two thoughts. Read the sentences: the
numbers say little about whether an observation is one a person would
recognize as theirs.

```bash
Scripts/memory-eval/run.sh
```

## Baseline (2026-10-22, macOS 26.6)

Four proposals, one kept: "You frequently mention Mara" on three grounded
thoughts. The three dropped were a preference and a project each resting
on one real thought plus an unrelated one the model cited anyway, and a
habit that repeated the kept record in other words. Before the grounding
gate and word-form sameness, all four would have been written.
