# Usability test, 2026-10-18

Three simulated users ran the phone-refocus build, each on its own simulator, on the build from before the delicacy pass (commit 7029e0c):

| Tester | Profile | Device | Method |
| --- | --- | --- | --- |
| P1 | First-time user, English only | iPhone 17 | Eight tasks, from onboarding to delete |
| P2 | Returning bilingual user (zh/en) | iPhone 17e | Eight retrieval tasks: Tide, Currents, search, Summarize, Move, export |
| P3 | Heuristic reviewer | iPhone 17 Pro Max | Nielsen's ten heuristics and the HIG. Its touch access was never granted, so tap flows were judged from code, plus Dynamic Type, Chinese UI and Calm Mode on device |

Raw reports and screenshots stay outside the repo. This page merges duplicates, tags each item with who hit it, and lists separately what the delicacy pass already fixed.

## Verdict

**The set of functions is close to enough; reliability is not.**
- **Capture** has the right entry points and is fast. But a capture can still be lost: the overlay's X discards words and recordings without asking, and an unsent draft dies with the app.
- **Getting things back is where trust breaks:**
  - The home screen shows a generated title instead of the user's words.
  - Currents rename and split on their own.
  - Today's resurfacing changes during the day and favours recent thoughts.
  - A deleted thought cannot be recovered.
  - Ask answers recall questions with interpretive prose. Without the on-device model, that prose is a fixed template.
- **Library search is the one path a returning user can trust**, and only for literal words in a title or body.

## Fixed by the delicacy pass (7029e0c)

- **Undo was unreachable** (P1). Its pill sat on the Ask tab, under 44 pt, and the tab won the tap. It is now one centered toast above the bar, with a 44 pt Undo, for the whole undo window.
- **The save phrase rotated among four lines** (P1, P3). There is now one.
- **A thought's page never showed its title or its current** (P2). The title now leads in New York, and the meta line names the current.
- **The capture bar sat over the search keyboard** (P1, P2). It steps aside while another field has the keyboard.
- **Ask kept the keyboard up and hid the sources** (P1). Sending folds the keyboard, and so does scrolling.
- **Destructive confirms anchored to the wrong control and had no Cancel** (P1). Every one is now the centered system alert.
- **Settings had five problems** (P1, P3):
  - it led with hardware setup;
  - its step rows looked tappable;
  - its section subtitles said nothing a user acts on;
  - the examples card was narrower;
  - it closed with "Done" while other sheets used other words.

  It is now a grouped list, the steps are a footer path, and it closes with ✕.
- **Two composer bars in one slot looked alike but differed** (P3). Ask's bar is now the capture bar's twin.
- **Three title treatments for three tabs** (P3). All three now use New York at 40 pt. P3 checked an older build; Library's large title is serif on 7029e0c.
- **Sheets used five dismiss styles** (P3). Every viewing sheet now closes with ✕; editing sheets keep Cancel and Save. A thought's sheet has the ✕ on the left, because its tools are on the right.
- **The stream's Summarize and + were bare glyphs, and its "Related currents" capsules did nothing** (P1, P2, P3). The first two are now labelled buttons, and the capsules are gone.
- **Theme tags differed between screens** (P1). Cards no longer carry tags; themes appear once, on the thought's page.
- **The language menu sat on the Summary header but controlled the transcript** (P2). It now sits on the Transcript label.
- **"Tap to type the words or re-transcribe." could not be tapped** (P3). It now opens the editor.
- **A Release build would not compile** (P3). Library's state was declared only in Debug.

## Open: blockers

1. **A deleted thought is gone for good** (P1). There is no undo, no recently deleted, and nothing under Show archived. Deleting a current's only thought also silently removes the current.
2. **Ask cannot re-find the user's own idea** (P1, P2, P3).
   - Recall questions get interpretive prose that cites seed examples and calls the user "the user". It twice misstated P2's screenshot idea.
   - Outside-world claims appear inside the grounded answer, and "Drawn from" listed nine of eleven thoughts.
   - Without the on-device model, the answer is a fixed English template ("Reading across …, a shared current emerges"). It is marked as on-device, so nothing says it is canned. It also has em dashes. That is the norm without Apple Intelligence, which includes most users in mainland China.

## Open: major

3. **A capture can be lost** (P3).
   - The overlay's ✕ discards typed words, and mid-take it discards the whole recording, with no confirmation or Undo.
   - An unsent draft disappears when iOS ends the app.
4. **Voice capture cannot be discovered from the screen** (P1, P3).
   - Nothing on screen shows hold-to-whisper or slide-to-lock, and there is no live recording state.
   - After onboarding there is no help. The onboarding's own comment promises a replay button that does not exist.
5. **A denied microphone looks like nothing happened** (P3). Holding the disc just raises the keyboard with "Typing is ready."
6. **The first capture from onboarding** fires the microphone and speech alerts back to back, then starts recording (P1).
7. **The meaning layer is unstable, and every surface inherits it** (P1, P2, P3).
   - The one-time re-theme on first Library open skips the current snap that captures get. It leaks prompt words ("conceptual theme"), copies words from entries, and splits currents into one-thought currents.
   - Currents also rename after a capture as understanding lands ("Dentist", then "Health Care", then "Health").
   - Tide groups by primary theme while a stream shows any matching theme, so a card and its stream disagree.
8. **Generated titles replace the user's words on Tide** and can invert meaning (P1). "Buy milk" became "Milk bought".
9. **Resurfacing is not a stable daily pick** (P2, P3).
   - It is recomputed from live inputs, so it changes during the day.
   - Its "echo" lift counts the candidate itself, so a 2-day-old note beats a forgotten one.
   - It gives no reason, and Let it rest has no undo.
