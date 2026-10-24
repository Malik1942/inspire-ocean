# Ask agent eval

Runs the Ask agent (`AskAgent`: the on-device model with `findThoughts`,
`listThoughts` and `readThought` over the person's thoughts) against a fixed
bilingual Ocean of twelve thoughts with phase-1 understanding records, and
nine questions: lists by kind, a Chinese question for an English thought, a
name, two translations, a summary, and one with no answer in the Ocean.

## What it reports

- **Sources right**: every thought an honest answer must cite was cited (or,
  when the model cited nothing, read in full or named in the answer by
  title, by a name it carries, or by its own words), and none it must not.
  What a tool merely surfaced does not count: the app shows the same set as
  "Drawn from", and retrieved is not cited. A reference the model invented
  (`[t99]`) is listed as `invented`; its sentence was dropped from the
  answer.
- **Language right**: the answer's dominant script matches the question's.
- **No answer**: the model never called a tool, or failed; the app falls back
  to the single-prompt path for these.
- **Mean latency** per question, tool calls included.

## How to run

```bash
Scripts/ask-agent-eval/run.sh
```

Rerun after any change to `AskAgent.instructions`, the tools' descriptions
or schemas, or the budget, and after macOS updates the model.

## Baseline (2026-10-22, macOS 26.6, Xcode 27.1)

Answered 8 to 9 of 9, sources right 7 to 9 of 9, language right 8 of 9, mean
latency 2.3 to 2.8s across four runs: the tool path the small model takes
varies from run to run, so single runs differ by one or two questions. The
first version (one embedding search behind `findThoughts`, no language
named in the prompt, no translation routing) answered 6 of 9 with sources
right on 4. What moved the numbers, in order: naming the question's
language and the rules at the end of the prompt; `findThoughts` ranking on
word vectors instead of the contextual model (which scores a short
question against everything at 0.65 to 0.88) and leading with a kind the
question names; translation routed by hand through a session of its own;
a retry with `findThoughts` results in the prompt when the model answered
without a tool.

## 2026-10-23: constraints, grounding, bounds

Sixteen questions now: added a done task to the fixture and "What tasks are
still open?" / 哪些任务已经完成了, and three compound questions (a kind and a
topic: bugs about Ask, 关于撤销提示的 bug, bugs about payments, which has no
answer). The source metric tightened as above, so the numbers are not
comparable with the baseline: answered 15 to 16 of 16, sources right 12 to
14 of 16, language right 15 to 16 of 16, mean latency 3.0 to 3.6s across
the last three runs. What stands out:

- The one unanswered question in a run failed on an opaque
  `tokengeneration` code 10 on the first turn. "Bugs about payments" failed
  this way until searches were capped (it had listed kind by kind, six
  calls); after that a different question failed once. `AskAgent` now
  retries through every attempt within its deadline, and the run after
  that answered all sixteen.
- The misses that remain are the model's choices, not the tools': a
  `withinDays` of 7 for 最近 that drops a 12-day-old idea; listing kind by
  kind for "about Mara" and never reaching memories; naming only two of
  four pictures in an otherwise right answer.
- `findThoughts` now keeps the topic and the status inside a named kind,
  the forced retry runs the whole question through it, and a named form or
  kind that nothing surfaced matches counts as looking in the wrong place.
