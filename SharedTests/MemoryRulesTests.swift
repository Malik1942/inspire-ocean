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

    func test_sameness_allowsWordForms() {
        XCTAssertTrue(MemoryRules.isSame("You frequently notice the light at the end of the day.", "You keep noticing the light at the end of the day."))
        XCTAssertFalse(MemoryRules.isSame("You frequently mention Mara.", "You keep noticing the light at the end of the day."))
    }
}
