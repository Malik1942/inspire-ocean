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
                .font(.title2.weight(.light))
        }
        .widgetURL(URL(string: "oryn://capture"))
        .containerBackground(for: .widget) { Color.clear }
    }

    /// Small — the whole widget is one capture surface.
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "drop")
                .font(.title3.weight(.light))
                .foregroundStyle(OceanTheme.foam)
            Spacer()
            Text("Catch a\nthought")
                .font(.headline.weight(.medium))
                .foregroundStyle(OceanTheme.foam)
                .lineSpacing(2)
            Spacer(minLength: 8)
            Text("Before it disappears")
                .font(.caption2)
                .foregroundStyle(OceanTheme.mist)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "oryn://capture"))
        .containerBackground(for: .widget) { OceanWidgetStyle.water }
    }

    /// Medium — Thought and Whisper side by side, resting at the waterline:
    /// header whispers at the top, open water between, actions at the bottom.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "water.waves")
                    .font(.caption2.weight(.light))
                Text("Oryn: Fast Capture")
                    .font(.caption2.weight(.medium))
                    .tracking(0.5)
            }
            .foregroundStyle(OceanTheme.mist)

            Spacer(minLength: 14)

            HStack(spacing: 8) {
                captureLink(
                    url: "oryn://capture/thought",
                    symbol: "text.cursor",
                    title: "Thought"
                )
                captureLink(
                    url: "oryn://capture/whisper",
                    symbol: "waveform",
                    title: "Whisper"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { OceanWidgetStyle.water }
    }

    /// One slim glass action — icon orb and title, centered. Depth comes from
    /// the lifted body and a soft drop, the hairline stays a whisper.
    private func captureLink(url: String, symbol: String, title: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.light))
                    .foregroundStyle(OceanTheme.foam)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OceanTheme.foam)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .shadow(color: .black.opacity(0.22), radius: 7, y: 2.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
    }
}
