import SwiftUI
import UIKit
import ImageIO

/// Today's thought when it has a picture: the picture is the stage. It fills
/// the top of Tide edge to edge from under the status bar, sharp at the top
/// and dissolving into a blur of itself at its foot, where the caption (the
/// label and the title) stands. Below it, the picture's own last rows carry
/// on, mirrored, stretched, blurred and darkened, and fade into the water, so
/// the page reads as one scene rather than a photograph on black (Malik,
/// 2026-11-02). Continuing the last rows, not an average of the picture,
/// leaves no seam where the picture ends.
///
/// On a light picture the water's dark rises behind the words, only as much
/// as the picture's light needs (read once, with its foot): behind the
/// caption, then on under the words below the stage. A dark picture gets
/// none and looks as it always has.
///
/// `height` is measured from the top edge of the screen. The view draws
/// `topInset` above its own frame and past the page's gutters, so the caller
/// places it first in the scroll content and it reaches every edge.
struct ResurfacingPicture<Caption: View>: View {
    let image: UIImage
    /// The picture's bytes and an id to cache its foot by.
    let data: Data
    let id: UUID
    let height: CGFloat
    let topInset: CGFloat
    /// The head stands below the picture instead of on it (accessibility
    /// sizes, with an empty caption), so the bleed's scrim holds all the way
    /// down rather than fading after the words' first lines.
    var holdsScrim = false
    @ViewBuilder let caption: Caption

    @State private var foot: PictureFoot.Reading?
    @State private var width: CGFloat = 0
    /// The caption's height with its foot inset, read off its layout. Only
    /// the layers behind it use it (the scrim, the reading), never the
    /// caption itself.
    @State private var captionHeight: CGFloat = 0

    /// How far the picture's foot carries on below it before the water
    /// takes over. Art-directed, with the blur and the darkening.
    private static var bleedDepth: CGFloat { 200 }

