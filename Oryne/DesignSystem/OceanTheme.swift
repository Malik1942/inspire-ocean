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

/// Color, type and gradient language for Oryne.
///
/// The Ocean should feel "atmospheric, calm, and alive" (§8) — deep and spatial,
/// with color drawn from each fragment's `hue`.
enum OceanTheme {

    // MARK: Palette — near-monochrome, spatial

    static let abyss   = Color(red: 0.02,  green: 0.02,  blue: 0.03)
    static let deep    = Color(red: 0.05,  green: 0.055, blue: 0.065)
    static let mid     = Color(red: 0.09,  green: 0.095, blue: 0.11)
    static let current = Color(red: 0.15,  green: 0.155, blue: 0.175)
    static let surface = Color(red: 0.24,  green: 0.245, blue: 0.27)

    static let foam  = Color.white.opacity(0.92)
    static let mist  = Color.white.opacity(0.50)
    static let faint = Color.white.opacity(0.26)

    /// Soft near-white for interactive accents — kept monochrome.
    static let accent   = Color(red: 0.82, green: 0.84, blue: 0.88)
    /// Whisper-warm white that sets a resurfacing fragment apart by temperature
    /// rather than saturation.
    static let glowWarm = Color(red: 0.95, green: 0.93, blue: 0.88)

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

// MARK: - OceanBackground

/// The deep, spatial ocean background used across the app.
///
/// An animated `MeshGradient` (iOS 18) gives a single continuous body of water
/// that flows organically — no discrete "blobs". The four corners are pinned to
/// the screen edges; the edge mid-points slide *along* their edge and the centre
/// roams gently, so the lit region drifts like light filtering through water.
/// A depth vignette darkens the edges for a sense of space.
///
/// `TimelineView(.animation)` runs uncapped, so ProMotion devices update at
/// their full refresh rate (60/120 Hz) and the flow is silky.
struct OceanBackground: View {
    var animated: Bool = true

    @Environment(\.calmAccessibility) private var calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 3×3 colour grid — near-monochrome, lit toward the upper-centre, sinking
    /// to abyssal dark at the lower corners.
    private let colors: [Color] = [
        OceanTheme.deep,  OceanTheme.mid,     OceanTheme.deep,
        OceanTheme.mid,   OceanTheme.current, OceanTheme.mid,
        OceanTheme.abyss, OceanTheme.deep,    OceanTheme.abyss
    ]

    var body: some View {
        // Calm Accessibility Mode and the system Reduce Motion setting both
        // still the water — one paused TimelineView quiets every screen that
        // stands on this background.
        TimelineView(.animation(paused: !animated || calm || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: points(t), colors: colors)
                .ignoresSafeArea()
                .overlay {
                    // Depth vignette — darkens the edges, holds focus centrally.
                    RadialGradient(
                        colors: [.clear, OceanTheme.abyss.opacity(0.55)],
                        center: .center,
                        startRadius: 90,
                        endRadius: 560
                    )
                    .ignoresSafeArea()
                }
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

// MARK: - Reusable components

/// A soft, glassy card used for content surfaces.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}

/// A small theme/keyword tag.
struct ThemeTag: View {
    let text: String
    var hue: Double = 0.55

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(OceanTheme.foam)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(OceanTheme.color(forHue: hue).opacity(0.20))
            )
            .overlay(
                Capsule().strokeBorder(OceanTheme.color(forHue: hue).opacity(0.30), lineWidth: 0.5)
            )
    }
}

extension View {
    /// Standard screen treatment: ocean background behind content.
    func oceanScreen(animated: Bool = true) -> some View {
        background(OceanBackground(animated: animated))
    }
}
