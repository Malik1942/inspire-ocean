import SwiftUI

/// The four controls Oryne allows. Every button in the app wears one of
/// these, so a glance says what a control is: the one main action, a quiet
/// action, a tool, or a word that acts.
///
/// Each is a form, a material and a motion composed together, and a variant
/// changes one facet and leaves the other two alone:
///
/// - Primary: a 44 pt capsule (form), Liquid Glass with the faint white
///   tint and foam words (material), the touch motion: the same glass as
///   the disc when it is ready, never a solid light fill. Save, Grow,
///   Continue, the send arrow.
/// - Secondary: the same capsule, the raised matte fill with foam words
///   (material). Chips, Undo, Summarize, Close. `selected` swaps the fill
///   for the selected one and nothing else.
/// - Icon: a 44 pt circle (form), Liquid Glass with a foam glyph
///   (material). Page chrome only: the gear, a close, the +.
/// - Link: no surface at all; a word or a glyph in the accent (or mist, when
///   quiet), inside a 44 pt target. Undo in a toast, Retry, Clear, a quiet
///   way on beside a section label.
///
/// Radii: anything up to a control's height is a full capsule; tiles
/// (anything you open) are `OceanRadius.card`; media at the top of a page
/// `OceanRadius.media`; a thumbnail inside a tile `OceanRadius.thumbnail`.
/// Glyphs are SF Symbols, outline variants, `OceanType.glyph`; only the
/// capture disc and Stop use fills. The Icon style is for page chrome,
/// never inside a tile: a chevron in content is a bare glyph.

extension OceanSpacing {
    /// Page margin, left and right, on every surface: the system's own
    /// margin for this window, so page tools, fields, tiles, bars and words
    /// start where a navigation bar puts its back button and a sheet its
    /// close. UIKit uses 16 pt on standard iPhones and 20 on wide ones
    /// (measured 2026-10-22: 16 at 402 pt, 20 at 420 and 440).
    @MainActor static var gutter: CGFloat {
        let width = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .map { $0.windows.first?.bounds.width ?? $0.screen.bounds.width }
            .max() ?? 0
        return width >= gutterBreakpoint ? gutterWide : gutterCompact
    }
}

/// Liquid Glass, the material of the tab bar and the navigation bar, for
/// the layer that floats over content: bars, the toast, page tools, sheet
/// chrome, the discs. Content-layer buttons stay matte (Secondary). Before
/// iOS 26 it falls back to the thin material the app used before.
extension View {
    @ViewBuilder
    func oceanGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            let base: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
            self.glassEffect(interactive ? base.interactive() : base, in: shape)
        } else {
            self.background(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.ultraThinMaterial), in: shape)
        }
    }
}

/// The one main action: the Icon style's glass in a capsule, with the
/// faint tint the capture disc takes when it is ready (Malik, 2026-10-18:
/// no solid light fills for active states). Disabled, it is plain glass
/// with mist words.
/// A control's words beside its glyph: a snug gap, the glyph first, both
/// in the control's own font. Every button style applies it, so a Label
/// in a button never falls back to the system's wide spacing.
struct OceanControlLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: OceanSpacing.snug) {
            configuration.icon
            configuration.title
        }
    }
}

struct OceanPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(OceanControlLabelStyle())
            .font(OceanType.controlStrong)
            .foregroundStyle(isEnabled ? OceanTheme.foam : OceanTheme.mist)
            .padding(.horizontal, OceanSpacing.controlInset)
            .frame(minHeight: OceanControlSize.height)
            .oceanGlass(in: Capsule(), tint: isEnabled ? OceanTheme.glassTint : nil)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(OceanMotion.touch, value: isEnabled)
    }
}

