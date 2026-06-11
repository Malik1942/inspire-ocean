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

/// Shared visual language for the widgets — the same deep, near-monochrome
/// water the app uses, rendered statically (widgets don't animate).
enum OceanWidgetStyle {
    static var water: LinearGradient {
        LinearGradient(
            colors: [OceanTheme.abyss, OceanTheme.deep, OceanTheme.mid],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
