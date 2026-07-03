import SpriteKit
import SwiftUI

/// Hosts the Ocean scene in SwiftUI and owns the boundary between the two
/// worlds: layout and fragment snapshots flow in when data changes (never per
/// frame), taps flow out to the field's existing handlers. Accessibility
/// signals (Calm Accessibility Mode, Reduce Motion) collapse into one
/// `MotionPolicy` here, the single stillness seam for every later phase.
struct OceanSceneView: View {

    let layout: OceanLayout
    let fragments: [FragmentSnapshot]
    var onTapFragment: (UUID) -> Void
    var onTapCluster: (String) -> Void

    @Environment(\.calmAccessibility) private var calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scene = OceanScene()

    var body: some View {
        SpriteView(
            scene: scene,
            // Match the device, exactly like the TimelineView this replaces:
            // full ProMotion where available, 60 elsewhere.
            preferredFramesPerSecond: UIScreen.main.maximumFramesPerSecond,
            options: [.allowsTransparency],
            debugOptions: Self.debugOptions
        )
        .onAppear { push() }
        .onChange(of: layout.signature) { _, _ in push() }
        // Snapshots can change without the layout moving (a title edit, for
        // example); accessibility labels must follow.
        .onChange(of: fragments) { _, _ in push() }
        .onChange(of: calm) { _, _ in push() }
        .onChange(of: reduceMotion) { _, _ in push() }
    }

    private func push() {
        scene.scaleMode = .resizeFill
        scene.onTapFragment = onTapFragment
        scene.onTapCluster = onTapCluster
        scene.apply(
            layout: layout,
            fragments: fragments,
            motion: .current(calm: calm, reduceMotion: reduceMotion),
            calm: calm
        )
    }

    /// Frame and node counters for performance checks, opted into per launch
    /// (OCEAN_SHOW_PERF=1) so demos stay clean.
    private static var debugOptions: SpriteView.DebugOptions {
        #if DEBUG
        if ProcessInfo.processInfo.environment["OCEAN_SHOW_PERF"] == "1" {
            return [.showsFPS, .showsNodeCount]
        }
        #endif
        return []
    }
}
