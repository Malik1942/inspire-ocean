# Oryne 2.1: identity spec (draft 2)

Status: built on branch `am/tide-stage-round4` (2026-11-02) from the Round 4
frames, with the changes below. Draft 2 (2026-10-30) follows as written;
where it and this section disagree, this section is what the app does.
Draft 1 (2026-10-29) is superseded; its findings stand, its answers do not.

## As built (2026-11-02)

Malik's calls after Round 3 and Round 4 of the wireframes, and in the
first look at the build:

- **Tide is left aligned.** Centered read like song lyrics and broke on long
  titles. Today's thought stands in the Reading light (warm, from the upper
  left) when it has no picture; with a picture or a link's image, the
  picture is the stage (360 pt from the screen's top edge, 300 for a link's
  image, shorter on a short page such as a phone in landscape) with the
  label and the title at its foot, and the picture's last
  visible rows carry on 200 pt below it, mirrored, blurred and darkened,
  fading from its foot. Titles step 34 / 28 / 24 pt at 40 and 80
  characters; the user's own words follow in New York 19.
- **The column keeps its label** (Drifted in, in SF) and shows a small
  picture at the end of any line that has one. The ladder is the one in
  "The depth ladder" below; Nearby starts at level 2.
- **One lamp, the warm Reading light, on every page.** Ask and the Library
  take Tide's light ("the same warm glow as the tide"). A thought or a
  current you open stands in the same light a step softer (`PageBackground`
  `.soft`, 70%), Archived in a trace of it (30%), and their titles and words
  take the warm light's white (`stageInk`, `stageWords`). This retires R2's
  cool light (Malik, 2026-11-03): those pages are sheets over a warm tab, so
  the cool light met the warm one at the sheet's edge and the two read as
  different rooms, a third temperature beside every warm picture. Depth is
  now how much of the lamp reaches a page, never another color of light.
  The ring stays blue: a mark, not a light.
- **New water on every page**: near-black touched warm at the top, cooling
  through the middle, abyss at the bottom; no bright middle, no vignette.
- **Page and sheet titles are New York medium** (34 and 28). SF read as plain
  and lazy; decision B is reversed. Section labels stay SF.
- **Whose words** (R4, decision F as recommended) is one rule in code,
  `Node.ownWords`, with tests: the serif only for what the user wrote or
  said; a summary, a site's words and a link's address stay in SF. The live
  take's words are the user's too: New York 22 with room between the lines
  (`whisperWords`), over water that quiets behind them while a take is live.
  On a picture stage the title and words are plain white: no warm light
  falls there.
