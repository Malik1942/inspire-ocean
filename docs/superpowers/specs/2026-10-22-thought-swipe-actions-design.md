# Swipe to Delete or Archive a Thought — Design Spec

**Date:** 2026-10-22 · **Branch:** `am/stoic-curie-f5ef22` (lands on `main`) · **Status:** approved by Malik in chat (2026-10-22), as posted

## Goal

Every thought is quick to delete or archive, the way Apple Notes does it:
swipe left on a row to reveal Delete and Archive; a full swipe deletes. A
swiped delete always has a way back.

## Decisions

| Decision | Choice |
|---|---|
| Mechanism | A SwiftUI `List` styled to keep the tiles, with the system `.swipeActions`. Not a custom drag on the `ScrollView` |
| Why List | On iOS 26 the system draws the actions as two flat discs beside the sliding tile (checked in a throwaway prototype), which already fits the tile look. It brings the full-swipe threshold and haptic, the rubber band, one open row at a time, closing on scroll, and the row-collapse animation. A custom drag would rebuild all of that and fight the vertical scroll and the sheet's swipe-down |
| Actions | Trailing swipe: Delete (system destructive red disc, outermost, the full-swipe action) and Archive (system gray disc) |
| Where the swipe goes | Currents page (`CurrentsPage`, search results included) and a current's stream (`ClusterStreamView`): single-column lists of the same tile |
| Where it does not | Tide's "Drifted in" and the Library: two-column card grids. On a half-width card the buttons would be wider than what is left of it, and iOS grids use long-press. The Library already has Archive and Delete in its long-press menu; "Drifted in" gets the same menu (Delete through the existing system alert). Resurfacing and Nearby keep their own actions |
| Way back | An Undo toast, the twin of `CaptureToast`, for 10 s (the capture undo window): "Thought deleted" or "Thought archived" with Undo |
| Model | No SwiftData change (a model change forces a CloudKit schema redeploy) |
| Confirm dialogs | None for a swiped delete (it can be undone). The thought page's trash and the Library's menu Delete keep the system alert |
| VoiceOver | Each thought tile is one element with Delete and Archive custom actions, the same paths as the swipe, plus an announcement. Library and "Drifted in" cards get the same two actions, through their own paths |
| Identifier | `.accessibilityIdentifier("currents.page")` on the Currents page |
| Branch | `main`, via this branch. The running build's branch (`am/apple-intelligence-oryne-248869`) also changes `CurrentsPage` and `ClusterStreamView`, and carries model changes that need a schema deploy; it picks this up when it merges `main` |

## How a removal works

`ThoughtRemoval` (Shared) is one delete or archive that can still be taken
back:

- **Delete** hides the thought and its branches at once by setting
  `isArchived` on every node of the subtree that was not archived already, the
  same first step `deleteNodeSafely` takes. It records exactly which nodes it
  changed. `updatedAt` is left alone.
- **Archive** is the Library's archive: `isArchived = true`,
  `updatedAt = .now`. It records the previous `updatedAt`.
- **Undo** puts back exactly what the removal changed. A branch the user had
  archived before stays archived. A node deleted meanwhile (a sync from
  another device) is skipped, never read.

`ThoughtRemovals` (app, one per page) owns the pending removal the toast
offers:

- A new removal settles the previous one first.
- **Settle** closes the way back: a pending delete goes through the existing
  `ModelContext.deleteNodeSafely`; a pending archive just stays archived.
- It settles when the 10 s window ends, when the page's sheet closes, and when
  the app leaves the foreground. If the app is killed inside the window, the
  thought is left archived, not lost (Library › Show archived).
- Each removal posts a VoiceOver announcement with the toast's words.

Archive stays reversible after the window through Library › Show archived ›
Restore, as today.

## The list styling

`CurrentsPage` and `ClusterStreamView` become plain `List`s: clear row
backgrounds, hidden separators, hidden scroll background over the existing
`OceanBackground`, and row insets that keep the 20 pt gutter, 10 pt between
tiles, and the existing gaps between a header and its tiles and between
currents. Rows open their thought through a navigation path (a `Button`), not
a `NavigationLink`, so the list draws no chevron. The headers, search field,
large title, Summarize and Add a thought are unchanged.

## The toast

`UndoToast` in `Oryne/DesignSystem`: the capture toast's capsule in the bar's
own glass (`OceanBarBackground`), 48 pt tall, the message in foam
subheadline medium, Undo in accent semibold with a 44 pt target. It floats at
the bottom of the page, above the Currents page's search field. `CaptureToast`
stays where it is (`Features/FastCapture/` belongs to PR #17); folding the two
together is a follow-up.

## Copy

New, in English and zh-Hans: "Thought deleted" → 灵感已删除, "Thought
archived" → 灵感已归档. Existing: Delete (删除), Archive (归档), Undo (撤销),
"Delete this thought?" and its message. No dashes in UI copy.

## Testing

- `SharedTests/ThoughtRemovalTests.swift` on an in-memory SwiftData store:
  delete hides the subtree and undo restores it; a branch archived before
  stays archived after undo; archive sets and undo restores `isArchived` and
  `updatedAt`; undo skips a node deleted meanwhile.
- A full build, `SharedTests`, and a pass on a throwaway simulator with real
  swipes: a partial swipe reveals both discs; a full swipe deletes and the
  toast's Undo restores the thought; Archive and its Undo; the accessibility
  tree shows one Delete and one Archive per tile.
