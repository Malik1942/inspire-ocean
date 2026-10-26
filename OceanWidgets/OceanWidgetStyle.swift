import SwiftUI
import WidgetKit
import ImageIO

/// WidgetKit owns the outside margins and removes the still water for tinted
/// and clear appearances. Controls wear the app's content surfaces.
enum OceanWidgetStyle {
    static var water: LinearGradient {
        LinearGradient(
            colors: [OceanTheme.abyss, OceanTheme.deep, OceanTheme.mid],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Timeline images must fit the extension's memory budget even when the
    /// original is a full camera image. Never decode the original in a view.
    static func thumbnail(_ data: Data?) -> Data? {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
    }
}
