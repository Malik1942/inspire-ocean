# Known issues

Deliberate trade-offs and deferred follow-ups. Each entry is dated; remove an
entry when it's resolved or no longer relevant.

## 2026-06-29 — UI copy: no em/en dashes (style rule, enforced)

Standing rule: **no em or en dashes (— –) in user-facing UI copy** — use a comma,
colon, or period instead. Applies retroactively, and to copy only (not to these
dev docs). Because the String Catalog (`Oryne/Resources/Localizable.xcstrings`) is
value-as-key, the English source string *is* the key: rewording the English
renames the key, so the Swift literal and the catalog entry must move together,
and both code sites must change for any string used in more than one place. In
`zh-Hans`, the matching change is dropping 「——」 for a full-width comma 「，」 or
colon 「：」 (per `docs/localization-glossary.md`).

The 12 pre-existing localized strings + 2 non-localized strings (`themeInputNotice`
in `NodeEditSheet.swift`, the "Ask Ocean" prefill in `ExpandedNodeView.swift`) that
predated the rule were **cleaned on `claude/dazzling-vaughan-8aa530`**.

**Deliberately retained (not UI copy — do not "fix"):** sample thought bodies in
`App/SeedData.swift`; model-facing prompt strings and AI-generated answer text in
`Services/LocalOceanAIService.swift` (AI-derived copy isn't localized, per the
glossary); the `#if DEBUG` stage logs in `LinkEnrichmentService.swift`; and the
literal `"—"`/`"–"` characters in `Services/PageContent.swift` (parser tokens, not
copy).

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

## 2026-06-28 — Dev machine: no-passphrase SSH key (deliberate)

- The git push key for this machine — `~/.ssh/id_ed25519` (registered to GitHub
  as the auth key for `Malik1942/inspire-ocean`, `origin` is now SSH) — was
  generated **without a passphrase**, on purpose, so pushes are non-interactive.
  Trade-off: anyone with read access to this machine's `~/.ssh` could push as me.
  Acceptable for a personal dev machine; revisit if that ever stops being true.
  To add a passphrase later: `ssh-keygen -p -f ~/.ssh/id_ed25519`.
