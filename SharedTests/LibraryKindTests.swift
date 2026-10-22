import XCTest
import SwiftData

/// `LibraryKind`: which thoughts the Library's one filter keeps, on an
/// in-memory store.
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class LibraryKindTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Node.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func thought(_ kind: NodeKind = .text, link: String? = nil, image: Bool = false) -> Node {
        let node = Node(kind: kind, title: "A thought", linkURLString: link,
                        imageData: image ? Data([0xFF, 0xD8, 0xFF]) : nil)
        context.insert(node)
        return node
    }

    private func kept(by filter: LibraryKind, _ nodes: [Node]) -> [Node] {
        nodes.filter(filter.admits)
    }

    func test_all_keepsEverything() {
        let nodes = [thought(), thought(.voice), thought(.image, image: true), thought(.link, link: "https://are.na")]
        XCTAssertEqual(kept(by: .all, nodes).count, nodes.count)
    }

    func test_links_includeALinkTypedIntoAThought() {
        let typed = thought(.text, link: "https://are.na/editorial")
        let shared = thought(.link, link: "https://developer.apple.com")
        let plain = thought(.text)

        XCTAssertEqual(kept(by: .link, [typed, shared, plain]).map(\.id), [typed.id, shared.id])
    }

    func test_text_isWhatHoldsNoLinkAndNoPicture() {
        let plain = thought(.text)
        let withLink = thought(.text, link: "https://are.na")
        let withPicture = thought(.text, image: true)
        let whisper = thought(.voice)

        XCTAssertEqual(kept(by: .text, [plain, withLink, withPicture, whisper]).map(\.id), [plain.id])
    }

    func test_images_includeAPictureOnAnotherKind() {
        let photo = thought(.image, image: true)
        let whisperWithPhoto = thought(.voice, image: true)
        let plain = thought(.text)

        XCTAssertEqual(kept(by: .image, [photo, whisperWithPhoto, plain]).map(\.id), [photo.id, whisperWithPhoto.id])
        XCTAssertEqual(kept(by: .voice, [photo, whisperWithPhoto, plain]).map(\.id), [whisperWithPhoto.id],
                       "A whisper with a photo is both")
    }
}
