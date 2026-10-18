import SwiftUI

/// Compact representation of a fragment, used in lists and detail sections.
struct NodeRow: View {
    let node: Node

    var body: some View {
        // A just-deleted node can linger for one render pass before its @Query
        // drops the row — and deleting a node with branches cascades, which
        // re-renders a child row mid-deletion. Reading any \Node attribute on a
        // detached object faults ("backing data was detached … \Node.themes"),
        // so render nothing until the row goes away. `modelContext` is metadata,
        // not backing-store data, so it stays safe to read once detached.
        if node.modelContext == nil {
            Color.clear.frame(width: 0, height: 0)
        } else {
            row
        }
    }

    /// Text only. A row is a place to go, not a preview: the title, then one
    /// meta line that says what kind of thought it is (a small glyph for a
    /// whisper, a link or a picture), when, and which current. Pictures are
    /// for cards and the thought itself. A fill, no border, no chevron.
    private var row: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(node.displayTitle)
                .font(.body.weight(.medium))
                .foregroundStyle(OceanTheme.foam)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            NodeMeta(node: node)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(OceanTheme.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A minimal flow layout that wraps its subviews onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var x: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                totalHeight += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            rows[rows.count - 1].append(subview)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