/// The quiet action, in the content layer: a matte capsule from the same
/// family as the tiles (a step brighter so it reads as a control), no rim,
/// 44 pt tall, foam words. Glass is for the layer that floats over content
/// (bars, toast, page tools, sheet chrome); a button that scrolls with the
/// cards wears the cards' material. `selected` is the on state of a choice
/// among several (a branch type, a chip that is on).
struct OceanSecondaryButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(OceanControlLabelStyle())
            .font(OceanType.control)
            .foregroundStyle(OceanTheme.foam)
            .padding(.horizontal, OceanSpacing.controlInset)
            .frame(minHeight: OceanControlSize.height)
            .background(OceanSurface(shape: Capsule(), raised: true, selected: selected, pressed: configuration.isPressed))
            .contentShape(Capsule())
            .animation(OceanMotion.touch, value: configuration.isPressed)
    }
}

/// A tool: a 44 pt glass circle with a foam glyph, the same cell as a tool
/// group and the navigation bar's own buttons. Inside a field it is the
/// compact disc (`OceanControlSize.compact`), as Messages sizes its +,
/// still inside a 44 pt target.
struct OceanIconButtonStyle: ButtonStyle {
    var size: CGFloat = OceanControlSize.height

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OceanType.glyph)
            .foregroundStyle(OceanTheme.foam)
            .frame(width: size, height: size)
            .oceanGlass(in: Circle())
            .frame(width: OceanControlSize.height, height: OceanControlSize.height)
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Primary in its icon form, the send and release arrow: a 44 pt glass
/// circle that stays glass. Ready, it takes a faint white tint and a
/// bright arrow, as the capture disc does while listening; never a solid
/// light disc that would be the brightest thing on screen.
struct OceanPrimaryIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OceanType.glyphStrong)
            .foregroundStyle(isEnabled ? OceanTheme.foam : OceanTheme.mist)
            .frame(width: OceanControlSize.height, height: OceanControlSize.height)
            .oceanGlass(in: Circle(), tint: isEnabled ? OceanTheme.glassTint : nil)
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// A word that acts, with no surface of its own: Undo beside a toast's
/// message, Retry under a link, Clear in a chip. Accent by default; `quiet`
/// for a way on that sits beside a section label and must never be louder
/// than it. Always a 44 pt target.
struct OceanLinkButtonStyle: ButtonStyle {
    enum Tone { case accent, quiet }
    var tone: Tone = .accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(OceanControlLabelStyle())
            .font(tone == .accent ? OceanType.controlStrong : OceanType.control)
            .foregroundStyle(!isEnabled ? OceanTheme.faint : tone == .accent ? OceanTheme.accent : OceanTheme.mist)
            .frame(minWidth: OceanControlSize.height, minHeight: OceanControlSize.height)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(OceanMotion.touch, value: configuration.isPressed)
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
    static func oceanSecondary(selected: Bool) -> OceanSecondaryButtonStyle { OceanSecondaryButtonStyle(selected: selected) }
}
extension ButtonStyle where Self == OceanIconButtonStyle {
    static var oceanIcon: OceanIconButtonStyle { OceanIconButtonStyle() }
    static func oceanIcon(size: CGFloat) -> OceanIconButtonStyle { OceanIconButtonStyle(size: size) }
}
extension ButtonStyle where Self == OceanLinkButtonStyle {
    static var oceanLink: OceanLinkButtonStyle { OceanLinkButtonStyle() }
    static func oceanLink(_ tone: OceanLinkButtonStyle.Tone) -> OceanLinkButtonStyle { OceanLinkButtonStyle(tone: tone) }
}

/// The system switch with its on state in `OceanTheme.switchOn`. The app's
/// monochrome tint drew a near-white track under the white knob, so on read
/// like off.
struct OceanSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .tint(OceanTheme.switchOn)
    }
}

extension ToggleStyle where Self == OceanSwitchToggleStyle {
    static var oceanSwitch: OceanSwitchToggleStyle { OceanSwitchToggleStyle() }
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

/// The send disc in Ask's bar, the twin of the capture disc: 44 pt glass.
/// Plain with a mist arrow while there is nothing to send; a faint white
/// tint and a bright arrow once there is.
struct OceanSendDiscStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OceanType.glyphStrong)
            .foregroundStyle(isEnabled ? OceanTheme.foam : OceanTheme.mist)
            .frame(width: OceanControlSize.height, height: OceanControlSize.height)
            .oceanGlass(in: Circle(), tint: isEnabled ? OceanTheme.glassTint : nil)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Circle())
            .animation(OceanMotion.touch, value: isEnabled)
    }
}

