import XCTest
import Foundation

/// The deterministic parts of currents as entities: how a current takes its
/// labels from its thoughts, which cross-language pairs are suggested for a
/// merge, and how a key reads.
final class CurrentRegistryTests: XCTestCase {

    func test_summaryFingerprint_changesWhenAMemberIsEditedOrSwapped_notWhenNothingDid() {
        let a = UUID(), b = UUID(), c = UUID()
        let before = Current.summaryFingerprint(of: [(a, "Dusk light: the lamp at six"), (b, "Color: linen and clay")])
        XCTAssertEqual(before, Current.summaryFingerprint(of: [(a, "Dusk light: the lamp at six"), (b, "Color: linen and clay")]))
        XCTAssertNotEqual(before, Current.summaryFingerprint(of: [(a, "Dusk light: the lamp at seven"), (b, "Color: linen and clay")]))
        XCTAssertNotEqual(before, Current.summaryFingerprint(of: [(a, "Dusk light: the lamp at six"), (c, "Color: linen and clay")]))
        XCTAssertNotEqual(before, Current.summaryFingerprint(of: [(b, "Color: linen and clay"), (a, "Dusk light: the lamp at six")]))
    }

    func test_labels_comeFromMembersWhoseThemeNamesTheCurrent() {
        let labels = CurrentRegistry.labels(for: "light-and-color", from: [
            (theme: "interior", themeKey: "interior", language: .en),          // joined by pick: names nothing
            (theme: "light & color", themeKey: "light-and-color", language: .en),
            (theme: "光与色彩", themeKey: "light-and-color", language: .zh),   // Chinese thought, English rendering = key
        ])
        XCTAssertEqual(labels.en, "light & color")
        XCTAssertEqual(labels.zh, "光与色彩")
    }

    func test_suggestions_pairAChineseCurrentWithTheEnglishOneItsThoughtsName() {
        let suggestions = CurrentRegistry.suggestions(
            currentKeys: ["光与色彩", "light-and-color", "cooking"],
            members: [
                ("光与色彩", "light-and-color"),
                ("光与色彩", "light-and-color"),
                ("光与色彩", "warmth"),
                ("light-and-color", "light-and-color"),
                ("cooking", "cooking"),
            ]
        )
        XCTAssertEqual(suggestions, [CurrentRegistry.MergeSuggestion(fromKey: "光与色彩", intoKey: "light-and-color")])
    }

    func test_suggestions_needThreeInFive_andAnExistingTarget() {
        XCTAssertEqual(CurrentRegistry.suggestions(
            currentKeys: ["光与色彩", "light-and-color"],
            members: [("光与色彩", "light-and-color"), ("光与色彩", "a"), ("光与色彩", "b")]
        ), [])
        XCTAssertEqual(CurrentRegistry.suggestions(
            currentKeys: ["光与色彩"],
            members: [("光与色彩", "light-and-color"), ("光与色彩", "light-and-color")]
        ), [])
    }

    func test_suggestions_neverPairTwoCurrentsOfOneScript() {
        XCTAssertEqual(CurrentRegistry.suggestions(
            currentKeys: ["light", "light-and-color"],
            members: [("light", "light-and-color"), ("light", "light-and-color")]
        ), [])
    }

    func test_humanized() {
        XCTAssertEqual(CurrentKey.humanized("light-and-color"), "Light and Color")
        XCTAssertEqual(CurrentKey.humanized("light & color"), "Light & Color")
        XCTAssertEqual(CurrentKey.humanized("光与色彩"), "光与色彩")
        XCTAssertEqual(CurrentKey.name(pinnedName: "Dusk", labelEN: "light", labelZH: nil, key: "k", preferringChinese: true), "Dusk")
        XCTAssertEqual(CurrentKey.name(pinnedName: nil, labelEN: "light and color", labelZH: "光与色彩", key: "k", preferringChinese: true), "光与色彩")
        XCTAssertEqual(CurrentKey.name(pinnedName: nil, labelEN: nil, labelZH: "光与色彩", key: "k", preferringChinese: false), "光与色彩")
    }
}
