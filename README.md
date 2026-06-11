# Oryne — iOS (V1 / MVP)

> *Oryne should not feel like managing ideas. It should feel like living alongside them.*

A mobile-first creative memory system. Fleeting thoughts, images, whispers, and
fragments **drift** into a living field where they **resurface**, **connect**, and
**branch** over time — built around fast capture, ambient rediscovery, and
conversational reflection.

This repository is the **V1 / MVP** built from `Inspire_Ocean_PRD_v4`. The
product was originally codenamed *Inspire Ocean*, then *Oryn*, and is now
**Oryne** — same vision, same interaction design, new name. The ocean/field/drift
language remains the product's metaphor system throughout.

---

## Running it

Requires **Xcode 16+** (built and verified on Xcode 26). The Xcode project is
generated from `project.yml` with [XcodeGen](https://github.com/yonsm/XcodeGen).

```bash
brew install xcodegen      # once
xcodegen generate          # creates Oryne.xcodeproj
open Oryne.xcodeproj
```

Then select an iPhone simulator and press ⌘R (scheme: **Oryne**).

> **Rebrand note.** App, project, scheme, and target are named **Oryne**. The
> bundle ids (`com.inspireocean.*`), App Group, SwiftData store name, widget
> kind strings, and the source folder names deliberately keep their original
> identifiers — changing them would orphan user data, placed widgets, and
> Shortcuts automations, and would churn git history. Deep links use `oryne://`;
> the legacy `oryn://` and `inspireocean://` schemes are still registered and accepted.

> **Signing note.** The app runs as-is in the simulator. To make the **Share
> Extension** and **App Group** active (so captures shared from other apps land
> in the same Ocean), open *Signing & Capabilities* for both targets and select
> your Team. Without a team the app still works — it transparently falls back to
> a local per-app store.

---

## V1 scope (PRD §15)

**Included & implemented**

| PRD | Feature | Where |
| --- | --- | --- |
| §7 | Drift Capture — text, voice, photo/screenshot, link | `Features/Capture` |
| §7 | Share-sheet capture (screenshots, text, links from any app) | `ShareExtension/` |
| §8 | Ocean Field v1 — legible atmospheric field: layered, theme-clustered, hierarchical, focus-isolating | `Features/Ocean` |
| §9 | Expanded Node View — why it mattered, nearby thoughts, branch, ask | `Features/NodeDetail` |
| §10 | Manual branching — question / concept / research / project | `Features/NodeDetail/BranchComposer.swift` |
| §11 | Ocean Dialogue v1 — Search / Synthesis / Expansion / Research, grounded in nodes | `Features/Ask` |
| §13 | Library — structured fallback: search, filter, time-grouped | `Features/Library` |

**Excluded from V1 (PRD §15):** collaboration, Vision Pro, social features.

---

## Architecture (PRD §14)

- **Frontend:** SwiftUI, native interaction patterns, iOS 18+.
- **Storage:** SwiftData, local-first. Store lives in a shared App Group
  container so the share extension writes into the same Ocean.
  See `Shared/Persistence/Persistence.swift`.
- **AI Layer:** a single protocol seam, `OceanAIService`.
  - `LocalOceanAIService` — on-device. Uses Apple's `NLEmbedding` for genuine
    **semantic** related-node sensing and dialogue retrieval, `NaturalLanguage`
    for theme detection, and `Speech` for voice transcription. Every dialogue
    response is **grounded in the user's saved nodes** (PRD risk mitigation:
    *AI feels generic → ground responses in saved nodes*). Dialogue reflections
    and concise titles are composed with Apple's on-device **Foundation
    Models** (Apple Intelligence) when the device is eligible, with grounded
    template / heuristic fallbacks otherwise.
  - `CloudOceanAIService` (the app's default) — the cloud seam (PRD §14),
    wired to the Anthropic Claude API (`claude-opus-4-8`). It self-activates
    when an `ANTHROPIC_API_KEY` is present in the environment (simulator:
    `SIMCTL_CHILD_ANTHROPIC_API_KEY=… xcrun simctl launch …`) or as an
    `AnthropicAPIKey` Info.plist entry injected from a local xcconfig —
    **never commit a key**. Retrieval, themes, and transcription always stay
    on-device; only the dialogue reflection and concise titles are composed in
    the cloud, grounded in the handful of fragments retrieval already
    selected. Without a key (or on any network failure) it behaves exactly
    like `LocalOceanAIService`. Optional env overrides: `OCEAN_CLOUD_MODEL`,
    `OCEAN_CLOUD_BASE_URL`.

### Data model (`Shared/Models`)
- `Node` — one inspiration fragment ("drift"). Branching is a self-referential
  `parent`/`children` relationship, so **the original is never overwritten**
  (Experience Principle: *Branching Over Editing*).
- `Conversation` / `ChatMessage` — persisted Ocean Dialogue threads, including
  the source node ids each response was grounded in.

### Ocean Field — a legible atmosphere (`Features/Ocean`)
Three deliberately separated layers so the space feels alive *and* informative:
- **Atmosphere** (`AtmosphereView`, `OceanBackground`) — drifting motes + depth
  fog. Purely decorative, never interactive.
- **Structure** (`OceanLayoutEngine`) — a cached, deterministic force-relaxation
  layout: related fragments cluster (theme attraction), newer fragments float
  up (recency → vertical), and collision avoidance guarantees breathing room so
  fragments and their labels never overlap. Only ~6 fragments live in the
  foreground; the rest fade into the depth.
- **Interaction** (`OceanNodeView`) — clean tappable nodes. Hierarchy is carried
  by size / brightness / blur / glow (relevance + resurfacing). Labels appear
  only for the foreground or the focused node (progressive disclosure). Tapping
  focuses a node: it expands, its full title appears, and neighbours softly part
  (focus-isolation) for tap confidence.

### Project layout
```
Shared/            # compiled into both the app and the share extension
  Models/          # Node, Conversation, enums
  Persistence/     # SwiftData stack (App Group aware)
  Services/        # ThemeDetector, EmbeddingService, NodeComposer
Oryne/             # the app
  App/             # entry point, root tabs, app state, seed data
  DesignSystem/    # OceanTheme, reusable components, NodeRow, FlowLayout
  Services/        # OceanAIService seam + Local/Cloud impls, audio, speech
  Intents/         # App Intents — Siri / Shortcuts / Spotlight capture
  Features/        # Capture · Ocean · NodeDetail · Ask · Library
ShareExtension/    # share-sheet capture
project.yml        # XcodeGen project definition
```

### Siri & hands-free capture (`Oryne/Intents`)
Built on the **App Intents** framework (Siri, Shortcuts, Spotlight, Apple
Intelligence actions):
- **"Hey Siri, add an inspiration to Oryne"** → Siri asks *"What would
  you like to capture?"*, transcribes your spoken answer, and saves it as a
  thought — without opening the app (`AddInspirationIntent`). The fragment is
  titled on-device.
- **Screenshots / images** → `SaveToOceanIntent` accepts an image + optional
  note. Because iOS won't let an app grab another app's screen by voice alone,
  wire it as a one-tap automation in Shortcuts: *Take Screenshot → Save to
  Oryne* (the share sheet covers the manual case).

---

## Notes & next steps

- First launch seeds ~10 evocative fragments so the Ocean feels alive and
  dialogue/rediscovery are demonstrable immediately (`App/SeedData.swift`).
- Testing seam: launch env var `OCEAN_START_TAB=capture|ocean|ask|library`
  opens straight to a tab.
- **On-device AI requires eligible hardware.** Foundation Models and Apple
  Intelligence only run on Apple-Intelligence-capable Macs/iPhones. On
  ineligible hardware the model reports `deviceNotEligible` and the app falls
  back to heuristics (titles still read cleanly) — no code change needed; the
  model path activates automatically on capable devices.
- Natural next steps toward the PRD's longer arc: wire `CloudOceanAIService` to a
  hosted model (for model-quality titles/dialogue on any device), add an Action
  Button binding to `AddInspirationIntent`, and a Home Screen capture widget.
