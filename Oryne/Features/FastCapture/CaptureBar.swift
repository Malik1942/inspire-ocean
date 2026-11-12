import SwiftUI

/// The capture bar above the tab bar on Tide, like a message composer:
/// words to tap to type, and a disc to tap or hold to whisper. Its
/// geometry is fixed so the disc sits concentric with the capsule's end
/// (FastCaptureLayout). The Library has none: it is for finding, and its
/// one input is its search.
///
/// A draft put away unsent waits here: its first line in place of the
/// question, and the disc is its send. Tapping the words brings it back.
struct CaptureBar: View {
    @Environment(CaptureControl.self) private var control

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                control.tap()
            } label: {
                CaptureBarWords(draft: control.parked?.line, glyph: control.parked?.glyph)
                    .padding(.leading, FastCaptureLayout.fieldLeading)
                    // The words stop short of the disc.
                    .padding(.trailing, FastCaptureLayout.buttonSize + FastCaptureLayout.discInset + OceanSpacing.gap)
                    // minWidth 0: long words are cut short instead of
                    // widening the bar.
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Past the bar's cap a long press shows its words large. They
            // are given here: by default the viewer shows the label.
            .accessibilityShowsLargeContentViewer {
                Text(verbatim: control.parked?.line ?? String(localized: "What are you noticing?"))
            }
            .accessibilityLabel("Capture a thought")
            // A draft of only pictures reads its line ("3 images").
            .accessibilityValue(Text(verbatim: control.parked.map { $0.text.trimmed.isEmpty ? $0.line : $0.text } ?? ""))
            .accessibilityHint(control.parked == nil
                ? Text("Opens the keyboard. The button beside it whispers.")
                : Text("Opens the keyboard. The button beside it releases the draft."))
            .accessibilityIdentifier("captureBar.field")

            CaptureHoldButton(
                size: FastCaptureLayout.buttonSize,
                send: control.parked == nil ? nil : { control.releaseParked = true }
            )
            .padding(.trailing, FastCaptureLayout.discInset)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: FastCaptureLayout.barHeight)
        // The words never spill past the capsule's ends; the surface and
        // its shadow sit outside the clip.
        .clipShape(Capsule())
        .background(OceanBarBackground())
        .frame(maxWidth: .infinity, alignment: .trailing)
        // The bar stays 56 pt: up to the largest standard size one line of
        // its words still fits the disc's 44 pt row.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// What the bar says: its question, or the first line of a draft put away,
/// cut with an ellipsis clear of the disc. The composer's card says the
/// same in the same place while it is folded, so the fold lands on the bar.
/// A draft's words are set in the user's serif, as they were typed; a line
/// that only names what rides along (a whisper, pictures) is Oryne's, in
/// SF, as the question is.
struct CaptureBarWords: View {
    let draft: String?
    /// Before a line that names what rides along (a whisper, pictures).
    var glyph: String? = nil

    private var role: OceanTextRole { glyph == nil ? OceanType.inputWords : OceanType.body }

