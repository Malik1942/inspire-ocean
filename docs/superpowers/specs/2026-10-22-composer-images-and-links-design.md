# Composer images and link sensing — Design Spec

**Date:** 2026-10-22 · **Branch:** `am/image-link-input-318138` · **Status:** approved 2026-10-22; built on this branch (plan: `docs/superpowers/plans/2026-10-22-composer-images-and-links.md`), reviewed per task and as a whole

## Goal

The capture composer has no way to add a picture or a link. Give it the image
input people already know from Claude and ChatGPT (a + in the composer, your
latest photos in the keyboard's place, attachments as thumbnails inside the
card), and
make links need no input at all: a link in the words is sensed and becomes the
thought's link card.

## Decisions (Malik, 2026-10-22)

| Decision | Choice |
|---|---|
| Where images come in | A + at the leading end of the open card's action row; the send disc stays at the trailing end |
| What + opens | A panel in the keyboard's place, as Messages does: a strip of the latest photos (tap one: attached, the keys come back), then Camera and All Photos. Was a short sheet until the simulator showed the embedded picker takes over any sheet it sits in (Malik chose the panel, 2026-10-22) |
| Where attachments show | A row of square thumbnails at the top of the card, above the words, each with its own ✕ |
| The Action Button screenshot | Becomes the first thumbnail of that row; the tall full-width preview goes |
| How links come in | Sensed in the typed words; no link field |
| The URL text at release | A link at the start or end of the words is lifted out (the card carries it); a link mid-sentence stays in the words. Words that are only a link become a link thought titled by its page |
| Feedback before release | A link tile with the site name joins the thumbnails; its ✕ keeps the link as plain words |
| The bar | Unchanged |

## What this rests on

- **The model already holds both.** `Node.images` keeps up to `Node.maxImages`
  (10) images as `NodeImage` children; `Node.linkURLString` keeps one link, and
  `LinkEnrichmentService` turns it into a rich card (title, thumbnail, on-device
  summary) whose context joins the thought's meaning. The thought page already
  renders a picture or strip first and the link card after the words. No model
  change, so no CloudKit schema redeploy.
- **What was lost.** The Capture tab removed in the phone refocus (`1d90869`)
  had a Photos picker and a Link field. Neither moved into the composer, whose
  only image path is the Action Button's auto screenshot
  (`FastCaptureRequest.imageData`, shown as a 116 pt preview).
- **Link detection.** `NSDataDetector` (`.link`) on 15 sample lines: it found
  full URLs, bare domains with paths (`nytimes.com/…`, `xhslink.com/…`, returned
  as `http://`), and links inside Chinese sentences, including one followed by a
  full-width comma. No false positives on `sunset.jpg`, `notes.md`, `3.5x`,
  `e.g.`, `foo.bar`. Emails come back as `mailto:`.
- **The strip needs no permission.** SwiftUI's embedded `PhotosPicker` (iOS 17;
  the app targets 18) with `.photosPickerStyle(.compact)` draws a one-row picker
  out of process, with live selection (`selectionBehavior: .continuous`). The
  app never reads the library itself, so there is no Photos permission prompt
  (Photos shows its own one-time "Private Access to Photos" notice over the
  strip the first time). Found on
  the simulator: embedded in any UIKit sheet it takes the sheet over (full
  height, see-through, content at the top), even when added after the sheet
  settles. Drawn in a panel inside the composer's overlay it behaves.
- **Camera** needs `NSCameraUsageDescription`. The phone's privacy strings are
  English only today (no `InfoPlist.xcstrings` for the app target); this one
  joins them.

## Design

### The open card

```
╭──────────────────────────────────────╮
│ [img ✕] [img ✕] [link  are.na ✕]     │  attachments: only when there are any
│ Love this palette https://are.na/b/42│  the field, as today
│ (+)                              (↑) │  + leading, the disc trailing
╰──────────────────────────────────────╯
```

- **+** is the `oceanIcon` disc (44 pt glass, 17 pt foam `plus`), the twin of
  the listening capsule's ✕. Captions (a refusal, "Flows into …") move to sit
  between + and the disc. + fades and stops taking touches while the card is
  folded, exactly like the captions. At 10 images it is disabled (dimmed).
- **Attachments row** sits above the field inside the card's 12 pt inset and
  scrolls sideways. Thumbnails are 64 pt squares, corner radius 12 (the card's
  24 less its inset, so concentric). Each carries a ✕ badge at its top trailing
  corner (white glyph on a dark disc, readable on any photo; hit area at least
  32 pt). The row only exists when something is attached, and is hidden while
  the card is folded.
