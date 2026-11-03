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
   tokens. Art-directed moments (each page's light, the picture stage's
   bleed, the sinking words, the microphone bars) stay in their views,
   marked `// art-directed`, which the lint skips.
6. **Native first.** Controls are 44 pt, the system's own; the gutter is the
   system's layout margin; type roles are Dynamic Type text styles where a
   system style exists, and where the size is ours, sized at every text size
   from Apple's own ramp between the two styles around it; glass is the
   system's Liquid Glass, on the floating layer only.

## The three facets

### Form

| Group | Swift | Roles |
|---|---|---|
| space | `OceanSpacing` | hairline 2, tight 4, snug 6, gap 8, item 12, inset 16, block 24, group 32, section 40; `insetCompact` = item, `afterLabel` = gap, `controlInset` = inset; `gutter` (16 or 20, computed in the app from the window width) |
| radius | `OceanRadius` | card 20, media 14, field = media, thumbnail 10, composer 24, icon 4; anything up to a control's height is a capsule |
| size | `OceanSize` | metaIcon 14, glyphSlot 18, removeTarget 32, thumbnail 44, pictureTile 64, banner 120, hero 200 (the share sheet's picture), stage 360, stageLink 300, depthThumb 36, readableWidth 560 (the reading column, growing with body), ringHero 48, ringStroke 1.5, ringHairline 1 (the disc at rest), ringStrokeListening 2 |
| control | `OceanControlSize` | height 44, bar 56, toast 48 (a minimum: a two-line toast grows), discInset 6 (its own primitive, so the folded composer's 6 + 44 + 6 never follows a retune of snug) |
| type | `OceanType`, `OceanWatchType` | see below |

Spacing contracts. One rule per relationship, measured between what you
see (a tile's or a field's edge, a line's text), never to an empty frame.
Things that belong together sit tight; groups sit far apart; the contrast
between the two is the hierarchy.

| Relationship | Space |
|---|---|
| A label to what it names | `afterLabel` (8), to the tile's or the field's edge or the paragraph's first line. A list of 44 pt rows sits right under its label (0): each row's own slack is the gap. A label row that carries a 44 pt control uses that control's slack |
| A header to its first group, on a page or a sheet | `block` (24) |
| A page's sections (Tide, a thought's page, Ask) | `section` (40), between what you see: where a 44 pt row starts or ends a section, its slack comes off the 40 (`OceanTextRole.rowSlack`) |
| Groups inside the Library's lists (time sections, currents, Archived) | `group` (32), tighter than a page's sections, so a list reads as one |
| Groups in a sheet; blocks inside one section | `block` (24) |
| A title to its words | `item` (12) on a page, a stage or a sheet; `snug` (6) inside a tile or a widget |
| Words to their actions | `inset` (16) on a page or a sheet; `gap` (8) inside a card |
| Buttons or chips in a row | `gap` (8). A title beside its own action, and tools on the floating layer, `item` (12) |
| A glyph to the words beside it | `snug` (6), everywhere |
| 44 pt line rows | spacing 0, with a `gap` floor inside the 44, so a line that wraps never touches the next; tiles sit `item` apart |
| Inside | a tile `inset` (16); a compact card or a field `insetCompact` (12); a 64 pt attachment tile `gap` (8); a capsule's or a Link's words keep a `tight` (4) floor above and below inside its 44 |
| A page's first content | `gap` (8) under the bar when the page has no title (Tide, a thought's page, the share sheet); a picture stage from the screen's top edge; `block` (24) under a title |
| A sheet's top | `OceanSheetHeader`'s: `gap` (8), the grabber (5), `item` (12), then the title row, so every sheet's name lands 26 to 30 below its edge |
| An empty state | left-aligned at the gutter where the first content would stand: a mark, `inset`, the headline, `gap`, the line, `inset`, the action (on the watch they stay centered: one focus per screen) |

A distance something moves (a new line's rise, a toast's rise, the caught
words' sink, the let-go sink, a card surfacing, the disc's touch reach) is
its own `// art-directed` constant at the value it was tuned to, never a
spacing token, so retuning space never moves motion.

Type roles. New York is the user's: a thought's name, their own words
(`Node.ownWords`: what they wrote or said, never a summary or a site's
words), a live take's words, and their words as they type them. It also
names places (a page's or a sheet's title, in New York medium, so a place
is named as carefully as the thought on Tide) and says the one word
Resurfacing, italic in the warm ink (design/identity-2.1.md, R4). SF is
Oryne's: labels, controls, meta, answers, a summary, a site's words, and
the prompt in an empty field.

A text role is an `OceanTextRole` (`Oryne/DesignSystem/OceanTextRole.swift`,
the roles generated into `OceanTokens.swift`): a face, a size, a weight, the
leading between its lines and its tracking, together. `.oceanText(_:)`
always sets all three of font, leading and tracking (a 0 resets what a
parent set), so no call site can take the font and drop the leading; the
lint fails on a hand-set `.lineSpacing`, `.tracking` or `.kerning`, and on a
face (`design: .serif`) set in a view. A role meets Dynamic Type in one of
three ways (`com.oryne.font.scale`):

- **native**: a system text style. The system sizes it, a
  `.dynamicTypeSize(...)` cap holds, and a live Text Size change follows.
- **curve**: a size of ours (24, 21, 19, 14, the 48 pt mark), sized at each
  of the twelve text sizes from Apple's own ramp (`com.oryne.dynamicType`),
  between the two styles around it or in proportion to one, so it keeps its
  rank at every size.
- **fixed**: never scales.

In the table, **extra** is the leading added at the default size (Large),
scaled with the role's size at the others so its ratio holds, and **line**
is the pitch: 1.193 times the size, plus the extra (New York and SF alike).
No line is shorter than its text style's own.

| Role | Face | Extra → line | Dynamic Type | Sets |
|---|---|---|---|---|
| pageTitle | New York 34 medium | 0 → 40.6 | native largeTitle | A place's name: the Library's title, Ask's large title, each onboarding page's headline |
| sheetTitle | New York 28 medium | 0 → 33.4 | native title1 | A sheet's name: Edit, Grow a branch, Move, Merge, Archived, a current's sheet, the onboarding setup step |
| navigationTitle | New York 17 medium | | fixed, like the system's inline titles | An inline bar's title: Ask folded, the share sheet (the bar's appearance); Settings, What Oryne knows about you (oceanInlineTitle) |
| thoughtTitle / thoughtTitleLong / thoughtTitleLongest | New York 34 / 28 / 24 medium | 0 → 40.6 / 33.4 / 28.6 | native largeTitle / native title1 / curve title2 to title1 | A thought's name as the subject, on Tide's stage and on its own page, by weighted length: up to 40, up to 80, longer (`OceanType.thoughtTitle(for:)`). Long is the large widget's title, Longest the medium widget's |
| stageLabel | New York 17 italic | 0 → 20.3 | native body | Resurfacing: on Tide, in the widget header, on the Lock Screen |
| thoughtBody | New York 19 | +5 → 27.7 (1.46) | curve body to title3 (step depth1) | The user's words on Tide and on their page; the transcript, folded or full |
| whisperWords | New York 22 | +8 → 34.2 (1.56) | native title2 | The live take's words, in a six-line window |
| inputWords | New York 17 | +4 → 24.3 (1.43) | native body (step depth2) | The user's words as they type them: the composer, the bar's parked draft, the listening note, Edit's title, words and note, a branch's words, the share sheet's note, `TranscriptEditor` |
| cardTitle | New York 17 | +2 → 22.3 (1.31) | native body (step depth2) | A thought's or a current's name on a tile, a row, a choice or a line: Library cards and rows, Branches, a current's and Archived's rows, Move and Merge choices, Tide's current tiles, Ask's sources, the branch parent, the small and Lock Screen widgets |
| cardWords | New York 15 | +4 → 21.9 (1.46) | native subheadline (step depth3) | The user's words previewed on a card or a widget |
| currentName | New York 21 | 0 → 25.1 | curve title3 to title2 (step depth0) | A current heading its rows in the Library; Adrift; the Archived row's word |
| depth0 to depth4 | New York 21 / 19 / 17 / 15 / 14 | 0 | curve title3 to title2 / curve body to title3 / native body / native subheadline / curve footnote to subheadline | The depth ladder; Nearby starts at depth2. depth3 also names a thought under a current's name on Tide's tiles |
| statement | SF 22 medium | +3 → 29.2 (1.33) | native title2 | Oryne's one line: Ask's question, the empty Tide's line, Listening, Quick Capture's Catch a thought, an empty widget's line |
| body | SF 17 | +4 → 24.3 (1.43) | native body | Oryne's words read whole: a summary, a page's description, the answer, Beyond your Ocean, Ask's opening line and samples, onboarding paragraphs and the setup line, shared text. Also Oryne's prompts in fields, the tools you type into (Ask, search, a theme, a link), the + panel's rows, New current |
| secondary | SF 15 | +3.5 → 21.4 (1.43) | native subheadline | A preview cut at two to four lines, an empty page's line, Ask's reading and status lines, a count after a name, a widget's tagline; and every sentence someone must read to act: a failure, a refusal, a privacy disclosure, a consequence, provenance |
| tileTitle | SF 16 medium | +2 → 21.1 (1.32) | native callout | Someone else's title on a tile: a link's page title, a plain link's address; Quick Capture's Lock Screen line |
| control / controlStrong | SF 15 medium / semibold | +2.5 → 20.4 (1.36) | native subheadline | Secondary buttons and chips, quiet Links, the toast's message, the focus chip, the transcript's language menu, the onboarding toggle, widget capsules / Primary buttons, accent Links |
| sectionLabel | SF 13 medium, tracked 0.4 | +2.5 → 18.0 (1.39) | native footnote | Every label (`OceanSectionLabel`): a section, a block, a field's name; a Settings header, the share sheet's Add a note, a Lock Screen label other than Resurfacing |
| meta | SF 13 | +2.5 → 18.0 | native footnote | Meta lines, domains, a status inside a card, captions, quiet guidance (a hint, the edited-transcript note, Flows into, setup notes), the composer's captions, a widget's meta |
| wordmark | SF 17 medium, tracked 2.5 | 0 | native headline | Oryne in the onboarding bar |
| glyphHero | SF Symbols 48 | 0 | curve, in proportion to largeTitle | The onboarding setup step's mark, a text role so it can scale |

Glyph roles are plain `Font`s (`kind: glyph`):

| Role | Face | Sets |
|---|---|---|
| glyph | SF 17 regular, fixed | A symbol in a 44 pt cell: a tool, an Icon button, a field's leading glyph |
| glyphStrong | SF 17 semibold, fixed | The send arrows |
| glyphDisclosure | SF 13 semibold, native footnote | A chevron or a mark that leads or ends a row in content; the composer tiles' glyphs |
| glyphMeta | SF 11 regular, native caption2 | The kind glyph leading a meta line |
| glyphSmall | SF 11 semibold, native caption2 | A ✕ or a chevron inside a control: a chip's ✕, the remove badge's ✕, a menu's chevron, All currents' chevron |
| glyphLarge | SF 20 regular, native title3 | A symbol standing in for a picture |
| badge | SF 11 bold, fixed | The +N count on a picture, and nothing else |

A glyph inside a line of words takes that line's text role, usually at
`.imageScale(.small)`, so it scales with the words. Its fixed-width slot
scales too, through `@ScaledMetric` at the call site, never through the
token (the toast's ring keeps `metaIcon` and never scales).

The watch has its own roles (`OceanWatchType`, applied with `.oceanText(_:)`
too) on watchOS's text styles, because watchOS sizes its styles in another
order than iOS. Sizes are the 44 to 49 mm watch's at its default text size;
the 40 to 42 mm watch's are in brackets. The wrist then reads title 20,
words 17, labels and meta 14: the phone's own order.

| Role | Face | Extra | Style | Sets |
|---|---|---|---|---|
| title | New York 20 [19] medium | 0 | title3 | Today's thought; a thought's name on its page |
| serif | New York 17 [16] | +3 | body | A Recent row's name; the user's own words |
| body | SF 17 [16] | +3 | body | A summary under its label; a notice or an instruction that is the screen's message; a catch time standing in for a name |
| strong | SF 17 [16] medium | 0 | body | Caught, Undo, the complication's line, the play glyph |
| label | SF 14 [13] medium, tracked 0.4 | 0 | footnote | Today, Summary |
| meta | SF 14 [13] | +2 | footnote | Status lines, a Recent row's meta, Waiting, Continues on iPhone, Getting audio, Listening, the player's time (monospaced digits) |
| timer | SF 20 [19] | 0 | title3 | The recording timer (monospaced digits) |

Reading sizes. SF words are 13 or more (meta, sectionLabel), and a sentence
someone must act on is 15 (secondary). New York reading text is 15 or more
(cardWords); 14 is depth4 alone, a one-line title a person taps. 11 is for
glyphs and the +N badge only; on the watch the floor is footnote, 14 [13].
No reading text shrinks to fit: a widget's title and the empty widget's
line may go to 0.9 (`minimumScaleFactor`), nothing else (the lint fails
under it), and a widget drops a line (`ViewThatFits`) before it shrinks
one.

In code:

- `.oceanText(role)` on any view. Only where a `Text` must carry its own
  font does a view call `role.font(at: typeSize)`: the depth ladder, so a
  sinking line's step still interpolates. A text view (a vertical
  `TextField`, a `TextEditor`) sets its role with `.oceanFieldText(role)`
  instead, which takes off the font's own leading that UIKit keeps and
  SwiftUI's `Text` drops, so typed lines keep the role's pitch; its line and
  its box counted in lines are `role.fieldLineHeight(at:)` and
  `role.fieldHeight(ofLines:at:)`.
- `.oceanLineLimit(n)` gives n lines at standard sizes and twice as many at
  accessibility sizes; `.oceanLineLimit(n, accessibility: m)` sets m, and
  nil there means no limit (the table below).
- `role.rowSlack(at:)` is the space a 44 pt row leaves above or below one
  line of the role, never under `gap`: how a page measures its 40 between
  what you see. `role.height(ofLines:at:)` sizes a box of `Text` counted in
  lines (the live words' window).
- `role.uiFont()` serves UIKit: `OceanType.applyNavigationTitleAppearance()`
  sets the navigation bar's large title in pageTitle and its inline title in
  navigationTitle.
- `OceanType.thoughtTitle(for:)` picks the stage's step by
  `TitleLength.weighted` (an East Asian wide or fullwidth character counts
  2) against `thoughtTitleSteps` (40 and 80, `com.oryne.steps` in the JSON).
- `OceanSectionLabel` draws every label. `.oceanPrompt(_:when:)` draws
  Oryne's SF prompt over a field that holds the user's New York words (the
  field passes an empty prompt; its title stays the VoiceOver label).
  `.oceanReadableColumn()` holds a page's words to `readableWidth`.

| Text | Lines | At accessibility sizes |
|---|---|---|
| The stage's title, in the light / on a picture | 4 / 3 | no limit (on a picture the head stands below it) |
| The stage's words, in the light / on a picture | 4 / 3 | 6 / 4 |
| A folded transcript | 3 | 3 (the fold) |
| Depth lines; current names; Move and Merge names; Tide's tile lines | 1 | 2 |
| Card, row and source titles; a link card's title | 2 | 4 |
| Card words, snippets, Tide's link description | 2 | 3 |
| Sheet titles | 2 | 4 |
| The Library's title | 1 | 2 |
| The focus chip, a plain link's address | 1 | 2 |
| Meta lines (NodeMeta) | 1 | no limit: one sentence that wraps |
| The toast | 2 | 3 |
| The composer's captions | 2 | 2 (the bar's 44 pt row) |
| A thought page's title and words, summaries, answers, questions, shared text, notices, failures, privacy lines | no limit | no limit |

The scale keeps its order at every text size, and the generator proves it
on every run: each `com.oryne.order` chain (the stage's titles down the
ladder; the smallest title over the stage's words over Nearby's first line;
the live words over the stage's words; a place's title down to meta; a
current's name over a card's title over its words) never inverts at any of
the twelve sizes and steps down at Large, and each `com.oryne.step` role
(thoughtBody, inputWords, cardTitle, cardWords, currentName) is its ladder
level in all but leading. A curve whose two styles do not bracket its size,
or a role on the retired `metrics` scale, stops the generator too.

### Material

| Group | Swift | Roles |
|---|---|---|
| color.water | `OceanTheme` | abyss, deep, mid, current, surface; waterTop and waterMiddle, which with abyss are every page's water, darkening downward |
| color.ink | `OceanTheme` | foam 92%, text 66%, mist 58%, faint 26%, onAccent, onPhoto; stageInk and stageWords (white in the warm light, on every phone page), coolInk and coolWords (white on the watch, where no lamp falls), depthInk0 to depthInk4 (the ladder, 90 to 52%, each at 4.5:1 or more) |
| color.surface | `OceanTheme` | fill 11%, raised 14%, pressedLift 6%, selected 19%, glassTint 18%, separator, scrim, photoScrim |
| color.accent | `OceanTheme` | accent, switchOn, warm (the one warm ink), stageLight (the Reading light), warmGlint (where the light catches the listening ring), ring (the icon's rim: the ring, a mark and never a light) |
| shadow | `OceanShadow` | tile, control, inset, bar, text (`.oceanShadow(_:)`) |

Inks for words. foam sets titles where no light ink applies, a control's
words, the user's typed words, Ask's question and answer, shared text, and
a notice that is a screen's whole message. text is reading a step below,
and every sentence someone must read (a failure, a refusal, a privacy
disclosure, provenance, a consequence). mist is the quiet ink: meta,
labels, counts, prompts, quiet guidance, status lines, quiet Links, tool,
state and disclosure glyphs, disabled words; it clears 4.5:1 on every ground
a word stands on, the warm light's tiles included. faint is never words and
never a glyph that means something: only the drawn grabber and the
segmented switch's dividers. warm sets the word Resurfacing, the listening
ring and the capture toast's ring as it arrives, never a glyph. No word
takes an opacity; the one exception, art-directed, is the watch's timer
dimming in Always On. foam, text, mist and faint step up with Increase
Contrast, to 100, 80, 72 and 40%, and stageWords and coolWords to their
titles' inks, 100% (`com.oryne.contrast`, through `OceanTheme.contrasting`).

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
| Primary button `.oceanPrimary` | capsule, 44 minimum with a tight floor above and below the words, controlInset, controlStrong | glass with glassTint, foam ink (plain glass, mist when disabled) | touch |
| Secondary button `.oceanSecondary` | capsule, 44 minimum with a tight floor, controlInset, control | raised surface, foam (mist when disabled); `selected` → selected surface | touch |
| Icon button `.oceanIcon` | 44 circle, glyph | glass, foam | touch |
| Link button `.oceanLink` | 44 target with a tight floor, controlStrong (or control when `.quiet`); a Menu wears it through `.menuStyle(.button).buttonStyle(.oceanLink(.quiet))` | no surface; accent (or mist), mist when disabled | touch |
| Tile (`NodeCard`, `NodeRow`, a choice) | card radius, inset, cardTitle + meta, snug between | fill surface, tile shadow | standard |
| Field `.oceanField(role)` / `TranscriptEditor` | field radius, insetCompact; inputWords where the user types their own words, body in a tool; Oryne's prompt over a New York field is an SF body overlay in mist (`.oceanPrompt`); `TranscriptEditor` is counted in lines of inputWords | fill surface | |
| Add field `OceanAddField` | capsule, 44 minimum with a tight floor, + glyph leading, body; return adds | fill surface | |
| Link card | media radius, insetCompact, pictureTile thumbnail | fill surface | |
| Picture strip `OceanPictureStrip` | pictureTile, thumbnail radius, gap | remove badge on photoScrim | standard |
| Toast `OceanToast` | toast height as a minimum: one line at 48, a second grows it (a third at accessibility sizes); controlInset leading, the ring and the words snug, control + Link | bar glass | lift |
| Sheet header `OceanSheetHeader` | the grabber (or, with `drawsGrabber: false` under the system's indicator, its clear 5 pt), item, then any title view in sheetTitle, two lines (four at accessibility sizes), with the one action (Primary) on its first baseline, ending on the gutter; at accessibility sizes the action moves under the title; no close, no cancel | glass action on the water | |
| Page tools | pinned at the top as the page scrolls: the system toolbar's items (Tide's gear); the Library's own bar holds one `OceanToolGroup` (search, then `OceanSegmentedSwitch` glyph cells, then the filter, past `OceanToolDivider`s) | glass; the Library's group morphs into its search field (`glassEffectID`) | lift |
| Floating bar `OceanBarBackground` | bar height capsule, or composer radius | glass; bar shadow before iOS 26 | lift |
| Section `OceanSectionLabel` | sectionLabel with a hairline lead-in (a row with an accessory is the controls' 44); afterLabel 8 to what you see, a list of 44 pt rows right under it (0: the rows' slack is the gap); group 32 between groups in the Library's lists, section 40 between a page's sections, measured to what you see | mist | |
| Page | the system's large title (New York via `OceanType.applyNavigationTitleAppearance()`), or on the Library a `pageTitle` in the page on the same baseline; Tide has none; gutter; the words in the readable column (`.oceanReadableColumn()`: readableWidth, growing with body, centered on iPad and in landscape, or on the leading gutter under an iPad large title (Ask, `alignment: .leading`), never reached by a phone in portrait); section between | `PageBackground(light:)`: warm (the Reading light, `StageLight`) for the three tabs, cool for a thought or a current you opened, faint for Archived | |
| Tide's stage | the Reading light and the stage head (stageLabel, a thoughtTitle step by `OceanType.thoughtTitle(for:)`, then thoughtBody item below); with a picture, `ResurfacingPicture`: stage 360 (a link's image 300) from the screen's top edge, shorter on a short page (a phone in landscape) so the caption's foot clears the capture bar, the head at its foot, title to words item; at accessibility sizes the head stands right below the picture | the picture dissolves into a blur of itself, its last visible rows carry on below, mirrored, blurred and darkened; on a light picture an adaptive scrim keeps the label, the title and the words readable (a dark picture gets none) | |
| Depth list `DepthList` | depth0 to depth4 on Apple's curve, each line a 44 pt row with a gap floor inside, depthThumb picture at the end; Nearby starts at level 2 | depthInk0 to depthInk4; foam with Increase Contrast | a new line enters on gentle, the rest step down on standard |
| Ring `OceanRing`, `OceanDiscRing` | `OceanRing`: ringStroke at any size, metaIcon in the capture toast, ringHero on the empty Tide. `OceanDiscRing`, the capture disc's rim and Ask's send: a ringHairline at rest, ringStroke when ready, ringStrokeListening while it listens; Ask's send wears none until there is a question | ring; listening, the warm light and the blue drift round the disc's ring; the toast's arrives warm and cools | the disc's states on touch, its warmth in on lift and out on gentle; lift on the toast |

Every button in the app wears one of the four styles, except in Settings,
whose Form keeps the system's own rows, toggles, pickers and row buttons. A
chip is a Secondary button. A chevron in content is a bare
`glyphDisclosure`, never an Icon button. Every label, over a section, a
block or a field, is an `OceanSectionLabel` in `sectionLabel`, and a
Settings header is set in the same role, in sentence case; a section and a
block are told apart by the space above them (40 against 24), never by
their type.

## Navigation: pages rise, nothing slides

One way to open anything (`Oryne/App/OceanNavigation.swift`): a thought,
a current, Archived and every task (edit, grow a branch, move, merge,
settings, capture) rise as sheets with a grabber and pull down to leave.
There is no left-to-right push anywhere. Inside a sheet, a thought's
branches and neighbours open in place: `OceanFadeStack` crossfades the
page to the next thought (the standard motion) and puts a back tool where
the system's would be. The swipe-back gesture does not exist on a
crossfade; the back tool and the sheet's pull-down are the ways out.

## What stays expressive

Marked `// art-directed` in code; the lint skips those lines.

- Each page's light: Tide's Reading light (`StageLight`) and its
  choreography when a thought rests (`OceanFieldView`), how much of it
  reaches an opened page and Archived (`PageBackground`), the light behind each onboarding page and
  Ask's reading line.
- The picture stage's bleed (`ResurfacingPicture`): its blur, darkening and
  fade, and the scrim that grows with a light picture; the depth ladder's
  picture opacities; the toast ring's cooling delay.
- The distances things move: a new line's rise, the toasts' rise, the
  caught words' sink, the let-go sink, a card surfacing, the disc's touch
  reach, each its own constant.
- The water itself: the mesh (`OceanBackground`), the shore gradient under
  the capture bar.
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
  current, Archived and Settings show the system's). The edit sheet has no
  Cancel either: pulling it down discards the draft (decided 2026-10-23).
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

## Identity 2.1 (2026-11-02)

The direction in `design/identity-2.1.md`, built from its Round 4 frames
(`design/identity-2.1-wireframes.html`). Each line is a role in the JSON.

- Whose words: the serif is the user's (a thought's name, `Node.ownWords`),
  the sans is Oryne's. Section labels moved to SF; thought names on cards
  and rows moved to New York (`cardTitle`); `resurfacingTitle` and the
  italic labels are gone, except Resurfacing itself (`stageLabel`). Page and
  sheet titles are New York medium: in SF they read as plain (Malik).
- Light: the three tabs stand in Tide's warm Reading light (Malik: Ask and
  the Library take the same glow); a thought or a current you opened stands
  in the same light a step softer, Archived in a trace of it. The cool light
  is retired (Malik, 2026-11-03): one lamp, depth is how much of it reaches. `glowWarm` is retired; `warm` is the one warm ink.
