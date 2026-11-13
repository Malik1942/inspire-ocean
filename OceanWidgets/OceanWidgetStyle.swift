import SwiftUI
import WidgetKit

/// WidgetKit owns the outside margins and removes the still water for tinted
/// and clear appearances. Controls wear the app's content surfaces.
enum OceanWidgetStyle {
    /// The app's water, darkening downward as on every page
    /// (design/identity-2.1.md, R1).
    static var water: LinearGradient {
        LinearGradient(
            colors: [OceanTheme.waterTop, OceanTheme.waterMiddle, OceanTheme.abyss],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The water with Tide's Reading light falling across it from the upper
    /// left, at the stage's own strength (`StageLight`, which the widget
    /// cannot import): the Resurfacing card for a thought without a picture.
    static var readingLight: some View {
        ZStack {
            water
            EllipticalGradient(
                stops: [
                    .init(color: OceanTheme.stageLight.opacity(0.30), location: 0), // art-directed: the light, as StageLight
                    .init(color: OceanTheme.stageLight.opacity(0.10), location: 0.55), // art-directed: the light, as StageLight
                    .init(color: .clear, location: 0.9)
                ],
                center: UnitPoint(x: 0.18, y: 0),
                startRadiusFraction: 0,
                endRadiusFraction: 1
            )
        }
    }
}
