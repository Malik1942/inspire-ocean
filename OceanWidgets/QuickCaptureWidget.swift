import WidgetKit
import SwiftUI

/// One tap to the existing capture flow. Medium offers typing and voice;
/// the smallest families honour the user's preferred input.
struct QuickCaptureWidget: Widget {
    let kind = "com.inspireocean.app.widgets.quickcapture"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickCaptureProvider()) { _ in
            QuickCaptureView()
        }
        .configurationDisplayName("Quick Capture")
        .description("Catch a thought or record a whisper.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

struct QuickCaptureEntry: TimelineEntry {
    let date: Date
}

struct QuickCaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickCaptureEntry {
        QuickCaptureEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickCaptureEntry) -> Void) {
        completion(QuickCaptureEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickCaptureEntry>) -> Void) {
        completion(Timeline(entries: [QuickCaptureEntry(date: .now)], policy: .never))
    }
}

struct QuickCaptureView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "drop")
                        .font(OceanType.glyphLarge)
                }
                .accessibilityLabel("Catch a thought")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: OceanSpacing.tight) {
                    Label("Oryne", systemImage: "drop")
                        .font(OceanType.eyebrow)
                        .widgetAccentable()
                    Text("Catch a thought")
                        .font(OceanType.tileTitle)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            case .accessoryInline:
                Label("Catch a thought", systemImage: "drop")
            case .systemMedium:
                medium
            default:
                small
            }
        }
        .widgetURL(URL(string: "oryne://capture"))
        .containerBackground(for: .widget) {
            if family == .systemSmall || family == .systemMedium {
                OceanWidgetStyle.water
            } else {
                Color.clear
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.gap) {
            Text("Catch a\nthought")
                .font(OceanType.subjectTitle)
                .foregroundStyle(OceanTheme.foam)
                .minimumScaleFactor(0.8)
                .lineLimit(2)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if !typeSize.isAccessibilitySize {
                Text("Before it disappears")
                    .font(OceanType.note)
                    .foregroundStyle(OceanTheme.text)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.block) {
            VStack(alignment: .leading, spacing: OceanSpacing.snug) {
                Text("Catch a thought")
                    .font(OceanType.subjectTitle)
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !typeSize.isAccessibilitySize {
                    Text("Before it disappears")
                        .font(OceanType.secondary)
                        .foregroundStyle(OceanTheme.text)
                        .lineLimit(1)
                }
            }
            OceanWidgetActions()
        }
        .padding(.horizontal, OceanSpacing.tight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#Preview(as: .systemSmall) {
    QuickCaptureWidget()
} timeline: {
    QuickCaptureEntry(date: .now)
}

#Preview(as: .systemMedium) {
    QuickCaptureWidget()
} timeline: {
    QuickCaptureEntry(date: .now)
}
