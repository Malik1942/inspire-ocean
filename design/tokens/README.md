# Oryne design tokens

One source of truth for every shared visual decision in Oryne, and the
reference for how the app composes them.

```
design/tokens/oryne.tokens.json      the source (DTCG 2025.10 format)
Scripts/design-tokens/generate.py    JSON -> Oryne/DesignSystem/OceanTokens.swift
Scripts/design-tokens/lint.sh        finds raw values in views that should be roles
Oryne/DesignSystem/OceanTokens.swift generated; every target compiles it
```

Change a value in the JSON, run the generator, and every sibling moves
together. Never edit the generated Swift.

```bash
python3 -I Scripts/design-tokens/generate.py          # write OceanTokens.swift
python3 -I Scripts/design-tokens/generate.py --check  # exit 1 when it is stale
sh Scripts/design-tokens/lint.sh                      # exit 1 on raw values in views
```

## Principles

1. **One source of truth.** The JSON owns supported values and their
   intent (`$description`). Swift is a generated artifact. Nothing in a view
   says `16` or `.white.opacity(0.08)`; it says `OceanSpacing.inset` or
   `OceanTheme.raised`.
2. **Roles before raw values.** Views read semantic roles (`inset`, `tile`,
   `control`, `lift`). The primitives (the 4 pt ladder, white at its
   opacities) live in the JSON's `primitive` group and are not emitted.
3. **Three facets.** Every token is form, material or motion. A component is
   one of each composed; a variant changes one facet and leaves the other
   two alone (a Secondary button's `selected` swaps the fill; its shape and
   its motion stay).
4. **Real surfaces over replicas.** The reference for a role is the
   production screen that wears it, named in the JSON's descriptions, not a
   catalog page.
5. **Systemize what repeats; preserve what expresses.** Shared decisions are
   tokens. Art-directed moments (the lamp, the water's vignette, the
   sinking words, the microphone bars) stay in their views, marked
   `// art-directed`, which the lint skips.
6. **Native first.** Controls are 44 pt, the system's own; the gutter is the
   system's layout margin; type roles are Dynamic Type text styles where a
   system style exists, and scaled by that style's metrics where the size is
   ours (the serif titles); glass is the system's Liquid Glass, on the
   floating layer only.

## The three facets

### Form

| Group | Swift | Roles |
|---|---|---|
| space | `OceanSpacing` | hairline 2, tight 4, snug 6, gap 8, item 12, inset 16, controlInset 20, block 24, section 40; `insetCompact` = item, `afterLabel` = inset; `gutter` (16 or 20, computed in the app from the window width) |
| radius | `OceanRadius` | card 20, media 14, field = media, thumbnail 10, composer 24, icon 4; anything up to a control's height is a capsule |
| size | `OceanSize` | metaIcon 14, glyphSlot 18, removeTarget 32, thumbnail 44, pictureTile 64, banner 120, hero 160 |
| control | `OceanControlSize` | height 44, toolCell 50, bar 56, toast 48, discInset 6 |
| type | `OceanType` | see below |

Type roles. New York names what a page is about and wears the italic
section labels; SF does everything else on one scale.

| Role | Face | Dynamic Type |
|---|---|---|
| pageTitle | New York 40 | metrics of largeTitle |
| resurfacingTitle | New York 32 | metrics of title1 |
| subjectTitle | New York 28 | title1 |
| sectionLabel | New York 21 italic | metrics of title3 |
| statement | SF 22 medium | title2 |
| wordmark | SF 17 medium, tracked 2.5 | headline |
| tileTitle | SF 16 medium | callout |
| body (+4 leading) | SF 17 | body |
| secondary (+3 leading) | SF 15 | subheadline |
| meta | SF 13 | footnote |
| note | SF 12 | caption |
| eyebrow | SF 13 semibold | footnote |
| control / controlStrong | SF 15 medium / semibold | subheadline |
| glyph / glyphStrong | SF 17 regular / semibold | fixed |
| glyphDisclosure, glyphMeta, glyphSmall, glyphLarge, glyphHero, badge | see JSON | |

### Material

| Group | Swift | Roles |
|---|---|---|
| color.water | `OceanTheme` | abyss, deep, mid, current, surface |
| color.ink | `OceanTheme` | foam 92%, text 66%, hint 58%, mist 50%, faint 26%, onAccent, onPhoto |
| color.surface | `OceanTheme` | fill 5.5%, raised 8%, pressedLift 4%, selected 12%, glassTint 18%, separator, scrim, photoScrim |
| color.accent | `OceanTheme` | accent, switchOn, glowWarm |
| shadow | `OceanShadow` | tile, control, inset, bar, text (`.oceanShadow(_:)`) |

Glass is not a token. `oceanGlass(in:tint:)` is the system's Liquid Glass
(the material of the tab bar) and belongs to the layer that floats over
content: bars, the toast, page tools, sheet chrome, the discs. Everything in
the content layer is `OceanSurface`: one flat fill, no gradient, no rim,
one soft shadow.

### Motion

