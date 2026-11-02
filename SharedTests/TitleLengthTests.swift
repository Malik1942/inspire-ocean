import XCTest

/// A thought's name steps down a size by how long it reads, not by how many
/// characters it holds: a Chinese character stands about as wide as two
/// Latin letters, so it counts 2 (`TitleLength.weighted`).
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class TitleLengthTests: XCTestCase {

    func testEmptyTitleHasNoLength() {
        XCTAssertEqual(TitleLength.weighted(""), 0)
    }

    func testLatinLettersCountOnce() {
        XCTAssertEqual(TitleLength.weighted("abc"), 3)
    }

    func testChineseCharactersCountTwice() {
        XCTAssertEqual(TitleLength.weighted("海洋"), 4)
    }

    func testMixedTitleAddsBoth() {
        XCTAssertEqual(TitleLength.weighted("Tide 潮"), 7)
    }

    func testFullwidthCountsTwiceAndHalfwidthOnce() {
        XCTAssertEqual(TitleLength.weighted("Ａ"), 2)
        XCTAssertEqual(TitleLength.weighted("ｱ"), 1)
    }

    func testEmojiCountsTwice() {
        XCTAssertEqual(TitleLength.weighted("🌊"), 2)
    }

    /// A letter and its combining accent are one character on screen.
    func testCombiningMarkCountsWithItsLetter() {
        XCTAssertEqual(TitleLength.weighted("e\u{301}"), 1)
    }

    /// Forty Chinese characters read as long as eighty Latin letters, so the
    /// title steps down a size, where forty English letters would not.
    func testFortyChineseCharactersReadAsEighty() {
        let title = String(repeating: "潮", count: 40)
        XCTAssertEqual(title.count, 40)
        XCTAssertEqual(TitleLength.weighted(title), 80)
    }
}
