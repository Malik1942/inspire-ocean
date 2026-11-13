import SwiftUI
import WidgetKit

/// Two capture actions, each a word with its symbol; where a narrow phone
/// leaves a capsule no room for both, the symbol steps aside so the word is
/// never cut.
struct OceanWidgetActions: View {
    var body: some View {
        GeometryReader { geometry in
            let width = max(0, (geometry.size.width - OceanSpacing.gap) / 2)
            HStack(spacing: OceanSpacing.gap) {
                action("Thought", symbol: "text.cursor", destination: "oryne://capture/thought")
                    .frame(width: width)
                action("Whisper", symbol: "waveform", destination: "oryne://capture/whisper")
                    .frame(width: width)
            }
        }
        .frame(height: OceanControlSize.height)
        // WidgetKit's fixed slot cannot grow the controls, so their labels
        // stop at the largest standard size, as the widget around them does.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func action(_ title: LocalizedStringKey, symbol: String, destination: String) -> some View {
        Link(destination: URL(string: destination)!) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: OceanSpacing.snug) {
                    Image(systemName: symbol)
                        .accessibilityHidden(true)
                    Text(title)
                        .lineLimit(1)
                }
                Text(title)
                    .lineLimit(1)
            }
            .oceanText(OceanType.control)
            .foregroundStyle(OceanTheme.foam)
            .padding(.horizontal, OceanSpacing.controlInset)
            .frame(maxWidth: .infinity)
            .frame(height: OceanControlSize.height)
            .background(OceanSurface(shape: Capsule(), raised: true))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
