import XCTest
import Foundation

/// Unit tests for `TitleDistiller.speaksLike`: a model title survives only in
/// the entry's own language.
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class TitleDistillerTests: XCTestCase {

    /// The observed bug (2026-10-19, also usability P2): on a phone whose
    /// second language is Chinese, "Merge check, one quiet line" came back
    /// titled 清静的检查合并.
    func testEnglishEntryRejectsChineseTitle() {
        XCTAssertFalse(TitleDistiller.speaksLike("清静的检查合并", entry: "Merge check, one quiet line"))
    }

    func testChineseEntryRejectsEnglishTitle() {
        XCTAssertFalse(TitleDistiller.speaksLike("Quiet toast", entry: "今天的面包很安静"))
    }

    func testMatchingLanguagesPass() {
        XCTAssertTrue(TitleDistiller.speaksLike("Golden hour walk", entry: "Streetlights coming on while the sky is still orange"))
        XCTAssertTrue(TitleDistiller.speaksLike("黄昏的路", entry: "走回家时天还是橙色的"))
    }

    /// A mixed entry follows its dominant language, the same split currents use.
    func testMixedEntryFollowsDominantLanguage() {
        XCTAssertTrue(TitleDistiller.speaksLike("界面的呼吸感", entry: "这个 UI 的留白让人放松"))
        XCTAssertTrue(TitleDistiller.speaksLike("Calm UI spacing", entry: "The spacing in this UI feels calm, 很舒服"))
    }
}
