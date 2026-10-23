import XCTest
import Foundation

final class AskReferencesTests: XCTestCase {

    func test_findsReferencesInOrder_includingGroupedOnes() {
        let text = "You keep returning to the tide [t2]. The bakery note [T1] and the two bugs [t3, t4] say the rest."
        XCTAssertEqual(AskReferences.references(in: text), ["t2", "t1", "t3", "t4"])
    }

    func test_stripRemovesMarkersAndTheSpaceBeforePunctuation() {
        let text = "You keep returning to the tide [t2]. Two bugs remain [t3, t4]，还有一个任务 [t5]。"
        XCTAssertEqual(AskReferences.strip(from: text), "You keep returning to the tide. Two bugs remain，还有一个任务。")
    }

    func test_textWithoutReferences_isUnchanged() {
        XCTAssertEqual(AskReferences.strip(from: "Nothing in your Ocean matches this yet."), "Nothing in your Ocean matches this yet.")
        XCTAssertEqual(AskReferences.references(in: "No refs here"), [])
    }

    func test_resolve_turnsInlineMarkersIntoTitles_andDropsTrailingOnes() {
        let titles = ["t1": "Ask 不会翻译", "t2": "Undo toast hides the tab bar"]
        XCTAssertEqual(
            AskReferences.resolve("你记过的 bug 有 [t1] 和 [t2]。", titles: titles),
            "你记过的 bug 有 “Ask 不会翻译” 和 “Undo toast hides the tab bar”。"
        )
        XCTAssertEqual(
            AskReferences.resolve("You keep returning to the tide [t2]. Two bugs remain [t1, t2].", titles: titles),
            "You keep returning to the tide. Two bugs remain."
        )
        XCTAssertEqual(
            AskReferences.resolve("Both [t1, t2] remain.", titles: titles),
            "Both “Ask 不会翻译”, “Undo toast hides the tab bar” remain."
        )
        XCTAssertEqual(
            AskReferences.resolve("Two bugs: [t1] and [t2]. The first is older [t1].", titles: titles),
            "Two bugs: “Ask 不会翻译” and “Undo toast hides the tab bar”. The first is older."
        )
        XCTAssertEqual(AskReferences.resolve("See [t9] for more", titles: titles), "See for more")
    }
}
