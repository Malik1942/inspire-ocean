import XCTest

/// The widgets' kinds. The app reloads a widget by its kind, and placed
/// widgets are keyed by it: a new string would orphan every widget of that
/// kind already on a Home Screen.
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class ResurfacingWidgetTests: XCTestCase {

    func test_widgetKind_isThePlacedWidgetsKind() {
        XCTAssertEqual(Resurfacing.widgetKind, "com.inspireocean.app.widgets.resurfacing")
    }

    /// The Quick Capture widget's kind, which the app reloads by when the
    /// input preference changes; a new string would orphan placed widgets.
    func test_quickCaptureKind_isThePlacedWidgetsKind() {
        XCTAssertEqual(FastCapturePreferences.widgetKind, "com.inspireocean.app.widgets.quickcapture")
    }
}
