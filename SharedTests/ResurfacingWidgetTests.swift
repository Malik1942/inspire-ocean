import XCTest

/// The Resurfacing widget's kind. The app reloads the widget by it when
/// today's pick changes, and placed widgets are keyed by it: a new string
/// would orphan every Resurfacing widget already on a Home Screen.
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class ResurfacingWidgetTests: XCTestCase {

    func test_widgetKind_isThePlacedWidgetsKind() {
        XCTAssertEqual(Resurfacing.widgetKind, "com.inspireocean.app.widgets.resurfacing")
    }
}