/// Page tools in one glass capsule, 44 pt tall, 44 pt cells (the Library's
/// view switch and filter). It sits in the system bar as one item with the
/// bar's own glass hidden, so this capsule is the only one.
struct OceanToolGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            // The bar enlarges its symbols; the group keeps the glyph's size.
            .imageScale(.medium)
            .tint(OceanTheme.foam)
            .frame(height: OceanControlSize.height)
            .oceanGlass(in: Capsule())
    }
}

/// One glyph in a tool group: the control glyph, foam, in a 44 pt cell.
struct OceanToolGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(OceanType.glyph)
            .foregroundStyle(OceanTheme.foam)
            .frame(width: OceanControlSize.height, height: OceanControlSize.height)
            .contentShape(Rectangle())
    }
}

/// A page's own search field, drawn like Tide's surfaces: the tile fill, a
/// capsule, body type, mist glyphs. In a bar over the page (`glass`) it
/// wears the floating layer's glass instead, like the tools it sits among.
struct OceanSearchField: View {
    @Binding var text: String
    let prompt: LocalizedStringKey
    var focused: FocusState<Bool>.Binding
    var glass = false

    @ViewBuilder
    var body: some View {
        if glass {
            field.oceanGlass(in: Capsule())
        } else {
            field.background(OceanSurface(shape: Capsule()))
        }
    }

    private var field: some View {
        HStack(spacing: OceanSpacing.gap) {
            Image(systemName: "magnifyingglass")
                .font(OceanType.glyph)
                .foregroundStyle(OceanTheme.mist)
            TextField(text: $text) {
                Text(prompt).foregroundStyle(OceanTheme.hint)
            }
            .font(OceanType.body)
            .foregroundStyle(OceanTheme.foam)
            .tint(OceanTheme.accent)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .focused(focused)
            .onSubmit { focused.wrappedValue = false }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(OceanType.glyph)
                        .foregroundStyle(OceanTheme.mist)
                        .frame(width: OceanSize.removeTarget, height: OceanControlSize.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, OceanSpacing.inset)
        .padding(.trailing, text.isEmpty ? OceanSpacing.inset : OceanSpacing.snug)
        .frame(height: OceanControlSize.height)
    }
}

/// Every page stands on the same water and the same light: the still
/// ocean and one warm lamp high on the left. The lamp is a radial light
/// across the whole screen, so it has no edge to show. Art-directed: the
/// lamp's reach and warmth are the page's own, not tokens.
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
        HStack(alignment: .firstTextBaseline, spacing: OceanSpacing.gap) {
            Image(systemName: node.kind.symbol)
                .font(OceanType.meta)
                .foregroundStyle(OceanTheme.mist)
                .frame(width: OceanSize.glyphSlot)
            Text(node.displayTitle)
                .font(OceanType.body)
                .foregroundStyle(OceanTheme.foam)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: OceanSpacing.gap)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(OceanType.glyphDisclosure)
                    .foregroundStyle(OceanTheme.faint)
            }
        }
        .padding(.vertical, OceanSpacing.gap)
        .frame(minHeight: OceanControlSize.height)
        .contentShape(Rectangle())
    }
}

/// The one toast: what happened, and the way back. A capsule in the bar's
/// own material, floating over the page for the whole undo window. The
/// capture toast and the removal toast are this one view.
struct OceanToast: View {
    /// Already localized: VoiceOver announces the same words.
    let message: String
    let actionTitle: LocalizedStringKey
    var actionAccessibilityLabel: LocalizedStringKey? = nil
    var action: () -> Void

    var body: some View {
        HStack(spacing: OceanSpacing.inset) {
            Text(message)
                .font(OceanType.control)
                .foregroundStyle(OceanTheme.foam)
                .lineLimit(1)
            Button(actionTitle, action: action)
                .buttonStyle(.oceanLink)
                .accessibilityLabel(actionAccessibilityLabel ?? actionTitle)
        }
        .padding(.leading, OceanSpacing.controlInset)
        .padding(.trailing, OceanSpacing.gap)
        .frame(height: OceanControlSize.toast)
        .background(OceanBarBackground(dense: true))
        .accessibilityElement(children: .contain)
    }
}

