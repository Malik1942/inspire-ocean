import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// `WidgetPicture`: the Resurfacing card's picture is cropped to the card's
/// exact size, and the water rises behind the words only on a light picture.
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class WidgetPictureTests: XCTestCase {

    /// A PNG of the given size: `bottom` over its lower `footShare`, `top`
    /// above it (gray levels, 0 to 1).
    private func png(width: Int, height: Int, top: CGFloat, bottom: CGFloat, footShare: CGFloat = 0.5) -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        // Core Graphics draws bottom up: y 0 is the picture's foot.
        context.setFillColor(CGColor(srgbRed: bottom, green: bottom, blue: bottom, alpha: 1))
        let foot = Int(CGFloat(height) * footShare)
        context.fill(CGRect(x: 0, y: 0, width: width, height: foot))
        context.setFillColor(CGColor(srgbRed: top, green: top, blue: top, alpha: 1))
        context.fill(CGRect(x: 0, y: foot, width: width, height: height - foot))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    private func size(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    func test_card_isExactlyTheCardsPixelSize() throws {
        let card = try XCTUnwrap(WidgetPicture.card(from: png(width: 1536, height: 1024, top: 0.5, bottom: 0.5),
                                                    pixelSize: CGSize(width: 1092, height: 510)))
        XCTAssertEqual(size(of: card.data), CGSize(width: 1092, height: 510))
    }

    func test_card_readsTheFootWhereTheWordsStand() throws {
        // A white sky over a dark street: the words stand on the street.
        let dark = try XCTUnwrap(WidgetPicture.card(from: png(width: 600, height: 600, top: 1, bottom: 0.1, footShare: 0.6),
                                                    pixelSize: CGSize(width: 300, height: 300)))
        XCTAssertLessThan(dark.groundLightness, 0.32 + 0.05)
        XCTAssertEqual(dark.scrimStrength, 0, accuracy: 0.05)

        let light = try XCTUnwrap(WidgetPicture.card(from: png(width: 600, height: 600, top: 0.1, bottom: 1),
                                                     pixelSize: CGSize(width: 300, height: 300)))
        XCTAssertGreaterThan(light.groundLightness, 0.95)
        XCTAssertEqual(light.scrimStrength, 0.68, accuracy: 0.02)
    }

    func test_card_refusesWhatIsNotAPicture() {
        XCTAssertNil(WidgetPicture.card(from: Data("not a picture".utf8), pixelSize: CGSize(width: 300, height: 150)))
        XCTAssertNil(WidgetPicture.card(from: png(width: 10, height: 10, top: 0, bottom: 0), pixelSize: .zero))
    }

    func test_scrim_noneOnADarkGround_cappedOnWhite() {
        XCTAssertEqual(WidgetPicture.scrimStrength(forLightness: 0), 0)
        XCTAssertEqual(WidgetPicture.scrimStrength(forLightness: 0.32), 0)
        XCTAssertEqual(WidgetPicture.scrimStrength(forLightness: 0.64), 0.5, accuracy: 0.0001)
        XCTAssertEqual(WidgetPicture.scrimStrength(forLightness: 1), 0.68, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(WidgetPicture.scrimStrength(forLightness: 5), 0.72)
    }

    func test_fillRect_coversTheCardAndCentersTheOverflow() {
        // A 3:2 picture in a wide card fills the width and spills top and bottom.
        let wide = WidgetPicture.fillRect(image: CGSize(width: 300, height: 200), in: CGSize(width: 400, height: 100))
        XCTAssertEqual(wide.width, 400, accuracy: 0.001)
        XCTAssertEqual(wide.height, 266.667, accuracy: 0.001)
        XCTAssertEqual(wide.midY, 50, accuracy: 0.001)
        // A tall picture in a square card fills the width and spills top and bottom.
        let tall = WidgetPicture.fillRect(image: CGSize(width: 100, height: 300), in: CGSize(width: 200, height: 200))
        XCTAssertEqual(tall.width, 200, accuracy: 0.001)
        XCTAssertEqual(tall.minY, -200, accuracy: 0.001)
    }
}