- The water darkens downward on every page (`waterTop`, `waterMiddle`,
  `abyss`): no bright middle, no vignette.
- Tide is a stage over a water column: no large title, the stage
  (`ResurfacingPicture` or the Reading light), then the depth ladder
  (`DepthList`) with no dates. Dates stay on a thought's page and in the
  Library. A picture's color carries on 200 pt below it and fades from its
  foot (Malik: farther and slower read as too much).
- Surfaces are brighter so a tile reads as a thing: fill 11% (1.32:1 on
  deep), raised 14%, selected 19%, pressedLift 6%.
- The ring (`ring`, `ringStroke`, `ringHairline`, `OceanRing`) is the
  capture disc's rim, the capture toast's mark and the empty Tide's: the one
  rim PHILOSOPHY §4 allows (Malik, 2026-11-02). The disc is clear glass in
  every state, never a grey fill: at rest a blue hairline; ready to send,
  the ring firms to 1.5 pt; listening, the ring (2 pt, `ringStrokeListening`)
  holds the app's two lights, warm (`warm`, `warmGlint`) and the ring's blue:
  the warmth flows in from the upper left on `lift`, the lights drift round
  at an uneven, water-like pace (one turn per 5.6 s with a 16° ebb), the warm
  side swells a little with the voice, and on `gentle` the warmth cools back
  into the blue; stilled, a plain fade. One component draws it,
  `OceanDiscRing`, for the capture disc and for Ask's send (`OceanSendDiscStyle`),
  so the two bars always match. Ask's send wears no ring until there is a
  question (`showsAtRest: false`): a disc that can do nothing wears no mark.
