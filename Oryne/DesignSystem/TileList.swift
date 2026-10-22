import SwiftUI

/// Tiles in a `List`, so the system's swipe actions work on them, laid out
/// as they are in a scroll view: no row backgrounds, no separators, the
/// water showing through. Rows set their own spacing.
extension View {
    func tileList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
    }

    /// One row of a tile list: the page gutter at the sides, `top` and
    /// `bottom` toward its neighbors. Two tiles sit an item gap apart.
    func tileRow(top: CGFloat = OceanSpacing.item / 2, bottom: CGFloat = OceanSpacing.item / 2) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: OceanSpacing.gutter, bottom: bottom, trailing: OceanSpacing.gutter))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
