import XCTest
import Foundation

/// Unit tests for `CurrentSnap`: which existing currents a new thought may
/// join, and how a model's pick is folded into its themes. The pick itself
/// comes from the on-device model (`FoundationCurrentPicker`) and is measured
/// by `Scripts/current-snap-eval`; everything here is the deterministic part.
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class CurrentSnapTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func member(_ key: String, _ title: String, daysAgo: Double = 0) -> CurrentSnap.Member {
        CurrentSnap.Member(key: key, title: title, createdAt: base.addingTimeInterval(-daysAgo * 86_400))
    }

    private func candidate(_ key: String) -> CurrentCandidate {
        CurrentCandidate(key: key, examples: [])
    }

    // MARK: - joinKey

    /// The observed bug (2026-09-22): "The room feels slower when the light
    /// turns warm." got ["light", "warmth"] and never joined "light and color".
    /// A valid pick is the key the thought joins.
    func test_joinKey_validPick_isTheKey() {
        XCTAssertEqual(
            CurrentSnap.joinKey(pick: "light-and-color", candidates: [candidate("light-and-color"), candidate("cooking")]),
            "light-and-color"
        )
    }

    func test_joinKey_nilOrNonePick_isNoSnap() {
        XCTAssertNil(CurrentSnap.joinKey(pick: nil, candidates: [candidate("light-and-color")]))
        XCTAssertNil(CurrentSnap.joinKey(pick: CurrentSnap.noneChoice, candidates: [candidate("light-and-color")]))
    }

    func test_joinKey_pickNotAmongCandidates_isNoSnap() {
        XCTAssertNil(CurrentSnap.joinKey(pick: "sunsets", candidates: [candidate("light-and-color")]))
    }

    /// Keys match exactly, so a near-miss spelling must not count.
    func test_joinKey_pickDifferingOnlyInCase_isNoSnap() {
        XCTAssertNil(CurrentSnap.joinKey(pick: "Light-And-Color", candidates: [candidate("light-and-color")]))
    }

    // MARK: - candidates

    func test_candidates_groupByKey_largestCurrentFirst_thenByKey() {
        let members = [
            member("cooking", "Weeknight noodles"),
            member("light and color", "Sunset gradient study"),
            member("light and color", "Golden hour on the walk home"),
            member("interface design", "A button without a label"),
        ]
        let keys = CurrentSnap.candidates(from: members, forEntry: "Warm light").map(\.key)
        XCTAssertEqual(keys, ["light and color", "cooking", "interface design"])
    }

    func test_candidates_examplesAreMostRecentTitles_cappedAtThree() {
        let members = [
            member("light and color", "Oldest", daysAgo: 9),
            member("light and color", "Newest", daysAgo: 0),
            member("light and color", "Middle", daysAgo: 3),
            member("light and color", "Older", daysAgo: 6),
        ]
        let current = CurrentSnap.candidates(from: members, forEntry: "Warm light").first
        XCTAssertEqual(current?.examples, ["Newest", "Middle", "Older"])
    }

    func test_candidates_skipBlankTitlesAsExamples() {
        let members = [member("cooking", "  "), member("cooking", "Weeknight noodles", daysAgo: 1)]
        let current = CurrentSnap.candidates(from: members, forEntry: "Braised ribs").first
        XCTAssertEqual(current?.examples, ["Weeknight noodles"])
    }

    func test_candidates_cappedAtMaxCandidates() {
        let members = (0..<(CurrentSnap.maxCandidates + 5)).map { member("topic \($0)", "Title \($0)") }
        XCTAssertEqual(CurrentSnap.candidates(from: members, forEntry: "Anything").count, CurrentSnap.maxCandidates)
    }

    /// A current literally named "none" would collide with the no-snap choice.
    func test_candidates_excludeKeyThatCollidesWithNoneChoice() {
        let members = [member("none", "Odd one"), member("cooking", "Weeknight noodles")]
        XCTAssertEqual(CurrentSnap.candidates(from: members, forEntry: "Braised ribs").map(\.key), ["cooking"])
    }

    // MARK: - candidates: one Ocean across languages

    /// SPEC decision 3: every current is offered whatever the entry's
    /// language, and the label the entry's language reads rides along.
    func test_candidates_offerEveryCurrent_withLabels() {
        let members = [
            CurrentSnap.Member(key: "光与色彩", title: "傍晚的光", createdAt: base),
            CurrentSnap.Member(key: "light-and-color", title: "Golden hour", createdAt: base, label: "Light and Color"),
        ]
        let english = CurrentSnap.candidates(from: members, forEntry: "The room feels slower when the light turns warm.")
        XCTAssertEqual(Set(english.map(\.key)), ["光与色彩", "light-and-color"])
        XCTAssertEqual(english.first { $0.key == "light-and-color" }?.label, "Light and Color")
        let chinese = CurrentSnap.candidates(from: members, forEntry: "光线变暖的时候房间好像变慢了。")
        XCTAssertEqual(Set(chinese.map(\.key)), ["光与色彩", "light-and-color"])
    }

    func test_isChinese_mixedEntryFollowsDominantScript() {
        XCTAssertTrue(CurrentSnap.isChinese("今天吃了个 burger"))
        XCTAssertFalse(CurrentSnap.isChinese("Had 饺子 with the team after the offsite"))
        XCTAssertFalse(CurrentSnap.isChinese("light and color"))
        XCTAssertFalse(CurrentSnap.isChinese("2026"))
    }

    // MARK: - candidates from nodes

    func test_nodeCurrentKey_anchorWinsOverFirstTheme() {
        let anchored = Node(title: "Desk at 6pm", themes: ["interior", "light and color"])
        anchored.anchorThemeKey = "light-and-color"
        XCTAssertEqual(anchored.currentKey, "light-and-color")
        XCTAssertEqual(Node(themes: ["cooking", "salt"]).currentKey, "cooking")
        XCTAssertEqual(Node(themes: ["light & color"]).currentKey, "light-and-color")
        XCTAssertNil(Node(themes: []).currentKey)
    }

    /// The thought being themed is already saved (with provisional concept
    /// themes from `NodeComposer.make`), so it must not offer itself as a
    /// current. Archived and example thoughts aren't part of the living Ocean.
    func test_candidatesInNodes_skipTheThoughtItselfArchivedExampleAndThemeless() {
        let fresh = Node(title: "Warm room", themes: ["light & atmosphere"])
        let archived = Node(title: "Old", themes: ["archived topic"], isArchived: true)
        let example = Node(title: "Example", themes: ["example topic"])
        example.isExample = true
        let themeless = Node(title: "Loose", themes: [])
        let member = Node(title: "Golden hour on the walk home", themes: ["light and color", "visual study"])
        let anchored = Node(title: "Desk at 6pm", themes: ["interior"])
        anchored.anchorThemeKey = "light-and-color"

        let candidates = CurrentSnap.candidates(
            in: [fresh, archived, example, themeless, member, anchored],
            excluding: fresh.id,
            forEntry: "The room feels slower when the light turns warm."
        )
        XCTAssertEqual(candidates.map(\.key), ["light-and-color"])
        XCTAssertEqual(Set(candidates.first?.examples ?? []), ["Golden hour on the walk home", "Desk at 6pm"])
    }

    // MARK: - prompt

    func test_prompt_listsEachCurrentWithItsExamples_thenTheEntry() {
        let prompt = CurrentSnap.prompt(
            entry: "The room feels slower when the light turns warm.",
            candidates: [
                CurrentCandidate(key: "light-and-color", examples: ["Golden hour on the walk home", "Desk at 6pm"], label: "Light and Color"),
                CurrentCandidate(key: "cooking", examples: []),
            ]
        )
        XCTAssertEqual(prompt, """
        Topics:
        - light-and-color (Light and Color): "Golden hour on the walk home", "Desk at 6pm"
        - cooking

        New entry:
        The room feels slower when the light turns warm.
        """)
    }
}
