import WidgetKit
import SwiftUI
import SwiftData

/// The same held daily thought as Tide, with its words and saved media.
/// Existing kind and node links preserve widgets already on the Home Screen.
struct ResurfacingWidget: Widget {
    let kind = Resurfacing.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ResurfacingProvider()) { entry in
            ResurfacingView(entry: entry)
        }
        .configurationDisplayName("Resurfacing")
        .description("A thought drifts back, with the words and pictures you saved.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct ResurfacingEntry: TimelineEntry {
    let date: Date
    let fragment: Fragment?
    var isUnavailable = false

    /// A value snapshot: views never reach back into SwiftData or decode an
    /// original image. The provider bounds the image before making the entry.
    struct Fragment {
        let id: UUID
        let title: String
        let snippet: String
        let symbol: String
        let kindLabel: String
        let ageDescription: String
        var sourceDomain: String?
        var thumbnailData: Data?
    }

    static var preview: Self {
        Self(date: .now, fragment: .init(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: String(localized: "A tool that listens"),
            snippet: String(localized: "What if a tool made room for a thought before asking what to do with it?"),
            symbol: "text.alignleft",
            kindLabel: NodeKind.text.label,
            ageDescription: String(localized: "3 weeks ago")
        ))
    }
}

struct ResurfacingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ResurfacingEntry {
        .preview
    }

    func getSnapshot(in context: Context, completion: @escaping (ResurfacingEntry) -> Void) {
        completion(context.isPreview ? .preview : load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ResurfacingEntry>) -> Void) {
        let entry = load()
        let nextMidnight = Calendar.current.nextDate(
            after: .now, matching: DateComponents(hour: 0, minute: 5), matchingPolicy: .nextTime
        ) ?? .now.addingTimeInterval(60 * 60 * 6)
        // A temporarily unreadable store should recover during the day too.
        let nextRefresh = entry.isUnavailable ? entry.date.addingTimeInterval(60 * 30) : nextMidnight
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func load() -> ResurfacingEntry {
        let now = Date.now
        let context = ModelContext(Persistence.shared)
        let descriptor = FetchDescriptor<Node>(
            predicate: #Predicate<Node> { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        do {
            let nodes = try context.fetch(descriptor)
            guard let node = Resurfacing.pick(from: nodes, now: now) else {
                return ResurfacingEntry(date: now, fragment: nil)
            }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let title = node.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = node.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            // Take only the first attachment. Reading imageDatas would load
            // every image in a ten-picture thought into the widget process.
            let image = node.orderedImages.first?.data ?? node.imageData ?? node.linkImageData
            return ResurfacingEntry(date: now, fragment: .init(
                id: node.id,
                title: title,
                snippet: snippet == title ? "" : snippet,
                symbol: node.kind.symbol,
                kindLabel: node.kind.label,
                ageDescription: formatter.localizedString(for: node.createdAt, relativeTo: now),
                sourceDomain: node.linkDomain,
                thumbnailData: OceanWidgetStyle.thumbnail(image)
            ))
        } catch {
            return ResurfacingEntry(date: now, fragment: nil, isUnavailable: true)
        }
    }
}