- **The ring** is the capture disc's rim, the capture toast's mark (arriving
  warm, cooling to the ring's color), the empty Tide's, and Ask's send once
  there is a question (no ring before it: a disc that can do nothing wears
  no mark). On the disc: a 1 pt blue hairline at rest, 1.5 pt when ready,
  and while it listens a 2 pt ring holding the warm light and the blue,
  drifting round at an uneven, water-like pace and cooling back to blue when
  the take ends; the bars inside still follow the microphone. One component
  draws it (`OceanDiscRing`). Malik chose it over §4's "never hard rims" as
  the 2.1 branding; PHILOSOPHY §4 now names it as the one rim. This replaces
  R3's "exactly three places" and its 1.5 / 3 pt strokes.
- The tab keeps `water.waves` (decision E as recommended). Currents stay
  below the column (decision G as recommended).
- **The user's words are New York as they type them** (`inputWords`): the
  composer, the bar's parked draft, the listening note, the edit sheet, a
  branch, the share sheet's note. Oryne's prompt in an empty field stays
  SF, drawn over the field.
- **Onboarding's headlines are their page's title** (`pageTitle`, New York
  34 medium): a page's name is a place's name.
- **"Resurfacing" is New York 17 italic everywhere**: on Tide and in the
  widget header in the warm ink, on the Lock Screen in the vibrant ink. The
  watch names its page "Today", in SF.
- **A thought's page steps its title like the stage**: 34 / 28 / 24 pt at
  40 and 80 characters by weighted length (`TitleLength`: an East Asian
  wide character counts 2, so a Chinese title steps where an English one
  twice as long does). A current's sheet is a sheet: New York 28, like
  Archived.
- **The ladder is 44 pt rows on Apple's curve**: every line a 44 pt row
  with an 8 pt floor inside, each level sized from Apple's own Dynamic Type
  ramp, so at no text size does it pass the stage's titles. Nearby shows
  three lines, on Tide and on the thought page.
- **`mist` is 58%** (was 50%): 4.5:1 on every ground a word stands on.
  `faint` never sets words. Increase Contrast brightens every ink, not only
  the ladder.
- **The picture stage** joins its title to its words at 12 pt, as the light
  does. An adaptive scrim keeps the label, the title and the words readable
  on a light picture; a dark picture looks as it did. At accessibility
  sizes the head stands right below the picture.
- **The empty Tide stands at the stage's place**: top left under the bar,
  in the Reading light, where the first thought will come back.
- **Widgets, the share sheet and the watch are in this alignment**
  (design/tokens/README.md, "Readability alignment"), which supersedes the
  scope line below.
- **Names as built.** The draft's tables keep their intent, not their
  names. In the JSON, `light/warm` is `accent.stageLight`, `light/cool` is
  `accent.ring`, `ink/litWarm` is `ink.stageInk` and `stageWords`,
  `ink/litCool` is `ink.coolInk`, `coolWords` and `depthInk0` to
  `depthInk4`, and `control/ringStroke` is `size.ringStroke`,
  `ringHairline` and `ringStrokeListening`. `tileTitle` stays SF 16 medium
  for someone else's title; a thought's name on a tile is `cardTitle`, New
  York 17. A new line on Tide rises 16 pt, not 18. The Motion table's
  Release row was not built.

Wireframes: `design/identity-2.1-wireframes.html`, first section ("The
direction: stage and column"), beside this file on branch
`am/tide-stage-round4`, uncommitted. Open it in Safari:
New York only renders in WebKit.

In scope: tokens, `Oryne/DesignSystem/`, Tide, the thought page, the
Library, the empty Tide, the capture disc and its toast, and the named
changes to information architecture and motion listed under "What this
asks CLAUDE.md to allow". Out of scope: the one gesture, the three tabs,
Liquid Glass on the floating layer, Calm Accessibility Mode and Reduce
Motion as switches, the Ocean field's layout engine, widgets beyond one
label color.

## Why draft 1 was not enough

Draft 1 found three real problems in 2.0:

1. **One axis.** Every ink and surface is white at an opacity on five
   grays. With a text-only thought, Tide is gray type on black.
2. **The icon owns a mark the app never repeats.** The rim-lit ring
   appears once, on the Home Screen.
3. **The serif is on the wrong side.** New York dresses Oryne's chrome
   while the user's words are SF at the meta line's weight.

It answered them with tokens: brighter fills, a candle color, a serif
swap. On the wireframes it read as the same dark notes app in other
fonts, because the skeleton was unchanged: a title, a list, a bar.
Malik: "I still didn't see the bone of my product." And the candle color
as ink read as cream type on gray.

The bone is an axis Oryne already describes in words and never draws.
Tide is the surface and the Library is the depth (phone-refocus SPEC,
decision 5); a thought sinks, and one day it comes back up; "returning
is the product" (PHILOSOPHY §6). 2.1 draws that vertical axis on every
screen. The tokens follow from it.

## Four rules

Every change below serves one of these. A change that serves none does
not belong in 2.1.

**R1. Light from above, depth below.** Every page has one light at the
top and water that darkens downward. Where a thing stands on that axis
says how near it is: the surface is now, the depth is the past.

**R2. Warm light means it returned; cool light means you reached for
it.** Today's resurfacing thought stands in a warm light: it came to you.
A thought you open stands in a cool light, the ring's color: you went to
it. The Library has no stage light at all: it is the depth. Warmth lives
in the light, never in the words. The only warm ink in the app is the
word "Resurfacing" and the ring while it listens.
*(As built, 2026-11-03: the cool light is retired. Every page stands in
the warm light; depth is how much of it reaches the page. See "As built"
above.)*

**R3. One mark: the ring.** The icon's ring is the only shape Oryne owns.
It appears in exactly three places: the capture disc, the toast that
follows a capture (the same ring, after it sinks), and the empty Tide.
Not on the tab bar (decision E).

**R4. Serif is the user's; sans is Oryne's.** New York sets a thought's
name and the user's own words. SF sets everything Oryne or anyone else
says: page names, labels, controls, meta, answers, a summary, a link's
description. Behind it is PHILOSOPHY §2: nothing should be "authored by
us and dressed as theirs".

## The screens

Sizes are at the default text size on a 402 pt wide phone with the
16 pt gutter. Colors are the tokens below.

### Tide: a stage over the water column

Top to bottom:

- **No large title.** The tab bar already says Tide; the page's first
  line is today's thought. The gear stays in the navigation bar, top
  right.
- **The stage.** The warm light falls from the top center (`light/warm`,
  an ellipse 70% of the width by 46% of the height, opacity 34% at the
  top, 12% at 55% of its reach, gone at 88%). It replaces 2.0's lamp,
  which stood high on the left. Centered in it, all text centered:
  - "Resurfacing": `stageLabel`, New York 19 italic, `accent/warm`.
  - The title: `resurfacingTitle`, New York 46 medium, `ink/litWarm`,
    up to three lines.
  - The words: `thoughtBody`, New York 19, `ink/litWarm` at 84%, up to
    three lines. Only if the user wrote or said them (R4); a summary
    shows nothing here.
  - The picture, if the thought has one, at `hero` height as in 2.0.
  - Nearby, Let it rest, and the play button for a voice thought: the
    same buttons as 2.0, centered in one row. Nearby opens its
    neighbours as depth lines from level 2 (below) between the stage
    and the column.
  - No meta line. When and where the thought came from is one tap away,
    on the thought page and in the Library (PHILOSOPHY §4: reachable by
    a tap or the Library).
- **The column.** The five newest thoughts, today's resurfacing one
  aside, exactly the set "Drifted in" shows in 2.0 (starter examples in
  a new Ocean). Titles only, centered, on the depth ladder: the newest
  sits just under the surface, each older one smaller and dimmer. No
  label, no cards, no pictures, no dates. Tapping a title opens the
  thought; the long-press menu (Archive, Delete) stays on every row.
- **Currents** stay below the column, as 2.0 has them, with their label
  in the new SF face. (Not drawn in the wireframes; decision G.)

**The capture moment.** Hold the disc and the ring thickens and warms;
let go and it sinks into the bar, the toast comes up with the same ring
cooling to the ring color, and the new thought enters the column just
under the surface while every older title steps one level deeper and
the oldest goes dark. Choreography under Motion.

### The thought page

- *(Retired 2026-11-03: the page stands in the Reading light at 70%, see
  "As built".)* **Cool light** from the top center (`light/cool`, an ellipse 90% of
  the width by 40% of the height, 16% at the top, 5% at 55%, gone at
  88%) over a sheet whose water darkens to `abyss`.
- The meta line stays where 2.0 has it, above the title. (The
  wireframe left it out to show the light; it stays.)
- The title: `subjectTitle`, New York 32 medium, `ink/litCool`. Left
  aligned: this page is for reading.
- The words: `thoughtBody`, New York 19 on a 28 pt line, `ink/litCool`
  at 84%, under the same R4 source rule. A summary or a link's
  description, when shown, is SF `body` in `text`.
- "Nearby": `sectionLabel` (SF) in `mist`, 5.3:1, then the neighbours
  as depth lines from level 2 (17, 15, 14), left aligned, so none
  outranks the page's own words. Summarize stays where it is.
- No tiles.

### The Library: the depth

- **No stage light.** A faint cool surface far above (`light/cool` at
  7%, reaching 22% of the height), and the water darkens as you scroll,
  `deep` to near `abyss`.
- The page title: `pageTitle`, SF 34 semibold, the system's own large
  title.
- **The one place with tiles**, because scanning is the job. Cards on
  `surface/fill` (white 11%). Title `tileTitle`, New York 17. Preview
  two lines by source (R4): the user's words in New York 15 `text`;
  a summary or a link's description in SF `secondary` `text`. Meta SF 13
  `mist`: the dates live here.

### Empty Tide

The stage with nobody on it. The warm light at about two thirds of
Tide's (22% at the top, 8% at 55%), the ring at `ringHero` (48 pt,
1.5 pt stroke, `accent/ring`) where the first thought will come back,
and the page's existing copy under it: "The Ocean is still" in
`statement`, its second line in `secondary` `mist`. No new strings.

### Ask and onboarding (not drawn)

They follow the rules without new layout. Ask is reached for: the faint
cool light of the Library, and its two lines in `glowWarm` go to `foam`
and `mist`. Onboarding keeps a warm light only on the page that shows a
thought returning; the other pages take the cool one or none.

## The depth ladder

One ladder for every list of thoughts that is not a grid: Tide's column,
Nearby on Tide, Nearby on the thought page. New York regular, sizes
relative to `body`.

Tide's column starts at level 0. **Nearby starts at level 2** (17, 15,
14 for its three neighbours), on Tide and on the thought page: a
neighbour never outranks the words of the thought it sits under
(`thoughtBody`, 19). Decided by Malik, 2026-10-31.

