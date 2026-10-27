import XCTest
import SwiftData

/// What a thought may carry when it leaves the device.
///
/// The share is the user's own words, an edited title, their link, and their
/// pictures. Example thoughts stay in, and so does everything the device
/// wrote (a distilled title, a summary, a page's text, a picture reading).
final class ThoughtShareContentTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Node.self, NodeImage.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    func test_example_isNotShareable() throws {
        let node = try thought { node in
            node.isExample = true
            node.text = "A starter thought"
            node.imageData = Data([1])
        }

        XCTAssertNil(ThoughtShareContent.make(from: node))
    }

    func test_machineTitle_isLeftOut() throws {
        let node = try thought { node in
            node.title = "Distilled title"
            node.titleEditedByUser = false
            node.text = "What I actually wrote"
        }

        let content = try share(node)
        XCTAssertNil(content.title)
        XCTAssertEqual(content.plainText, "What I actually wrote")
    }

    func test_editedTitle_isKept() throws {
        let node = try thought { node in
            node.title = "Mine"
            node.titleEditedByUser = true
            node.text = "What I actually wrote"
        }

        let content = try share(node)
        XCTAssertEqual(content.title, "Mine")
        XCTAssertEqual(content.plainText, "Mine\n\nWhat I actually wrote")
    }

    func test_titleEqualToWords_isNotRepeated() throws {
        let node = try thought { node in
            node.title = "What I actually wrote"
            node.titleEditedByUser = true
            node.text = "What I actually wrote"
        }

        let content = try share(node)
        XCTAssertNil(content.title)
        XCTAssertEqual(content.plainText, "What I actually wrote")
    }

    func test_voice_includesTranscriptNotSummary() throws {
        let node = try thought { node in
            node.transcription = "the sea was grey"
            node.summary = "MACHINE SUMMARY"
        }

        let content = try share(node)
        XCTAssertEqual(content.words, "the sea was grey")
        XCTAssertFalse(content.plainText.contains("MACHINE SUMMARY"))
    }

    func test_typedAndTranscript_keepsBothTypedFirst() throws {
        let node = try thought { node in
            node.text = "I wrote this"
            node.transcription = "I said this"
        }

        let content = try share(node)
        XCTAssertEqual(content.words, "I wrote this\n\nI said this")
    }

    func test_typedAndIdenticalTranscript_keepsTheWordsOnce() throws {
        let node = try thought { node in
            node.text = "I wrote this"
            node.transcription = "I wrote this"
        }

        let content = try share(node)
        XCTAssertEqual(content.words, "I wrote this")
    }

    func test_link_carriesURLAndNoteNotPageText() throws {
        let node = try thought { node in
            node.text = "a note"
            node.linkURLString = "https://example.com/page"
            node.linkTitle = "PAGE TITLE"
            node.linkDescription = "PAGE DESCRIPTION"
            node.linkSummary = "PAGE SUMMARY"
        }

        let content = try share(node)
        XCTAssertEqual(content.plainText, "a note\n\nhttps://example.com/page")
        XCTAssertFalse(content.plainText.contains("PAGE TITLE"))
        XCTAssertFalse(content.plainText.contains("PAGE DESCRIPTION"))
        XCTAssertFalse(content.plainText.contains("PAGE SUMMARY"))
    }

    func test_linkAlreadyInWords_isNotRepeated() throws {
        let node = try thought { node in
            node.text = "see https://example.com/page today"
            node.linkURLString = "https://example.com/page"
        }

        let content = try share(node)
        XCTAssertNil(content.link)
        XCTAssertEqual(content.plainText, "see https://example.com/page today")
    }

    func test_linkWithoutNote_sharesTheURL() throws {
        let node = try thought { node in
            node.linkURLString = "https://example.com/page"
            node.linkTitle = "PAGE TITLE"
        }

        let content = try share(node)
        XCTAssertFalse(content.hasWords)
        XCTAssertEqual(content.plainText, "https://example.com/page")
    }

    func test_images_followSortIndex() throws {
        let node = try thought(images: [
            (Data([10]), 2),
            (Data([20]), 0),
            (Data([30]), 1),
        ])

        let content = try share(node)
        XCTAssertEqual(content.images, [Data([20]), Data([30]), Data([10])])
    }

    func test_legacyImage_isIncluded() throws {
        let node = try thought { node in
            node.imageData = Data([7])
        }

        let content = try share(node)
        XCTAssertEqual(content.images, [Data([7])])
        XCTAssertFalse(content.hasWords)
        XCTAssertEqual(content.plainText, "")
    }

    func test_pictureReading_isLeftOut() throws {
        let node = try thought { node in
            node.text = "my note"
            node.pictureText = "NO PARKING"
            node.pictureLabels = ["lighthouse"]
            node.themes = ["THEMESECRET"]
        }

        let content = try share(node)
        XCTAssertEqual(content.plainText, "my note")
        XCTAssertFalse(content.plainText.contains("NO PARKING"))
        XCTAssertFalse(content.plainText.contains("lighthouse"))
        XCTAssertFalse(content.plainText.contains("THEMESECRET"))
    }

    func test_summaryAlone_isNotShareable() throws {
        let node = try thought { node in
            node.summary = "MACHINE SUMMARY"
        }

        XCTAssertNil(ThoughtShareContent.make(from: node))
    }

    func test_emptyWhisper_isNotShareable() throws {
        let node = try thought { node in
            node.transcription = "   "
        }

        XCTAssertNil(ThoughtShareContent.make(from: node))
    }

    func test_make_doesNotChangeTheThought() throws {
        let node = try thought { node in
            node.text = "kept"
            node.summary = "MACHINE SUMMARY"
        }
        let updated = node.updatedAt

        _ = ThoughtShareContent.make(from: node)

        XCTAssertEqual(node.text, "kept")
        XCTAssertEqual(node.summary, "MACHINE SUMMARY")
        XCTAssertEqual(node.updatedAt, updated)
        XCTAssertFalse(node.titleEditedByUser)
    }

    // MARK: - Fixtures

    private func thought(
        images: [(Data, Int)] = [],
        _ apply: (Node) -> Void = { _ in }
    ) throws -> Node {
        let node = Node()
        apply(node)
        let records = images.map { NodeImage(data: $0.0, sortIndex: $0.1) }
        if !records.isEmpty { node.images = records }
        context.insert(node)
        records.forEach { context.insert($0) }
        try context.save()
        return node
    }

    private func share(_ node: Node) throws -> ThoughtShareContent {
        try XCTUnwrap(ThoughtShareContent.make(from: node))
    }
}
