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
    let kind = "com.inspireocean.app.widgets.resurfacing"

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
                    .widgetURL(URL(string: "oryn://node/\(fragment.id.uuidString)"))
            } else {
                empty
                    .widgetURL(URL(string: "oryn://capture"))
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
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.heart")
                        .font(.caption2)
                    Text("Resurfacing")
                        .font(.caption2.weight(.semibold))
                }
                Text(fragment.title)
                    .font(.headline)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .systemMedium:
            VStack(alignment: .leading, spacing: 8) {
                header
                Text(fragment.title)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(2)
                if !fragment.snippet.isEmpty {
                    Text(fragment.snippet)
                        .font(.caption)
                        .foregroundStyle(OceanTheme.mist)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text(fragment.ageDescription)
                    .font(.caption2)
                    .foregroundStyle(OceanTheme.faint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        default: // systemSmall
            VStack(alignment: .leading, spacing: 6) {
                header
                Spacer(minLength: 0)
                Text(fragment.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(3)
                Text(fragment.ageDescription)
                    .font(.caption2)
                    .foregroundStyle(OceanTheme.faint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.up.heart")
                .font(.caption2.weight(.light))
            Text("Resurfacing")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(OceanTheme.glowWarm)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "water.waves")
                .font(.title3.weight(.light))
                .foregroundStyle(OceanTheme.mist)
            Spacer(minLength: 0)
            Text("The Ocean is still")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(OceanTheme.foam)
            Text("Capture a few thoughts and one will drift back.")
                .font(.caption2)
                .foregroundStyle(OceanTheme.mist)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
