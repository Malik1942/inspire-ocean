import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// A thought's picture made ready to fill the Resurfacing widget's card:
/// cropped to the card's exact shape about the center, at the card's own
/// pixel size (WidgetKit refuses to archive an image much larger than its
/// widget, and a full camera image would also break the extension's memory
/// budget), plus how light it is where the words stand.
///
/// The darkening follows the stage on Tide (`ResurfacingPicture`'s caption
/// scrim): none on a picture at 0.32 or darker, rising on a lighter one to at
/// most 0.72 on white, so a dark picture looks as it is and the words stay
/// readable on a bright one. Retune the two together.
enum WidgetPicture {

    /// The part of the card the words stand on, up from its foot.
    static let ground: CGFloat = 0.55

    struct Card: Equatable {
        /// JPEG, exactly the requested pixel size.
        let data: Data
        /// How light the words' ground is, 0 to 1 (the 90th percentile of
        /// its luma, as the stage reads it).
        let groundLightness: CGFloat
        /// How dark the water rises behind the words, 0 to 0.72.
        var scrimStrength: CGFloat { WidgetPicture.scrimStrength(forLightness: groundLightness) }
    }

    /// The card's picture, or nil when the bytes are not an image or the
    /// size is empty.
    static func card(from data: Data, pixelSize: CGSize) -> Card? {
        let width = Int(pixelSize.width.rounded()), height = Int(pixelSize.height.rounded())
        guard width > 0, height > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                // Enough to fill the card's longer side from a picture of any
                // shape; never the original's full size.
                kCGImageSourceThumbnailMaxPixelSize: min(2048, 2 * max(width, height)),
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(upright, in: fillRect(image: CGSize(width: upright.width, height: upright.height),
                                           in: CGSize(width: width, height: height)))
        guard let card = context.makeImage() else { return nil }
        let stands = max(1, Int((CGFloat(height) * ground).rounded()))
        let foot = card.cropping(to: CGRect(x: 0, y: height - stands, width: width, height: stands))
        guard let jpeg = jpeg(card) else { return nil }
        return Card(data: jpeg, groundLightness: foot.map(lightness(of:)) ?? 0)
    }

    /// Where to draw an image so it fills `target` without distortion,
    /// centered, its overflow falling outside on the longer axis.
    static func fillRect(image: CGSize, in target: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return CGRect(origin: .zero, size: target) }
        let scale = max(target.width / image.width, target.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (target.width - size.width) / 2, y: (target.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// The stage's caption scrim for a ground this light: none at 0.32 or
    /// darker; on white, enough for the title at 7.5:1.
    static func scrimStrength(forLightness gray: CGFloat) -> CGFloat {
        guard gray > 0.32 else { return 0 }
        return min(1 - 0.32 / gray, 0.72)
    }

    /// How light a region is for a word standing on it: the 90th percentile
    /// of its luma (0.2126 R′ + 0.7152 G′ + 0.0722 B′ as encoded), 0 to 1. A
    /// percentile rather than the mean, so one bright patch behind a word
    /// counts on an otherwise dark picture. Read from a copy at most 96 px
    /// wide: the scrim needs a level, not detail.
    static func lightness(of image: CGImage) -> CGFloat {
        let scale = min(1, 96 / CGFloat(max(1, image.width)))
        let width = max(1, Int(CGFloat(image.width) * scale)), height = max(1, Int(CGFloat(image.height) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
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

    private static func jpeg(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
