import XCTest
import Foundation

final class MemoryRulesTests: XCTestCase {

    func test_sameness_byContentWords_andNormalizedText() {
        XCTAssertTrue(MemoryRules.isSame("You keep returning to light.", "you keep returning to the light"))
        XCTAssertTrue(MemoryRules.isSame("你一直在想换工作。", "你一直在想换工作"))
        XCTAssertFalse(MemoryRules.isSame("You keep returning to light.", "You are planning a trip to Lisbon with Mara."))
    }

    func test_fresh_dropsDuplicates_blanks_andOverlong() {
        let kept = MemoryRules.fresh(
            ["You keep returning to light.", "  ", "you keep returning to the light", String(repeating: "x", count: 200), "Mara keeps appearing in your plans."],
            against: ["You keep returning to the light and its color."]
        )
        XCTAssertEqual(kept, ["Mara keeps appearing in your plans."])
    }

    func test_prune_removesRecordsWhoseEvidenceIsAllGone_keepsUserEdited_andCaps() {
        let live = UUID(), gone1 = UUID(), gone2 = UUID()
        let standing = MemoryRules.Standing(id: UUID(), evidence: [live, gone1], userEdited: false, createdAt: .now)
        let groundless = MemoryRules.Standing(id: UUID(), evidence: [gone1, gone2], userEdited: false, createdAt: .now)
        let edited = MemoryRules.Standing(id: UUID(), evidence: [gone1], userEdited: true, createdAt: .now)
        let noEvidence = MemoryRules.Standing(id: UUID(), evidence: [], userEdited: false, createdAt: .now)
        XCTAssertEqual(MemoryRules.toPrune([standing, groundless, edited, noEvidence], liveThoughtIDs: [live]), [groundless.id])

        let many = (0..<(MemoryRules.maxRecords + 2)).map { i in
            MemoryRules.Standing(id: UUID(), evidence: [], userEdited: false, createdAt: Date(timeIntervalSince1970: Double(i)))
        }
        let pruned = MemoryRules.toPrune(many, liveThoughtIDs: [])
        XCTAssertEqual(pruned, [many[0].id, many[1].id])
    }

    func test_preamble_capsLinesAndCharacters() {
        XCTAssertNil(MemoryRules.preamble([]))
        let records = (0..<12).map { (kind: MemoryKind.concern, text: "Observation number \($0) about you.") }
        let preamble = MemoryRules.preamble(records)!
        XCTAssertEqual(preamble.split(separator: "\n").count, MemoryRules.preambleRecords)
        XCTAssertTrue(preamble.hasPrefix("- (concern) Observation number 0"))
        let long = [(kind: MemoryKind.habit, text: String(repeating: "a", count: 150))] + Array(repeating: (kind: MemoryKind.habit, text: String(repeating: "b", count: 150)), count: 7)
        XCTAssertLessThanOrEqual(MemoryRules.preamble(long)!.count, MemoryRules.preambleCharacters)
    }

    func test_dismissed_isRemembered() {
        let defaults = UserDefaults(suiteName: "MemoryRulesTests-\(UUID().uuidString)")!
        XCTAssertFalse(MemoryRules.isDismissed("You keep returning to light.", defaults: defaults))
        MemoryRules.dismiss("You keep returning to light.", defaults: defaults)
        XCTAssertTrue(MemoryRules.isDismissed("you keep returning to the light", defaults: defaults))
    }

    func test_groundedEvidence_keepsOnlyThoughtsThatTouchTheObservation() {
        let evidence = [
            "Linen curtains, not blinds. The light through linen is the whole point of the room.",
            "Ran 5k this morning, knees complained.",
            "Night train to Lisbon with Mara, we talked until the windows went grey.",
        ]
        XCTAssertEqual(MemoryRules.groundedEvidence(for: "You prefer linen curtains over blinds.", evidence: evidence), [0])
        XCTAssertEqual(MemoryRules.groundedEvidence(for: "Mara keeps appearing in your plans.", evidence: evidence), [2])
        XCTAssertEqual(MemoryRules.groundedEvidence(for: "You keep mentioning things.", evidence: evidence), [])
    }