| Level | Size | Ink (`ink/litCool` at) | Row | Contrast on Tide | Nearby, thought page |
|---|---|---|---|---|---|
| 0, newest | 21 | 90% | 44 pt (an 8 pt floor) | 14.7:1 | not used |
| 1 | 19 | 76% | 44 pt (an 8 pt floor) | 10.6:1 | not used |
| 2 | 17 | 64% | 44 pt (an 8 pt floor) | 7.7:1 | 7.6:1 |
| 3 | 15 | 56% | 44 pt (an 8 pt floor) | 6.1:1 | 6.0:1 |
| 4, oldest shown | 14 | 52% | 44 pt (an 8 pt floor) | 5.3:1 | 5.3:1 |
| leaving | 14, the oldest's own | fading to 0% | 44 pt, while it fades | (only while it fades) | |

**The floor is 4.5:1 for every row a person can tap.** The wireframe
used 78 / 56 / 38 / 24 / 13%; the last three measure 3.2, 1.9 and
1.3:1 and fail. Size and spacing now carry most of the depth;
brightness carries the rest, above the floor. With Increase Contrast on,
every row is `foam` and depth is size alone.

Contrast is computed from the wireframe's gradients at each row's
position; re-measure from device screenshots.

## Where this differs from the wireframes

The wireframes show the direction; this file is the contract. Where they
disagree, this file wins, for these reasons:

