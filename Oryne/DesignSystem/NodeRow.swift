import SwiftUI

/// Compact representation of a fragment, used in lists and detail sections.
struct NodeRow: View {
    let node: Node
    /// Off inside a current, where every row shares it.
    var showsCurrent = true

    /// The picture at the trailing edge, decoded once. Until the node's
    /// images have been looked at, an image thought holds the picture's
    /// place, so the row never shifts when it lands.
    @State private var thumbnail: UIImage?
    @State private var pictureResolved = false
    @State private var hasPicture = false
    /// A whisper's length, read once.
    @State private var length: String?

    /// The picture's side: a control's height, so it sits inside the row's
    /// two lines without growing it.
    private static let pictureSide: CGFloat = OceanSize.thumbnail

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

    /// A row is a place to go, not a preview: the title, then one meta line
    /// that says what kind of thought it is, when, and which current. Each
    /// kind keeps what tells it apart without opening it: a thought with a
    /// picture shows it small at the trailing edge, a link leads its meta
    /// line with its site's icon and domain, a whisper with its length.
    /// A fill, no border, no chevron.
    private var row: some View {
        HStack(spacing: OceanSpacing.item) {
            VStack(alignment: .leading, spacing: OceanSpacing.snug) {
                Text(node.displayTitle)
                    .font(OceanType.tileTitle)
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                NodeMeta(node: node, detail: node.linkDomain ?? length, siteIcon: siteIcon, showsCurrent: showsCurrent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if pictureResolved ? hasPicture : node.kind == .image {
                picture
            }
        }
        .padding(OceanSpacing.inset)
        .background(OceanSurface(shape: RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)))
        .contentShape(RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous))
        .task(id: node.id) { await resolveCues() }
    }

    private var siteIcon: UIImage? {
        node.linkDomain.flatMap { SiteIcons.shared.icon(for: $0) }
    }

    /// The hue placeholder holds the square; the picture fills it and is
    /// clipped to a thumbnail's corners.
    private var picture: some View {
        OceanTheme.color(forHue: node.hue).opacity(0.25)
            .frame(width: Self.pictureSide, height: Self.pictureSide)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: OceanRadius.thumbnail, style: .continuous))
            .accessibilityHidden(true)
    }

    /// Everything the row needs beyond its title, each read once: the site's
    /// icon (from the cache, or fetched for a link saved before icons were
    /// kept), a whisper's length, and the first picture, downsampled off the
    /// main thread.
    private func resolveCues() async {
        if let site = node.linkDomain, let url = node.linkURL {
            SiteIcons.shared.load(site: site, pageURL: url)
        }
        if node.kind == .voice, length == nil, let data = node.audioData,
           let seconds = AudioDurations.seconds(for: data, id: node.id) {
            length = AudioDurations.format(seconds)
        }
        guard !pictureResolved else { return }
        let data = node.imageDatas.first
        hasPicture = data != nil
        pictureResolved = true
        guard let data else { return }
        let side = Self.pictureSide * 3
        thumbnail = await Task.detached(priority: .utility) { () -> UIImage? in
            UIImage(data: ImageDownsampler.downsample(data, maxPixel: side) ?? data)
        }.value
    }
}

/// A minimal flow layout that wraps its subviews onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = OceanSpacing.gap

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
