import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A text role (design/tokens/README.md): a face, a size, a weight, the
/// leading between its lines and its tracking, always set together by
/// `.oceanText(_:)` (`.oceanFieldText(_:)` in a text view), so a call site
/// can never take the font and drop the leading. The roles are generated
/// into OceanTokens.swift.
///
/// Compiled into every target that compiles OceanTokens.swift (the app, the
/// share extension, the widgets, the watch), so SwiftUI only, with UIKit
/// behind `os(iOS)`.
struct OceanTextRole: Equatable {
    enum Scale: Equatable {
        /// A system text style: the system sizes it, obeys a `dynamicTypeSize` cap,
        /// follows a live Text Size change and Bold Text.
        case native(Font.TextStyle)
        /// A size of ours, sized at each text size from `sizes` (Apple's ramp,
        /// interpolated by the generator), so it keeps its rank at every size.
        case curve
        /// Never scales.
        case fixed
    }

    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let italic: Bool
    let scale: Scale
    /// Extra points between lines at the default text size (Large), scaled
    /// in proportion to the role's size at the others.
    let leading: CGFloat
    let tracking: CGFloat
    /// The role's size at every text size, xSmall through accessibility5;
    /// nil for fixed and watch roles.
    let sizes: [CGFloat]?

    /// One line of New York or SF on iOS, as a multiple of its size
    /// (measured): the line a role's leading is added to.
    private static let naturalLine: CGFloat = 1.193

    /// The role's point size at a text size; its own size where it has no
    /// table (fixed, the watch).
    func pointSize(at typeSize: DynamicTypeSize) -> CGFloat {
        guard let sizes, let index = DynamicTypeSize.allCases.firstIndex(of: typeSize), index < sizes.count else {
            return size
        }
        return sizes[index]
    }

    /// A native role is the system's text style, so the system sizes it and
    /// a `dynamicTypeSize` cap holds; a curve or fixed role is a system font
    /// at its own size for this text size.
    func font(at typeSize: DynamicTypeSize) -> Font {
        let font: Font
        switch scale {
        case .native(let style):
            font = .system(style, design: design).weight(weight)
        case .curve, .fixed:
            font = .system(size: pointSize(at: typeSize), weight: weight, design: design)
        }
        return italic ? font.italic() : font
    }

    /// The extra leading at a text size, in proportion to the role's size so
    /// its ratio holds at every size.
    func lineSpacing(at typeSize: DynamicTypeSize) -> CGFloat {
        guard sizes != nil, size > 0 else { return leading }
        return leading * pointSize(at: typeSize) / size
    }

    /// One line of the role, without leading.
    func lineHeight(at typeSize: DynamicTypeSize) -> CGFloat {
        Self.naturalLine * pointSize(at: typeSize)
    }

    /// The height `lines` lines of the role take at a text size: each
    /// line's pitch (its line and its leading), less the leading under the
    /// last. What a box counted in lines of Text (the live words' window)
    /// is sized from; an editor's is `fieldHeight(ofLines:at:)`.
    func height(ofLines lines: Int, at typeSize: DynamicTypeSize) -> CGFloat {
        let leading = lineSpacing(at: typeSize)
        return CGFloat(lines) * (lineHeight(at: typeSize) + leading) - leading
    }

    /// The space a 44 pt row leaves above or below one line of this role.
    func rowSlack(at typeSize: DynamicTypeSize, floor: CGFloat = OceanSpacing.gap) -> CGFloat {
        max(floor, (OceanControlSize.height - lineHeight(at: typeSize)) / 2)
    }

    #if os(iOS)
    /// The role for UIKit appearances (the navigation bar's titles): a
    /// native role scaled by its text style's metrics, so it follows Dynamic
    /// Type; a curve role at the current text size; a fixed one as it is.
    func uiFont() -> UIFont {
        switch scale {
        case .native(let style):
            return UIFontMetrics(forTextStyle: Self.uiStyle(style)).scaledFont(for: baseFont(size: size))
        case .curve:
            let typeSize = DynamicTypeSize(UITraitCollection.current.preferredContentSizeCategory) ?? .large
            return baseFont(size: pointSize(at: typeSize))
        case .fixed:
            return baseFont(size: size)
        }
    }

    /// One line of the role in a UIKit text view (a vertical TextField, a
    /// TextEditor). A text view keeps the leading a system text style
    /// builds into its font, where Text drops it for the role's own: New
    /// York body at Large is a 22 pt line here and 20.3 in Text.
    func fieldLineHeight(at typeSize: DynamicTypeSize) -> CGFloat {
        let font = fieldFont(at: typeSize)
        return font.ascender - font.descender + max(0, font.leading)
    }

