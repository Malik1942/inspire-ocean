import SwiftUI

/// Display type for the Tide page: a serif in three places only (the page
/// title, the italic section labels, the resurfacing title); the system
/// font everywhere else. `face` picks the serif; `.none` turns it off.
enum OceanType {
    enum Face { case none, instrument, newYork, baskerville }

    static let face: Face = .newYork

    static var pageTitle: Font { display(size: 40, relativeTo: .largeTitle) }
    static var sectionLabel: Font { display(size: 21, relativeTo: .title3, italic: true) }
    static var resurfacingTitle: Font { display(size: 32, relativeTo: .title) }

    private static func display(size: CGFloat, relativeTo style: Font.TextStyle, italic: Bool = false) -> Font {
        switch face {
        case .none:
            let base = Font.system(size: size, weight: style == .largeTitle ? .bold : .semibold)
            return italic ? base.italic() : base
        case .newYork:
            let base = Font.system(size: size, weight: .regular, design: .serif)
            return italic ? base.italic() : base
        case .baskerville:
            return .custom(italic ? "Baskerville-Italic" : "Baskerville", size: size, relativeTo: style)
        case .instrument:
            return .custom(italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular", size: size, relativeTo: style)
        }
    }
}
