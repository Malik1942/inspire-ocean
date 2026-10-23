import WidgetKit
import SwiftUI

/// Drift Capture from the Home Screen and Lock Screen (PRD §7: "widget").
///
/// - systemSmall — one tap opens Fast Capture with the user's preferred input.
/// - systemMedium — Thought (typing-first) and Whisper (voice-first) buttons.
/// - accessoryCircular — Lock Screen: one tap into Fast Capture.
struct QuickCaptureWidget: Widget {
    let kind = "com.inspireocean.app.widgets.quickcapture"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickCaptureProvider()) { _ in
            QuickCaptureView()
        }
        .configurationDisplayName("Quick Capture")
        .description("Catch a thought before it disappears.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

// MARK: - Provider (static — the widget never changes)

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

// MARK: - Views

struct QuickCaptureView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            lockScreen
        case .systemMedium:
            medium
        default:
            small
        }
    }

    /// Lock Screen circle — a single drop, one tap to capture.
    private var lockScreen: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "drop")
                .font(OceanType.glyphLarge)
        }
        .widgetURL(URL(string: "oryne://capture"))
        .containerBackground(for: .widget) { Color.clear }
    }

    /// Small — the whole widget is one capture surface.
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "drop")
                .font(OceanType.glyphLarge)
                .foregroundStyle(OceanTheme.mist)
            Spacer()
            Text("Catch a\nthought")
                .font(OceanType.tileTitle)
                .foregroundStyle(OceanTheme.foam)
                .lineSpacing(OceanSpacing.hairline)
            Spacer(minLength: OceanSpacing.gap)
            Text("Before it disappears")
                .font(OceanType.meta)
                .foregroundStyle(OceanTheme.mist)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "oryne://capture"))
        .containerBackground(for: .widget) { OceanWidgetStyle.water }
    }

    /// Medium — Thought and Whisper side by side, resting at the waterline:
    /// header whispers at the top, open water between, actions at the bottom.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The widget names what it is the way a page does: New York.
            HStack(alignment: .firstTextBaseline, spacing: OceanSpacing.gap) {
                Image(systemName: "water.waves")
                    .font(OceanType.glyphLarge)
                    .foregroundStyle(OceanTheme.mist)
                Text("Fast Capture")
                    .font(OceanType.subjectTitle)
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: OceanSpacing.inset)

            HStack(spacing: OceanSpacing.gap) {
                captureLink(
                    url: "oryne://capture/thought",
                    symbol: "text.cursor",
                    title: "Thought"
                )
                captureLink(
                    url: "oryne://capture/whisper",
                    symbol: "waveform",
                    title: "Whisper"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { OceanWidgetStyle.water }
    }

    /// One action: the app's Secondary control, a raised matte capsule with
    /// a glyph and a word, 44 pt. No gradient, no rim: the widget wears the
    /// same surfaces as the app.
    private func captureLink(url: String, symbol: String, title: LocalizedStringKey) -> some View {
        Link(destination: URL(string: url)!) {
            Label(title, systemImage: symbol)
                .font(OceanType.control)
                .foregroundStyle(OceanTheme.foam)
                .frame(maxWidth: .infinity)
                .frame(height: OceanControlSize.height)
                .background(OceanSurface(shape: Capsule(), raised: true))
        }
    }
}
