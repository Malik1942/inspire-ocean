import SwiftUI

/// The three controls Oryne allows. Every button in the app wears one of
/// these, so a glance says what a control is: the one main action, a quiet
/// action, or a tool.
///
/// - Primary: accent fill, abyss ink. Release, Keep, the capture disc ready.
/// - Secondary: glass capsule, foam label. Chips, Undo, Summarize, Close.
/// - Icon: a 36 pt glass circle in a 44 pt target, mist glyph. Gear, X.
///
/// Radii: anything up to 48 pt tall is a full capsule; cards are 20 pt
/// continuous; media inside a card 14 pt. Glyphs are SF Symbols, outline
/// variants, regular weight, 17 pt; only the capture disc and Stop use fills.
enum OceanRadius {
    static let card: CGFloat = 20
    static let media: CGFloat = 14
}

struct OceanPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? OceanTheme.abyss : Color.white.opacity(0.62))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isEnabled ? OceanTheme.accent : Color.white.opacity(0.12), in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: isEnabled)
    }
}

struct OceanSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(OceanTheme.foam)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.08), in: Capsule())
    }
}

struct OceanIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(OceanTheme.mist)
            .frame(width: 36, height: 36)
            .background(.ultraThinMaterial, in: Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }
}

/// Primary in its icon form: a 36 pt accent circle in a 44 pt target.
struct OceanPrimaryIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isEnabled ? OceanTheme.abyss : Color.white.opacity(0.62))
            .frame(width: 36, height: 36)
            .background(isEnabled ? OceanTheme.accent : Color.white.opacity(0.12), in: Circle())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }
}

extension ButtonStyle where Self == OceanPrimaryIconButtonStyle {
    static var oceanPrimaryIcon: OceanPrimaryIconButtonStyle { OceanPrimaryIconButtonStyle() }
}
extension ButtonStyle where Self == OceanPrimaryButtonStyle {
    static var oceanPrimary: OceanPrimaryButtonStyle { OceanPrimaryButtonStyle() }
}
extension ButtonStyle where Self == OceanSecondaryButtonStyle {
    static var oceanSecondary: OceanSecondaryButtonStyle { OceanSecondaryButtonStyle() }
}
extension ButtonStyle where Self == OceanIconButtonStyle {
    static var oceanIcon: OceanIconButtonStyle { OceanIconButtonStyle() }
}

/// The settings gear every tab wears in the same place. Toolbar items take
/// the system's own treatment (iOS 26 draws its glass around them), so the
/// Icon style is for controls inside content, not in toolbars.
struct SettingsGearButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Ocean settings")
    }
}
