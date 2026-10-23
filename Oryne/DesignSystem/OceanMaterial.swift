import SwiftUI

/// The material facet in code: the one matte surface, its shadow, and the
/// small things laid on a photograph. Compiled into every target (the app,
/// the share extension, the widgets, the watch), so SwiftUI only.

/// One drop shadow, as the generated `OceanShadow` roles describe it.
struct OceanShadowValue {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    /// The role's shadow under this view. `enabled: false` draws none and
    /// costs nothing (a card translating in a reorder drops its shadow so
    /// the blur is not re-rasterized every frame).
    func oceanShadow(_ shadow: OceanShadowValue, enabled: Bool = true) -> some View {
        self.shadow(color: enabled ? shadow.color : .clear, radius: enabled ? shadow.radius : 0, x: shadow.x, y: shadow.y)
    }
}

/// The one matte surface for everything in the content layer: tiles, link
/// cards, fields, the search field and the quiet buttons. A single flat
/// fill, no gradient, no rim, no gloss, resting on a soft shadow so it sits
/// just above the water. The shadow belongs to the shape alone, so it stays
/// cheap even under a picture.
///
/// Form is the shape; material is the fill and the shadow; the press is the
/// only motion, and the caller animates it.
struct OceanSurface<S: Shape>: View {
    let shape: S
    /// Controls sit a step brighter than tiles so they read as controls.
    var raised = false
    /// A control's on state: the segmented switch's thumb, a chosen chip.
    var selected = false
    var pressed = false
    var shadow = true

    private var fill: Color {
        if selected { return OceanTheme.selected }
        return raised ? OceanTheme.raised : OceanTheme.fill
    }

    var body: some View {
        shape
            .fill(fill)
            .overlay {
                if pressed { shape.fill(OceanTheme.pressedLift) }
            }
            .oceanShadow(raised || selected ? OceanShadow.control : OceanShadow.tile, enabled: shadow)
    }
}

/// The small ✕ in a picture's corner: a white glyph on a dark disc, so it
/// reads on any photo, inside a 32 pt target. VoiceOver reaches it as its
/// tile's named action.
struct OceanRemoveBadge: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(OceanType.badge)
                .foregroundStyle(OceanTheme.onPhoto)
                .frame(width: OceanSize.metaIcon + OceanSpacing.tight, height: OceanSize.metaIcon + OceanSpacing.tight)
                .background(OceanTheme.photoScrim, in: Circle())
                .padding(OceanSpacing.tight)
                .frame(width: OceanSize.removeTarget, height: OceanSize.removeTarget, alignment: .topTrailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
