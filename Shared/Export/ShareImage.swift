import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A picture made safe to hand to another app.
///
/// Pictures saved from the share extension or Siri keep the file they arrived
/// as, which can still carry a location. Every picture that leaves is
/// re-encoded here as an upright JPEG with no metadata, and no larger than
/// the caller asks. ImageIO does the work, so this stays out of UIKit. A
/// picture that cannot be read is counted, so the caller can say so instead
/// of dropping it quietly.
enum ShareImage {
    /// Longest edge for a picture leaving the device. The same edge in-app
    /// attachments are stored at.
    static let maxPixel: CGFloat = 1600

    /// An upright JPEG no wider or taller than `maxPixel`, with no metadata.
    /// Nil when `data` is not a picture.
    static func prepared(_ data: Data, maxPixel: CGFloat) -> Data? {
        guard let image = thumbnail(from: data, maxPixel: maxPixel) else { return nil }
        return jpeg(from: image)
    }

    /// Each picture `prepared`, in the same order. `skipped` is how many
    /// could not be read.
    static func preparedAll(_ datas: [Data], maxPixel: CGFloat) -> (images: [Data], skipped: Int) {
        var images: [Data] = []
        var skipped = 0
        for data in datas {
            if let image = prepared(data, maxPixel: maxPixel) {
                images.append(image)
            } else {
                skipped += 1
            }
        }
        return (images, skipped)
    }

    /// The picture, upright, never decoded larger than `maxPixel`.
    private static func thumbnail(from data: Data, maxPixel: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Pixels only. An empty property dictionary is what keeps the original
    /// location and camera data from being copied onto the new file.
    private static func jpeg(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [:] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