| Role | Animation | For |
|---|---|---|
| touch | easeOut 150 ms | a control answering a finger |
| quick | easeOut 180 ms | a quick state change; the Reduce Motion stand-in |
| standard | smooth 350 ms | layout, folding, a section opening |
| lift | spring 0.36 / 0.86 | something floating in or out over the page |
| gentle | cubic(0.3, 0, 0.2, 1) 800 ms | the arrival of something new |

## Components (form + material + motion)

| Component | Form | Material | Motion |
|---|---|---|---|
| Primary button `.oceanPrimary` | capsule, 44, controlInset, controlStrong | glass with glassTint, foam ink (plain glass, mist when disabled) | touch |
| Secondary button `.oceanSecondary` | capsule, 44, controlInset, control | raised surface, foam; `selected` → selected surface | touch |
| Icon button `.oceanIcon` | 44 circle, glyph | glass, foam | touch |
| Link button `.oceanLink` | 44 target, controlStrong (or control when `.quiet`) | no surface; accent (or mist) | touch |
| Tile (`NodeCard`, `NodeRow`, a choice) | card radius, inset, tileTitle + meta, snug between | fill surface, tile shadow | standard |
| Field `.oceanField()` / `TranscriptEditor` | field radius, insetCompact, body | fill surface | |
| Add field `OceanAddField` | capsule, 44, + glyph leading, body; return adds | fill surface | |
| Link card | media radius, insetCompact, pictureTile thumbnail | fill surface | |
| Picture strip `OceanPictureStrip` | pictureTile, thumbnail radius, gap | remove badge on photoScrim | standard |
| Toast `OceanToast` | toast height, controlInset leading, control + Link | bar glass | lift |
| Sheet header `OceanSheetHeader` | grabber, then subjectTitle with the one action (Primary) on the same line ending on the gutter, as Tide's tools sit on its title; a quiet Cancel word beside it only where swipe-down is guarded | glass action on the water | |
| Floating bar `OceanBarBackground` | bar height capsule, or composer radius | glass; bar shadow before iOS 26 | lift |
| Section | sectionLabel, afterLabel to content, section between | mist (glowWarm for the one lit section) | |
| Page | PageTitleRow, gutter, section between | PageBackground (water + lamp) | |

Every button in the app wears one of the four styles. A chip is a Secondary
button. A chevron in content is a bare `glyphDisclosure`, never an Icon
button. A label above a field or a block is an `eyebrow`; a label above a
section is a `sectionLabel`.

## What stays expressive

Marked `// art-directed` in code; the lint skips those lines.

- Tide's lamp and its choreography when a thought rests (`OceanFieldView`),
  and the same lamp on the onboarding pages and behind Ask's reading line.
- The water itself: the mesh, the vignette (`OceanBackground`), the shore
  gradient under the capture bar.
- The caught words sinking (`FastCaptureSessionView.sink`), the microphone's
  level bars and the disc's glyph scaling with the disc
  (`CaptureHoldButton`), the wrist's waveform.
- A fade mask over a folded transcript.

## Decisions made in the alignment (2026-10-23)

The system existed in parts (`OceanType`, `OceanSpacing`, `OceanRadius`,
`OceanMotion`) and most views bypassed them. These are the decisions that
closed the gaps; each is one line in the JSON to change.

- One 4 pt ladder: 2 / 4 / 6 / 8 / 12 / 16 / 20 / 24 / 40. Tiles are now 12
  apart (were 10 in lists, 12 in grids); Tide's sections are 40 apart like
  every other page (were 32).
- One capsule inset for Primary and Secondary, a tile's 16 (were 20 and
  18), and one label style in every button: glyph, a snug gap, the words.
- Every chip is a 44 pt Secondary button: Listen, Re-transcribe, Restore, Add
  image, Re-derive, a branch type, a theme on the draft (its ✕ inside).
  These were four different 22 to 30 pt capsules with four fonts.
- A fourth style, Link, for words that act without a surface: Undo, Retry,
  Clear, All currents, Try again, a remove ✕ in a card.
- Primary is glass with the faint white tint and foam words, the ready
  disc's own material, never the solid accent fill (Malik, 2026-10-18).
- Sheets open like pages (`OceanSheetHeader`): a grabber, the one action
  as Primary, the subject in New York. No close button on any sheet: the
  pull down is the way out, and the grabber says so (the thought page, a
  current, Archived and Settings show the system's). The edit sheet keeps a
  quiet Cancel word because it holds the pull back while there are unsaved
  edits.
- Field names in the edit sheet and the branch composer are eyebrows (were
  headline bold); the question in Ask, a current's name, an empty page's
  line and the onboarding setup title share `subjectTitle`.
- One field surface for everything you type into (radius 14, the tile
  fill); it was 12 with two fills, and 10 in the branch composer.
- Choice rows (Move to a current, Merge into) are tiles: card radius, inset,
  no hairline border.
- No `GlassCard` in the content layer (the branch composer and the
  onboarding setup card are tiles now); glass stays on the floating layer.
- The widgets, the share sheet and the watch wear the app's own surfaces
  and type: the share sheet's blue palette is gone; the widget's gradient
  pill with a hairline is a Secondary capsule; the widget's and the Lock
  Screen's titles follow the type roles.
- Serif titles (`pageTitle`, `resurfacingTitle`, `sectionLabel`) now follow
  Dynamic Type through their text style's metrics; at the default size they
  are unchanged.
