import SwiftUI
import WidgetKit

/// Two capture actions with enough room for their symbols and words. Ask
/// belongs to the large reading widget's header, outside this capture row.
struct OceanWidgetActions: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            let width = max(0, (geometry.size.width - OceanSpacing.item) / 2)
            HStack(spacing: OceanSpacing.item) {
                action("Thought", symbol: "text.cursor", destination: "oryne://capture/thought")
                    .frame(width: width)
                action("Whisper", symbol: "waveform", destination: "oryne://capture/whisper")
                    .frame(width: width)
            }
        }
        .frame(height: OceanControlSize.height)
        // WidgetKit's fixed slot cannot grow the controls. Saved words follow
        // accessibility sizes; action labels stop at the largest standard size.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func action(_ title: LocalizedStringKey, symbol: String, destination: String) -> some View {
        Link(destination: URL(string: destination)!) {
            HStack(spacing: OceanSpacing.snug) {
                if !typeSize.isAccessibilitySize {
                    Image(systemName: symbol)
                        .font(OceanType.glyph)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(OceanType.control)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
            }
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
