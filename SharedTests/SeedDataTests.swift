import XCTest
import SwiftData

/// Unit tests for the seed / re-localization contract in `SeedData`.
///
/// The load-bearing invariant: seeded examples must be born *untouched*
/// (no `*EditedByUser` flags), because `relocalizeExamplesIfNeeded` reads
/// those same flags as "did the user edit anything" when deciding whether a
/// per-app language change may wipe and re-seed the examples. Protection from
/// the understanding backfill comes from `isExample`, not from the flags.
final class SeedDataTests: XCTestCase {

    // MARK: - insertExamples

    @MainActor
    func test_seededExamples_carryNoUserEditFlags() throws {
        let container = try ModelContainer(
            for: Node.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        SeedData.insertExamples(into: context, now: Date())

        let examples = try context.fetch(FetchDescriptor<Node>())
        XCTAssertEqual(examples.count, 2)
        for node in examples {
            XCTAssertTrue(node.isExample)
            XCTAssertFalse(node.titleEditedByUser,
                           "a seeded example born 'edited' blocks language re-seed forever")
            XCTAssertFalse(node.themesEditedByUser,
                           "a seeded example born 'edited' blocks language re-seed forever")
            XCTAssertFalse(node.transcriptEditedByUser)
            XCTAssertFalse(node.positionPinnedByUser)
            XCTAssertFalse(node.title.isEmpty, "examples ship pre-titled")
            XCTAssertFalse(node.themes.isEmpty, "examples ship pre-themed")
        }
    }

    // MARK: - shouldRelocalizeExamples (pure decision)

    func test_languageChange_untouchedExamples_reseeds() {
        XCTAssertEqual(
            SeedData.shouldRelocalizeExamples(
                seeded: true, realCount: 0, exampleCount: 2,
                anyExampleEdited: false,
                recordedLanguage: "en", currentLanguage: "zh-Hans"
            ),
            .reseed("zh-Hans")
        )
    }

    func test_languageChange_editedExample_skips() {
        XCTAssertEqual(
            SeedData.shouldRelocalizeExamples(
                seeded: true, realCount: 0, exampleCount: 2,
                anyExampleEdited: true,
                recordedLanguage: "en", currentLanguage: "zh-Hans"
            ),
            .skip
        )
    }

    func test_languageChange_realWritingPresent_skips() {
        XCTAssertEqual(
            SeedData.shouldRelocalizeExamples(
                seeded: true, realCount: 3, exampleCount: 2,
                anyExampleEdited: false,
                recordedLanguage: "en", currentLanguage: "zh-Hans"
            ),
            .skip
        )
    }

    func test_sameLanguage_skips() {
        XCTAssertEqual(
            SeedData.shouldRelocalizeExamples(
                seeded: true, realCount: 0, exampleCount: 2,
                anyExampleEdited: false,
                recordedLanguage: "en", currentLanguage: "en"
            ),
            .skip
        )
    }

    func test_clearedExamples_skips() {
        XCTAssertEqual(
            SeedData.shouldRelocalizeExamples(
                seeded: true, realCount: 0, exampleCount: 0,
                anyExampleEdited: false,
                recordedLanguage: "en", currentLanguage: "zh-Hans"
            ),
            .skip
        )
    }

    func test_unknownBaseline_adoptsCurrentLanguage() {
        XCTAssertEqual(
            SeedData.shouldRelocalizeExamples(
                seeded: true, realCount: 0, exampleCount: 2,
                anyExampleEdited: false,
                recordedLanguage: nil, currentLanguage: "zh-Hans"
            ),
            .adoptBaseline("zh-Hans")
        )
    }

    func test_notYetSeeded_skips() {
        XCTAssertEqual(
            SeedData.shouldRelocalizeExamples(
                seeded: false, realCount: 0, exampleCount: 0,
                anyExampleEdited: false,
                recordedLanguage: nil, currentLanguage: "zh-Hans"
            ),
            .skip
        )
    }
}
