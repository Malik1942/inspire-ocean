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

/// What rides on the composer's card above the words: a whisper taken back
/// (Undo, or a save the store refused), its pictures in the order picked, a
/// quiet tile in the place of each one still loading, and the link sensed in
/// the words. A whisper with no words would otherwise ride along unseen and
/// keep the disc on Send while the field looks empty. Tiles 64 pt high whose corners sit
/// concentric with the card's, each with its own ✕ (to VoiceOver, one
/// element with a named action). The row scrolls sideways once it is
/// wider than the card.
struct CaptureAttachments: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calmAccessibility) private var calm

    /// The pictures in pick order, loading or landed.
    let slots: [CapturePictureSlots<CaptureImage>.Slot]
    /// The link a release would attach.
    var link: LinkSensing.Sensed? = nil
    var onRemoveImage: (CaptureImage.ID) -> Void
    /// The link tile's ✕, with the link's URL.
    var onRemoveLink: (String) -> Void = { _ in }
    /// A loading tile's ✕: lets go of the pictures still on their way.
    var onCancelLoading: () -> Void = {}
    /// The length of a whisper riding along, when there is one.
    var whisper: TimeInterval? = nil
    /// The whisper tile's ✕: lets the recording go.
    var onRemoveWhisper: () -> Void = {}

    static let tileSize: CGFloat = OceanSize.pictureTile
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
            HStack(spacing: OceanSpacing.gap) {
                if let whisper {
                    whisperTile(whisper)
                        .transition(.opacity)
                }
                ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                    switch slot {
                    case .picture(let image):
                        thumbnail(image, number: index + 1)
                            .transition(arrival)
                    case .loading:
                        loadingTile(number: index + 1)
                            .transition(.opacity)
                    }
                }
                if let link {
                    linkTile(link)
                        .transition(.opacity)
                }
            }
        }
        .frame(height: Self.tileSize)
    }

    /// Which picture this is, "Image 2 of 3", counting the ones still
    /// loading: they hold their places.
    private func position(_ number: Int) -> Text {
        Text("Image \(number) of \(slots.count)")
    }

    private func thumbnail(_ image: CaptureImage, number: Int) -> some View {
        Image(uiImage: image.thumbnail)
            .resizable()
            .scaledToFill()
            .frame(width: Self.tileSize, height: Self.tileSize)
            .clipShape(tileShape)
            .overlay(alignment: .topTrailing) {
                OceanRemoveBadge { onRemoveImage(image.id) }
            }
            // VoiceOver's ring is the tile, not the filled picture spilling
            // past it.
            .contentShape(.accessibility, tileShape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(position(number))
            .accessibilityAction(named: Text("Remove image")) { onRemoveImage(image.id) }
    }

    /// A picture still on its way. Its ✕ lets go of the loads, so one that
    /// stalls (an iCloud original while offline) never holds the card.
    private func loadingTile(number: Int) -> some View {
        tileShape
            .fill(OceanTheme.raised)
            .frame(width: Self.tileSize, height: Self.tileSize)
            .overlay { ProgressView().tint(OceanTheme.mist) }
            .overlay(alignment: .topTrailing) {
                OceanRemoveBadge(action: onCancelLoading)
            }
            .contentShape(.accessibility, tileShape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(position(number))
            .accessibilityValue(Text("Loading"))
            .accessibilityAction(named: Text("Cancel"), onCancelLoading)
    }

    /// A whisper riding along: its length under the waveform glyph, on the
    /// link tile's quiet fill. Its ✕ lets the recording go.
    private func whisperTile(_ seconds: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "waveform")
                .font(OceanType.glyphDisclosure)
                .foregroundStyle(OceanTheme.mist)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(verbatim: AudioDurations.format(seconds))
                .oceanText(OceanType.meta)
                .foregroundStyle(OceanTheme.foam)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
        .padding(OceanSpacing.gap)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(width: Self.tileSize, height: Self.tileSize, alignment: .leading)
        .background(OceanTheme.raised, in: tileShape)
        .overlay(alignment: .topTrailing) {
            OceanRemoveBadge(action: onRemoveWhisper)
        }
        .contentShape(.accessibility, tileShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Whisper"))
        .accessibilityValue(Text(verbatim: AudioDurations.format(seconds)))
        .accessibilityAction(named: Text("Remove whisper"), onRemoveWhisper)
    }

    /// The sensed link: its site's name under the link glyph, on the quiet
    /// fill of a content control. Its ✕ leaves the link in the words as
    /// text, never attached.
    private func linkTile(_ link: LinkSensing.Sensed) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "link")
                .font(OceanType.glyphDisclosure)
                .foregroundStyle(OceanTheme.mist)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            // Read once, as the tile's value.
            Text(verbatim: link.host)
                .oceanText(OceanType.meta)
                .foregroundStyle(OceanTheme.foam)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
        .padding(OceanSpacing.gap)
        // The glyph and the site's name grow up to the largest standard
        // size, the largest at which both lines still fit the 64 pt tile.
        // Past it a long press shows the name large; VoiceOver reads it.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(
            minWidth: Self.tileSize, maxWidth: 168,
            minHeight: Self.tileSize, maxHeight: Self.tileSize,
            alignment: .leading
        )
        .background(OceanTheme.raised, in: tileShape)
        .overlay(alignment: .topTrailing) {
            OceanRemoveBadge { onRemoveLink(link.urlString) }
        }
        .contentShape(.accessibility, tileShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(NodeKind.link.label))
        .accessibilityValue(Text(verbatim: link.host))
        .accessibilityAction(named: Text("Remove link")) { onRemoveLink(link.urlString) }
        .accessibilityShowsLargeContentViewer {
            Label {
                Text(verbatim: link.host)
            } icon: {
                Image(systemName: "link")
            }
        }
    }
}
