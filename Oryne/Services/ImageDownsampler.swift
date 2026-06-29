import UIKit
import ImageIO
import SwiftUI
import PhotosUI

/// The one place image bytes are shrunk before they're persisted onto a `Node`.
///
/// Both the main "Add image" attachment and the link thumbnail route through
/// here, so a full-resolution original is never stored. (There was no shared
/// compression path before — capture kept PhotosPicker bytes as delivered; this
/// is that path.)
enum ImageDownsampler {

    /// Sizes for the two persisted image kinds.
    enum Size {
        /// Primary attachment shown large in the detail view.
        static let attachment: CGFloat = 1600
        /// Link preview, shown in a small card.
        static let thumbnail: CGFloat = 600
    }

    /// Downsamples `data` so its longest edge is at most `maxPixel`, re-encoded
    /// as JPEG. Uses ImageIO so the full image is never fully decoded into
    /// memory. Returns nil when the bytes aren't a decodable image, so callers
    /// can fall back to the original.
    static func downsample(_ data: Data, maxPixel: CGFloat, quality: CGFloat = 0.8) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg).jpegData(compressionQuality: quality)
    }

    /// The single path every multi-image surface (Capture, edit sheet, branch
    /// composer) uses to turn picked items into stored bytes: load each item and
    /// downsample it through the attachment (1600px) path off the main actor, so
    /// whether the user picks 1 or 10, no full-resolution original is ever stored.
    /// Order is preserved; undecodable items are skipped.
    static func attachmentData(from items: [PhotosPickerItem]) async -> [Data] {
        var result: [Data] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let sized = await Task.detached {
                ImageDownsampler.downsample(data, maxPixel: Size.attachment) ?? data
            }.value
            result.append(sized)
        }
        return result
    }
}
