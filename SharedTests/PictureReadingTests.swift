import XCTest
import Foundation

/// The deterministic half of reading a picture into words: what the device
/// read becomes one passage the understanding and retrieval layers take.
final class PictureReadingTests: XCTestCase {

    // MARK: Text

    func test_text_dropsNoise_dedupes_andKeepsReadingOrder() {
        let text = PictureReading.tidyText(["Blue  Bottle Coffee", "•", "x", "Cappuccino x2", "blue bottle coffee", "9.50"])
        XCTAssertEqual(text, "Blue Bottle Coffee Cappuccino x2 9.50")
    }

    func test_text_isNil_whenNothingSurvives() {
        XCTAssertNil(PictureReading.tidyText([]))
        XCTAssertNil(PictureReading.tidyText(["-", " ", "·"]))
    }

    func test_text_stopsAtTheCap() {
        let lines = (0..<100).map { "line number \($0) of the long screenshot" }
        let text = PictureReading.tidyText(lines)!
        XCTAssertLessThanOrEqual(text.count, PictureReading.maxTextLength)
        XCTAssertTrue(text.hasPrefix("line number 0"))
    }

    func test_text_keepsChinese() {
        XCTAssertEqual(PictureReading.tidyText(["红烧肉 小火慢炖"]), "红烧肉 小火慢炖")
    }

    // MARK: Labels

    func test_labels_dropGeneric_dedupe_andCap() {
        let labels = PictureReading.tidyLabels(["outdoor", "land", "Sunset", "sea_shore", "sunset", "beach", "sky", "cloud", "dune", "wave"])
        XCTAssertEqual(labels, ["sunset", "sea shore", "beach", "sky", "cloud"])
    }

    // MARK: The passage

    func test_context_namesThePicture_thenItsWords() {
        XCTAssertEqual(
            PictureReading.context(text: "Blue Bottle Coffee 9.50", labels: ["document", "text"]),
            "Picture of document and text. Text in the picture: Blue Bottle Coffee 9.50"
        )
        XCTAssertEqual(PictureReading.context(text: nil, labels: ["beach", "sea", "sunset"]), "Picture of beach, sea and sunset.")
        XCTAssertEqual(PictureReading.context(text: "Hello", labels: []), "Text in the picture: Hello")
        XCTAssertEqual(PictureReading.context(text: "  ", labels: []), "")
    }

    // MARK: On a thought

    func test_node_meaningAndRetrieval_carryThePicture_onlyOnceRead() {
        let node = Node(kind: .image, imageData: Data([0xFF, 0xD8]))
        XCTAssertTrue(node.hasImages)
        XCTAssertTrue(node.needsPictureReading)
        XCTAssertEqual(node.pictureContext, "")
        XCTAssertEqual(node.rawContent, "")

        node.pictureText = "Cappuccino x2"
        node.pictureLabels = ["document"]
        node.pictureReadingVersion = PictureReading.version
        XCTAssertFalse(node.needsPictureReading)
        XCTAssertEqual(node.pictureContext, "Picture of document. Text in the picture: Cappuccino x2")
        XCTAssertEqual(node.meaningText, node.pictureContext)
        XCTAssertEqual(node.rawContent, node.pictureContext)
        XCTAssertTrue(node.searchableText.contains("Cappuccino"))
        XCTAssertTrue(node.retrievalTexts.joined().contains("Cappuccino"))

        node.clearPictureReading()
        XCTAssertTrue(node.needsPictureReading)
        XCTAssertEqual(node.pictureContext, "")
    }

    func test_node_withoutPictures_hasNoPictureContext() {
        let node = Node(text: "Just words")
        XCTAssertFalse(node.needsPictureReading)
        XCTAssertEqual(node.pictureContext, "")
        XCTAssertEqual(node.meaningText, "Just words")
    }
}