10. **"Switch to 中文" overwrites the stored transcript** (P2). It drops the summary and changes what search matches. Switching back writes a different summary.
11. **Search ignores the summary and the other-language transcript** (P2), even the summary printed on the card itself.
12. **Move is an arrow that reads as Share** (P1, P2, P3), and nothing confirms a move.
13. **Summarize is still hard to find and can land out of sight** (P2, P3). It is missing from Tide's current cards and the Currents page. From a stream opened inside All currents, the answer lands behind the Currents sheet.
14. **The App Store rating prompt fires in the first session** (P1, P2). It swallowed a hold-to-whisper and a tap.
15. **The New York display type does not scale with Dynamic Type** (P3). This covers the page titles, section labels, resurfacing title, a thought's title and the Ask question.

## Open: minor, by surface

- **Capture**
  - Holds under 1 s give no feedback, and silent whispers save as identical "Whisper" cards (P1).
  - With long text, the composer clips the top line (P3).
  - An English capture got a Chinese title (P2).
  - "Flows into …" is a faint caption (P2).
  - The keyboard dictation mic sits beside the disc (P3).
- **Tide**
  - Drifted in shows two-week-old thoughts, is not in time order, and repeats the resurfacing pick (P2, P3).
  - The Nearby toggle shows no state (P3).
  - The empty state drops the title and the gear (P3).
  - Example cards vanish after the first capture (P1).
  - Relative times do not refresh (P1).
  - Current cards have a fixed 72 pt height and will clip at large text (P3).
- **Navigation**
  - A thought opens as a sheet from Tide but as a push elsewhere, and sheets stack three deep (P1, P3).
  - Search exists twice, in Library and in Currents (P2, P3).
- **Currents**
  - No rename, merge or create (P1, P2).
  - Names are Title Case on cards but lowercase in meta lines (P3).
- **Thought page and edit**
  - The edit sheet still carries captions nobody acts on, including "Original audio is temporarily preserved to improve understanding." (P3).
  - "Themes shape where thoughts drift" is wrong once a thought is moved (P2, P3).
  - The keyboard covers "Add a theme" (P2).
  - "Transcribing…" is a 120-second guess (P3).
- **Ask**
  - There is no fresh question, the past vanishes on relaunch, and an answer cannot be kept as a thought (P1, P2, P3).
  - The sample prompts often find nothing (P3).
  - Summaries use two voices and leak "fragment" and "thread" (P2).
  - Every answer waits at least 1.2 s (P3).
- **Library**
  - Active filters are invisible: the empty state says "Nothing here yet" (P1, P2, P3).
  - The filter menu mixes kinds, Show archived and a Currents link (P1, P2).
  - Search persists across tab switches for hours (P2).
  - Archive gives no feedback (P3).
  - "No fragments match" offers no next step (P3).
- **Settings and export**
  - Tap-to-record exists only inside Calm Mode (P3).
  - "A full JSON backup" has no restore (P3).
  - Export takes two taps and has no preview or scope (P2, P3).
  - "Auto Screenshot" is unexplained, and onboarding calls it "Screenshot + voice" (P1, P3).
  - The Hardware picker only switches instructions (P3).
- **Language**
  - zh-Hans is missing for "Currents", which shows in English on Chinese Tide (P3).
  - It is also missing for "Arrangement", "Recent", "Related", "Show related", "Clear related", "Clear", "Related to %@" and "OK" (P3).
  - About 20 strings are still marked needs review (P3).
  - The vocabulary drifts between Ocean, sea, water, Tide, fragment and drift (P3).
- **Energy.** The background mesh redraws every frame for a drift of at most 3/255 per channel (P3).

## Notes on decisions already made

- **"Carried into the sea"** is your wording. P1 read the old sea phrase as "thrown away", and P3 suggests "Saved". Worth a second look, since this is the one moment the user needs to know the thought is safe.
- **"Grow a branch" stays on the thought page by your call.** P3 flags it against the thesis that growing ideas is desk work.

## Expected and missing

- Recover a deleted thought, and archive from the thought itself.
- The user's own words on Tide, with the generated title second.
- One search over title, summary and both transcripts, shared by Library and Ask.
- A recall answer that quotes the matched thought first.
- The current named on the thought and tappable; rename and merge currents.
- A visible recording state, a lock hint, "nothing heard" handling, and a replayable "How Oryne works".
- A daily pick that holds all day, a reason for it, and undo for Let it rest.
- A fresh question in Ask, and keeping an answer as a thought.
- Export scope and a preview.

## Suggested order

1. **Nothing gets lost.** Recoverable delete; a ✕ that keeps a draft and asks before discarding audio; drafts that survive the app ending; a clear message when the microphone is off.
2. **Stable meaning.** Run the re-theme through the current snap; strip prompt echoes and copied words; use one membership rule; add eval cases; pin the daily resurfacing pick without the self-echo.
3. **Getting it back.** One summary-aware, bilingual index for search and Ask. Recall answers lead with the matched thought. No templated interpretation when the model is absent.
4. **Teach the gestures.** A hold hint and a lock chevron, a "How Oryne works" replay, a calmer first-run permission sequence, and the rating prompt kept out of early sessions.
5. **Quick wins in one pass.** Missing zh strings, a labelled Move, current names in one spelling, the leftover captions, Dynamic Type for New York, and minimum height on current cards.