    var body: some View {
        if let draft {
            HStack(spacing: OceanSpacing.snug) {
                if let glyph {
                    // Inside the line, so it takes the line's role and
                    // grows with its words.
                    Image(systemName: glyph)
                        .oceanText(role)
                        .imageScale(.small)
                        .foregroundStyle(OceanTheme.mist)
                        .accessibilityHidden(true)
                }
                Text(verbatim: draft)
                    .oceanText(role)
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else {
            Text("What are you noticing?")
                .oceanText(OceanType.body)
                .foregroundStyle(OceanTheme.mist)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// The bar's Liquid Glass capsule, at the bar's frame: listening in the
/// overlay draws in it, so the bar never changes shape or material.
/// Taller content grows it into a rounded rectangle with the same end
/// radius, which at one line is exactly the capsule. Typing grows the
/// same glass into the composer's card instead.
struct CaptureCapsule<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(FastCaptureLayout.discInset)
            .frame(maxWidth: .infinity, minHeight: FastCaptureLayout.barHeight, alignment: .leading)
            .background(OceanBarBackground(cornerRadius: FastCaptureLayout.endRadius))
    }
}

/// Places the bar above the tab bar on Tide. The Library's one input is its
/// search, and Ask has its own bar.
struct CaptureBarPlacement: ViewModifier {
    let show: Bool
    /// A hold that began on the bar's disc: the overlay's identical capsule
    /// is drawn in the same frame, so the bar goes invisible but keeps the
    /// finger until it lifts or locks.
    var keepsTouch = false
    let control: CaptureControl

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            CaptureBar()
                .environment(control)
                .modifier(CaptureBarColumn(control: control))
                .padding(.horizontal, OceanSpacing.gutter)
                .padding(.bottom, FastCaptureLayout.restClearance(control.tabBarEdge))
                .ignoresSafeArea(.keyboard)
                .opacity(show ? 1 : 0)
                .allowsHitTesting(show || keepsTouch)
                .animation(OceanMotion.quick, value: show)
        }
    }
}

/// How wide the capture bar, its composer and its toast stand: the page's
/// own column. On a big screen that is Tide's reading column, or Tide's
/// trailing half once it splits (the depth's, beside the hero); on a phone
/// the column is the page and nothing changes. A width rather than a
/// branch, so an open composer keeps its field, and its focus, when the
/// page turns.
///
/// It stands inside the page's gutters, so the trailing half begins half
/// the page in, past the gutter: half the width it is given plus a gutter.
struct CaptureBarColumn: ViewModifier {
    let control: CaptureControl
    /// Off for a composer in a sheet, which keeps the sheet's width.
    var applies = true
    @Environment(\.isBigScreen) private var isBigScreen
    @ScaledMetric(relativeTo: .body) private var readable = OceanSize.readableWidth
    /// The width inside the gutters, read off the full-width frame, which
    /// the inset never changes.
    @State private var width: CGFloat = 0

    private var halved: Bool { applies && control.tideSplits }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: applies && isBigScreen && !halved ? readable : .infinity)
            .padding(.leading, halved ? width / 2 + OceanSpacing.gutter : 0)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// The surface every floating bar wears: the capture bar, Ask's bar, the
/// capture toast. Dense enough to read over anything: material under a deep
/// tint, one soft shadow. A capsule, or a rounded rectangle with the same
/// end radius once a bar grows past one line.
struct OceanBarBackground: View {
    /// nil draws a capsule.
    var cornerRadius: CGFloat? = nil
    /// A toast: the deep water as a tint on the glass, so its words read
    /// at once over any page.
    var dense = false
    /// Circular by default: at half the height that is exactly the
    /// capsule, so a bar growing past one line keeps its ends. The open
    /// composer's card is continuous.
    var style: RoundedCornerStyle = .circular

    var body: some View {
        if let cornerRadius {
            surface(RoundedRectangle(cornerRadius: cornerRadius, style: style))
        } else {
            surface(Capsule())
        }
    }

    /// Liquid Glass, like the tab bar under it; the old dense material
    /// before iOS 26.
    @ViewBuilder
    private func surface<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(dense ? Glass.regular.tint(OceanTheme.toastTint) : .regular, in: shape)
        } else {
            shape
                .fill(.regularMaterial)
                .overlay(shape.fill(OceanTheme.deep.opacity(0.55)))
                .oceanShadow(OceanShadow.bar)
        }
    }
}

/// The shore under the capture bar: content dims as it runs beneath the
/// bar and the tab bar. Lives inside each tab's content so it sits under
/// the tab bar, never over it.
struct ShoreGradient: View {
    var body: some View {
        VStack {
            Spacer()
            LinearGradient(
                stops: [
                    .init(color: OceanTheme.abyss.opacity(0), location: 0),
                    .init(color: OceanTheme.abyss.opacity(0.7), location: 0.5),
                    .init(color: OceanTheme.abyss.opacity(0.92), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 200)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// While the composer is open over a page, the page's scroll view keeps an
/// empty bar of the composer's height at its bottom edge, so the system's
/// scroll edge effect softens what runs under the card instead of letting
/// it refract into the glass's rim. Closed, the bar is 0 pt: nothing moves.
struct CaptureComposerEdge: ViewModifier {
    @Environment(CaptureControl.self) private var control

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: control.composerHeight)
                    .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}
