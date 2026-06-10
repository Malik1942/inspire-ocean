import SwiftUI

/// A single fragment in the Ocean's *interaction layer*.
///
/// Visual hierarchy is carried by size, brightness, depth-blur, and a single
/// restrained glow — never stacked heavy effects. The glass uses
/// `.ultraThinMaterial` with a small radial specular to keep it clean and crisp
/// rather than frosted-over. Labels appear only for foreground or focused nodes
/// (progressive disclosure), with a minimal pill on focus.
struct OceanNodeView: View {
    let node:      Node
    let placement: OceanPlacement
    var isFocused: Bool   = false
    var isDimmed:  Bool   = false
    var pulse:     Double = 0     // 0…1 ambient breathing phase (sin-mapped)

    // MARK: Derived geometry

    private var diameter: CGFloat { placement.radius * 2 }

    private var color: Color {
        OceanTheme.color(forHue: node.hue, brightness: 0.60 + 0.40 * placement.prominence)
    }

    private var showLabel:  Bool { placement.tier == .foreground || isFocused }
    private var showGlyph:  Bool { placement.radius >= 14 }
    private var hitSize:    CGFloat { max(diameter, 52) }

    // MARK: Scale

    private var focusScale: CGFloat { isFocused ? 1.16 : 1.0 }

    /// Breathing is very subtle — you notice it when staring, not at a glance.
    private var pulseScale: CGFloat {
        if placement.isResurfacing { return 1.0 + CGFloat(pulse) * 0.035 }
        if placement.tier == .foreground { return 1.0 + CGFloat(pulse) * 0.012 }
        return 1.0
    }

    // MARK: Depth / focus modifiers

    private var nodeOpacity: Double {
        if isFocused { return 1.0 }
        if isDimmed  { return placement.tier == .foreground ? 0.38 : 0.20 }
        // Background orbs sit clearly above the water so they read as fragments,
        // not background texture — but stay below the foreground.
        return placement.tier == .foreground ? 1.0 : (0.50 + 0.38 * placement.prominence)
    }

    private var blurRadius: CGFloat {
        if isFocused { return 0 }
        // Only a whisper of depth-blur on background orbs — enough to recede,
        // not so much that it smears away their outline.
        var b: CGFloat = placement.tier == .background
            ? CGFloat(1 - placement.prominence) * 0.12
            : 0
        if isDimmed { b += 2.0 }
        return b
    }

    /// Rim colour — every orb gets a defined edge. The small background orbs get
    /// a clearer outline so they read as fragments; the foreground reads through
    /// its fill, glyph and label, so its rim stays subtle.
    private var rimColor: Color {
        if placement.isResurfacing {
            return OceanTheme.glowWarm.opacity(isFocused ? 0.60 : 0.34)
        }
        if isFocused { return Color.white.opacity(0.30) }
        return Color.white.opacity(placement.tier == .background ? 0.12 : 0.12)
    }

    // MARK: Body

    var body: some View {
        ZStack {
            // Invisible, generous touch target — always at least 52 pt.
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: hitSize, height: hitSize)

            orb

            if showLabel {
                label.offset(y: diameter / 2 + 13)
            }
        }
        .scaleEffect(focusScale * pulseScale)
        .opacity(nodeOpacity)
        .blur(radius: blurRadius)
        .contentShape(Circle())
        // Smooth Apple-style spring for focus transitions.
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: isFocused)
        .animation(.spring(response: 0.50, dampingFraction: 0.88), value: isDimmed)
    }

    // MARK: Orb

    /// A calm, translucent presence in the water — not a solid glass button.
    /// Kept deliberately quiet so no single orb dominates the field; hierarchy
    /// comes from subtle differences in tint, rim and the faint focus halo.
    private var orb: some View {
        ZStack {
            // Faint halo only when focused or resurfacing — otherwise nothing,
            // so the resting field stays even and balanced.
            if isFocused || placement.isResurfacing {
                Circle()
                    .fill(placement.isResurfacing ? OceanTheme.glowWarm : Color.white)
                    .frame(width: diameter * 1.3, height: diameter * 1.3)
                    .blur(radius: diameter * 0.32)
                    .opacity(isFocused ? 0.10 : 0.06)
            }

            // Translucent glass core — softened so it reads as part of the water.
            Circle()
                .fill(.ultraThinMaterial)
                .opacity(0.55)
                // Whisper of tint so hierarchy is legible without colour noise.
                .overlay(
                    Circle().fill(color.opacity(0.03 + 0.05 * placement.prominence))
                )
                // Soft top-down sheen — gentle, not a sharp glass glint.
                .overlay(
                    Circle().fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isFocused ? 0.14 : 0.08),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                )
                // Defined rim — gives each orb a clear edge against the water.
                .overlay(
                    Circle().strokeBorder(
                        rimColor,
                        lineWidth: placement.tier == .background ? 0.75 : 0.5
                    )
                )
                .overlay { if showGlyph { glyph } }
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                // Single soft shadow — lifts the orb just off the water.
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        }
    }

    // MARK: Glyph

    @ViewBuilder
    private var glyph: some View {
        if let data = node.imageData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable().scaledToFill()
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .opacity(0.82)
        } else {
            Image(systemName: node.kind.symbol)
                .font(.system(size: diameter * 0.28, weight: .regular))
                .foregroundStyle(Color.white.opacity(isFocused ? 0.7 : 0.5))
        }
    }

    // MARK: Label

    private var label: some View {
        Text(placement.title)
            .font(isFocused ? .caption.weight(.medium) : .caption2.weight(.light))
            .foregroundStyle(isFocused ? OceanTheme.foam : OceanTheme.mist)
            .multilineTextAlignment(.center)
            .lineLimit(isFocused ? 3 : 2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: max(88, diameter * 1.5))
            .padding(.horizontal, isFocused ? 9 : 0)
            .padding(.vertical,   isFocused ? 5 : 0)
            .background {
                if isFocused {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                }
            }
            // Text shadow — provides separation without a background when unfocused.
            .shadow(color: .black.opacity(isFocused ? 0 : 0.75), radius: 3)
            .animation(.spring(response: 0.36, dampingFraction: 0.84), value: isFocused)
    }
}
