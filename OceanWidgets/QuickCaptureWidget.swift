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
                        .oceanText(OceanType.sectionLabel)
                        .widgetAccentable()
                    Text("Catch a thought")
                        .oceanText(OceanType.tileTitle)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            case .accessoryInline:
                Label("Catch a thought", systemImage: "drop")
            // A Home Screen slot cannot grow, so its words stop at the
            // largest standard size; typeSize is read above the cap, so the
            // tagline still steps aside at accessibility sizes.
            case .systemMedium:
                medium
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            default:
                small
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
            Text("Catch a thought")
                .oceanText(OceanType.statement)
                .foregroundStyle(OceanTheme.foam)
                .lineLimit(3)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if !typeSize.isAccessibilitySize {
                Text("Before it disappears")
                    .oceanText(OceanType.secondary)
                    .foregroundStyle(OceanTheme.text)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.inset) {
            VStack(alignment: .leading, spacing: OceanSpacing.snug) {
                Text("Catch a thought")
                    .oceanText(OceanType.statement)
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                if !typeSize.isAccessibilitySize {
                    Text("Before it disappears")
                        .oceanText(OceanType.secondary)
                        .foregroundStyle(OceanTheme.text)
                        .lineLimit(1)
                }
            }
            OceanWidgetActions()
        }
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
