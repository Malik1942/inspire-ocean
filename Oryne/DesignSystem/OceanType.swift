import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Type for Oryne. The roles (what a page title, a tile title, a meta line,
/// a control's words are set in) are generated into `OceanTokens.swift`
/// from `design/tokens/oryne.tokens.json`; roles are OceanTextRole values,
/// set with .oceanText, which carries a role's leading and tracking with
/// its font (OceanTextRole.swift). This file holds how a role meets the
/// navigation bar.
///
/// New York, Apple's serif, is the user's: a thought's name and their own
/// words, wherever they appear (design/identity-2.1.md, R4). The system
/// sans is Oryne's: section labels, controls, meta lines, answers, a
/// summary, a site's words. A reader can tell whose words these are without
/// reading them. Two exceptions: the names of places (a tab's or a sheet's
/// title, New York medium, so a page is named as carefully as the thought
/// on Tide; Malik, 2026-11-02) and the word Resurfacing, italic in the
/// warm ink.
enum OceanType {
    #if os(iOS)
    /// The navigation bar names its place in New York, in foam: the large
    /// title in `pageTitle` (Ask's), and the inline title in
    /// `navigationTitle` (Ask's folded on scroll, the share sheet; Settings
    /// and the memory page set theirs with `oceanInlineTitle`). The Library
    /// sets its own title where the large one stands; Tide names itself only
    /// in the tab bar.
    static func applyNavigationTitleAppearance() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [
            .font: pageTitle.uiFont(),
            .foregroundColor: UIColor(OceanTheme.foam)
        ]
        bar.titleTextAttributes = [
            .font: navigationTitle.uiFont(),
            .foregroundColor: UIColor(OceanTheme.foam)
        ]
    }
    #endif
}

#if os(iOS)
extension View {
    /// An inline title in New York for a page that hides the navigation
    /// bar's background (Settings, What Oryne knows about you). Hiding it
    /// gives the bar an appearance of SwiftUI's own, without the title font
    /// `applyNavigationTitleAppearance` sets, so the name stands in the bar's
    /// principal place instead. The bar keeps the title itself for the back
    /// button and VoiceOver.
    func oceanInlineTitle(_ title: LocalizedStringKey) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .oceanText(OceanType.navigationTitle)
                        .foregroundStyle(OceanTheme.foam)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}
#endif
