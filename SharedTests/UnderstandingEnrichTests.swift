import XCTest
import Foundation

/// The enrichment gate added with the understanding record: thoughts whose
/// record predates the current reader are enriched, newest first, only when
/// a model is there to do it.
final class UnderstandingEnrichTests: XCTestCase {

    private let landed = UnderstandingBackfill.semanticLayerLanded
    private let day: TimeInterval = 86_400

    func test_titledRecentThought_withOldRecord_isEnriched_whenModelAvailable() {
        XCTAssertEqual(
            UnderstandingBackfill.work(isExample: false, hasTitle: true, createdAt: landed + day, migrating: false,
                                       understandingVersion: 0, modelAvailable: true),
            .enrich
        )
    }

    func test_oldRecord_isLeftAlone_withoutAModel() {
        XCTAssertNil(
            UnderstandingBackfill.work(isExample: false, hasTitle: true, createdAt: landed + day, migrating: false,
                                       understandingVersion: 0, modelAvailable: false)
        )
    }

    func test_currentRecord_isLeftAlone() {
        XCTAssertNil(
            UnderstandingBackfill.work(isExample: false, hasTitle: true, createdAt: landed + day, migrating: false,
                                       understandingVersion: ThoughtReading.version, modelAvailable: true)
        )
    }

    func test_namingAndRetheming_comeBeforeEnrichment() {
        XCTAssertEqual(
            UnderstandingBackfill.work(isExample: false, hasTitle: false, createdAt: landed + day, migrating: false,
                                       understandingVersion: 0, modelAvailable: true),
            .understand
        )
        XCTAssertEqual(
            UnderstandingBackfill.work(isExample: false, hasTitle: true, createdAt: landed - day, migrating: true,
                                       understandingVersion: 0, modelAvailable: true),
            .retheme
        )
    }

    func test_examples_areNeverEnriched() {
        XCTAssertNil(
            UnderstandingBackfill.work(isExample: true, hasTitle: true, createdAt: landed + day, migrating: false,
                                       understandingVersion: 0, modelAvailable: true)
        )
    }
}
