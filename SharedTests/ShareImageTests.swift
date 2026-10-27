import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// Pictures that leave the device are upright JPEGs with no location or
/// camera metadata, in the order they were given. A picture that cannot be
/// read is counted, not dropped quietly.
final class ShareImageTests: XCTestCase {

    func test_prepared_stripsLocationAndCaptureDate() throws {
        let original = try image(width: 20, height: 10, gps: true, captureDate: true)
        let source = try properties(of: original)
        XCTAssertNotNil(source[kCGImagePropertyGPSDictionary])
        let exif = source[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNotNil(exif?[kCGImagePropertyExifDateTimeOriginal])

        let prepared = try XCTUnwrap(ShareImage.prepared(original, maxPixel: 1600))
        let stripped = try properties(of: prepared)
        XCTAssertNil(stripped[kCGImagePropertyGPSDictionary])
        let strippedExif = stripped[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(strippedExif?[kCGImagePropertyExifDateTimeOriginal])
        let tiff = stripped[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        XCTAssertNil(tiff?[kCGImagePropertyTIFFDateTime])
    }

    func test_prepared_writesPNGAsJPEG() throws {
        let png = try image(width: 12, height: 8, kind: .png)
        XCTAssertEqual(png.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))

        let prepared = try XCTUnwrap(ShareImage.prepared(png, maxPixel: 1600))
        XCTAssertEqual(prepared.prefix(2), Data([0xFF, 0xD8]))
    }

    func test_prepared_capsTheLongEdge() throws {
        let original = try image(width: 4000, height: 3000)
        let prepared = try XCTUnwrap(ShareImage.prepared(original, maxPixel: 1600))
        let size = try pixelSize(of: prepared)
        XCTAssertEqual(max(size.width, size.height), 1600)
        XCTAssertLessThanOrEqual(size.width, 1600)
        XCTAssertLessThanOrEqual(size.height, 1600)
    }

    func test_prepared_turnsARotatedPictureUpright() throws {
        // Stored 400×200, tagged so it displays as 200×400. The copy that
        // leaves is the displayed size, and is not tagged as rotated again.
        let original = try image(width: 400, height: 200, orientation: 6)
        let prepared = try XCTUnwrap(ShareImage.prepared(original, maxPixel: 1600))
        let size = try pixelSize(of: prepared)
        XCTAssertEqual(size.width, 200)
        XCTAssertEqual(size.height, 400)
        let orientation = try properties(of: prepared)[kCGImagePropertyOrientation] as? Int
        XCTAssertTrue(orientation == nil || orientation == 1)
    }

    func test_prepared_returnsNilForBytesThatAreNotAPicture() {
        XCTAssertNil(ShareImage.prepared(Data([0, 1, 2, 3]), maxPixel: 1600))
    }

    func test_preparedAll_keepsOrderAndCountsWhatItCouldNotRead() throws {
        let first = try image(width: 8, height: 8)
        let third = try image(width: 9, height: 6)
        let result = ShareImage.preparedAll(
            [first, Data([0, 1, 2, 3]), third],
            maxPixel: 1600
        )

        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(result.images.count, 2)
        XCTAssertEqual(result.images[0], ShareImage.prepared(first, maxPixel: 1600))
        XCTAssertEqual(result.images[1], ShareImage.prepared(third, maxPixel: 1600))
    }

    // MARK: - Fixtures

    private enum Kind { case jpeg, png }

    private func image(
        width: Int,
        height: Int,
        kind: Kind = .jpeg,
        orientation: Int? = nil,
        gps: Bool = false,
        captureDate: Bool = false
    ) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            XCTFail("Could not draw a fixture")
            return Data()
        }
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let picture = context.makeImage() else {
            XCTFail("Could not draw a fixture")
            return Data()
        }

        let data = NSMutableData()
        let type = kind == .jpeg ? UTType.jpeg : UTType.png
        guard let destination = CGImageDestinationCreateWithData(
            data,
            type.identifier as CFString,
            1,
            nil
        ) else {
            XCTFail("Could not encode a fixture")
            return Data()
        }
        var properties: [CFString: Any] = [:]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        if gps {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 37.78,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.42,
                kCGImagePropertyGPSLongitudeRef: "W",
            ]
        }
        if captureDate {
            properties[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifDateTimeOriginal: "2020:01:02 03:04:05",
            ]
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFDateTime: "2020:01:02 03:04:05",
            ]
        }
        CGImageDestinationAddImage(destination, picture, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func pixelSize(of data: Data) throws -> (width: Int, height: Int) {
        let props = try properties(of: data)
        let width = try XCTUnwrap(props[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(props[kCGImagePropertyPixelHeight] as? Int)
        return (width, height)
    }
}
