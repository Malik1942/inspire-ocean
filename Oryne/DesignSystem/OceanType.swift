import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Type for Oryne. The roles (what a page title, a tile title, a meta line,
/// a control's words are set in) are generated into `OceanTokens.swift`
/// from `design/tokens/oryne.tokens.json`; this file holds how a role meets
/// Dynamic Type and the navigation bar.
///
/// New York, Apple's serif, names what a page is about (a tab's title, a
/// thought or a current on its own page, a question in Ask) and wears the
/// italic section labels. The system sans does everything else, on one
/// scale: tile titles, running text, meta lines, controls.
enum OceanType {
    #if os(iOS)
    /// The navigation bar's large title in `pageTitle`'s face, size and ink:
    /// every tab (Tide, Ask, the Library) names itself with the system's
    /// large title, which folds into the bar's own small title on scroll.
    static func applyLargeTitleAppearance() {
        let size = pageTitleSize
        let base = UIFont.systemFont(ofSize: size, weight: .regular)
        let serif = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: serif),
            .foregroundColor: UIColor(OceanTheme.foam)
        ]
    }
    #endif
}

/// How the generated type roles are built.
enum OceanFont {
    /// A fixed point size that still follows Dynamic Type: scaled by the
    /// metrics of the text style it stands in for, so a 40 pt serif title
    /// grows and shrinks with the system's large title. At the default
    /// content size the factor is exactly 1. Where UIKit's metrics are not
    /// available (the watch) the size stays fixed.
    static func metrics(size: CGFloat, weight: Font.Weight, design: Font.Design, italic: Bool, relativeTo style: Font.TextStyle) -> Font {
        #if os(iOS)
        let base = UIFont.systemFont(ofSize: size, weight: uiWeight(weight))
        var traits: UIFontDescriptor.SymbolicTraits = []
        if italic { traits.insert(.traitItalic) }
        var descriptor = base.fontDescriptor.withDesign(uiDesign(design)) ?? base.fontDescriptor
        if !traits.isEmpty, let italicised = descriptor.withSymbolicTraits(traits) {
            descriptor = italicised
        }
        let styled = UIFont(descriptor: descriptor, size: size)
        return Font(UIFontMetrics(forTextStyle: uiStyle(style)).scaledFont(for: styled))
        #else
        let font = Font.system(size: size, weight: weight, design: design)
        return italic ? font.italic() : font
        #endif
    }

    #if os(iOS)
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
