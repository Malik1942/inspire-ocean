import XCTest
import SwiftData

/// Whose words these are. Only the user's own (what they wrote, what they
/// said) stand in the serif; everything the device or a website wrote is
/// left to the system's face.
final class OwnWordsTests: XCTestCase {

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

    func test_writtenWords_areTheirs() throws {
        let node = try thought { node in
            node.title = "A button that doesn't need a label"
            node.text = "  If the icon is the action, the word next to it is noise.\n"
        }

        XCTAssertEqual(node.ownWords, "If the icon is the action, the word next to it is noise.")
    }

    func test_whisper_isTheirs() throws {
        let node = try thought { node in
            node.title = "Rain"
            node.transcription = "Everything is quieter after the rain."
        }

        XCTAssertEqual(node.ownWords, "Everything is quieter after the rain.")
    }

    func test_summaryAndLinkWords_areNotTheirs() throws {
        let node = try thought { node in
            node.title = "Apple Design Principles"
            node.summary = "A summary the device wrote."
            node.linkURLString = "https://developer.apple.com/design/"
            node.linkDescription = "The site's own description."
            node.linkSummary = "What enrichment learned."
        }

        XCTAssertNil(node.ownWords)
    }

    func test_bareAddress_isNotTheirWords() throws {
        let node = try thought { node in
            node.title = "Apple Design Principles"
            node.text = "https://developer.apple.com/design/"
            node.linkURLString = "https://developer.apple.com/design/"
        }

        XCTAssertNil(node.ownWords)
    }

    func test_wordsThatAreOnlyTheTitle_areNotRepeated() throws {
        let node = try thought { node in
            node.text = "Desk at 6pm"
        }

        XCTAssertNil(node.ownWords)
    }

    private func thought(_ apply: (Node) -> Void) throws -> Node {
        let node = Node()
        apply(node)
        context.insert(node)
        try context.save()
        return node
    }
}
