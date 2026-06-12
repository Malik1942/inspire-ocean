import SwiftUI

/// A *current* in the Ocean's interaction layer: one conceptual region holding
/// every thought that expresses its theme.
///
/// A current carries atmosphere and meaning, never arithmetic: the concept
/// label sits below, size and tint carry weight, and density is expressed by
/// the particles orbiting it — no number inside. Visual language is
/// unchanged: translucent glass, a whisper of tint, one restrained rim.
struct ClusterOrbView: View {
    let placement: ClusterPlacement
    var isDimmed: Bool = false
    var pulse: Double = 0     // 0…1 ambient breathing phase (sin-mapped)

    @Environment(\.calmAccessibility) private var calm

    private var diameter: CGFloat { placement.radius * 2 }

    private var color: Color {
        OceanTheme.color(forHue: placement.hue, brightness: 0.62 + 0.38 * placement.prominence)
    }

    var body: some View {
        ZStack {
            orb
            // The label drifts a little off true center (per-current, stable)
            // so the field reads as named water, not pinned data points.
            label.offset(
                x: placement.labelOffset.width,
                y: diameter / 2 + 13 + placement.labelOffset.height
            )
        }
        .scaleEffect(1.0 + CGFloat(pulse) * 0.014)
        .opacity(isDimmed ? 0.35 : 1.0)
        // The tappable region includes the label hanging below the orb —
        // the most legible thing about a current should open it too. The
        // position never carries meaning a tap can't reach.
        .contentShape(ClusterTapShape(labelDrop: 48))
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: isDimmed)
    }

    private var orb: some View {
        Circle()
            .fill(.ultraThinMaterial)
            // A more present glass — reads as lit water, not a faded ghost.
            // Separation from the dark field comes from body and a soft depth
            // shadow, never a hard border or a glow.
            .opacity(0.74)
            // Tint carries the concept's identity; brightness carries recency.
            .overlay(
                Circle().fill(color.opacity(0.10 + 0.09 * placement.prominence))
            )
            // Soft light from above — the orb's gentle, ambient luminosity.
            .overlay(
                Circle().fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            )
            .overlay(
                Circle().strokeBorder(
                    Color.white.opacity(0.07 + 0.06 * placement.prominence),
                    lineWidth: 0.6
                )
            )
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            // A deeper, soft shadow lifts the orb clearly off the water.
            .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
    }

    /// A semantic whisper, not a caption: light weight, airy tracking, mist
    /// tones that brighten only slightly with the current's recency. Calm
    /// Accessibility trades the whisper for legibility — these labels are
    /// the field's only words, so they're the first thing the mode brightens.
    private var label: some View {
        Text(placement.label)
            .font(calm ? .caption.weight(.medium) : .caption2.weight(.light))
            .kerning(calm ? 0.2 : 0.6)
            .foregroundStyle(calm
                ? OceanTheme.foam
                : OceanTheme.mist.opacity(0.74 + 0.24 * placement.prominence))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: max(96, diameter * 1.6))
            .shadow(color: .black.opacity(0.55), radius: 2.5)
    }
}

/// One thought, drawn as a small mote gathered around its current. Motes keep
/// the water alive and show each current's density; identity lives one tap
/// away (mote → thought, current → stream).
struct ThoughtMoteView: View {
    let mote: MotePlacement
    var isDimmed: Bool = false
    var pulse: Double = 0

    @Environment(\.calmAccessibility) private var calm

    private var diameter: CGFloat { mote.radius * 2 }

    /// Stable per-thought variation (0…1): no two particles share quite the
    /// same presence — some sit forward in the water, some recede.
    private var shimmer: Double {
        Double(NodeComposer.stableHash(mote.id.uuidString + "✦") % 1000) / 1000
    }

    var body: some View {
        ZStack {
            // Generous invisible touch target for a small visual; Calm
            // Accessibility widens it to the full 44pt the HIG asks for.
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: calm ? 44 : 36, height: calm ? 44 : 36)

            if mote.isResurfacing {
                Circle()
                    .fill(OceanTheme.glowWarm)
                    .frame(width: diameter * 1.7, height: diameter * 1.7)
                    .blur(radius: diameter * 0.45)
                    .opacity(0.10 + pulse * 0.06)
            }

            Circle()
                .fill(.ultraThinMaterial)
                .opacity(0.72)
                .overlay(
                    Circle().fill(
                        OceanTheme.color(forHue: mote.hue, brightness: 0.85).opacity(0.13)
                    )
                )
                .overlay(
                    Circle().strokeBorder(
                        mote.isResurfacing
                            ? OceanTheme.glowWarm.opacity(0.45)
                            : Color.white.opacity(0.10 + shimmer * 0.12),
                        lineWidth: 0.75
                    )
                )
                .frame(width: diameter, height: diameter)
                .scaleEffect(mote.isResurfacing ? 1.0 + CGFloat(pulse) * 0.05 : 1.0)
                .opacity(mote.isResurfacing ? 1.0 : 0.55 + shimmer * 0.45)
        }
        .opacity(isDimmed ? 0.25 : 1.0)
        .contentShape(Circle())
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: isDimmed)
    }
}

// MARK: - Hit shapes

/// The orb plus the label hanging below it, so tapping a current's *name*
/// opens its stream too. The Ocean's positions are atmosphere; its words are
/// the interface — both should answer a touch.
private struct ClusterTapShape: Shape {
    var labelDrop: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: rect)
        path.addRect(CGRect(
            x: rect.minX - 12,
            y: rect.midY,
            width: rect.width + 24,
            height: rect.height / 2 + labelDrop
        ))
        return path
    }
}