- What rides along on the capture card is always shown: a whisper taken
  back with no words is a tile with its length and a ✕, and a parked
  whisper reads in the bar with the waveform glyph, never as typed text.

## Readability alignment (2026-11-02)

Every page, component, widget, the share sheet and the watch on one type
and spacing system, balancing reading with the 2.1 identity. Each line is a
role in the JSON or a contract above.

- Paragraphs get their room back, and the room is part of the type role: a
  role sets its font, its leading and its tracking together
  (`OceanTextRole`, `.oceanText(_:)`), so no screen can drop the leading.
  The user's paragraphs (Tide's words, a thought's page, card previews) sit
  at 1.46; Oryne's (summaries, answers, onboarding) at 1.43. No small line
  falls under its system style's own line height.
- Reading text is 13 pt or more in SF and 15 in New York. The 12 pt `note`
  is retired; every sentence someone must read to act (a failure, a
  refusal, a privacy disclosure, the merge consequence, provenance) is
  `secondary`, 15, in `text`.
- No word is set in `faint`. `mist` rises from 50% to 58%, which clears
  4.5:1 on every ground, the warm light's tiles included, and Increase
  Contrast brightens every ink, not only the depth ladder. On a light
  picture an adaptive scrim keeps Resurfacing, the title and the words
  readable; a dark picture looks as it did.
