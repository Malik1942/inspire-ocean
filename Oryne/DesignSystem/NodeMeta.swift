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
    /// A link's site icon, in the kind glyph's place.
    var siteIcon: UIImage? = nil
    var showsCurrent = true

    private var line: String {
        var parts: [String] = []
        if let detail, !detail.isEmpty { parts.append(detail) }
        parts.append(node.createdAt.formatted(.relative(presentation: .named)))
        if showsCurrent, let key = node.currentKey { parts.append(OceanLayoutEngine.displayLabel(for: key)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: OceanSpacing.snug) {
            if let siteIcon {
                Image(uiImage: siteIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: OceanSize.metaIcon, height: OceanSize.metaIcon)
                    .clipShape(RoundedRectangle(cornerRadius: OceanRadius.icon, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                // Any thought that carries a link reads as one, even a
                // typed thought a link was pasted into.
                Image(systemName: node.linkURL != nil ? NodeKind.link.symbol : node.kind.symbol)
                    .font(OceanType.glyphMeta)
                    .frame(width: OceanSize.metaIcon)
            }
            if node.isBranch, let bt = node.branchType {
                Image(systemName: bt.symbol).font(OceanType.glyphMeta)
            }
            Text(line)
                .truncationMode(.tail)
            if node.isExample {
                Text("Example")
                    .foregroundStyle(OceanTheme.faint)
                    .layoutPriority(1)
            }
        }
        .font(OceanType.meta)
        .foregroundStyle(OceanTheme.mist)
        .lineLimit(1)
    }
}
