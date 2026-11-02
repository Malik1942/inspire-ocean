import SwiftUI

/// The one meta line every row and card wears under a thought's title:
/// what kind of thought it is (always first, in a slot that grows with the
/// line, so columns align), an optional lead (a whisper's length, a link's
/// domain), when it was caught, and, when asked, its current. Footnote,
/// mist, one line. The date never truncates: a long lead gives way first,
/// in its middle, then the current at its end. At accessibility sizes the
/// line is a sentence that wraps, the kind glyph on its first line.
struct NodeMeta: View {
    let node: Node
    /// Lead-in after the kind glyph (a whisper's length, a link's domain).
    var detail: String? = nil
    /// A link's site icon, in the kind glyph's place.
    var siteIcon: UIImage? = nil
    var showsCurrent = true

    @ScaledMetric(relativeTo: .caption2) private var slot = OceanSize.metaIcon
    @Environment(\.dynamicTypeSize) private var typeSize

    private var current: String? {
        guard showsCurrent, let key = node.currentKey else { return nil }
        return OceanLayoutEngine.displayLabel(for: key)
    }

    private var date: String {
        node.createdAt.formatted(.relative(presentation: .named))
    }

    var body: some View {
        // A site icon is a bitmap with no baseline of its own (it would
        // stand on the line's), so a link's row stays centered.
        HStack(alignment: typeSize.isAccessibilitySize && siteIcon == nil ? .firstTextBaseline : .center, spacing: OceanSpacing.snug) {
            if let siteIcon {
                Image(uiImage: siteIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: slot, height: slot)
                    .clipShape(RoundedRectangle(cornerRadius: OceanRadius.icon, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                // Any thought that carries a link reads as one, even a
                // typed thought a link was pasted into.
                Image(systemName: node.linkURL != nil ? NodeKind.link.symbol : node.kind.symbol)
                    .font(OceanType.glyphMeta)
                    .frame(width: slot)
            }
            if node.isBranch, let bt = node.branchType {
                Image(systemName: bt.symbol).font(OceanType.glyphMeta)
            }
            line
            if node.isExample {
                Text("Example")
                    .layoutPriority(1)
            }
        }
        .oceanText(OceanType.meta)
        .foregroundStyle(OceanTheme.mist)
        .oceanLineLimit(1)
    }

    /// The lead, the date and the current as their own words, so each gives
    /// way in its own order: the date is laid out first and never cut. At
    /// accessibility sizes they are one Text with no limit instead, so the
    /// line wraps between words and no part breaks inside its own column.
    @ViewBuilder
    private var line: some View {
        if typeSize.isAccessibilitySize {
            Text(verbatim: [detail, date, current].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .lineLimit(nil)
        } else {
            HStack(spacing: 0) {
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .truncationMode(.middle)
                    Self.separator
                }
                Text(date)
                    .layoutPriority(2)
                if let current {
                    Self.separator
                    Text(current)
                        .layoutPriority(1)
                }
            }
        }
    }

    private static var separator: some View {
        Text(verbatim: " · ")
            .layoutPriority(2)
    }
}
