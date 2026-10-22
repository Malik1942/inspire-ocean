import SwiftUI

/// One picture on the composer's card: the bytes a release keeps and the
/// small image the card shows. The thumbnail is decoded once, when the
/// picture is added, so typing never decodes a photo again.
struct CaptureImage: Identifiable {
    let id = UUID()
    let data: Data
    let thumbnail: UIImage

    /// A tile's 64 pt at 3x, on the picture's short edge, so any shape
    /// fills the square tile without upscaling.
    static let thumbnailPixels: CGFloat = 192

    /// Nil when the bytes aren't a picture ImageIO can read.
    init?(data: Data) {
        guard let thumbnail = ImageDownsampler.image(data, fillingSquare: Self.thumbnailPixels) else { return nil }
        self.data = data
        self.thumbnail = thumbnail
    }

    /// Several pictures, decoded off the main actor, in order; any that
    /// can't be read are left out.
    static func make(from datas: [Data]) async -> [CaptureImage] {
        await Task.detached { datas.compactMap(CaptureImage.init(data:)) }.value
    }
}

/// What rides on the composer's card above the words: its pictures, a
/// quiet tile for each one still loading, and the link sensed in the
/// words. Square tiles of 64 pt whose corners sit concentric with the
/// card's, each with its own ✕. The row scrolls sideways once it is wider
/// than the card.
struct CaptureAttachments: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calmAccessibility) private var calm

    let images: [CaptureImage]
    /// Pictures picked but not yet loaded.
    var pending = 0
    /// The link a release would attach.
    var link: LinkSensing.Sensed? = nil
    var onRemoveImage: (CaptureImage.ID) -> Void
    /// The link tile's ✕, with the link's URL.
    var onRemoveLink: (String) -> Void = { _ in }

    static let tileSize: CGFloat = 64
    /// The card's corner less its inset, so the tiles sit concentric.
    static let tileRadius: CGFloat = FastCaptureLayout.cardRadius - FastCaptureLayout.cardInset

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous)
    }

    /// Reduce Motion: tiles fade in place instead of growing in.
    private var arrival: AnyTransition {
        reduceMotion || calm ? .opacity : .scale(scale: 0.8).combined(with: .opacity)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images) { image in
                    thumbnail(image)
                        .transition(arrival)
                }
                ForEach(0..<pending, id: \.self) { _ in
                    loadingTile
                        .transition(.opacity)
                }
                if let link {
                    linkTile(link)
                        .transition(.opacity)
                }
            }
        }
        .frame(height: Self.tileSize)
    }

    private func thumbnail(_ image: CaptureImage) -> some View {
        Image(uiImage: image.thumbnail)
            .resizable()
            .scaledToFill()
            .frame(width: Self.tileSize, height: Self.tileSize)
            .clipShape(tileShape)
            .overlay(alignment: .topTrailing) {
                RemoveBadge(label: Text("Remove image")) { onRemoveImage(image.id) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(NodeKind.image.label))
    }

    private var loadingTile: some View {
        tileShape
            .fill(Color.white.opacity(0.08))
            .frame(width: Self.tileSize, height: Self.tileSize)
            .overlay { ProgressView().tint(OceanTheme.mist) }
            .accessibilityHidden(true)
    }

    /// The sensed link: its site's name under the link glyph, on the quiet
    /// fill of a content control. Its ✕ leaves the link in the words as
    /// text, never attached.
    private func linkTile(_ link: LinkSensing.Sensed) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "link")
                .font(.footnote.weight(.medium))
                .foregroundStyle(OceanTheme.mist)
            Spacer(minLength: 0)
            Text(verbatim: link.host)
                .font(.footnote)
                .foregroundStyle(OceanTheme.foam)
                .lineLimit(1)
        }
        .padding(10)
        .frame(
            minWidth: Self.tileSize, maxWidth: 168,
            minHeight: Self.tileSize, maxHeight: Self.tileSize,
            alignment: .leading
        )
        .background(Color.white.opacity(0.08), in: tileShape)
        .overlay(alignment: .topTrailing) {
            RemoveBadge(label: Text("Remove link")) { onRemoveLink(link.urlString) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(NodeKind.link.label))
        .accessibilityValue(Text(verbatim: link.host))
    }
}

/// The small ✕ in a tile's corner: a white glyph on a dark disc, so it
/// reads on any photo, inside a 32 pt target.
private struct RemoveBadge: View {
    let label: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.black.opacity(0.6), in: Circle())
                .padding(4)
                .frame(width: 32, height: 32, alignment: .topTrailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
