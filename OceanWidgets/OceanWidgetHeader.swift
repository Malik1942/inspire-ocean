import SwiftUI
import WidgetKit

/// The Resurfacing widget's header: the word Resurfacing in the stage's own
/// label, italic New York in the warm ink, as it stands above today's
/// thought on Tide. Its glyph sits in the same line a step smaller, in mist:
/// warm sets only the word, never a glyph.
///
/// The word is never cut: the glyph steps aside where the line cannot hold
/// both, and the size stops at xxLarge, where the word alone still fits the
/// narrowest small widget.
struct OceanWidgetHeader: View {
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        let word = Text(title).foregroundStyle(OceanTheme.warm)
        ViewThatFits(in: .horizontal) {
            Label {
                word
            } icon: {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .foregroundStyle(OceanTheme.mist)
            }
            word
        }
        .oceanText(OceanType.stageLabel)
        .lineLimit(1)
        // Outside the role, so the role reads the capped size.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .widgetAccentable()
        .accessibilityAddTraits(.isHeader)
    }
}
