import WidgetKit
import SwiftUI

/// One tap to the existing capture flow, in the app's identity (Malik,
/// 2026-11-12: the widget still wore the look from before 2.1). Both Home
/// Screen cards stand in Tide's warm Reading light, as the Resurfacing card
/// does for a thought without a picture, with the ring's disc top right and
/// the words at the foot, bottom left, in New York. One container, the card:
/// no capsule or fill inside it (Malik, 2026-11-12: the capture bar copied
/// into the card nested three containers). Medium is the capture bar's two
/// routes: the card, which asks "What are you noticing?", opens the keyboard,
/// and the ring whispers. Small is one tap into the
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
        // Medium's card is the question, so it types; small's single tap
        // opens the preferred input.
        .widgetURL(URL(string: family == .systemMedium ? "oryne://capture/thought" : "oryne://capture"))
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

    /// The ring top right, a whisper; the question at the foot, bottom left,
    /// and with it the whole card, opens the keyboard.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Link(destination: URL(string: "oryne://capture/whisper")!) {
                    CaptureDisc(symbol: FastCaptureInputPreference.voiceFirst.symbol)
                }
                .accessibilityLabel("Whisper")
            }
            Spacer(minLength: OceanSpacing.gap)
            title("What are you noticing?")
                .lineLimit(2)
                .accessibilityLabel("Catch a thought")
                .accessibilityAddTraits(.isButton)
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

/// The capture disc: the ring's hairline rim at 44 pt, the one shape Oryne
/// owns (design/identity-2.1.md, R3), around the input's glyph. No fill: the
/// ring alone marks it on the card.
private struct CaptureDisc: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .oceanText(OceanType.control)
            .foregroundStyle(OceanTheme.foam)
            .frame(width: OceanControlSize.height, height: OceanControlSize.height)
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