- **Link tile** is the row's last item: same 64 pt height, a flat quiet fill
  (white 8%, radius 12), the `link` glyph above the site name (host without
  `www.`, one line), and the same ✕. Its ✕ dismisses that link: it stays in the
  words as text and is never attached.
- Images are decoded into small thumbnails once, when attached; typing never
  re-decodes photos.
- A picture still loading shows a quiet tile with the same ✕: it lets go of
  the loads on their way, so a stalled one (an iCloud original while offline)
  never holds the card. A send tapped while pictures load waits for them, and
  goes with what landed if their ✕ is tapped.

### The + panel

```
╭──────────────────────────────────────╮
│ What are you noticing?               │  the card, where it sat on the keys
│ (+)                              (≋) │
╰──────────────────────────────────────╯
╭──────────────────────────────────────╮
│ [▣][▣][▣][▣][▣][▣] → latest photos    │  the panel, in the keyboard's place
│  ◉  Camera                           │
│  ▦  All Photos                       │
╰──────────────────────────────────────╯
```

- + swaps the keyboard for the panel, and back. The panel is drawn by the
  composer's overlay (never a sheet), with the card's gutter edges, 24 pt
  continuous corners, 12 pt inset and glass. Its height is the keyboard's
  less the home indicator's inset, so the card does not move when + swaps
  them. The tab bar steps away under it, as it does under the keys.
- Focusing the words (a tap on the field, the + again, a photo picked)
  brings the keys back and the panel steps aside; so does a take starting,
  open water, or anything that ends composing.
- **Strip:** embedded `PhotosPicker`, compact style, images only, continuous
  selection, with search, collection navigation, the staging area and the
  selection actions disabled and its accessories hidden, filling the panel
  above the rows. The first tap attaches that photo and the keys come back.
  Inside a current's sheet (the composer `asSheet`) there is no strip, only
  the rows: the strip would take that sheet over.
- **Camera** (`camera`): the panel closes, then the system camera full screen
  (`UIImagePickerController`, photo only). One shot is attached. The row is
  hidden where no camera exists.
- **All Photos** (`photo.on.rectangle`): the panel closes, then the system
  Photos picker with multi-select up to the room left.
- Every photo goes through `ImageDownsampler` (1600 px longest edge) before it
  is kept. When more were picked than fit, the existing notice shows in the
  captions: "Only added %lld, %lld images max."
- Returning from the camera or the picker (with or without a pick), the field
  takes the keyboard again.

### Link sensing

A new pure `LinkSensing` in `Shared/Services` (so `SharedTests` can test it):

- **Find:** `NSDataDetector` links, `http` and `https` only. A match typed
  without a scheme becomes `https://` + the match; a typed `http://` stays.
  Every final `?` right after a link is the sentence's, not the URL's (the
  detector reads it as an empty query, which means nothing). A link ends
  where prose typed right against it begins: CJK text and its marks,
  full-width forms, curly quotes and dashes (the detector would carry them
  in, so "https://a.com这个不错" would store a broken link).
- **Choose:** the first sensed link whose URL the user has not dismissed.
- **Lift:** the chosen link is at the **leading edge** when only whitespace
  precedes it, and at the **trailing edge** when only whitespace and sentence
  punctuation (`. , ; ! ? … 。 ， ； ！ ？ 、`) follow it. At an edge, the link and
  that trailing punctuation leave the words, and so does whatever joined the
  link to them (`- – — | · : ： , ， ; ； 、` beside it): "Great read - link",
  "Love this: link", "link, great read" and "看这个：link" keep "Great read",
  "Love this", "great read" and "看这个". A question or exclamation mark before
  the link stays. A link at the start leaves the words only when something
  sets it apart from what follows: a space, a separator then a space, a
  full-width mark, or CJK text ("https://a.com这个不错" keeps "这个不错").
  Otherwise the words keep it: "stripe.com’s new docs" stays whole, and
  "https://a.com -5 degrees" keeps its minus. Anywhere else the words keep
  the link. Words that were only the link become empty.
- **The tile** follows the field: sensed half a second after the last edit
  (so a half-typed `apple.co` never shows), and at once when the card opens
  with words already in it (a seed, a parked draft, an undo) or a paste adds
  more than one character.

### Release

- The composer hands `CaptureSession.release` the field as typed, the images,
  the chosen link (`CaptureDraft.linkURLString`), the dismissed links, and any
  audio. The draft stays exactly what the user had, so Undo restores the URL
  in the words and the dismissals with it.
- `release` builds the node's words by lifting the link from the typed text
  (from the field-held transcript when a corrected whisper is being sent), and
  resolves the kind from what the draft holds: audio → `.voice`; words →
  `.text`; else images → `.image`; else a link → `.link`.
