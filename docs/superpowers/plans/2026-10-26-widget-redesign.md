# Widget redesign implementation plan

Implementation used the repository's single-agent workflow. Malik authorized
commit and local merge on 2026-10-26. Preserve unrelated untracked files.

1. Extract OceanWidgetStyle from OceanWidgetsBundle.swift into
   OceanWidgets/OceanWidgetStyle.swift. Add OceanWidgetHeader, OceanWidgetActions and OceanWidgetImage files: shared header, equal-width
   44 pt action links and a bounded ImageIO thumbnail decoder. Reuse the
   existing token roles and use desaturated image rendering in accented mode.
2. Update OceanWidgets/QuickCaptureWidget.swift: remove the redundant Home Screen brand header and use the two-action row, keep preferred-input routing for small/circular, and add
   rectangular/inline Lock Screen families.
3. Update OceanWidgets/ResurfacingWidget.swift: snapshot kind, domain and a
   bounded thumbnail; suppress duplicate snippets; distinguish store failure
   from no pick. Add large-family reading and action rows. Keep node links,
   held daily picks and midnight timeline policy. Mark saved content private.
4. Add the Ask case to AppState.handleDeepLink. Route `oryne://ask` from the
   action row, leaving question entry in the app. If a composer is open,
   CaptureControl.parkForNavigation requests its existing put-away path in
   FastCaptureSessionView, after pictures have loaded. A new capture clears
   the request. Verify that a typed draft comes back unchanged.
5. Add OceanWidgets/Localizable.xcstrings, including gallery descriptions,
   new empty states and all reused widget labels, in English and zh-Hans.
6. Generate with:
   `xcodegen generate --project /Users/malik/Developer/Oryne-main --project-root /Users/malik/Documents/inspire-ocean`
   Build using that project, the Oryne scheme and booted iPhone 17 simulator,
   with CODE_SIGNING_ALLOWED=NO. Run SharedTests and token checks. Render the
   actual SwiftUI widget views in a temporary simulator host for visual QA,
   then verify installed widget links with simctl openurl and simulator UI.

Success: app and extensions build, tests pass, localized layouts fit, saved
media is visible without unbounded decoding, and each link opens its intended
existing destination. Record any platform-only checks not exercised.

## Follow-up from Locant, 2026-10-26

- Resurfacing labels use OceanType.sectionLabel, the app's New York serif.
- Home Screen Quick Capture removes the duplicate Oryne brand line.
- OceanWidgetActions contains Thought and Whisper only, each with the shared
  control font and 16 pt horizontal insets, with a 12 pt gap between capsules.
- Ask moves into the large Resurfacing header as a separate quiet link.
- Medium Resurfacing drops its excerpt when necessary to keep the title legible.
- Verify standard, Chinese, accessibility and compact-width renders, then build
  and reinstall the app on the simulator.
