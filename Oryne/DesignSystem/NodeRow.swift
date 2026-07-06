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

    private var row: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(OceanTheme.color(forHue: node.hue).opacity(0.3))
                        .frame(width: 40, height: 40)
                    if let data = node.imageDatas.first, let ui = UIImage(data: data) {
                        Image(uiImage: ui).resizable().scaledToFill()
                            .frame(width: 40, height: 40).clipShape(Circle())
                    } else {
                        Image(systemName: node.kind.symbol)
                            .foregroundStyle(OceanTheme.foam)
                    }
                }
                // "+N" when a node carries more than the one shown.
                if node.imageDatas.count > 1 {
                    Text(verbatim: "+\(node.imageDatas.count - 1)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(OceanTheme.accent, in: Capsule())
                        .offset(x: 3, y: 3)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(node.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if node.isBranch, let bt = node.branchType {
                        Image(systemName: bt.symbol).font(.caption2).foregroundStyle(OceanTheme.accent)
                    }
                    Text(node.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption2).foregroundStyle(OceanTheme.faint)
                    if let theme = node.themes.first {
                        Text("· \(theme)").font(.caption2).foregroundStyle(OceanTheme.mist).lineLimit(1)
                    }
                    if node.isExample {
                        Text("Example")
                            .font(.caption2)
                            .foregroundStyle(OceanTheme.mist)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.white.opacity(0.06), in: Capsule())
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(OceanTheme.faint)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