- `CaptureSession.beginUnderstanding` also starts `LinkEnrichmentService`
  for a node with a link. A link thought has no words of its own, so the
  understanding pass finds nothing and the page's title and summary name it
  once enrichment lands (its `rederiveContext`). Undo deleting the node makes
  enrichment's later writes no-ops (each stage re-fetches by id).
- Spoken words are never scanned. A typed note riding on a whisper is.
- `CaptureDraft.imageData` (the single screenshot slot) goes; the composer
  always passes `imageDatas`.

### Drafts: whisper, park, undo

- With pictures on the card the disc is the send, as with words: an
  attachment is something to send, the way Claude and ChatGPT treat it. A
  take that starts with pictures already on the card (the Action Button's
  screenshot opened to whisper) carries them, and the sensed link of any
  typed note, into the whisper.
- Open water parks the draft with its images and dismissals. While pictures
  are still loading it only folds the keys or the panel: the bar can't hold a
  picture that hasn't landed.
  `ParkedCapture.line` with no words reads "Whisper" when audio waits, else
  "Image" for one picture and "%lld images" for more (was "Screenshot").
- Undo returns words, images, link dismissals and audio to the card; the
  pictures come back through their loading tiles, decoded off the main actor.

### Copy

| Key | zh-Hans | Status |
|---|---|---|
| Add image | 添加图片 | exists (accessibility label of +) |
| Remove image | 移除图片 | exists (thumbnail ✕) |
| Remove link | 移除链接 | exists (link tile ✕) |
| Image | 图片 | exists (parked line) |
| Only added %lld, %lld images max. | 仅添加了 %lld 张，最多 %lld 张图片。 | exists |
| Camera | 相机 | new |
| All Photos | 所有照片 | new |
| Show keyboard | 显示键盘 | new (the +, while the panel is open) |
| %lld images | %lld 张图片 | new (parked line) |
| NSCameraUsageDescription: Oryne uses the camera to catch what you see. | (English only, like its siblings) | new |

"Remove screenshot" and "Screenshot" lose their only uses and are pruned from
the catalog if nothing else references them. No dashes in any of it.

## Components

| File | Change |
|---|---|
| `Shared/Services/LinkSensing.swift` | New. Find, choose, lift; pure, no UI |
| `SharedTests/LinkSensingTests.swift` | New |
| `Oryne/Features/FastCapture/CaptureAttachments.swift` | New. The row: thumbnails, link tile, ✕ badges |
| `Oryne/Features/FastCapture/CaptureAttachPanel.swift` | New. The + panel, and the camera wrapper |
| `Oryne/App/RootTabView.swift` | The tab bar steps away while the + panel is up (`CaptureControl.attachPanelOpen`) |
| `Oryne/Features/FastCapture/FastCaptureSessionView.swift` | Images as a list with thumbnails, +, the row, the + panel in the keyboard's place, sensed link state, camera and picker; release passes images, link and dismissals |
| `Oryne/Features/FastCapture/CaptureControl.swift` | `ParkedCapture` holds images and dismissals; its line |
| `Oryne/Services/CaptureSession.swift` | `CaptureDraft` loses `imageData`, gains dismissed links; `release` lifts and resolves the kind; `beginUnderstanding` starts link enrichment |
| `project.yml` | `NSCameraUsageDescription` |
| `Oryne/Resources/Localizable.xcstrings` | New keys above |

## Error handling

- An image that won't load or decode is skipped (the shared downsampler path).
- No camera: the row is hidden. Camera access denied: the system's own camera
  screen explains it; nothing custom.
- A link that can't be reached: the existing card shows the bare URL and its
  retry.
- A refused save keeps the whole draft on the card (unchanged).

## Testing

- **Unit (`LinkSensingTests`):** full URL; bare domain to https; typed http
  kept; mailto ignored; no false positives (`sunset.jpg`, `3.5x`, `e.g.`);
  trailing lift with a period; leading lift; mid-sentence kept; link only to
  empty words; Chinese trailing lift (`看这个 https://…`) and mid-sentence keep
  (`… xhslink.com/a/AbC123，复制后打开`); two links take the first; a dismissed
  first link takes the second; all dismissed gives none.
- **Simulator:** the + panel's strip attaches one photo and the card stays put; All Photos attaches several
  and the 10 cap notice shows; Action Button seed shows as a thumbnail; release
  writes `NodeImage` rows in order; a typed link shows the tile, and release
  writes `linkURLString`, lifted words and the kind, then the thought page
  shows the card; a dismissed link stays text; Undo and a parked draft bring
  everything back; zh-Hans copy; Reduce Motion; VoiceOver labels.

## Out of scope

Pasting an image into the field, Files, drag and drop, reordering thumbnails,
a rich preview fetched inside the composer, link sensing in the share
extension, localizing the phone's privacy strings.
