import SwiftUI

/// Display type for the Tide page. The brand's serif (Instrument Serif,
/// OFL, the website's display face) is used in three places only: the page
/// title, the section labels (italic), and the resurfacing title. Everything
/// else is the system font. `useSerif` switches the whole treatment off.
enum OceanType {
    static let useSerif = true

    private static let serif = "InstrumentSerif-Regular"
    private static let serifItalic = "InstrumentSerif-Italic"

    /// The page title ("Tide").
    static var pageTitle: Font {
        useSerif ? .custom(serif, size: 40, relativeTo: .largeTitle) : .largeTitle.bold()
    }

    /// Section labels: a quiet italic line.
    static var sectionLabel: Font {
        useSerif ? .custom(serifItalic, size: 21, relativeTo: .title3) : .subheadline.weight(.semibold)
    }

    /// The resurfacing thought's title, the one lit thing.
    static var resurfacingTitle: Font {
        useSerif ? .custom(serif, size: 32, relativeTo: .title) : .title2.weight(.semibold)
    }
}
