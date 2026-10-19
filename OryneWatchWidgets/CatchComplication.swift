import WidgetKit
import SwiftUI

/// A static launcher (spec §1): one tap opens Oryne already listening. It
/// shows no queue status; that lives on the idle screen.
struct CatchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OryneCatch", provider: CatchProvider()) { _ in
            CatchComplicationView()
        }
        .configurationDisplayName("Catch a thought")
        .description("Opens Oryne, already listening.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular])
    }
}

struct CatchEntry: TimelineEntry {
    let date: Date
}

struct CatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> CatchEntry {
        CatchEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (CatchEntry) -> Void) {
        completion(CatchEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CatchEntry>) -> Void) {
        completion(Timeline(entries: [CatchEntry(date: .now)], policy: .never))
    }
}

struct CatchComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(WatchDeepLink.catchURL)
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                Text("Catch a thought")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryCorner:
            Image(systemName: "waveform")
                .font(.title3)
                .accessibilityLabel(Text("Catch a thought"))
                .widgetLabel { Text(verbatim: "Oryne") }
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "waveform")
                    .font(.title3)
                    .accessibilityLabel(Text("Catch a thought"))
            }
        }
    }
}