- Sizes follow Apple's own Dynamic Type ramp. Our own sizes (24, 21, 19, 14)
  sit between their neighbouring system styles at every text size, so the
  stage's title, its words and the depth ladder keep their order at all
  twelve, and the generator checks it on every run.
- Fixed boxes stop clipping: the toast, the fields and the focus chip have
  minimum heights and Tide's current tiles take their content's; the live
  words have a six-line window that never cuts the newest words; editors
  are counted in lines. The 56 pt capture bar stays exact, because its words
  and the folded composer stop growing at xxxLarge, with the Large Content
  Viewer. Ask's bar, its twin, caps its words at xxxLarge too.
- Spacing is one rule per relationship, measured between what you see (the
  spacing contracts): most labels sit 8 above what they name, and a list of
  44 pt rows sits right under its label; sections are 40 apart on a page
  and 32 apart inside the Library's lists; every sheet opens the same way.
- The user's words are New York as they type them (`inputWords`), with
  Oryne's prompts in SF. A thought's page steps its title like the stage
  (`OceanType.thoughtTitle(for:)`, a Chinese character counting 2); a
  current's sheet is a sheet (28); onboarding's headlines are their page's
  title (`pageTitle`); Resurfacing is New York 17 italic on the Lock Screen
  too.
- The brand stays where Malik put it: New York for the user's words, for
  thoughts' names and for places' names; the italic warm Resurfacing; the
  left-aligned stage with titles stepping 34 / 28 / 24 at 40 and 80
  characters; the ladder's 21 / 19 / 17 / 15 / 14 and its inks; the ring;
  SF 13 medium tracked labels.
