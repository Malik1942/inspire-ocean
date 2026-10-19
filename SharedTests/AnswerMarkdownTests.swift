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

    // MARK: - AnswerLength

    /// The observed run-on (2026-10-19): a Summarize answer of nine
    /// sentences that drifted from the fragments after the fourth.
    func test_longAnswer_keepsFourSentences() {
        let text = "You keep returning to light. You study the sunset. You match its shift. "
            + "You avoid the overlay. You feel calm in your artwork. You feel at peace."
        XCTAssertEqual(
            AnswerLength.capped(text),
            "You keep returning to light. You study the sunset. You match its shift. You avoid the overlay."
        )
    }

    func test_shortAnswer_isUntouched() {
        let text = "You keep returning to light.\n\nIt cools before it ends."
        XCTAssertEqual(AnswerLength.capped(text), text)
    }

    func test_chinese_isCutBySentence() {
        let text = "你一直在回到光。你在研究日落。你想匹配它的变化。你不再叠加滤镜。你在作品里感到平静。"
        XCTAssertEqual(AnswerLength.capped(text), "你一直在回到光。你在研究日落。你想匹配它的变化。你不再叠加滤镜。")
    }
}
