# Oryne — Product Philosophy

> *Oryne should not feel like managing ideas. It should feel like living alongside them.*

These are the guardrails for every implementation decision. When a feature,
fix, or refactor is in tension with one of these, the principle wins — or the
principle gets amended here, deliberately, first.

---

## 1. Capture

**Capture before consciousness.** The moment between having a thought and
judging it is the product. Anything that lengthens that moment — a required
field, a category picker, a confirmation step — is a regression, whatever it
adds.

- Capture must work in under two seconds from any entry point (tab, overlay,
  Action Button, widget, Siri, share sheet).
- A whisper is caught the moment recording stops. Review refines what was
  caught; it never gates whether it was caught.
- Interruptions (a call, Siri, a lost mic) end a take the way a tap on stop
  does — capture what was caught. The app never sits stuck "Listening…".
- Mode switches, tab switches, and backgrounding never discard words. If the
  user typed something and then spoke, both survive.

**Test:** would this change make someone hesitate before capturing? Then no.

## 2. Ownership

**The user owns meaning. The system interprets; it never overrules.**

- AI fills *untouched* fields only. A title, theme, or transcript the user has
  edited is theirs forever (`titleEditedByUser`, `themesEditedByUser`,
  `transcriptEditedByUser` are the enforcement seam — every interpretation
  pass goes through `NodeComposer.applyUnderstanding`).
- Branching over editing: growing an idea never overwrites the original.
- Audio is provenance, not an asset to manage. It exists so the words can be
  checked and re-heard, not to be trimmed, scrubbed, or organized. Once a
  transcript is confirmed, the audio may quietly expire.
- Deletion is honest and reversible at the moment it happens (named Undo,
  grace periods, confirmation for the permanent step) — and final once the
  user has said so. No tombstones, no "trash" to manage.
- The Ocean's contents are the user's water. Nothing in it should ever be
  authored by us and dressed as theirs.

**Test:** after this change, can the system ever silently replace something
the user wrote? Then no.

## 3. AI behavior

**Grounded, modest, and honest about where words come from.**

- Every reflection is grounded in the user's saved fragments. Retrieval,
  themes, and transcription stay on-device; only composition may go to the
  cloud, and only with the handful of fragments retrieval already chose.
- Degradation is visible where silence would mislead: a cloud answer that
  quietly fell back to the device says so ("Composed offline"); an answer with
  nothing nearby to draw from never pretends to be grounded.
- Knowledge from beyond the user's notes is always marked apart ("Beyond your
  Ocean") — grounded water and open sea never mix in one voice.
- The AI is a reflective partner, not an oracle: it suggests, hints, and
  resurfaces. It never assigns, schedules, or nags.

**Test:** if the network died mid-session, would the user be told anything
untrue — by words *or by omission*? Then no.

## 4. Motion

**Motion is atmosphere, never information.**

- Nothing the user needs to know is carried only by movement, glow, or
  position. The drift exists so the space feels alive; every fact it implies
  is reachable through a tap, a label, or the Library.
- Presence comes from lifted glass bodies and soft depth shadows — never
  halos, luminous cores, or hard rims.
- All ambient motion shares one off-switch: the system Reduce Motion setting
  and Calm Accessibility Mode still the water completely. A stilled Ocean is
  the same Ocean.
- Animation runs at full ProMotion when it runs, and doesn't run at all when
  nobody benefits — battery is part of calm.

**Test:** if every animation froze, would the app lose any *meaning*? Then the
design leans on motion too hard.

## 5. Trust

**The app never claims more certainty than it has.**

- Success is stated only after it is verified. A confirmation shown before a
  save is checked is a lie with good intentions.
- Normal operation feels ambient: working states breathe, safe states settle,
  everything ephemeral. Only failure raises its voice — explicitly, with the
  words preserved and a way to act (retry, restore, undo). Failure never
  auto-fades.
- Every destructive act can be taken back for a breath (undo by name, never a
  bare ✕ that quietly means delete). Grace windows fail toward keeping the
  user's data.
- Feedback language stays small: *working · safe · needs attention*. No
  syncing spinners, no retry counters, no implementation detail on screen.

**Test:** does the UI ever say "done" before the system knows it's done? Then
fix that before anything else.

## 6. Memory

**Rediscovery is a rhythm, not a queue.**

- One fragment resurfaces per day — deterministic, so every surface (field,
  widget) agrees on which.
- What rises is genuinely forgotten (idle time carries the weight), sometimes
  an echo of what the user is exploring now (shared currents lift older
  thoughts), and never the same memory on a loop (a met fragment rests).
- Recurring thoughts are surfaced as observations ("a thought you keep
  returning to"), never converted into obligations.
- Understanding stabilizes over time: re-interpretation respects everything
  the user has touched, and a corrected thought doesn't teleport across the
  Ocean.

**Test:** does this feature make old thoughts *return*, or make the user *go
get* them? Returning is the product.

## 7. Retrieval

**The Ocean is atmosphere; the Library is the contract.**

- The field is for ambient encounter: clusters, density, the day's
  resurfacing. It deliberately shows a curated fraction of the water.
- Anything the user deliberately looks for must be reachable through
  structure: the Library (search, filter, time), cluster streams, and Ask.
  Position in the field is never the only path to a thought.
- Ask answers from the user's fragments first, names what it found, and shows
  its sources as chips that open the real thing.

**Test:** can a screen-reader user, or someone who never learned the field's
layout, reach every thought? They must.

## 8. Calm computing

**Oryne competes with nothing for the user's attention.**

- No badges, no streaks, no counts framed as progress, no "you haven't
  captured today". The Ocean is indifferent to neglect and warm on return.
- No task management, no folders, no dashboards, no workflows. The moment
  organizing the Ocean becomes work, we've built the wrong product.
- Settings stay few and real. Every toggle must change how the Ocean treats
  the user, not decorate a preferences screen.
- Words stay human and unhurried, in the water's own language — but clarity
  outranks poetry wherever the user must act ("Undo", "Try again", "Delete"
  are named for what they do).

**Test:** would this feature make Oryne feel like a tool that needs tending?
Then it belongs in some other app.

---

## Using this document

- In review, cite the principle, not taste: "violates Trust §5 — confirmation
  before verification" beats "feels wrong".
- New features should name, in their PR description, which principle they
  serve and which they risk.
- These principles change only deliberately — a PR that amends this file —
  never by drift.
