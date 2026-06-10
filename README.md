# Inspire Ocean — iOS (V1 / MVP)

> *Inspire Ocean should not feel like managing ideas. It should feel like living alongside them.*

A mobile-first creative memory system. Fleeting thoughts, images, whispers, and
fragments **drift** into a living field where they **resurface**, **connect**, and
**branch** over time — built around fast capture, ambient rediscovery, and
conversational reflection.

This repository is the **V1 / MVP** built from `Inspire_Ocean_PRD_v4`.

---

## Running it

Requires **Xcode 16+** (built and verified on Xcode 26). The Xcode project is
generated from `project.yml` with [XcodeGen](https://github.com/yonsm/XcodeGen).

```bash
brew install xcodegen      # once
xcodegen generate          # creates InspireOcean.xcodeproj
open InspireOcean.xcodeproj
```

Then select an iPhone simulator and press ⌘R.

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
  - `LocalOceanAIService` (default, ships in V1) — on-device. Uses Apple's
    `NLEmbedding` for genuine **semantic** related-node sensing and dialogue
    retrieval, `NaturalLanguage` for theme detection, and `Speech` for voice
    transcription. Every dialogue response is **grounded in the user's saved
    nodes** (PRD risk mitigation: *AI feels generic → ground responses in saved
    nodes*). Concise, fully-displayable fragment titles are interpreted with
    Apple's on-device **Foundation Models** (Apple Intelligence) when the device
    is eligible, with a heuristic fallback otherwise.
  - `CloudOceanAIService` — drop-in cloud seam (PRD §14). Conforms to the same
    protocol; swapping it in `InspireOceanApp.swift` requires **no UI changes**.
    `TODO`s mark exactly where the network calls go.

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
InspireOcean/      # the app
  App/             # entry point, root tabs, app state, seed data
  DesignSystem/    # OceanTheme, reusable components, NodeRow, FlowLayout
  Services/        # OceanAIService seam + Local/Cloud impls, audio, speech
  Intents/         # App Intents — Siri / Shortcuts / Spotlight capture
  Features/        # Capture · Ocean · NodeDetail · Ask · Library
ShareExtension/    # share-sheet capture
project.yml        # XcodeGen project definition
```

### Siri & hands-free capture (`InspireOcean/Intents`)
Built on the **App Intents** framework (Siri, Shortcuts, Spotlight, Apple
Intelligence actions):
- **"Hey Siri, add an inspiration to Inspire Ocean"** → Siri asks *"What would
  you like to capture?"*, transcribes your spoken answer, and saves it as a
  thought — without opening the app (`AddInspirationIntent`). The fragment is
  titled on-device.
- **Screenshots / images** → `SaveToOceanIntent` accepts an image + optional
  note. Because iOS won't let an app grab another app's screen by voice alone,
  wire it as a one-tap automation in Shortcuts: *Take Screenshot → Save to
  Inspire Ocean* (the share sheet covers the manual case).

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
