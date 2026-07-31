import XCTest
import Foundation

/// Unit tests for `AnswerMarkdown` — the parsing step between a model
/// answer's raw markdown and the styled text the Ask transcript renders.
final class AnswerMarkdownTests: XCTestCase {

    func test_boldMarkers_styleTheText_insteadOfShowingAsterisks() {
        let rendered = AnswerMarkdown.attributed("**The pattern of noticing.** It keeps returning.")
        let plain = String(rendered.characters)

        XCTAssertFalse(plain.contains("*"), "Markdown markers should be consumed, not displayed")
        XCTAssertTrue(plain.hasPrefix("The pattern of noticing."))
        XCTAssertTrue(
            rendered.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true },
            "The bolded stretch should carry the strong-emphasis intent Text renders as bold"
        )
    }

    func test_italicMarkers_styleTheText() {
        let rendered = AnswerMarkdown.attributed("A *quiet* tension.")

        XCTAssertEqual(String(rendered.characters), "A quiet tension.")
        XCTAssertTrue(
            rendered.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true }
        )
    }

    func test_paragraphBreaks_surviveParsing() {
        let rendered = AnswerMarkdown.attributed("**First.** One thread.\n\nSecond thread, plainer.")

        XCTAssertEqual(
            String(rendered.characters),
            "First. One thread.\n\nSecond thread, plainer.",
            "Blank-line paragraph breaks must reach Text intact"
        )
    }

    func test_plainText_passesThroughUntouched() {
        let text = "No markup here, just water."
        XCTAssertEqual(String(AnswerMarkdown.attributed(text).characters), text)
    }
}
