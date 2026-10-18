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

    /// Text first, and the text column always starts on the same line: a
    /// picture, when the thought has one, sits at the trailing edge as the
    /// row's attachment. No chevron: the fill says the row is a place to go.
    /// What kind of thought it is lives in the meta line as a small glyph.
    private var row: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(node.displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if node.kind == .voice || node.kind == .link {
                        Image(systemName: node.kind.symbol)
                            .font(.caption2)
                            .foregroundStyle(OceanTheme.mist)
                    }
                    if node.isBranch, let bt = node.branchType {
                        Image(systemName: bt.symbol).font(.caption2).foregroundStyle(OceanTheme.mist)
                    }
                    Text(node.createdAt.formatted(.relative(presentation: .named)))
                        .foregroundStyle(OceanTheme.mist)
                    if let theme = node.themes.first {
                        Text("· \(theme)").foregroundStyle(OceanTheme.mist).lineLimit(1)
                    }
                    if node.isExample {
                        Text("Example").foregroundStyle(OceanTheme.faint)
                    }
                }
                .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let data = node.imageDatas.first ?? node.linkImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
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
