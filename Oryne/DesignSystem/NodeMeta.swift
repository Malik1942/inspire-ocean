import SwiftUI

/// The one meta line every row and card wears under a thought's title:
/// what kind of thought it is (always, so columns align), when it was
/// caught, and, when asked, its current. Footnote, mist, one line.
struct NodeMeta: View {
    let node: Node
    /// Extra lead-in after the kind glyph (a whisper's length, for example).
    var detail: String? = nil
    var showsCurrent = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: node.kind.symbol)
                .font(.caption2)
                .frame(width: 14)
            if node.isBranch, let bt = node.branchType {
                Image(systemName: bt.symbol).font(.caption2)
            }
            if let detail, !detail.isEmpty {
                Text(detail)
                Text(verbatim: "·")
            }
            Text(node.createdAt.formatted(.relative(presentation: .named)))
            if showsCurrent, let theme = node.themes.first {
                Text(verbatim: "·")
                Text(theme)
            }
            if node.isExample {
                Text("Example").foregroundStyle(OceanTheme.faint)
            }
        }
        .font(.footnote)
        .foregroundStyle(OceanTheme.mist)
        .lineLimit(1)
    }
}
