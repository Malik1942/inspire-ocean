# Resurfacing Widget Follows Tide's Pick: Design Spec

**Date:** 2026-10-22 · **Branch:** `am/dreamy-wiles-4719d7`, on top of `e1dfa45` (`am/sweet-archimedes-ec45ca`: today's pick holds all day) · **Status:** approved by Malik in chat (2026-10-22)

## Goal

The Resurfacing Home Screen widget shows the thought Tide shows, right after
it changes, not at the next 00:05 refresh. Today the widget asks for a new
timeline only after midnight and nothing in the app calls `WidgetCenter`, so
after Let it rest, or when today's pick is archived or deleted, the widget
keeps the old thought and its `oryne://node/<id>` link until then (launch
film audit 2026-09-22, product issue 3).

## Decisions

| Decision | Choice |
|---|---|
| Trigger | Tide's pick. In `OceanFieldView`, `.onChange(of: resurfacing?.id, initial: true)` reloads the widget. `resurfacing` is the thought Tide shows, so the widget reloads exactly when that changes: Let it rest, today's pick archived or deleted, an Undo that brings it back, or no pick at all |
| `initial: true` | One reload when Tide first appears, for a pick that changed while the app was closed (a reseed, an archive synced from another device). The widget runs no CloudKit, so opening the app is the earliest moment it can learn of those. `initial` also runs on every return to the Tide tab (seen on the simulator), so a `@State` flag lets only the first one reload; a real change (`old != new`) always does |
| Its own `onChange` | The existing one closes Nearby. The reload sits beside it, so a launch or a tab switch never touches Nearby |
| What reloads | Only the Resurfacing kind (`reloadTimelines(ofKind:)`), not Quick Capture or the control |
| Budget | Reloads the app asks for while it is in the foreground do not count against the widget's daily budget (Apple, "Keeping a widget up to date"). The timeline's own 00:05 refresh is unchanged |
| Kind string | `Resurfacing.widgetKind` in Shared, used by both the widget and the app. Its value is unchanged: placed widgets are keyed by it, and a new one would remove every widget already on a Home Screen. A SharedTests case pins it |
| Hold | Depends on `e1dfa45`: `Resurfacing.pick` holds the day's pick in the App Group defaults, so the reloaded widget reads the app's pick instead of scoring its own |
| Model | No SwiftData change (it would force a CloudKit schema redeploy) |
| Not chosen | Reloading when the app goes to the background: it reloads on every exit, those reloads count against the budget, and the old thought can flash as the Home Screen comes up. Reloading at every rest, archive, delete and undo site (Tide, the Library, a thought's page, PR #20's removals): easy to miss one, and every removal path would have to know about the widget |

## What the simulator showed (iOS 26.5)

- **The Library case holds.** The Library is another tab, but archiving
  today's pick there still runs the hidden Tide tab's `onChange`: the app
  asked for the reload within a second, and the widget showed the next pick.
- **WidgetKit lets one reload a foreground session through at once.** The
  first request while the app is in front reloads immediately ("Allowing
  first refresh while foreground", budget exempt `containerApp`). Later ones
  in the same session are throttled and coalesced, then run once when the
  app goes to the background ("Flushing pending reload request due to
  background transition", budget exempt `free`). Either way the widget is
  current within about a second of leaving the app, and the app's reloads
  cost none of the widget's daily budget; only the 00:05 refresh is budgeted.
- That is also why a reload on every return to the tab would be waste: it
  spends the session's immediate reload on a pick that did not change.
- **The final build, each traced in chronod's log:** a cold launch after a
  change made while the app was closed asked once, and the stale widget
  caught up; Tide to Ask and back asked for nothing; Let it rest and a
  Library archive each asked once, and the widget matched Tide.

## Testing

- `SharedTests`: a case pins the kind string; written first, it fails until
  `Resurfacing.widgetKind` exists.
- The reload is view code that SharedTests cannot reach. On a throwaway
  simulator with the Resurfacing widget on the Home Screen: Let it rest in
  Tide, and the widget shows Tide's new pick; archive today's pick from the
  Library, and the widget shows the next one.
