import SwiftUI

extension EnvironmentValues {
    /// A big screen: regular width and regular height, as on iPad and on
    /// iPhone Duo's inner display, never a phone in either orientation (a
    /// Plus or Max phone on its side is regular wide but compact high).
    /// Pages use the room there (Tide's two halves, more Library columns,
    /// bars on the reading column); everywhere else they keep the phone's
    /// layout.
    var isBigScreen: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
}

/// How a page stands on a big screen (`isBigScreen`): whether it splits into
/// two halves, and which half something opened stands in.
///
/// The halves are the page's own width cut in two, even: the page already
/// stops at the tab bar's column where it stands upright beside it (iPhone
/// Duo), so the column stands aside and the rest is half and half (Malik,
/// 2026-11-10). On iPhone Duo that puts the line between them a little short
/// of the fold, by half the column's width.
@MainActor
enum BigScreen {
    /// The narrowest a half stands: about a phone's column (370 pt on a
    /// 402 pt phone).
    static let columnLeast: CGFloat = 360

    /// Whether a page this size stands in two halves: turned wider than
    /// tall, with room for two columns a phone wide. Upright it keeps one
    /// column: the vertical axis is the page's bone.
    static func splits(_ size: CGSize) -> Bool {
        size.width > size.height
            && size.width >= 2 * (columnLeast + OceanSpacing.gutter) + OceanSpacing.section
    }

    /// Whether the screen folds down the page, as iPhone Duo's inner display
    /// does: its halves read as two screens, so what is opened stands in one
    /// of them instead of a sheet over both. Read while the screen lies flat
    /// too, so the page stays put as it opens and closes.
    nonisolated static func folds(in proxy: GeometryProxy) -> Bool {
        guard #available(iOS 27.1, *) else { return false }
        return proxy.reservedRegions(kind: .division, options: .includeInactive)
            .contains { $0.frame.height > $0.frame.width }
    }

    /// The half of a split page that something opened stands in, the page's
    /// edge to its middle: one half shows what was opened, the other where
    /// it was opened from.
    enum Side {
        case leading, trailing
    }
}
