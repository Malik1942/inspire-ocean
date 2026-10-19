import XCTest
import Foundation

/// Unit tests for `UnderstandingBackfill`: which thoughts the Library's
/// understanding pass touches on open, and how. The understanding itself
/// comes from the model; this is the deterministic gate in front of it.
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class UnderstandingBackfillTests: XCTestCase {

    private let landed = UnderstandingBackfill.semanticLayerLanded
    private let day: TimeInterval = 86_400

    private func work(
        example: Bool = false,
        titled: Bool = true,
        createdAt: Date,
        migrating: Bool
    ) -> UnderstandingBackfill.Work? {
        UnderstandingBackfill.work(isExample: example, hasTitle: titled, createdAt: createdAt, migrating: migrating)
    }

    // MARK: - The one-time semantic re-theme

    /// The observed bug (2026-10-19): on the first Library open of an
    /// install, thoughts understood at capture were re-themed in isolation,
    /// and "light and color", "product ideas" and "cooking" became
    /// "thought", "quick", "melody" and "creative direction".
    func test_thoughtCapturedSinceTheSemanticLayer_keepsItsThemes_onTheMigratingOpen() {
        XCTAssertNil(work(createdAt: landed + 130 * day, migrating: true))
    }

    func test_thoughtCapturedTheInstantTheLayerLanded_keepsItsThemes() {
        XCTAssertNil(work(createdAt: landed, migrating: true))
    }

    func test_keywordEraThought_isRethemed_whileMigrating() {
        XCTAssertEqual(work(createdAt: landed - day, migrating: true), .retheme)
    }

    func test_keywordEraThought_isLeftAlone_onceTheMigrationHasRun() {
        XCTAssertNil(work(createdAt: landed - day, migrating: false))
    }

    // MARK: - Untitled thoughts

    /// Branches and share-sheet captures can arrive untitled; the pass
    /// names them whatever their age and whether or not it is migrating.
    func test_untitledThought_isUnderstood_whateverItsAge() {
        for createdAt in [landed - day, landed + day] {
            for migrating in [true, false] {
                XCTAssertEqual(work(titled: false, createdAt: createdAt, migrating: migrating), .understand)
            }
        }
    }

    // MARK: - Examples

    /// Examples are curated and re-localized wholesale; the pass never
    /// retitles or re-themes them, even untitled and keyword-era.
    func test_example_isNeverTouched() {
        XCTAssertNil(work(example: true, titled: false, createdAt: landed - day, migrating: true))
        XCTAssertNil(work(example: true, titled: true, createdAt: landed - day, migrating: true))
    }
}
