# Embedding floor sweep

Re-derives the Ask dialogue relevance floor, `EmbeddingService.dialogueRetrievalFloor`
(currently 0.70). The floor decides whether a retrieved fragment is relevant
enough to enter an Ocean Dialogue answer; below it, nothing enters and the honest
empty state fires. Its value depends on the score distribution produced by
Apple's on-device `NLEmbedding`, so if Apple revises that model the floor can
silently stop separating real matches from noise. This script measures the
distribution again so the value can be rechecked.

## What it measures

For each documented corridor anchor it prints the query's top score, the intended
target fragment's score and rank, and how many fragments clear the floor:

- **R8 noise ceiling**: a nonsense query ("quantum accounting standards"). Its
  top score is the highest that pure noise reaches. The floor must sit above it,
  so the query lands the empty state.
- **R2 paraphrase target**: a paraphrase ("why do I put off beginning work")
  whose intended fragment shares no keywords ("Blank page judgment"). The floor
  must sit at or below the target's score, so the paraphrase still recalls it.
- **T6 boundary case**: the terse phrasing ("notifications interrupt attention")
  whose target ("Attention Drain") sits just under the floor. This is the one
  accepted recall loss: natural phrasings of the same thought score well above
  the floor, only this terse wording falls short.

## How to run

Against the currently booted simulator's store:

```
./run.sh
```

Against a specific store:

```
./run.sh /path/to/InspireOcean.store
```

`run.sh` calls `extract.py` (pulls each non-archived node's title, text, and
themes into the same searchable text the app builds) then `sweep.swift`
(reproduces `EmbeddingService` exactly: averaged NLEmbedding word vectors,
cosine, keyword-overlap fallback). Requires a Mac with Xcode's Swift toolchain
and Python 3, both standard on a dev machine.

## Corridor at time of writing

Measured against the seeded 60-fragment audit store (48 synthetic drifts plus
12 known targets), floor 0.70:

| Anchor | Score | Meaning |
| --- | --- | --- |
| R8 noise ceiling | 0.6725 | highest a nonsense query reaches; floor sits above it |
| R2 paraphrase target (Blank page judgment) | 0.7404 | keyword-free paraphrase target; floor sits below it |
| T6 boundary (Attention Drain, terse query) | 0.685 | accepted recall loss for one terse phrasing |

The floor sits in a narrow corridor, roughly 0.03 above the noise ceiling and
0.04 below the paraphrase target. That margin is inherent to NLEmbedding
averaged-vector cosine, whose scores compress into a 0.5 to 0.84 range. If a
future NLEmbedding revision moves the noise ceiling above the target, a single
absolute floor can no longer separate them and retrieval needs stopword or IDF
weighting rather than a threshold tweak.
