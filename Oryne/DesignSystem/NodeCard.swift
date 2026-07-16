import SwiftUI

/// A vertical, variable-height card for a fragment, sized for the Library
/// masonry grid. `NodeRow` is the compact list form; this is the
/// content-forward grid form: image or link-preview banner, title, snippet,
/// link domain, themes, and the fragment's metadata.
struct NodeCard: View {
    let node: Node

    /// Edge-glow intensity (0...1). Driven by Handoff 2's relatedness focus; 0
    /// here, so the card draws no glow until a caller raises it.
    var glow: Double = 0

    /// The focused anchor in a "Show related" reorder. It reads as a steady
    /// `accent` edge (cool, constant), distinct from the warm decaying `glow` of
    /// its related cards, so the anchor is the source, not the strongest match.
    var isAnchor: Bool = false

    /// Suppress the edge shadow while the card is translating in a reorder. A
    /// blurred shadow re-rasterizes the card (image included) into an offscreen
    /// buffer every frame it moves; the stroke stays (cheap vector) and the
    /// shadow returns when motion settles. Callers set this only during the move.
    var suppressShadow: Bool = false

    /// Banner presence and bitmap are resolved ONCE (in `.task`) and cached, so
    /// no render, and crucially no reorder frame, reads the image blob or decodes
    /// again. `bannerData` walks a relationship and loads external-storage bytes;
    /// calling it every render was the main-thread cost that made image columns
    /// stutter during a reorder. `bannerHint` reserves banner height synchronously
    /// on the first render (before the check lands) so height never jumps.
    @State private var bannerImage: UIImage?
    @State private var bannerResolved = false
    @State private var bannerExists = false
    @State private var extraImages = 0

    var body: some View {
        // The same detached-node guard NodeRow uses: a just-deleted node can
        // linger for one render pass, and faulting any \Node attribute on a
        // detached object crashes. `modelContext` is metadata, safe to read
        // once detached; anything else (including `imageDatas`, which walks the
        // images relationship) is not, so it must come after this guard.
        if node.modelContext == nil {
            Color.clear.frame(width: 0, height: 0)
        } else {
            card
        }
    }

    /// The banner's backing bytes: an attached image first, else the link's
    /// preview image. Computed accessors walk relationships, so callers read
    /// this once per render, not repeatedly.
    private var bannerData: Data? {
        node.imageDatas.first ?? node.linkImageData
    }

    /// Cheap synchronous guess used only for the first render, before `.task`
    /// resolves the real answer, so banner height is reserved without reading the
    /// blob. Image and link fragments carry a banner; text does not.
    private var bannerHint: Bool {
        node.kind == .image || node.kind == .link || node.hasRichLink
    }

    private var showBanner: Bool { bannerResolved ? bannerExists : bannerHint }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showBanner { banner }

            VStack(alignment: .leading, spacing: 8) {
                Text(node.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !node.snippet.isEmpty {
                    Text(node.snippet)
                        .font(.caption)
                        .foregroundStyle(OceanTheme.mist)
                        .lineLimit(showBanner ? 2 : 4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Keyed on the URL, not the kind: a link captured in-app is a
                // .text node carrying linkURLString; only the share extension
                // makes .link nodes. The card shows the link wherever one is.
                if let domain = node.linkDomain {
                    HStack(spacing: 4) {
                        Image(systemName: "link").font(.caption2)
                        Text(domain)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(OceanTheme.mist)
                }

                if !node.themes.isEmpty || node.isExample {
                    tags
                }

                footer
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        // Clip the whole card (not just the fill) so the banner's top corners
        // round with it. Matches NodeRow's 14pt continuous radius.
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if isAnchor {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OceanTheme.accent, lineWidth: 1.5)
            } else if glow > 0 {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OceanTheme.glowWarm.opacity(glow), lineWidth: 1)
            }
        }
        // One cheap shadow, no stacked blur, free when neither is set, and
        // suppressed entirely while the card translates in a reorder (a moving
        // blurred shadow re-rasterizes the image every frame). The stroke carries
        // the highlight; this is only a tight edge-light hugging the border, so
        // several lit cards read as rim-lit, never as a hazy background bloom.
        .shadow(color: edgeShadow, radius: (isAnchor || glow > 0) && !suppressShadow ? 5 : 0)
        .task(id: node.id) { await loadImage() }
    }

    /// The hue placeholder is what participates in layout: it accepts the
    /// proposed size exactly, so the card's width never follows the image.
    /// The image paints in an overlay (overlays cannot affect layout), fills,
    /// and is clipped; `scaledToFill` directly in the stack would report an
    /// overflowing size and inflate the card, which is exactly the "weird
    /// size and ratio" failure this layout avoids.
    private var banner: some View {
        OceanTheme.color(forHue: node.hue).opacity(0.25)
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .overlay {
                if let bannerImage {
                    Image(uiImage: bannerImage)
                        .resizable()
                        .scaledToFill()
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .overlay(alignment: .topTrailing) {
                // "+N" when the fragment carries more than the one shown.
                if extraImages > 0 {
                    Text(verbatim: "+\(extraImages)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(OceanTheme.accent, in: Capsule())
                        .padding(6)
                }
            }
    }

    /// Themes (up to two) and the Example badge, wrapping when narrow.
    private var tags: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(node.themes.prefix(2)), id: \.self) { theme in
                tagCapsule(theme)
            }
            if node.isExample {
                tagCapsule(String(localized: "Example"))
            }
        }
    }

    private func tagCapsule(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(OceanTheme.mist)
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color.white.opacity(0.06), in: Capsule())
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if node.isBranch, let bt = node.branchType {
                Image(systemName: bt.symbol)
                    .font(.caption2).foregroundStyle(OceanTheme.accent)
            }
            Image(systemName: node.kind.symbol)
                .font(.caption2).foregroundStyle(OceanTheme.faint)
            Text(node.createdAt.formatted(.relative(presentation: .named)))
                .font(.caption2).foregroundStyle(OceanTheme.faint)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    /// The edge shadow colour: steady accent for the anchor, warm-decaying for a
    /// related card, and clear otherwise. Opacities stay low on purpose: on the
    /// abyss background a wide warm bloom reads as smeared light, so the halo is
    /// kept just strong enough to lift the edge off the dark.
    private var edgeShadow: Color {
        if isAnchor { return OceanTheme.accent.opacity(0.25) }
        if glow > 0 { return OceanTheme.glowWarm.opacity(glow * 0.22) }
        return .clear
    }

    /// Resolve banner presence and the decoded bitmap exactly once. Reads the
    /// blob here (main actor, safe), counts extra images from the relationship
    /// (not by loading every blob), off-mains the downsample+decode, and caches
    /// all of it. Guarded so a reorder (same node id) never re-reads or re-decodes
    /// on a layout pass, which is what made image columns stutter.
    private func loadImage() async {
        guard !bannerResolved else { return }
        let data = bannerData
        // Count extras from the relationship only; the legacy single `imageData`
        // is one image (0 extra). Never load the blob a second time just to count.
        extraImages = max(0, (node.images?.count ?? 1) - 1)
        bannerExists = (data != nil)
        bannerResolved = true
        guard let data else { return }
        let decoded = await Task.detached(priority: .utility) { () -> UIImage? in
            let bytes = ImageDownsampler.downsample(data, maxPixel: ImageDownsampler.Size.thumbnail) ?? data
            return UIImage(data: bytes)
        }.value
        if let decoded { bannerImage = decoded }
    }
}