- No animation, `OceanMotion` token or motion distance changed: each
  spacing token that doubled as a distance something moves became its own
  constant at its value.

Retired, and what replaces them:

| Retired | Replaced by |
|---|---|
| stageTitle, stageTitleLong, stageTitleLongest | thoughtTitle, thoughtTitleLong, thoughtTitleLongest: they name a thought on Tide and on its page |
| subjectHeading (New York 32) | `OceanType.thoughtTitle(for:)` on a thought's page; sheetTitle on a current's sheet |
| subjectTitle (New York 28, the widgets) | thoughtTitleLong (the large widget), thoughtTitleLongest (the medium, at every size: the families stop at xxxLarge); statement for Oryne's lines (Catch a thought, the empty widget) |
| eyebrow (SF 13 semibold) | sectionLabel, through `OceanSectionLabel` |
| note (SF 12) | meta for a quiet line, secondary for a sentence someone must read, `OceanWatchType.meta` on the watch |
| badge as the remove ✕ | glyphSmall |
| the `hint` ink | mist, now 58%, hint's old value |
| the `sheetTop` space | `OceanSheetHeader`'s geometry (`drawsGrabber: false` under the system's indicator) |
| the generated `*Size`, `*Leading` and `*Tracking` constants | none: a role carries its leading and tracking, and UIKit asks `role.uiFont()` |
| `OceanFont.metrics` | `OceanTextRole`, native or curve; the generator refuses `metrics` |
| `TranscriptEditor(minHeight:maxHeight:)` | `minLines:maxLines:`, in lines of inputWords |
| the watch's raw text styles | `OceanWatchType` |

Kept apart on purpose: pageTitle and thoughtTitle, and sheetTitle and
thoughtTitleLong, share their values at Large and stay separate roles, so
retuning a place's title never moves Tide's stage; meta and sectionLabel;
secondary, control and controlStrong (reading, a control, the main action);
glyph and glyphStrong; glyphMeta and glyphSmall.
