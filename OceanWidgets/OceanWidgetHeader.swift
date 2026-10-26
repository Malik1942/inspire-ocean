import SwiftUI
import WidgetKit

struct OceanWidgetHeader: View {
    let title: LocalizedStringKey
    let symbol: String
    var warm = false

    var body: some View {
        Label {
            Text(title)
                .font(OceanType.sectionLabel)
        } icon: {
            Image(systemName: symbol)
                .font(OceanType.glyphMeta)
        }
            .foregroundStyle(warm ? OceanTheme.glowWarm : OceanTheme.mist)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .widgetAccentable()
            .accessibilityAddTraits(.isHeader)
    }
}
