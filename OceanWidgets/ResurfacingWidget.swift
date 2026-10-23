import WidgetKit
import SwiftUI
import SwiftData

/// Ambient rediscovery on the Home Screen (PRD §12: "ambient resurfacing";
/// §16: "build strong rediscovery loops").
///
/// Shows the fragment that is resurfacing today — the same one the Ocean Field
/// surfaces, via the shared `Resurfacing` pick. Tapping opens the app with the
/// node focused in the Ocean.
struct ResurfacingWidget: Widget {
    let kind = Resurfacing.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ResurfacingProvider()) { entry in
            ResurfacingView(entry: entry)
        }
        .configurationDisplayName("Resurfacing")
        .description("A forgotten fragment drifts back each day.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Provider

struct ResurfacingEntry: TimelineEntry {
    let date: Date
    /// nil when the Ocean is still too young to resurface anything.
    let fragment: Fragment?

    struct Fragment {
        let id: UUID
        let title: String
        let snippet: String
        let symbol: String
        let ageDescription: String
    }
}

struct ResurfacingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ResurfacingEntry {
        ResurfacingEntry(date: .now, fragment: .init(
            id: UUID(),
            title: "What would a tool feel like",
            snippet: "A tool that listens instead of asks…",
            symbol: "text.alignleft",
            ageDescription: "3 weeks ago"
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (ResurfacingEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ResurfacingEntry>) -> Void) {
        // The pick changes daily — refresh just after the next midnight.
        // Within the day, the app reloads this when Tide's pick changes.
        let nextMidnight = Calendar.current.nextDate(
            after: .now, matching: DateComponents(hour: 0, minute: 5), matchingPolicy: .nextTime
        ) ?? .now.addingTimeInterval(60 * 60 * 6)
        completion(Timeline(entries: [load()], policy: .after(nextMidnight)))
    }

    private func load() -> ResurfacingEntry {
        let context = ModelContext(Persistence.shared)
        let descriptor = FetchDescriptor<Node>(
            predicate: #Predicate<Node> { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let nodes = try? context.fetch(descriptor),
              let node = Resurfacing.pick(from: nodes)
        else {
            return ResurfacingEntry(date: .now, fragment: nil)
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full

        return ResurfacingEntry(date: .now, fragment: .init(
            id: node.id,
            title: node.displayTitle,
            snippet: node.snippet,
            symbol: node.kind.symbol,
            ageDescription: formatter.localizedString(for: node.createdAt, relativeTo: .now)
        ))
    }
}

// MARK: - Views

struct ResurfacingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ResurfacingEntry

    var body: some View {
        Group {
            if let fragment = entry.fragment {
                content(fragment)
                    .widgetURL(URL(string: "oryne://node/\(fragment.id.uuidString)"))
            } else {
                empty
                    .widgetURL(URL(string: "oryne://capture"))
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryRectangular {
                Color.clear
            } else {
                OceanWidgetStyle.water
            }
        }
    }

    @ViewBuilder
    private func content(_ fragment: ResurfacingEntry.Fragment) -> some View {
        switch family {
        case .accessoryRectangular:
            // The Lock Screen draws in its own tone; only the type is ours.
            VStack(alignment: .leading, spacing: OceanSpacing.hairline / 2) {
                HStack(spacing: OceanSpacing.tight) {
                    Image(systemName: "arrow.up.heart")
                        .font(OceanType.glyphMeta)
                    Text("Resurfacing")
                        .font(OceanType.glyphSmall)
                }
                Text(fragment.title)
                    .font(OceanType.tileTitle)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .systemMedium:
            // A medium widget reads like Tide's resurfacing: the title in New
            // York, its words under it, when it was caught.
            VStack(alignment: .leading, spacing: OceanSpacing.gap) {
                header
                Text(fragment.title)
                    .font(OceanType.subjectTitle)
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if !fragment.snippet.isEmpty {
                    Text(fragment.snippet)
                        .font(OceanType.secondary)
                        .foregroundStyle(OceanTheme.text)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text(fragment.ageDescription)
                    .font(OceanType.meta)
                    .foregroundStyle(OceanTheme.mist)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        default: // systemSmall
            VStack(alignment: .leading, spacing: OceanSpacing.snug) {
                header
                Spacer(minLength: 0)
                Text(fragment.title)
                    .font(OceanType.tileTitle)
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(3)
                Text(fragment.ageDescription)
                    .font(OceanType.meta)
                    .foregroundStyle(OceanTheme.mist)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        // Tide's warm section label, at the widget's scale: an eyebrow.
        HStack(spacing: OceanSpacing.tight) {
            Image(systemName: "arrow.up.heart")
                .font(OceanType.glyphMeta)
            Text("Resurfacing")
                .font(OceanType.eyebrow)
        }
        .foregroundStyle(OceanTheme.glowWarm)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.snug) {
            Image(systemName: "water.waves")
                .font(OceanType.glyphLarge)
                .foregroundStyle(OceanTheme.mist)
            Spacer(minLength: 0)
            Text("The Ocean is still")
                .font(OceanType.tileTitle)
                .foregroundStyle(OceanTheme.foam)
            Text("Capture a few thoughts and one will drift back.")
                .font(OceanType.meta)
                .foregroundStyle(OceanTheme.mist)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