- **The depth ladder** has a 4.5:1 floor (above); the wireframe's deepest
  rows fail it.
- **The thought page keeps its meta line.** The wireframe left it out.
- **"Nearby" is `mist`.** The wireframe's white 34% measures 3.1:1.
- **Fills are 11%**, not the 10% drawn: 10% misses 1.3:1.
- **The stage's words are 19 pt**, one `thoughtBody` with the thought
  page, not the 20 pt drawn. One point is not worth a second token.
- **Not drawn**: the stage's buttons (Nearby, Let it rest, play), a
  resurfacing thought with a picture, Currents, Ask, onboarding. They
  follow the rules as written here.

## Token changes

Paths are the JSON's. "Now" is 2.0.

### form/type

| Role | Now | 2.1 | Rule |
|---|---|---|---|
| `resurfacingTitle` | New York 32 regular | New York 46 medium, metrics of largeTitle | R1, R2. The one lit thought is the biggest type in the app. |
| `thoughtBody` (new) | none | New York 19 regular, 28 pt line, metrics of body | R4. The user's words on the stage and on the thought page. `body` stays SF for Oryne's words. |
| `stageLabel` (new) | none | New York 19 italic | R2. "Resurfacing", the sea's one spoken word (decision A). |
| `depth/0` … `depth/4` (new) | none | New York 21 / 19 / 17 / 15 / 14 regular, metrics of body | R1. The depth ladder. |
| `subjectTitle` | New York 28 regular | New York 32 medium, **thoughts and currents only** | R4. Ask's question moves to `statement`. |
| `tileTitle` | SF 16 medium | New York 17 regular | R4. A card's title is the thought's name. |
| `pageTitle` | New York 40 | SF 34 semibold (the system large title) | R4, decision B. Ask and the Library; Tide has none. |
| `sectionLabel` | New York 21 | SF 13 medium, tracking 0.4 | R4. Nearby, Currents. |
| `statement` | SF 22 medium | unchanged; also Ask's question | R4. |
| everything else | | unchanged | |

### material/color