    var body: some View {
        // The bleed lies inside this view's own frame, under the stage; the
        // page's next lines are pulled up over it by the bottom padding.
        // The picture's layers reach the screen's sides past the safe area
        // (landscape); the caption keeps to the page's column.
        ZStack(alignment: .top) {
            bleed
                .ignoresSafeArea(.container, edges: .horizontal)
            bleedScrim
                .ignoresSafeArea(.container, edges: .horizontal)
            ZStack(alignment: .bottomLeading) {
                picture
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0.48), .init(color: .clear, location: 0.96)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    // The width the picture is shown at, edge to edge: it
                    // is cropped to this frame.
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                    .ignoresSafeArea(.container, edges: .horizontal)
                // The status bar reads on any picture.
                LinearGradient(colors: [OceanTheme.scrim, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.18))
                    .allowsHitTesting(false)
                    .ignoresSafeArea(.container, edges: .horizontal)
                captionScrim
                    .ignoresSafeArea(.container, edges: .horizontal)
                caption
                    .oceanShadow(OceanShadow.text)
                    .oceanReadableColumn()
                    .padding(.horizontal, OceanSpacing.gutter)
                    .padding(.bottom, OceanSpacing.item)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { captionHeight = $0 }
            }
            .frame(height: height)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height + Self.bleedDepth, alignment: .top)
        .padding(.top, -topInset)
        .padding(.bottom, -Self.bleedDepth)
        .padding(.horizontal, -OceanSpacing.gutter)
        .task(id: footKey) {
            guard width > 0 else { return }
            let reading = await PictureFoot.reading(of: data, key: footKey, aspect: width / height, ground: ground)
            // Read for a picture, crop or caption that has since changed:
            // the newer reading lands instead.
            guard !Task.isCancelled else { return }
            foot = reading
        }
    }

    /// What the foot's reading depends on, so a new picture, crop or
    /// caption is read afresh and an unchanged one comes from the cache.
    private var footKey: PictureFoot.Key {
        PictureFoot.Key(id: id, bytes: data.count,
                        aspect: Int((width / height * 100).rounded()),
                        ground: Int((ground * 20).rounded()))
    }

    /// How much of the stage the caption stands on, up from its foot: the
    /// bottom 55%, or the caption's own height when it stands taller (a
    /// long title at a larger text size, a shorter stage).
    private var ground: CGFloat {
        min(1, max(0.55, standing / height)) // art-directed: where the caption stands
    }

    /// The caption's height on the stage. None when the head stands below
    /// the picture (`holdsScrim`): the caption is then empty, reports no
    /// layout, and its last height would linger.
    private var standing: CGFloat { holdsScrim ? 0 : captionHeight }

    private var picture: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay { Image(uiImage: image).resizable().scaledToFill() }
            .clipped()
            .accessibilityHidden(true)
    }

    /// A blurred copy of the picture under its own dissolving foot, then its
    /// last rows mirrored below it, darkened so words stay readable on them,
    /// fading out into the water.
    private var bleed: some View {
        let total = height + Self.bleedDepth
        return VStack(spacing: 0) {
            picture
            Group {
                if let rows = foot?.rows {
                    Image(uiImage: rows).resizable().scaleEffect(x: 1, y: -1)
                } else {
                    OceanTheme.deep
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.bleedDepth)
        }
        // Not opaque: an opaque blur stopped at the picture's foot and left a
        // seam; the soft edges this leaves at the sides fall on dark water.
        .blur(radius: 32, opaque: false) // art-directed: the picture carrying on
        .colorMultiply(Color(white: 0.64)) // art-directed: darkened under the words
        .mask {
            // Fading from the picture's foot on: no more than a breath of
            // its color under the words (Malik, 2026-11-02).
            LinearGradient(stops: [
                .init(color: .black, location: height / total),
                .init(color: .black.opacity(0.35), location: (height + Self.bleedDepth * 0.35) / total), // art-directed: the fade
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
        .frame(height: total, alignment: .top)
        .allowsHitTesting(false)
    }

    /// The abyss behind the caption on a light picture: rising from the
    /// stage's top to as dark as the picture needs at 45% of the stage, and
    /// holding to its foot. A caption that stands higher (a long title at a
    /// larger text size, a shorter stage) takes the full stop up with its
    /// top, so none of its words stands above the dark.
    @ViewBuilder
    private var captionScrim: some View {
        let strength = Self.captionStrength(foot?.captionGray)
        if strength > 0 {
            let full = min(0.45, max(0.15, 1 - standing / height)) // art-directed: the caption scrim
            LinearGradient(stops: Self.captionStops(strength: strength, full: full), startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
    }

    /// The caption scrim's rise, eased at both ends (smoothstep) over the
    /// whole stage above `full`: a straight ramp over 15% of the stage, up
    /// to 62% dark on a near-white picture, read as a hard edge across it
    /// rather than the water rising (Malik, 2026-11-03).
    private static func captionStops(strength: CGFloat, full: CGFloat) -> [Gradient.Stop] {
        let steps = 8
        let rise = (0...steps).map { step -> Gradient.Stop in
            let t = CGFloat(step) / CGFloat(steps)
            let eased = t * t * (3 - 2 * t)
            return .init(color: OceanTheme.abyss.opacity(strength * eased), location: full * t)
        }
        return rise + [.init(color: OceanTheme.abyss.opacity(strength), location: 1)]
    }

    /// The abyss carried on below the stage, under the words: the caption's
    /// strength at the foot, so the two meet without an edge, then the
    /// bleed's own.
    @ViewBuilder
    private var bleedScrim: some View {
        let atFoot = Self.captionStrength(foot?.captionGray)
        let held = Self.bleedStrength(foot?.footGray)
        if atFoot > 0 || held > 0 {
            LinearGradient(stops: Self.bleedStops(atFoot: atFoot, held: held, holds: holdsScrim),
                           startPoint: .top, endPoint: .bottom)
                .frame(height: Self.bleedDepth)
                .padding(.top, height)
                .allowsHitTesting(false)
        }
    }

    /// The bleed scrim reaches its own strength 24 pt below the foot and
    /// holds it to 96 pt, under the words' first lines, then is gone by the
    /// bleed's end; it holds to the end when the head stands there.
    private static func bleedStops(atFoot: CGFloat, held: CGFloat, holds: Bool) -> [Gradient.Stop] {
        let reached: [Gradient.Stop] = [
            .init(color: OceanTheme.abyss.opacity(atFoot), location: 0),
            .init(color: OceanTheme.abyss.opacity(held), location: 24 / bleedDepth) // art-directed: the bleed scrim
        ]
        if holds {
            return reached + [.init(color: OceanTheme.abyss.opacity(held), location: 1)]
        }
        return reached + [
            .init(color: OceanTheme.abyss.opacity(held), location: 96 / bleedDepth), // art-directed: the bleed scrim
            .init(color: OceanTheme.abyss.opacity(0), location: 1)
        ]
    }

    /// The caption scrim's strength on a picture this light where the
    /// caption stands: none at 0.32 or darker, so a dark picture looks as it
    /// always has; on white, enough for the warm label at 4.8:1 and the
    /// title at 7.5:1.
    private static func captionStrength(_ gray: CGFloat?) -> CGFloat {
        guard let gray, gray > 0.32 else { return 0 } // art-directed: the caption scrim
        return min(1 - 0.32 / gray, 0.72) // art-directed: the caption scrim
    }

    /// The bleed scrim's strength under the words below the stage. The bleed
    /// is the foot darkened (the bleed's colorMultiply), so it needs less; on
    /// white, foam words clear 8.4:1 and the domain in text 5.2:1.
    private static func bleedStrength(_ gray: CGFloat?) -> CGFloat {
        guard let gray else { return 0 }
        let bleed = 0.64 * gray // art-directed: the bleed's own darkening
        guard bleed > 0.26 else { return 0 } // art-directed: the bleed scrim
        return min(1 - 0.26 / bleed, 0.65) // art-directed: the bleed scrim
    }
}

/// What the stage reads off its picture, once for each picture, crop and
/// caption (`Key`), off the main thread, from a small upright copy: its
/// last visible rows, which carry on below it, and how light it is where
/// words stand on it.
private enum PictureFoot {
    /// What a reading depends on: the picture (its thought, and its length
    /// in bytes, which a replaced picture changes), the crop's aspect to
    /// the hundredth and the caption's ground to 0.05.
    struct Key: Hashable {
        let id: UUID
        let bytes: Int
        let aspect: Int
        let ground: Int
    }

    struct Reading {
        /// The bottom quarter of the shown picture.
        let rows: UIImage
        /// How light the caption's ground is: the part of the shown picture
        /// the caption stands on, up from its foot.
        let captionGray: CGFloat
        /// How light the rows the bleed carries on are.
        let footGray: CGFloat
    }

    /// One reading per thought, returned only for its exact key: a new
    /// picture, crop or caption replaces the thought's last reading instead
    /// of piling up (a window resized live would leave one per step).
    @MainActor private static var cache: [UUID: (key: Key, reading: Reading)] = [:]

    @MainActor
    static func reading(of data: Data, key: Key, aspect: CGFloat, ground: CGFloat) async -> Reading? {
        if let known = cache[key.id], known.key == key { return known.reading }
        guard let read = await Task.detached(priority: .utility, operation: { measure(data, aspect: aspect, ground: ground) }).value else { return nil }
        let reading = Reading(rows: UIImage(cgImage: read.rows), captionGray: read.captionGray, footGray: read.footGray)
        cache[key.id] = (key, reading)
        return reading
    }

    /// The part of the picture the stage shows: the stage fills its frame, so
    /// it crops the picture to the frame's aspect about the center, and the
    /// rows that continue below must be the rows seen at its foot. Its bottom
    /// quarter carries on below the stage; its bottom `ground` (a fraction
    /// of its height) is where the caption stands. At most 240 px wide:
    /// blurred, more would be wasted.
    private static func measure(_ data: Data, aspect: CGFloat, ground: CGFloat) -> (rows: CGImage, captionGray: CGFloat, footGray: CGFloat)? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 240
        ] as CFDictionary
        guard aspect > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let width = CGFloat(upright.width), height = CGFloat(upright.height)
        var shown = CGRect(x: 0, y: 0, width: width, height: height)
        if width / height > aspect {
            shown.size.width = height * aspect
            shown.origin.x = (width - shown.width) / 2
        } else {
            shown.size.height = width / aspect
            shown.origin.y = (height - shown.height) / 2
        }
        let quarter = max(1, shown.height / 4)
        guard let rows = upright.cropping(to: CGRect(x: shown.minX, y: shown.maxY - quarter, width: shown.width, height: quarter).integral) else { return nil }
        let stands = max(1, shown.height * ground)
        let caption = upright.cropping(to: CGRect(x: shown.minX, y: shown.maxY - stands, width: shown.width, height: stands).integral)
        return (rows, caption.map { lightness(of: $0) } ?? 0, lightness(of: rows))
    }

    /// How light a region is for a word standing on it: the 90th percentile
    /// of its luma, from sRGB as encoded (0.2126 R′ + 0.7152 G′ + 0.0722 B′),
    /// 0 to 1. A percentile rather than the mean, so a bright patch behind a
    /// word counts on an otherwise dark picture.
    private static func lightness(of image: CGImage) -> CGFloat {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return 0 }
        var histogram = [Int](repeating: 0, count: 256)
        for pixel in stride(from: 0, to: width * height * 4, by: 4) {
            let luma = 0.2126 * Double(pixels[pixel]) + 0.7152 * Double(pixels[pixel + 1]) + 0.0722 * Double(pixels[pixel + 2])
            histogram[min(255, Int(luma.rounded()))] += 1
        }
        let rank = Int((Double(width * height) * 0.9).rounded(.up))
        var seen = 0
        for (level, count) in histogram.enumerated() {
            seen += count
            if seen >= rank { return CGFloat(level) / 255 }
        }
        return 1
    }
}
