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

/// The row every tab opens with: the tab's name in New York, its tools in
/// one frosted group at the right. Same size, place and spacing on Tide,
/// Ask and Library; it scrolls with the page.
struct PageTitleRow<Tools: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var tools: Tools

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(OceanType.pageTitle)
                .foregroundStyle(OceanTheme.foam)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            OceanToolGroup { tools }
        }
        .padding(.top, 8)
    }
}

extension PageTitleRow where Tools == SettingsTool {
    /// The common case: the gear alone, which makes the group a circle.
    init(title: LocalizedStringKey, showSettings: Binding<Bool>) {
        self.init(title: title) { SettingsTool(isPresented: showSettings) }
    }
}

/// Page tools in one frosted capsule, 36 pt tall in a 44 pt target. One tool
/// makes a circle (Tide's and Ask's gear); three make a capsule (Library).
struct OceanToolGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .tint(OceanTheme.mist)
            .frame(height: 36)
            .background(.ultraThinMaterial, in: Capsule())
            .frame(minHeight: 44)
    }
}

/// One glyph in a tool group: 17 pt regular, mist, a 36 pt cell.
struct OceanToolGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(OceanTheme.mist)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
    }
}

struct SettingsTool: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button { isPresented = true } label: { OceanToolGlyph(systemName: "gearshape") }
            .buttonStyle(.plain)
            .accessibilityLabel("Ocean settings")
    }
}

/// A page's own search field, drawn like Tide's surfaces: the tile fill, a
/// capsule, body type, mist glyphs.
struct OceanSearchField: View {
    @Binding var text: String
    let prompt: LocalizedStringKey
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(OceanTheme.mist)
            TextField(text: $text) {
                Text(prompt).foregroundStyle(OceanTheme.hint)
            }
            .font(.body)
            .foregroundStyle(OceanTheme.foam)
            .tint(OceanTheme.accent)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .focused(focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(OceanTheme.mist)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, text.isEmpty ? 16 : 6)
        .frame(height: 44)
        .background(OceanTheme.fill, in: Capsule())
    }
}

/// Every page stands on the same water and the same light: the moving
/// ocean and one warm lamp high on the left. The lamp is a radial light
/// across the whole screen, so it has no edge to show.
struct PageBackground: View {
    var lampLift: Double = 0
    var lampDim: Double = 1

    var body: some View {
        ZStack {
            OceanBackground()
            GeometryReader { geo in
                RadialGradient(
                    colors: [OceanTheme.glowWarm.opacity((0.11 + lampLift) * lampDim),
                             OceanTheme.glowWarm.opacity((0.04 + lampLift * 0.4) * lampDim),
                             .clear],
                    center: UnitPoint(x: 0.4, y: 0.3),
                    startRadius: 0,
                    endRadius: geo.size.height * 0.36
                )
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
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