| Role | Now | 2.1 | Rule |
|---|---|---|---|
| `light/warm` (new) | none | 1.00 / 0.70 / 0.41 | R2. The stage light, as light only (opacity gradients), never as ink. |
| `light/cool` (new) | none | = `accent/ring` | R2. The light of a thought you reached for. |
| `accent/ring` (new) | none | 0.68 / 0.78 / 0.92, sampled from `icon-1024.png`'s rim | R3, decision C. The ring at rest, and the cool light. 11.2:1 on `deep`. |
| `accent/warm` (new) | none | 1.00 / 0.77 / 0.55 | R2. The two warm inks: "Resurfacing" (7.5:1 on the lit stage) and the ring while listening. |
| `ink/litWarm` (new) | none | 1.00 / 0.97 / 0.93 | R2. White in the warm light. Not cream: the light tints it, the ink stays white. 12.7:1 at the brightest point under the title. |
| `ink/litCool` (new) | none | 0.95 / 0.96 / 1.00 | R2. White in the cool light and in the water: the thought page and every depth line. |
| `accent/glowWarm` | 0.95 / 0.93 / 0.88 | **retired** | Each use moves: the lamp to `light/warm`; Tide's warm label and the widget header to `accent/warm`; Ask's lines and the Library's meta to `foam` / `mist`; Ask's glow to `light/cool`; the Library's relatedness glow on `NodeCard` to `accent/ring` (you reached for it); onboarding per the screen notes. |
| `surface/fill` | white 5.5% | white 11% | 1.32:1 on `deep`; 10% measured 1.28:1 and missed the 1.3 target. |
| `surface/raised` | white 8% | white 14% | Keeps the ladder fill < raised < selected. |
| `surface/selected` | white 12% | white 19% | Same. |
| `surface/pressedLift` | white 4% | white 6% | Visible on the new fills. |
| `surface/separator` | = raised | = raised (14%) | Follows. |
| `water/*` | | unchanged | The water is right; nothing stood on it. |
| `ink/*` | | unchanged | `mist` on an 11% tile is 4.8:1. |

New primitives: white 6, 11, 14, 19.

### form/size, form/control

| Role | 2.1 | Rule |
|---|---|---|
| `control/ringStroke` | 1.5 pt at rest, 3 pt while listening | R3. |
| `size/ringHero` | 48, the empty Tide's ring, where `glyphHero` sat | R3. |

### motion

No new curves or durations. The new choreography below is art-directed
from the existing tokens and marked `// art-directed` in code.

## Motion (new; needs Malik's explicit go-ahead)

| Moment | What moves | Token | Reduce Motion, Calm |
|---|---|---|---|
| Hold the disc | The ring's stroke 1.5 → 3 pt and `accent/ring` → `accent/warm`; its brightness follows the microphone level in place of the level bars | `touch` | The stroke and color still swap (a state); the brightness holds still. |
| Release | The ring contracts and sinks 16 pt as it fades; the disc returns to rest | `lift`, then `touch` | A plain fade, `quick`. |
| The toast | Its leading ring (`metaIcon`, 14 pt) arrives warm and cools to `accent/ring` | `lift`, 120 ms after the toast | Arrives cool. |
| A new thought on Tide | It enters level 0 from 18 pt above, fading in; every other title steps one level down in size, ink and spacing; the one past level 4 fades out and leaves | entry `gentle`; steps `standard` | Titles take their new places at once; the new one fades in, `quick`. |
| Let it rest | Unchanged from 2.0. The lamp's dim and lift now act on the stage light. | as 2.0 | as 2.0 |

PHILOSOPHY §4 test, freeze every animation: the column still reads
newest on top, the light still says which thought came back, the toast
still says the thought is in. Nothing is carried by motion alone.

The ring is a 1.5 pt stroke the icon already owns, drawn without blur,
glow or halo (§4: "never halos, luminous cores, or hard rims"). If it
reads as a lit rim on device, it is wrong.

## What this asks CLAUDE.md to allow

`CLAUDE.md` protects these; this spec names them, and each needs Malik's
yes before code.

- **`Oryne/DesignSystem/`**: tokens, `PageBackground`, `NodeCard`, a new
  depth list component, the large title appearance.
- **Information architecture on Tide**: the large title goes; "Drifted
  in" becomes the column (same five thoughts, but titles only: no cards,
  pictures, dates or label); the resurfacing block is centered and loses
  its meta line.
- **Motion**: the five rows above.

Nothing else in the flows changes: every tap, menu and sheet goes where
it goes in 2.0.

## What this touches in code

Expected files:

- `design/tokens/oryne.tokens.json` (every row above), then the
  generator into `OceanTokens.swift`.
- `OceanControls.swift`: `PageBackground` takes a light (warm stage,
  cool, faint cool, none) instead of one lamp.
