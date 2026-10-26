import XCTest
import Foundation

/// The wrist reads a thought the way the phone's thought page does
/// (`ExpandedNodeView.reading`). No app-module import: SharedTests compiles
/// Shared/ directly.
final class WristSnapshotSourceTests: XCTestCase {

    private let placeholders: Set<String> = ["Whisper", "语音"]

    private func source(_ node: Node) -> WristSnapshotBuilder.Source {
        WristSnapshotBuilder.Source(node: node, placeholders: placeholders)
    }

    func test_whisperWithASummary_readsTheSummary() {
        let node = Node(kind: .voice, title: "Lighthouse café", transcription: "Warm light at closing time")
        node.summary = "A room that tells you to stay."
        let s = source(node)
        XCTAssertEqual(s.summary, "A room that tells you to stay.")
        XCTAssertEqual(s.words, "Warm light at closing time")
        XCTAssertEqual(s.title, "Lighthouse café")
        XCTAssertTrue(s.isVoice)
    }

    func test_summaryWithoutATranscript_isNotRead() {
        let node = Node(kind: .voice, title: "Lighthouse café")
        node.summary = "Stale"
        XCTAssertNil(source(node).summary)
    }

    func test_placeholderTitle_isNoName() {
        XCTAssertNil(source(Node(kind: .voice, title: "Whisper")).title)
        XCTAssertNil(source(Node(kind: .voice, title: "语音")).title)
    }

    func test_link_readsItsPageSummary_andItsOwnText() {
        let node = Node(kind: .link, title: "Grids", text: "Use this for the issue", linkURLString: "https://example.com")
        node.linkSummary = "How magazines build their grids."
        let s = source(node)
        XCTAssertEqual(s.summary, "How magazines build their grids.")
        XCTAssertEqual(s.words, "Use this for the issue")
        XCTAssertFalse(s.isVoice)
    }

    func test_note_readsItsOwnText() {
        let s = source(Node(kind: .text, title: "Warm to cool", text: "Not a filter"))
        XCTAssertNil(s.summary)
        XCTAssertEqual(s.words, "Not a filter")
    }

    func test_words_areHidden_whenTheyAreTheTitle() {
        let s = source(Node(kind: .text, title: "Warm to cool", text: " Warm to cool\n"))
        XCTAssertEqual(s.title, "Warm to cool")
        XCTAssertNil(s.words)
    }

    func test_audio_isReportedOnlyWhenThere() {
        XCTAssertTrue(source(Node(kind: .voice, audioData: Data([1]))).hasAudio)
        XCTAssertFalse(source(Node(kind: .voice)).hasAudio)
    }
}