    func test_groundedEvidence_needsTheSameLean_notJustTheSameWords() {
        let evidence = [
            "I hate linen curtains, they hold the dust.",
            "Linen curtains again; the light through them at six is the best thing in the flat.",
        ]
        XCTAssertEqual(MemoryRules.groundedEvidence(for: "You prefer linen curtains.", evidence: evidence), [1])
        XCTAssertEqual(MemoryRules.groundedEvidence(for: "You don't like linen curtains.", evidence: evidence), [0])
        XCTAssertEqual(MemoryRules.groundedEvidence(for: "你不喜欢亚麻窗帘。", evidence: ["我不喜欢亚麻窗帘。", "亚麻窗帘真好看。"]), [0])
        XCTAssertTrue(MemoryRules.negated("I never finish the books I start."))
        XCTAssertFalse(MemoryRules.negated("这家店不错，下次再来。"))
    }

    func test_dismissed_isRememberedAcrossTombstones_andTombstonesAreCapped() {
        let defaults = UserDefaults(suiteName: "MemoryRulesTests-\(UUID().uuidString)")!
        XCTAssertTrue(MemoryRules.isDismissed("you keep returning to the light", among: ["You keep returning to light."], defaults: defaults))
        XCTAssertFalse(MemoryRules.isDismissed("Mara keeps appearing in your plans.", among: ["You keep returning to light."], defaults: defaults))

        let stones = (0..<(MemoryRules.maxTombstones + 3)).map { (id: UUID(), dismissedAt: Date(timeIntervalSince1970: Double($0))) }
        XCTAssertEqual(MemoryRules.tombstonesToDrop(stones), [stones[0].id, stones[1].id, stones[2].id])
        XCTAssertEqual(MemoryRules.tombstonesToDrop(Array(stones.prefix(5))), [])
    }

    func test_sameness_allowsWordForms() {
        XCTAssertTrue(MemoryRules.isSame("You frequently notice the light at the end of the day.", "You keep noticing the light at the end of the day."))
        XCTAssertFalse(MemoryRules.isSame("You frequently mention Mara.", "You keep noticing the light at the end of the day."))
    }

    func test_softened_dropsClaimsOfRepetition_onFewerThanThreeThoughts() {
        XCTAssertEqual(MemoryRules.softened("You frequently mention Oryne.", grounded: 2), "You mention Oryne.")
        XCTAssertEqual(MemoryRules.softened("你经常提到 Oryne。", grounded: 2), "你提到 Oryne。")
        XCTAssertEqual(MemoryRules.softened("You frequently mention Oryne.", grounded: 3), "You frequently mention Oryne.")
    }

    func test_summaryProblem_catchesPreamble_firstPerson_echo_andMissingYou() {
        let members = ["- “Grandma's handwriting”: Grandma's handwriting on the recipe card; the kitchen smelled of star anise."]
        XCTAssertNotNil(MemoryRules.summaryProblem("Here is a description of the thoughts that run through your mind:", memberTexts: members))
        XCTAssertNotNil(MemoryRules.summaryProblem("I am thinking about a quiet morning walk.", memberTexts: members))
        XCTAssertNotNil(MemoryRules.summaryProblem("“Grandma's handwriting”: Grandma's handwriting on the recipe card; the kitchen smelled of star anise.", memberTexts: members))
        XCTAssertNotNil(MemoryRules.summaryProblem("Digital minimalism is a philosophy of reducing distraction.", memberTexts: members))
        XCTAssertNil(MemoryRules.summaryProblem("You keep returning to the kitchen you grew up in and the hands that cooked there.", memberTexts: members))
        XCTAssertNil(MemoryRules.summaryProblem("你一直在回想外婆的厨房和她的字迹。", memberTexts: members))
    }

    func test_cleanedPageSummary_dropsPreamble_rejectsRefusals() {
        XCTAssertEqual(
            MemoryRules.cleanedPageSummary("Sure, here is a summary of the Are.na Editorial page:\n\nThe page shares essays and interviews on attention."),
            "The page shares essays and interviews on attention."
        )
        XCTAssertNil(MemoryRules.cleanedPageSummary("I can't summarize the content of the page, as it is filled with repetitive text."))
        XCTAssertNil(MemoryRules.cleanedPageSummary("Sure! Here is the summary."))
        XCTAssertEqual(MemoryRules.cleanedPageSummary("Essays on slow software and attention."), "Essays on slow software and attention.")
    }

    func test_cleanedPageSummary_dropsMarkdownHeadings() {
        XCTAssertEqual(
            MemoryRules.cleanedPageSummary("## What's new in the Foundation Models framework\nA video presentation announcing the new features."),
            "A video presentation announcing the new features."
        )
    }
}