- `OceanType.swift`: `applyLargeTitleAppearance` in SF.
- A new `DepthList.swift` in `DesignSystem/`: the ladder, used by Tide's
  column and both Nearby lists.
- `OceanFieldView.swift`: the stage, the column, no large title, the
  column's choreography.
- `ExpandedNodeView.swift`: the cool light, the type, Nearby as a depth
  list, `sectionTitle` in SF.
- `LibraryView.swift`, `NodeCard.swift`: the light, the card's faces,
  the meta and glow colors.
- `CaptureHoldButton.swift`, `CaptureBar.swift`,
  `FastCaptureSessionView.swift`: the ring, its listening and its
  release.
- `CaptureToast.swift`: the leading ring.
- `AskView.swift`, `OceanOnboardingView.swift`,
  `OceanWidgets/OceanWidgetHeader.swift`: the retired `glowWarm`.
- `Shared/Models/Node.swift`: whether a thought's preview is the user's
  own words (their text or transcript) or someone else's (a summary, a
  link's description), next to `snippet`, with a test. Anything in
  `Shared/` runs the test suite.

No new user-facing strings. No schema change.

## Verification

1. **The gray test.** Tide with a text-only resurfacing thought and no
   pictures in the column. Pass: it is recognizably Oryne (a lit stage,
   a sinking column, the ring in the bar). Fail: gray type on black.
2. **The axis test.** Tide, a thought page and the Library side by side,
   text blurred. Pass: a stranger can say which thought came back, which
   one someone opened, and which screen is the archive.
3. **Contrast.** Sample pixels from device screenshots. Every word
   ≥ 4.5:1 against the ground at its own position, including the
   deepest depth line; a tile ≥ 1.3:1 against its ground; the ring
   ≥ 3:1. Include the widget's "Resurfacing" header in `accent/warm`
   on the widget's own background, which this file does not measure.
4. **Whose words.** Cover every string on Tide, the thought page and
   the Library. Serif is a thought's name or the user's words; sans is
   everyone else; no exception without a line in this file.
5. **Ring count.** The ring appears in four places plus the icon: the
   capture disc and Ask's send, the capture toast, the empty Tide.
6. **Dynamic Type** at xxxLarge and AX3: the 34 / 28 / 24 pt titles wrap
   without clipping; the stage's titles stay above the ladder, and its
   words above Nearby's first line, at every text size
   (`generate.py --check` proves the order at all twelve); the ring does
   not scale with type. **Increase Contrast**: every depth line at
   `foam`.
7. **Reduce Motion and Calm Accessibility Mode**: no steps in the
   column, no breathing ring, the warm/cool swap still shows.
8. **The freeze test** (§4), as above.
9. Rebuild the App Store set and the hero. Finding 1 is the check: the
   screens read without the sunset.

## Decisions

Settled on 2026-10-30 by picking the direction:

- **A. Section labels.** One exception: "Resurfacing" stays New York
  italic, now in `accent/warm`, on the stage. Every other label is SF.
- **B. Page titles.** Strict: SF 34 semibold on Ask and the Library;
  none on Tide.
- **C. Ring color.** Sampled from the icon: 0.68 / 0.78 / 0.92.
- **D. Fills.** Tide has no tiles in its stage or column; the Library
  keeps them at 11%.
- The candle `glowWarm` as ink is rejected; warmth is light.

Settled on 2026-10-31:

- **Nearby on the ladder.** Nearby starts at level 2 (17 / 15 / 14), so
  a neighbour never outranks the thought's own words.

Open (Malik's):

- **E. The tab glyph.** Draft 1 put the ring on Tide's tab. In the
  wireframes it reads as a generic circle, and it shares the bottom band
  of the screen with the capture disc: two plain circles where only one
  is the button. Recommendation: keep `water.waves`, and keep the ring
  to three places (R3).
- **F. Names and words.** Most titles are drafted by Oryne and edited by
  the user only sometimes. Recommendation: a title is the name of the
  user's thought and always wears New York, whoever drafted it, since it
  is theirs to change; the words under it wear New York only when the
  user wrote or said them. The alternative (sans for a title Oryne
  drafted) would set one list in two faces at random.
- **G. Currents on Tide.** Not drawn. Recommendation: keep them below
  the column, unchanged in 2.1 apart from the label face, and look again
  once the stage is on a device.
- **H. Motion.** The five rows under Motion are new choreography; the
  column's steps above all. Yes or no per row.
