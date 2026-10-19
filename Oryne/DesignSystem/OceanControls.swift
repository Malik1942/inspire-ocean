import SwiftUI

/// The three controls Oryne allows. Every button in the app wears one of
/// these, so a glance says what a control is: the one main action, a quiet
/// action, or a tool.
///
/// - Primary: accent fill, abyss ink. Release, Keep, the capture disc ready.
/// - Secondary: glass capsule, foam label. Chips, Undo, Summarize, Close.
/// - Icon: a 36 pt glass circle in a 44 pt target, mist glyph. Gear, X.
///
/// Radii: anything up to 56 pt tall is a full capsule; tiles (anything you
/// open: a card, a row, a current) are 20 pt continuous; media at the top of
/// a page 14 pt; a thumbnail inside a tile 10 pt. Glyphs are SF Symbols,
/// outline variants, regular weight, 17 pt; only the capture disc and Stop
/// use fills. The Icon style is for page chrome (the gear, a close), never
/// inside a tile: a chevron in content is a bare glyph.
enum OceanRadius {
    static let card: CGFloat = 20
    static let media: CGFloat = 14
    static let thumbnail: CGFloat = 10
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

/// The send disc in Ask's bar, the twin of the capture disc: 44 pt, flat.
/// Matte while there is nothing to send, Primary once there is.
struct OceanSendDiscStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isEnabled ? OceanTheme.abyss : OceanTheme.mist)
            .frame(width: FastCaptureLayout.buttonSize, height: FastCaptureLayout.buttonSize)
            .background(isEnabled ? OceanTheme.accent : Color.white.opacity(0.10), in: Circle())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.15), value: isEnabled)
    }
}

/// The row every tab opens with: the tab's name in New York and the gear at
/// the right, on one line. Tide and Ask draw it in their content; Library's
/// system large title wears the same face (OceanType).
struct PageTitleRow: View {
    let title: LocalizedStringKey
    @Binding var showSettings: Bool

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(OceanType.pageTitle)
                .foregroundStyle(OceanTheme.foam)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            SettingsGearButton(isPresented: $showSettings)
                .buttonStyle(.oceanIcon)
        }
        .padding(.top, 8)
    }
}

/// A thought mentioned inside something else (an answer's sources, the
/// resurfacing thought's neighbours): its kind and its title, a line of
/// text, no tile. A tile is for a list of thoughts; a line is a reference.
struct ThoughtLine: View {
    let node: Node
    var showsChevron = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: node.kind.symbol)
                .font(.footnote)
                .foregroundStyle(OceanTheme.mist)
                .frame(width: 18)
            Text(node.displayTitle)
                .font(.body)
                .foregroundStyle(OceanTheme.foam)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OceanTheme.faint)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
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