struct ResurfacingView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var typeSize
    let entry: ResurfacingEntry

    var body: some View {
        Group {
            if let fragment = entry.fragment {
                content(fragment)
                    .privacySensitive()
                    .widgetURL(URL(string: "oryne://node/\(fragment.id.uuidString)"))
            } else {
                empty
                    .widgetURL(URL(string: entry.isUnavailable ? "oryne://" : "oryne://capture"))
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
            VStack(alignment: .leading, spacing: OceanSpacing.tight) {
                Label("Resurfacing", systemImage: "arrow.up.heart")
                    .font(OceanType.eyebrow)
                    .lineLimit(1)
                    .widgetAccentable()
                Text(fragment.title)
                    .font(OceanType.tileTitle)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityElement(children: .combine)
        case .systemLarge:
            large(fragment)
        case .systemMedium:
            medium(fragment)
        default:
            small(fragment)
        }
    }

    private func small(_ fragment: ResurfacingEntry.Fragment) -> some View {
        VStack(alignment: .leading, spacing: OceanSpacing.tight) {
            header
            if !typeSize.isAccessibilitySize, let data = fragment.thumbnailData {
                OceanWidgetImage(data: data)
                    .frame(maxWidth: .infinity)
                    .frame(height: OceanSize.thumbnail)
                    .clipShape(RoundedRectangle(cornerRadius: OceanRadius.thumbnail, style: .continuous))
            }
            if fragment.thumbnailData == nil || typeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
            Text(fragment.title)
                .font(OceanType.tileTitle)
                .foregroundStyle(OceanTheme.foam)
                .lineLimit(fragment.thumbnailData == nil || typeSize.isAccessibilitySize ? 3 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            if !typeSize.isAccessibilitySize {
                Label(fragment.ageDescription, systemImage: fragment.symbol)
                    .font(OceanType.note)
                    .foregroundStyle(OceanTheme.text)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func medium(_ fragment: ResurfacingEntry.Fragment) -> some View {
        VStack(alignment: .leading, spacing: OceanSpacing.gap) {
            header
            HStack(alignment: .top, spacing: OceanSpacing.item) {
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: OceanSpacing.tight) {
                        title(fragment)
                        if !typeSize.isAccessibilitySize {
                            excerpt(fragment, lines: 1)
                        }
                    }
                    title(fragment)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize, let data = fragment.thumbnailData {
                    thumbnail(data, side: OceanSize.pictureTile)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            metadata(fragment)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func large(_ fragment: ResurfacingEntry.Fragment) -> some View {
        VStack(alignment: .leading, spacing: OceanSpacing.gap) {
            readingHeader
            if !typeSize.isAccessibilitySize, let data = fragment.thumbnailData {
                OceanWidgetImage(data: data)
                    .frame(maxWidth: .infinity)
                    .frame(height: OceanSize.banner)
                    .clipShape(RoundedRectangle(cornerRadius: OceanRadius.media, style: .continuous))
            }
            title(fragment)
            excerpt(fragment, lines: typeSize.isAccessibilitySize ? 2 : (fragment.thumbnailData == nil ? 4 : 1))
            Spacer(minLength: 0)
            metadata(fragment)
            OceanWidgetActions()
                .unredacted()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        OceanWidgetHeader(title: "Resurfacing", symbol: "arrow.up.heart", warm: true)
    }

    private var readingHeader: some View {
        HStack(spacing: OceanSpacing.item) {
            header
            Spacer(minLength: OceanSpacing.gap)
            // The app's quiet Link, which the widget cannot import: a way on
            // beside a section label, never louder than it.
            Link(destination: URL(string: "oryne://ask")!) {
                HStack(spacing: OceanSpacing.snug) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .accessibilityHidden(true)
                    Text("Ask")
                }
                .font(OceanType.control)
                .foregroundStyle(OceanTheme.mist)
                .frame(minWidth: OceanControlSize.height, minHeight: OceanControlSize.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .unredacted()
        }
    }

    private func title(_ fragment: ResurfacingEntry.Fragment) -> some View {
        Text(fragment.title)
            .font(typeSize.isAccessibilitySize && family == .systemMedium ? OceanType.tileTitle : OceanType.subjectTitle)
            .foregroundStyle(OceanTheme.foam)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .layoutPriority(1)
    }

    @ViewBuilder
    private func excerpt(_ fragment: ResurfacingEntry.Fragment, lines: Int) -> some View {
        if !fragment.snippet.isEmpty {
            Text(fragment.snippet)
                .font(OceanType.secondary)
                .foregroundStyle(OceanTheme.text)
                .lineLimit(lines)
        }
    }

    private func metadata(_ fragment: ResurfacingEntry.Fragment) -> some View {
        HStack(spacing: OceanSpacing.gap) {
            Label(fragment.sourceDomain ?? fragment.kindLabel, systemImage: fragment.symbol)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(fragment.ageDescription)
        }
        .font(OceanType.note)
        .foregroundStyle(OceanTheme.text)
        .lineLimit(1)
    }

    private func thumbnail(_ data: Data, side: CGFloat) -> some View {
        OceanWidgetImage(data: data)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: OceanRadius.thumbnail, style: .continuous))
    }

    @ViewBuilder
    private var empty: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: OceanSpacing.tight) {
                Label("Oryne", systemImage: "water.waves")
                    .font(OceanType.eyebrow)
                    .widgetAccentable()
                Text(entry.isUnavailable ? "Open Oryne to reconnect" : "Nothing resurfacing yet")
                    .font(OceanType.note)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        } else {
            VStack(alignment: .leading, spacing: OceanSpacing.gap) {
                if !typeSize.isAccessibilitySize || family != .systemMedium {
                    if family == .systemLarge {
                        readingHeader
                    } else {
                        header
                    }
                }
                Spacer(minLength: 0)
                Text(entry.isUnavailable ? "Open Oryne to reconnect" : "Nothing resurfacing yet")
                    .font(family == .systemSmall || (typeSize.isAccessibilitySize && family == .systemMedium)
                          ? OceanType.tileTitle : OceanType.subjectTitle)
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(typeSize.isAccessibilitySize && family == .systemSmall ? 3 : 2)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
                if !typeSize.isAccessibilitySize || family == .systemLarge {
                    Text(entry.isUnavailable
                         ? "Your thoughts will be here when your Ocean is available."
                         : "Your thoughts need a little time to drift back.")
                        .font(OceanType.note)
                        .foregroundStyle(OceanTheme.text)
                        .lineLimit(family == .systemSmall ? 3 : 2)
                }
                if family != .systemSmall {
                    Spacer(minLength: 0)
                    OceanWidgetActions()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

#Preview(as: .systemSmall) {
    ResurfacingWidget()
} timeline: {
    ResurfacingEntry.preview
    ResurfacingEntry(date: .now, fragment: nil)
}

#Preview(as: .systemMedium) {
    ResurfacingWidget()
} timeline: {
    ResurfacingEntry.preview
    ResurfacingEntry(date: .now, fragment: nil, isUnavailable: true)
}

#Preview(as: .systemLarge) {
    ResurfacingWidget()
} timeline: {
    ResurfacingEntry.preview
}
