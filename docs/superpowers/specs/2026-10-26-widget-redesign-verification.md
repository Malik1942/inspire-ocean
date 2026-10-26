# Widget redesign verification

Date: 2026-10-26. Branch: `codex/widget-redesign`.

## Checked

- Generated the local project under `/Users/malik/Developer/Oryne-main` from
  this checkout. App, phone widget, share extension and watch targets build
  with signing disabled for the iPhone 17 simulator (iOS 26.5).
- SharedTests: 302 tests passed, zero failures. No shared model, persistence,
  selection, watch or token source changed.
- Token generator check, visual-token lint and `git diff --check` pass.
- The widget string catalog contains 25 complete English and Simplified
  Chinese translations, including gallery descriptions and Control Center.
- Actual SwiftUI widget layouts rendered in a temporary simulator host at
  small 170x170, medium 364x170, large 364x382 and rectangular accessory
  sizes. Only the read-only widget-family environment reader was replaced
  with an explicit family parameter in the host's generated copies.
- Reviewed English, Chinese, long-title and accessibility-size renderings,
  with media, empty and unavailable-store entries. Fixed a truncated small
  header, crowded title and oversized action labels found during inspection.
- Thumbnail checks in the simulator: nil and malformed data return nil;
  a 1800x1000 source produces a thumbnail whose longest edge is 512 pixels.
- Opened the real WidgetKit gallery and placed the medium Quick Capture
  widget on the Home Screen. Its Thought action opens the composer with image
  attachment and voice controls. The initial Ask action opened Ask; the final
  layout moves this link to the large Resurfacing header.
- Reproduced Ask leaving an existing composer over its page. After the fix,
  typed `Widget draft preservation check`, left the app, tapped the widget's
  Ask action and saw Ask without the composer. Reopened Thought and verified
  the exact text survived. Cleared the temporary unsent draft afterward.

## Boundaries

The media examples in exported previews are fixtures, not the user's saved
thoughts. Store-failure and empty layouts were rendered from explicit entries;
no real store failure was induced. The loading-photo guard and active-save
guard use the existing capture lifetime; no new recording or camera permission
was granted during QA. Live microphone capture, physical-device Lock Screen,
Always On, and the system's tinted/clear compositor were not exercised.

Images use desaturated accented rendering and backgrounds remain removable,
following [Apple's widget appearance guidance](https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass).

## Changed files

- `QuickCaptureWidget.swift`: current-token layouts, shared actions and new
  rectangular/inline Lock Screen families.
- `ResurfacingWidget.swift`: media/source metadata, large reading layout,
  sensitive-content handling and honest empty/failure states.
- `OceanWidgetStyle.swift`, `OceanWidgetHeader.swift`,
  `OceanWidgetActions.swift`, `OceanWidgetImage.swift`: shared widget visuals
  and bounded thumbnail decoding, extracted from the bundle where applicable.
- `Localizable.xcstrings`: widget-specific English and Chinese copy.
- `AppState.swift`, `CaptureControl.swift`, `FastCaptureSessionView.swift`:
  Ask URL entry and a draft-preserving handoff through existing put-away.
- Design and implementation notes in `docs/superpowers`.

Initial verification left the changes uncommitted. Malik subsequently
authorized a commit and local merge on 2026-10-26. Unrelated untracked work
is excluded from that commit.

## Locant follow-up, 2026-10-26

Addressed capture `20261026-022957-836o` and the request for serif Resurfacing
labels. Quick Capture no longer repeats Oryne above its title. The bottom row
now contains only Thought and Whisper, with 12 pt between capsules and the
shared 16 pt horizontal control insets. Labels use the normal control role
without needing to squeeze three actions into the medium width. Ask is a
separate quiet link in the large Resurfacing header. Resurfacing labels now
use the app's New York serif section-label role, including the accessory.
The medium reading layout omits its excerpt when the title needs two lines.

Rebuilt app and extensions. Token checks and diff checks pass. Reviewed updated
English, Chinese and accessibility-size previews, plus a 320x158 compact
capture layout. No shared logic or app navigation changed in this follow-up.
Reinstalled the built app and confirmed the two-button layout and removed
brand line in the actual Home Screen widget, not only the preview host.

The next spacing pass removes the stretched spacer in medium Quick Capture:
the title and existing helper line form one block, with 24 pt to the actions,
equal side insets, and vertical centering. Reviewed 364x170 and 320x158
renders and the accessibility layout (which omits the helper). The app and
extensions rebuild successfully; token lint and diff checks pass. Reinstalled
the updated app on the simulator. Only QuickCaptureWidget.swift changed in
this pass, alongside these design notes.
