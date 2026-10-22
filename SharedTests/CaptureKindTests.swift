import XCTest
import Foundation

/// Unit tests for `NodeKind.captured`: the kind a capture release gives a
/// thought from what it holds.
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class CaptureKindTests: XCTestCase {

    func testARecordingIsAWhisperWhateverRidesAlong() {
        XCTAssertEqual(NodeKind.captured(voice: true, words: "", images: 2, link: true), .voice)
    }

    func testWordsMakeAThought() {
        XCTAssertEqual(NodeKind.captured(voice: false, words: "Love this palette", images: 1, link: true), .text)
    }

    func testPicturesWithoutWordsMakeAnImage() {
        XCTAssertEqual(NodeKind.captured(voice: false, words: "  \n", images: 1, link: true), .image)
    }

    func testALinkAloneMakesALink() {
        XCTAssertEqual(NodeKind.captured(voice: false, words: "", images: 0, link: true), .link)
    }

    func testNothingFallsBackToAThought() {
        XCTAssertEqual(NodeKind.captured(voice: false, words: "", images: 0, link: false), .text)
    }
}
