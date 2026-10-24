# Oryne — Engineering Harness

Oryne is an inspiration-capture iOS app (SwiftUI, SwiftData + CloudKit, iOS 18+).
Product guardrails live in `PHILOSOPHY.md`; when code and philosophy conflict,
philosophy wins. Cite the principle by section when it decides something.

## Build and verify

```bash
xcodegen generate                      # after adding/removing/moving any file
xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -scheme Oryne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

A task is not done until the build passes. Run tests when you touched
anything under `Shared/`.

## Layout rules

```
Shared/        compiled into app + share extension + widgets. Models,
               Persistence, Services (pure logic, no UI), Export.
Oryne/         the app. App/ (entry, tabs, state), DesignSystem/ (theme,
               reusable components), Services/ (AI seam, audio, speech),
               Intents/, Features/ (Capture · Ocean · NodeDetail · Ask · Library).
ShareExtension/, OceanWidgets/   thin shells over Shared/.
```

- New logic goes where its dependents are: needed by extension or widgets →
  `Shared/`; app-only → `Oryne/Services/` or the owning feature folder.
  Never a new top-level folder without asking.
- One type per file unless the types are private helpers of the file's type.
- Match the existing comment style: doc comments explain *why* and the
  contract, not what the line does. No commented-out code.
- No third-party dependencies. If a task seems to need one, stop and ask.
- Localized user-facing strings via `String(localized:)`, as the codebase
  already does. Never hardcode English UI text.

## Do not touch (unless the task explicitly names it)

- `Oryne/DesignSystem/` — components, OceanTheme, materials, spacing.
- Any animation, transition, or motion parameter anywhere. Motion is
  atmosphere (PHILOSOPHY §4) and has been tuned by hand.
- Information architecture: tabs, navigation flows, sheet structure,
  what appears on which screen.
- `OceanLayoutEngine` and the Ocean field's visual behavior.
- Existing user flows in `Features/`. Adding a clearly-scoped entry point a
  task asks for is fine; restructuring a flow is not.
- `project.yml` beyond registering new files in existing targets.

When a task seems to require touching any of these, stop and say so instead
of improvising.

## Data rules

- Every stored property on a `@Model` needs a default (CloudKit).
- Fields the user edited are theirs forever: respect the
  `*EditedByUser` flags; interpretation passes go through
  `NodeComposer.applyUnderstanding` only.
- `isExample` content stays out of exports, resurfacing, and stats.
- Schema changes must be additive and migration-safe. Never rename or
  repurpose an existing stored property.

## Workflow

- Single agent, no gate ceremony. Before non-trivial work, state a plan in
  a few bullets and proceed; ask only when a decision is genuinely Malik's.
- Keep diffs scoped to the task. No drive-by refactors, renames, or
  formatting sweeps outside touched code.
- Never commit or push unless explicitly asked. When asked, small commits
  with plain messages.
- Finish by summarizing what changed, file by file, in a few lines.
