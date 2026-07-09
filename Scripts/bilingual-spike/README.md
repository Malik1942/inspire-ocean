# Bilingual voice spike harness

A throwaway diagnostic app — not part of Oryne, never ships. It answers two
questions from `docs/plans/bilingual-voice/BRIEF.md` before any app code is
written:

- **S1** — does the iOS 26 `Speech.SpeechTranscriber` adapt to Mandarin/English
  showing up in the same utterance?
- **S2** — do two concurrent on-device `SFSpeechRecognizer` tasks (zh-CN +
  en-US) fed from one tap run cleanly, or does iOS throttle/fail one?

## Why a full app, not a script

`SpeechAnalyzer`/`SpeechTranscriber` and dual on-device `SFSpeechRecognizer`
both need microphone + speech-recognition entitlements and (in practice) a
real device — on-device speech recognition is historically unreliable in
Simulator. That rules out a bare `swift run.sh` script like
`Scripts/embedding-floor-sweep`. This is its own tiny `xcodegen` project
(`project.yml` here, separate from `project.yml` at the repo root), so it
never touches Oryne's target, signing, or assets. Generate and open it with:

```
cd Scripts/bilingual-spike
xcodegen generate
open BilingualSpike.xcodeproj
```

Select your personal team under Signing & Capabilities (same as Oryne), then
run on **a physical iPhone on iOS 26**. Both tests need that: Test A's APIs
(`SpeechTranscriber`, `SpeechAnalyzer`, `AssetInventory`) are iOS 26+ only,
and on-device recognition in general behaves unreliably in Simulator.

The API calls were checked against the actual iOS 26.5 SDK on this machine
(`.swiftinterface` + headers, not just docs) and the harness builds clean
against `iphonesimulator26.5`. The one thing that could NOT be verified here
— no physical device/mic in this environment — is runtime behavior: exact
`SpeechTranscriber.results` completion timing, and whether asset downloads
or dual recognizer tasks behave as expected in practice. Watch for anything
that looks like a hang or an unexpected thrown error on first run.

## What it does

One take, run through both harnesses:

1. **Record** — taps the mic once, writes it to a `.caf` file, and live-feeds
   the same buffers to Test B (two concurrent `SFSpeechRecognizer` tasks:
   zh-CN + en-US, `requiresOnDeviceRecognition = true`). Partials + average
   segment confidence are logged live as streams `B-zh` / `B-en`.
2. **Run SpeechTranscriber pass** (after stopping the recording) — replays
   the saved file through Test A: a `SpeechTranscriber` configured for zh-CN,
   then (separately) one configured for en-US. `SpeechTranscriber`'s locale
   is fixed at construction — there's no API to switch it mid-stream — so
   this is two sequential single-locale passes over the same audio, logged
   as streams `A-zh` / `A-en`. Comparing those two logs is how "mid-stream
   adaptation" gets measured for this API (see S1 below).

The log view shows everything live; use **Share log** to export the full
timestamped text.

## The 3 takes to record

Record each as its own take (pick the segmented label before hitting
Record), roughly 5-10 seconds:

1. **Pure Mandarin** — an ordinary Mandarin sentence, no English words.
2. **Pure English** — an ordinary English sentence, no Mandarin.
3. **Code-switched** — one sentence that mixes both mid-utterance, the way
   you'd actually drift — e.g. start in Mandarin, drop into an English
   phrase partway through, back to Mandarin (or the reverse). This is the
   one that actually exercises S1 and the tolerance note below; the other
   two are controls/sanity checks.

For each take: Record → speak → Stop → **Run SpeechTranscriber pass** →
wait for both `A-zh` and `A-en` to log "pass complete" → **Share log** (or
just read it on-screen) before moving to the next take.

## Reading the logs

**S1 — mid-stream adaptation (streams `A-zh`, `A-en`, code-switched take):**
Compare the two passes' text side by side. Per BRIEF.md decision 5's
"asymmetric tolerance" claim, expect: `A-zh`'s transcript stays roughly
coherent through the English-embedded portion (even if the English words
come out romanized or approximated), while `A-en`'s transcript degrades into
fluent-sounding nonsense once it hits the Mandarin portion. If instead both
degrade equally, or `A-zh` also falls apart on the English portion, that
overturns the assumption the legacy bake-off's "ambiguity resolves to zh"
default (decision 5) is built on — flag it before A2/A3 build on top of it.

**S2 — dual on-device throttling (streams `B-zh`, `B-en`, any take, live):**
For each stream, check: (1) does it log partials at a cadence that roughly
tracks your speech, or does it visibly stall while the other stream is
active? (2) any `error:` lines — especially anything that looks like a
resource/restricted-mode error (e.g. `kAFAssistantErrorDomain`) rather than
a normal end-of-utterance signal? (3) on the pure-Mandarin and pure-English
takes, does the matching-language stream report high confidence and the
other stream low/near-zero (sanity check both streams are actually live, not
one silently starved)? Clean partials + confidence on both streams with no
errors = dual on-device tasks run unthrottled. A stall or error on one
stream while the other is active = throttling, and the legacy bake-off
(BRIEF.md decision 5) needs a fallback for it.

**Malik's own note (code-switched take, `A-zh` log):** after reading it,
write one line on how well the zh model tolerated your embedded English —
garbled but present, dropped outright, or correctly transliterated? That's
the calibration point for how much to trust "zh model survives embedded
English" for your actual speech, not just a hypothetical one.
