import SwiftUI

/// The Reading light, the app's one lamp: warm light from the upper left
/// that falls across the top of every page, on Tide onto the thought that
/// came back (design/identity-2.1.md). It is light, never ink: one gradient
/// over the whole screen with no edge to show, gone before the page's lower
/// half.
///
/// `lift` and `dim` carry the lamp's choreography when a thought is let go
/// (`OceanFieldView.rest`): it lowers while one sinks and warms a touch
/// while the next rises. `dim` also says how much of the lamp reaches a
/// page below the tabs (`PageBackground`). Art-directed: the light's reach
/// and strength are Tide's own, not tokens.
struct StageLight: View {
    var lift: Double = 0
    var dim: Double = 1

    var body: some View {
        GeometryReader { geo in
            // An ellipse as wide as the screen and 55% as tall, centered on
            // the top edge a fifth of the way in from the left.
            EllipticalGradient(
                stops: [
                    .init(color: OceanTheme.stageLight.opacity((0.30 + lift) * dim), location: 0), // art-directed: the light
                    .init(color: OceanTheme.stageLight.opacity((0.10 + lift * 0.4) * dim), location: 0.55), // art-directed: the light
                    .init(color: .clear, location: 0.9)
                ],
                center: UnitPoint(x: 0.18, y: 0),
                startRadiusFraction: 0,
                endRadiusFraction: 1
            )
            .frame(width: geo.size.width, height: geo.size.height * 0.55)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
