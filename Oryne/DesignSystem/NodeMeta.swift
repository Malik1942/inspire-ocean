import SwiftUI

/// The one meta line every row and card wears under a thought's title:
/// what kind of thought it is (always first, in a fixed-width slot, so
/// columns align), an optional lead (a whisper's length, a link's domain),
/// when it was caught, and, when asked, its current. Footnote, mist, one
/// line that truncates at its end.
struct NodeMeta: View {
    let node: Node
    /// Lead-in after the kind glyph (a whisper's length, a link's domain).
    var detail: String? = nil
    var showsCurrent = true

    private var line: String {
        var parts: [String] = []
        if let detail, !detail.isEmpty { parts.append(detail) }
        parts.append(node.createdAt.formatted(.relative(presentation: .named)))
        if showsCurrent, let theme = node.themes.first { parts.append(theme) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: node.kind.symbol)
                .font(.caption2)
                .frame(width: 14)
            if node.isBranch, let bt = node.branchType {
                Image(systemName: bt.symbol).font(.caption2)
            }
            Text(line)
                .truncationMode(.tail)
            if node.isExample {
                Text("Example")
                    .foregroundStyle(OceanTheme.faint)
                    .layoutPriority(1)
            }
        }
        .font(.footnote)
        .foregroundStyle(OceanTheme.mist)
        .lineLimit(1)
    }
}
