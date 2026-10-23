import SwiftUI

/// Tiles in a `List`, so the system's swipe actions work on them, laid out
/// as they are in a scroll view: no row backgrounds, no separators, the
/// water showing through. Rows set their own spacing.
///
/// The page gutter is the list's margin, not the rows' inset: each row is
/// exactly as wide as its tile, so a swiped tile keeps the system's own
/// gap to the first button, the same gap as between the buttons.
extension View {
    func tileList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, OceanSpacing.gutter, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 0)
    }

    /// One row of a tile list, edge to edge in the list's margins, `top`
    /// and `bottom` toward its neighbors. Two tiles sit an item gap apart.
    func tileRow(top: CGFloat = OceanSpacing.item / 2, bottom: CGFloat = OceanSpacing.item / 2) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
