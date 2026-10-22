# Ask agent eval

Runs the Ask agent (`AskAgent`: the on-device model with `findThoughts`,
`listThoughts` and `readThought` over the person's thoughts) against a fixed
bilingual Ocean of twelve thoughts with phase-1 understanding records, and
nine questions: lists by kind, a Chinese question for an English thought, a
name, two translations, a summary, and one with no answer in the Ocean.

## What it reports

- **Sources right**: every thought an honest answer must cite was cited (or,
  when the model cited nothing, surfaced by a tool), and none it must not.
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
