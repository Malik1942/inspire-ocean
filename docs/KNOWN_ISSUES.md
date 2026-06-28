# Known issues

Deliberate trade-offs and deferred follow-ups. Each entry is dated; remove an
entry when it's resolved or no longer relevant.

## 2026-06-28 — Link enrichment + node editing

- **DEBUG hook `ORYNE_FORCE_SUMMARIZATION` + stage logging (`#if DEBUG`) — KEPT
  deliberately.** Lets either device-capability fork (full vs metadata-only) be
  exercised on one simulator and traces each stage to the console. Never compiled
  into release. Retained for future link-pipeline debugging
  (`LinkEnrichmentService.swift`).
- **Extractor low-severity edges left unfixed** (`PageContent.swift`): #1 a `>`
  inside a quoted HTML attribute can leak a stray `">` fragment from tag
  stripping; #2 HTML5 *unquoted* `<meta>` attributes aren't parsed. Both feed
  only the noise-tolerant on-device summarizer (the structured OG title/
  description/image use a separate quote-aware parser and are unaffected), and
  real Open Graph pages quote their attributes. Revisit only if real OG pages
  ever hit them. (The genuine correctness bug in the same area — `&amp;`
  double-decoding — was fixed.)

## 2026-06-28 — watchOS Phase 1 (committed on `feat/watchos-quick-capture`)

- **Still owes on-device runtime verification** (simulator can't prove it):
  a decodable, non-empty recording on the wrist; the denied-microphone-permission
  UI/recovery; and the always-on-display / wrist-down recording lifecycle. See
  `docs/HARDWARE_CHECKLIST.md` for the broader device pass.
