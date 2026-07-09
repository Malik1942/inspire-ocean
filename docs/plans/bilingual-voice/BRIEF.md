# Bilingual Voice Recognition — Design Brief (single source of truth)

Commit this file at `docs/plans/bilingual-voice/BRIEF.md`. Every agent prompt says
"Read docs/plans/bilingual-voice/BRIEF.md first" instead of restating this context.

## Goal
Voice capture recognizes Chinese and English — including bilingual users — with live
transcription in whichever language is spoken. Zero configuration UI. On-device only.

## Locked decisions
1. **Main language = system language** (`Locale.preferredLanguages[0]`), resolved fresh at
   every capture start. Never cache. Never use raw `Locale.current` (a `zh-Hans-US` user
   must resolve to `zh-CN` recognition, not fail).
2. **Alternate language** = next entry in `Locale.preferredLanguages` supported by speech
   recognition. Monolingual users have no alternate → zero extra cost for them.
3. **No language chip / no in-app setting.** Language is governed by iOS Settings only.
4. **iOS 26+ path**: `SpeechAnalyzer` + Apple's `SpeechTranscriber` module, assets via
   `AssetInventory`. **iOS 18–25 path**: `SFSpeechRecognizer` with explicit resolved locale.
5. **Live bilingual strategy (legacy path)**: 2-second *bake-off* — two recognition
   requests fed from the existing single tap, silent scoring (output length vs audio
   level, segment confidence, script coverage), lock the winner, cancel the loser.
   Ambiguity resolves to **zh** (asymmetric tolerance: zh model survives embedded
   English; en model produces confident garbage on Chinese).
6. **No mid-take re-arbitration.** One drift ≈ one dominant language. Mid-take switches
   are served by zh-model tolerance (one direction) and post-capture dual-pass (other).
7. **File path dual-pass**: if the main-language transcript shows loud failure signals
   (sparse output relative to duration, low confidence), re-run with alternate locale,
   pick winner. Audio is the immutable source of truth — transcripts are recomputable.
8. **Escape hatch**: "Re-transcribe in 中文 / English" action in `ExpandedNodeView`.
9. **Rename** our class `SpeechTranscriber` → `DriftTranscriber` (collides with Apple's
   iOS 26 `Speech.SpeechTranscriber`). Call sites: `Oryne/Services/SpeechTranscriber.swift`,
   `Oryne/Services/LocalOceanAIService.swift:15`.
10. **FM prompts** (`LocalOceanAIService`): add "Reply in the same language as the entry."
    to title + theme prompts; add a character cap for zh titles (6 words ≈ 6–10 chars).
11. **Embeddings**: evaluate `NLContextualEmbedding` (multilingual, one space for zh+en
    kinship) vs dual `NLEmbedding` routing. Re-run `Scripts/embedding-floor-sweep` to
    re-tune `SemanticThemes.relatednessFloor` for whichever wins. Audit whitespace
    tokenization (SemanticThemes overlap, TitleDistiller) → `NLTokenizer`.
12. **Asset readiness**: if alternate language exists, ensure its model at app launch on
    Wi-Fi, not mid-capture. First-use download shows "准备中文识别…" state, never a
    silent recording-only degrade when download is merely pending.

## Key files
- `Oryne/Services/LiveTranscriber.swift` — live capture engine (tap → file + recognition;
  taskGeneration restart machinery; interruption observers). The delicate file.
- `Oryne/Services/SpeechTranscriber.swift` — file-based transcription (→ DriftTranscriber).
- `Oryne/Services/LocalOceanAIService.swift` — FM sessions (titles/themes/reflections).
- `Shared/Services/EmbeddingService.swift` — hardcoded `.english` NLEmbedding (the bug).
- `Shared/Services/SemanticThemes.swift`, `Scripts/embedding-floor-sweep/sweep.swift`.
- `Oryne/Features/Capture/CaptureView.swift`, `Oryne/Features/Node/…ExpandedNodeView`.
- Project: xcodegen from `project.yml`, deployment target iOS 18.0.

## Invariants (do not break)
- Capture never blocks or fails because recognition is unavailable — recording always
  proceeds (`speechAvailability == .unavailable` degrade path).
- Audio file (AAC .m4a → `Node.audioData`, `@Attribute(.externalStorage)`) is untouched
  by any of this work.
- One action per capture screen; Ocean surface gesture budget is closed.
- New user-facing strings: English source now, batch zh-Hans behind the export line for
  the standard `localization-review` pass. Do not hand-write zh strings into xcstrings.

## Verification gates (Malik runs on device)
Matrix: {iOS 26, iOS 18} × {pure zh, pure en, mixed 中英} × {live capture, recorded drift}.
Plus: asset download offline/cellular behavior; bake-off lock timing feels instant;
kinship spot-check zh node ↔ related en node if contextual embeddings ship.