    /// The leading a text view needs between its lines so they land on the
    /// role's own pitch, the one Text sets: what is left of the role's
    /// leading once the style's own is counted.
    func fieldLineSpacing(at typeSize: DynamicTypeSize) -> CGFloat {
        max(0, lineHeight(at: typeSize) + lineSpacing(at: typeSize) - fieldLineHeight(at: typeSize))
    }

    /// `height(ofLines:at:)` in a text view: what an editor counted in
    /// lines is sized from, so it holds exactly that many of its lines.
    func fieldHeight(ofLines lines: Int, at typeSize: DynamicTypeSize) -> CGFloat {
        let leading = fieldLineSpacing(at: typeSize)
        return CGFloat(lines) * (fieldLineHeight(at: typeSize) + leading) - leading
    }

    /// The role's font as SwiftUI hands it to a text view. A native role
    /// is its text style's font in the role's design, which carries the
    /// style's leading (weight and slant never change its line); a curve
    /// or fixed role is a system font at its size, which carries none.
    /// Not `uiFont()`: a font scaled by UIFontMetrics has no leading.
    private func fieldFont(at typeSize: DynamicTypeSize) -> UIFont {
        guard case .native(let style) = scale else { return baseFont(size: pointSize(at: typeSize)) }
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        let styled = UIFontDescriptor.preferredFontDescriptor(withTextStyle: Self.uiStyle(style), compatibleWith: traits)
        return UIFont(descriptor: styled.withDesign(Self.uiDesign(design)) ?? styled, size: 0)
    }

    private func baseFont(size: CGFloat) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: Self.uiWeight(weight))
        var descriptor = system.fontDescriptor.withDesign(Self.uiDesign(design)) ?? system.fontDescriptor
        if italic, let slanted = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) {
            descriptor = slanted
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }

    private static func uiDesign(_ design: Font.Design) -> UIFontDescriptor.SystemDesign {
        switch design {
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        default: .default
        }
    }

    private static func uiStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
    #endif
}

/// Sets a role's font, leading and tracking, all three always: a 0 resets
/// what a parent set, so a role never inherits another's leading. The text
/// size comes from the environment, already clamped by any
/// `.dynamicTypeSize(...)` cap.
private struct OceanText: ViewModifier {
    let role: OceanTextRole
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content
            .font(role.font(at: typeSize))
            .lineSpacing(role.lineSpacing(at: typeSize))
            .tracking(role.tracking)
    }
}

#if os(iOS)
/// `OceanText` for a UIKit text view: the same font and tracking, and the
/// leading lowered by what the text style's font already carries, which a
/// text view keeps where Text replaces it. Typed lines then sit as the
/// same words will once they are Text.
private struct OceanFieldText: ViewModifier {
    let role: OceanTextRole
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content
            .font(role.font(at: typeSize))
            .lineSpacing(role.fieldLineSpacing(at: typeSize))
            .tracking(role.tracking)
    }
}
#endif

/// A line limit that opens up at accessibility sizes, where the same words
/// take more lines. nil there means no limit.
private struct OceanLineLimit: ViewModifier {
    let lines: Int
    let accessibility: Int?
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.lineLimit(typeSize.isAccessibilitySize ? accessibility : lines)
    }
}

extension View {
    /// Sets this text in a role: its font, its leading and its tracking.
    func oceanText(_ role: OceanTextRole) -> some View {
        modifier(OceanText(role: role))
    }

    #if os(iOS)
    /// Sets a text view's words in a role (a vertical TextField, a
    /// TextEditor) on the role's own line pitch. Text and one-line fields
    /// take `oceanText`.
    func oceanFieldText(_ role: OceanTextRole) -> some View {
        modifier(OceanFieldText(role: role))
    }
    #endif

    /// `lines` at standard text sizes, twice as many at accessibility sizes.
    func oceanLineLimit(_ lines: Int) -> some View {
        modifier(OceanLineLimit(lines: lines, accessibility: lines * 2))
    }

    /// `lines` at standard text sizes and `accessibility` at accessibility
    /// sizes, where nil sets no limit.
    func oceanLineLimit(_ lines: Int, accessibility: Int?) -> some View {
        modifier(OceanLineLimit(lines: lines, accessibility: accessibility))
    }
}
