import WidgetKit
import SwiftUI

/// One tap to the existing capture flow, in the app's identity (Malik,
/// 2026-11-12: the widget still wore the look from before 2.1). Both Home
/// Screen cards stand in Tide's warm Reading light, as the Resurfacing card
/// does for a thought without a picture, and name themselves in New York.
/// Medium carries the capture bar as it stands on Tide: the question opens
/// the keyboard, the ring's disc whispers. Small is one tap into the
/// preferred input, so it names that input ("Whisper a thought" or "Type a
/// thought") and shows its glyph in the same disc, top right: a small widget
/// has only the one tap, and it should say what the tap does.
struct QuickCaptureWidget: Widget {
    let kind = FastCapturePreferences.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickCaptureProvider()) { entry in
            QuickCaptureView(entry: entry)
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
    /// What one tap opens, so the small card shows the right glyph.
    var input: FastCaptureInputPreference = .voiceFirst
}

struct QuickCaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickCaptureEntry {
        QuickCaptureEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickCaptureEntry) -> Void) {
        completion(QuickCaptureEntry(date: .now, input: FastCapturePreferences.inputPreference))
    }

    /// The app reloads the widgets when the preference changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickCaptureEntry>) -> Void) {
        completion(Timeline(entries: [QuickCaptureEntry(date: .now, input: FastCapturePreferences.inputPreference)],
                            policy: .never))
    }
}

struct QuickCaptureView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuickCaptureEntry

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
            // largest standard size.
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
                OceanWidgetStyle.readingLight
            } else {
                Color.clear
            }
        }
    }

    /// The disc top right, what the tap does at the foot, bottom left: the
    /// whole card is the tap.
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                CaptureDisc(symbol: entry.input.symbol)
            }
            Spacer(minLength: OceanSpacing.gap)
            title(smallTitle)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(smallTitle)
    }

    /// The one tap's action, in the preferred input.
    private var smallTitle: LocalizedStringKey {
        entry.input == .voiceFirst ? "Whisper a thought" : "Type a thought"
    }

    /// The name top left, the capture bar at the foot.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Catch a thought")
                .lineLimit(1)
            Spacer(minLength: OceanSpacing.gap)
            CaptureBarCopy()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func title(_ words: LocalizedStringKey) -> some View {
        Text(words)
            .oceanText(OceanType.thoughtTitleLongest)
            .foregroundStyle(OceanTheme.stageInk)
            .minimumScaleFactor(0.9)
    }
}

/// The capture bar as it stands on Tide, at its own measures: a 56 pt
/// capsule, its question in mist from the end's curve, the disc inset 6 pt
/// at the trailing end. The widget cannot draw Liquid Glass, so the capsule
/// wears the content layer's raised surface. Two links: the question opens
/// the keyboard, the disc a whisper.
private struct CaptureBarCopy: View {
    private var height: CGFloat { OceanControlSize.bar }

    var body: some View {
        HStack(spacing: OceanSpacing.gap) {
            Link(destination: URL(string: "oryne://capture/thought")!) {
                Text("What are you noticing?")
                    .oceanText(OceanType.body)
                    .foregroundStyle(OceanTheme.mist)
                    .lineLimit(1)
                    .padding(.leading, height / 2 - OceanSpacing.gap)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Catch a thought")
            Link(destination: URL(string: "oryne://capture/whisper")!) {
                CaptureDisc(symbol: FastCaptureInputPreference.voiceFirst.symbol)
            }
            .accessibilityLabel("Whisper")
            .padding(.trailing, OceanControlSize.discInset)
        }
        .frame(height: height)
        .background(OceanSurface(shape: Capsule(), raised: true))
    }
}

/// The capture disc: a 44 pt circle with the ring's hairline rim, the one
/// shape Oryne owns (design/identity-2.1.md, R3), and the input's glyph.
private struct CaptureDisc: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .oceanText(OceanType.control)
            .foregroundStyle(OceanTheme.foam)
            .frame(width: OceanControlSize.height, height: OceanControlSize.height)
            .background(Circle().fill(OceanTheme.fill))
            .overlay(Circle().strokeBorder(OceanTheme.ring, lineWidth: OceanSize.ringHairline))
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}

#Preview(as: .systemSmall) {
    QuickCaptureWidget()
} timeline: {
    QuickCaptureEntry(date: .now)
    QuickCaptureEntry(date: .now, input: .typingFirst)
}

#Preview(as: .systemMedium) {
    QuickCaptureWidget()
} timeline: {
    QuickCaptureEntry(date: .now)
}
