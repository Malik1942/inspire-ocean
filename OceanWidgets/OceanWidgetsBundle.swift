import WidgetKit
import SwiftUI

/// Oryne's Home Screen / Lock Screen widgets and Control Center
/// control (PRD §7 entry points: widget, Control Center; §12 ambient
/// resurfacing).
@main
struct OceanWidgetsBundle: WidgetBundle {
    var body: some Widget {
        QuickCaptureWidget()
        ResurfacingWidget()
        FastCaptureControl()
    }
}
