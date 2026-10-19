import SwiftUI
import UIKit

/// Display type: New York, Apple's serif, names what a page is about (a
/// tab's title, a thought or a current on its own page, a question in Ask)
/// and wears the italic section labels. The system sans does everything
/// else, on one scale:
///
/// - Tile title: 17 semibold (`.body.weight(.semibold)`), foam.
/// - Reading text: 17 regular foam for the main words, 15 (`.subheadline`)
///   in `OceanTheme.text` for snippets and summaries.
/// - Meta: 13 (`.footnote`), mist, one line (`NodeMeta`).
/// - Eyebrow: 13 semibold, mist, a label right above what it names.
enum OceanType {
    static var pageTitle: Font { .system(size: 40, weight: .regular, design: .serif) }
    static var sectionLabel: Font { .system(size: 21, weight: .regular, design: .serif).italic() }
    static var resurfacingTitle: Font { .system(size: 32, weight: .regular, design: .serif) }
    /// A thought's title on its page, a current's name on its sheet, the
    /// question an answer replies to.
    static var subjectTitle: Font { .system(size: 28, weight: .regular, design: .serif) }
    static var eyebrow: Font { .footnote.weight(.semibold) }

    /// The navigation bar's large title in the same face and size as
    /// `pageTitle`, so a system large title (Library, Currents) matches the
    /// custom title rows on Tide and Ask.
    static func applyLargeTitleAppearance() {
        let base = UIFont.systemFont(ofSize: 40, weight: .regular)
        let serif = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: 40) } ?? base
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: serif)
        ]
    }
}

/// One gutter and one ladder. Things that belong together sit tight; groups
/// sit far apart. The contrast between the two is the hierarchy.
enum OceanSpacing {
    /// Page margin, left and right, on every surface.
    static let gutter: CGFloat = 20
    /// A title and its meta line.
    static let tight: CGFloat = 4
    /// Items in one list.
    static let item: CGFloat = 10
    /// Blocks inside one section: a title block, a summary, a transcript.
    static let block: CGFloat = 24
    /// Between sections.
    static let section: CGFloat = 40
}

/// Three motions, used everywhere: a quick state change, the standard
/// settle (layout, folding), and the gentle arrival of something new.
enum OceanMotion {
    static let quick = Animation.easeOut(duration: 0.18)
    static let standard = Animation.smooth(duration: 0.35)
    static let gentle = Animation.timingCurve(0.3, 0, 0.2, 1, duration: 0.8)
}
