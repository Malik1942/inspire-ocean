import SwiftUI

// MARK: - Calm Accessibility Mode

/// Calm Accessibility Mode: the same Ocean, stilled.
///
/// The default experience keeps its drift and whisper-light labels. With this
/// mode on (Ocean → settings), the water holds still, the labels that carry
/// information brighten, and touch targets widen — the metaphor survives, the
/// strain doesn't. The system Reduce Motion setting stills the water too,
/// independently of this switch.
///
/// Lives here (not its own file) because the widget target compiles exactly
/// this one DesignSystem file — `OceanBackground` below reads the key, so the
/// key must travel with it.
enum CalmAccessibility {
    /// App-Group-backed so every surface agrees.
    static let key = "ocean.calmAccessibilityMode"
}

extension EnvironmentValues {
    /// True when Calm Accessibility Mode is on. Injected once at the root;
    /// views read the environment, not the preference store, so previews and
    /// tests can set it directly.
    @Entry var calmAccessibility: Bool = false
}

/// Color for Oryne. The roles (the water, the inks, the surfaces, the
/// accents) are generated into `OceanTokens.swift` from
/// `design/tokens/oryne.tokens.json`; this file holds what a value cannot
/// say: a fragment's hue, and the water itself.
///
/// The Ocean should feel "atmospheric, calm, and alive" (§8) — deep and
/// spatial, near-monochrome, with brightness carrying hierarchy.
enum OceanTheme {
    /// A subtle, near-monochrome color for a fragment given its stored hue.
    /// Brightness carries hierarchy; the hue only nudges temperature ±0.025 so
    /// the field stays essentially black-and-white and spatial.
    static func color(forHue hue: Double, saturation: Double = 0, brightness: Double = 0.9) -> Color {
        let b = max(0, min(1, brightness))
        let shift = (hue - 0.5) * 0.05
        return Color(red: min(1, b + shift), green: b, blue: max(0, b - shift))
    }

    static func gradient(forHue hue: Double) -> LinearGradient {
        let base = color(forHue: hue, brightness: 0.82)
        return LinearGradient(
            colors: [base.opacity(0.9), base.opacity(0.45), mid.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension OceanTheme {
    /// An ink that steps up when the person turns on Increase Contrast: the
    /// generated inks (foam, text, mist, faint, stageWords, coolWords) take
    /// their brighter value wherever they are drawn, not only the depth
    /// ladder. On iOS it is a dynamic color the environment resolves;
    /// elsewhere it is `normal`.
    static func contrasting(_ normal: Color, increased: Color) -> Color {
        #if os(iOS)
        let normal = UIColor(normal)
        let increased = UIColor(increased)
        return Color(uiColor: UIColor { traits in
            traits.accessibilityContrast == .high ? increased : normal
        })
        #else
        return normal
        #endif
    }
}

// MARK: - OceanBackground

/// The deep, spatial ocean background used across the app.
///
/// An animated `MeshGradient` (iOS 18) gives a single continuous body of water
/// that flows organically — no discrete "blobs". The four corners are pinned to
/// the screen edges; the edge mid-points slide *along* their edge and the centre
/// roams gently, so the lit region drifts like light filtering through water.
///
/// The water darkens downward, as on every page (design/identity-2.1.md,
/// R1): a near-black touched warm at the top where the light comes in,
/// cooling through the middle, sinking to abyss. No bright middle and no
/// vignette; a page's light lies over it (`PageBackground`, `StageLight`).
///
/// `TimelineView(.animation)` runs uncapped, so ProMotion devices update at
/// their full refresh rate (60/120 Hz) and the flow is silky.
struct OceanBackground: View {
    /// Off by default (Malik, 2026-10-18): the drift moved at most 3/255 per
    /// channel, invisible, yet redrew the whole screen every frame and made
    /// every glass control above it recompute; the app idled at 30 to 55%
    /// CPU. The still water is the same picture. Onboarding may opt in.
    var animated: Bool = false

    @Environment(\.calmAccessibility) private var calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 3×3 colour grid: one row per depth, top to bottom.
    private let colors: [Color] = [
        OceanTheme.waterTop,    OceanTheme.waterTop,    OceanTheme.waterTop,
        OceanTheme.waterMiddle, OceanTheme.waterMiddle, OceanTheme.waterMiddle,
        OceanTheme.abyss,       OceanTheme.abyss,       OceanTheme.abyss
    ]

    var body: some View {
        // Calm Accessibility Mode and the system Reduce Motion setting both
        // still the water — one paused TimelineView quiets every screen that
        // stands on this background.
        TimelineView(.animation(paused: !animated || calm || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: points(t), colors: colors)
                .ignoresSafeArea()
        }
    }

    /// Mesh control points. Corners pinned; edge mid-points constrained to slide
    /// along their edge (so the mesh never pulls away from a screen edge); the
    /// centre roams freely at a low amplitude.
    private func points(_ t: Double) -> [SIMD2<Float>] {
        let topMidX:   Float = 0.5 + Float(sin(t * 0.050)) * 0.06
        let botMidX:   Float = 0.5 + Float(cos(t * 0.045)) * 0.06
        let leftMidY:  Float = 0.5 + Float(cos(t * 0.040)) * 0.07
        let rightMidY: Float = 0.5 + Float(sin(t * 0.055)) * 0.07
        let centreX:   Float = 0.5 + Float(sin(t * 0.037)) * 0.10
        let centreY:   Float = 0.5 + Float(cos(t * 0.032)) * 0.08
        return [
            SIMD2(0, 0),         SIMD2(topMidX, 0),       SIMD2(1, 0),
            SIMD2(0, leftMidY),  SIMD2(centreX, centreY), SIMD2(1, rightMidY),
            SIMD2(0, 1),         SIMD2(botMidX, 1),       SIMD2(1, 1)
        ]
    }
}

extension View {
    /// Standard screen treatment: ocean background behind content.
    func oceanScreen(animated: Bool = true) -> some View {
        background(OceanBackground(animated: animated))
    }
}