/// A text field in the content layer: the tile fill in the field's corner,
/// body type in foam, the compact inset, a control's height. The same
/// surface whether it holds one line or an editor.
struct OceanFieldSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(OceanType.body)
            .foregroundStyle(OceanTheme.foam)
            .tint(OceanTheme.accent)
            .padding(.vertical, OceanSpacing.gap)
            .padding(.horizontal, OceanSpacing.insetCompact)
            .frame(minHeight: OceanControlSize.height)
            .background(OceanTheme.fill, in: RoundedRectangle(cornerRadius: OceanRadius.field, style: .continuous))
    }
}

extension View {
    func oceanField() -> some View { modifier(OceanFieldSurface()) }
}

/// A strip of pictures on a draft (the edit sheet, a branch): each a
/// picture tile with its remove badge, scrolling sideways past the width.
struct OceanPictureStrip: View {
    let datas: [Data]
    var onRemove: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OceanSpacing.gap) {
                ForEach(Array(datas.enumerated()), id: \.offset) { index, data in
                    if let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable().scaledToFill()
                            .frame(width: OceanSize.pictureTile, height: OceanSize.pictureTile)
                            .clipShape(RoundedRectangle(cornerRadius: OceanRadius.thumbnail, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                OceanRemoveBadge { onRemove(index) }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text("Image \(index + 1) of \(datas.count)"))
                            .accessibilityAction(named: Text("Remove image")) { onRemove(index) }
                    }
                }
            }
        }
        .frame(height: OceanSize.pictureTile)
    }
}

/// How a sheet opens, in the grammar of a tab's large title: the
/// grabber that says the sheet can be pulled away (every sheet's way out),
/// then the subject in New York with the sheet's one action on the same
/// line as Primary, ending on the gutter. No close and no cancel: a sheet
/// is pulled down, and what it held unsaved goes with it.
///
/// The grabber is drawn here, not asked of the system, so every sheet
/// opens the same way.
struct OceanSheetHeader<Action: View>: View {
    let title: Text
    @ViewBuilder var action: Action

    var body: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.item) {
            OceanSheetGrabber()
            HStack(alignment: .center, spacing: OceanSpacing.item) {
                title
                    .font(OceanType.subjectTitle)
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                action
            }
            .frame(minHeight: OceanControlSize.height)
        }
    }
}

extension OceanSheetHeader where Action == EmptyView {
    /// A sheet with no action of its own (a picker: tapping a choice is the action).
    init(title: Text) {
        self.init(title: title) { EmptyView() }
    }
}

/// The system grabber's own proportions, drawn on the water at the top of
/// a sheet's content. Hidden from VoiceOver: the sheet's dismiss gesture
/// is the system's.
struct OceanSheetGrabber: View {
    var body: some View {
        Capsule()
            .fill(OceanTheme.faint)
            .frame(width: OceanSize.grabberWidth, height: OceanSize.grabberHeight)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// A field that adds to a list of chips (a theme): the search field's
/// capsule and height, a + where the magnifier sits, and return adds. No
/// separate button to find.
struct OceanAddField: View {
    @Binding var text: String
    let prompt: LocalizedStringKey
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: OceanSpacing.gap) {
            Image(systemName: "plus")
                .font(OceanType.glyph)
                .foregroundStyle(OceanTheme.mist)
            TextField(text: $text) {
                Text(prompt).foregroundStyle(OceanTheme.hint)
            }
            .font(OceanType.body)
            .foregroundStyle(OceanTheme.foam)
            .tint(OceanTheme.accent)
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .onSubmit(onAdd)
        }
        .padding(.horizontal, OceanSpacing.inset)
        .frame(height: OceanControlSize.height)
        .background(OceanSurface(shape: Capsule()))
    }
}
