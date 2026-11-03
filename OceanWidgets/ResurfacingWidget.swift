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
        /// The words under the title, as on a card: the user's own where
        /// there are some (Node.ownWords), else a summary or a link's
        /// description; empty when they would only repeat the title.
        let words: String
        /// The words are the user's, so they wear the serif; anyone else's
        /// are SF (design/identity-2.1.md, R4).
        let wordsAreOwn: Bool
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
            words: String(localized: "What if a tool made room for a thought before asking what to do with it?"),
            wordsAreOwn: true,
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
            let own = node.ownWords
            // Take only the first attachment. Reading imageDatas would load
            // every image in a ten-picture thought into the widget process.
            let image = node.orderedImages.first?.data ?? node.imageData ?? node.linkImageData
            return ResurfacingEntry(date: now, fragment: .init(
                id: node.id,
                title: title,
                words: own ?? (snippet == title ? "" : snippet),
                wordsAreOwn: own != nil,
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
            // The title keeps two lines where they fit under the label and
            // drops to one where the text size leaves room for only one.
            ViewThatFits(in: .vertical) {
                lockScreen(fragment, titleLines: 2)
                lockScreen(fragment, titleLines: 1)
            }
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .accessibilityElement(children: .combine)
        // A Home Screen slot cannot grow, so its words stop at the largest
        // standard size; typeSize is read above the cap, so the layouts
        // still make room at accessibility sizes.
        case .systemLarge:
            large(fragment)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        case .systemMedium:
            medium(fragment)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        default:
            small(fragment)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    private func lockScreen(_ fragment: ResurfacingEntry.Fragment, titleLines: Int) -> some View {
        VStack(alignment: .leading, spacing: OceanSpacing.tight) {
            Label("Resurfacing", systemImage: "arrow.up.heart")
                .oceanText(OceanType.stageLabel)
                .imageScale(.small)
                .lineLimit(1)
                .widgetAccentable()
            Text(fragment.title)
                .oceanText(OceanType.cardTitle)
                .lineLimit(titleLines)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The title takes two lines under a picture and three without; the age
    /// line goes before the title is cut.
    private func small(_ fragment: ResurfacingEntry.Fragment) -> some View {
        ViewThatFits(in: .vertical) {
            smallStack(fragment, showsAge: true)
            smallStack(fragment, showsAge: false)
        }
        .accessibilityElement(children: .combine)
    }

    private func smallStack(_ fragment: ResurfacingEntry.Fragment, showsAge: Bool) -> some View {
        let showsPicture = !typeSize.isAccessibilitySize && fragment.thumbnailData != nil
        return VStack(alignment: .leading, spacing: OceanSpacing.snug) {
            header
            if showsPicture, let data = fragment.thumbnailData {
                OceanWidgetImage(data: data)
                    .frame(maxWidth: .infinity)
                    .frame(height: OceanSize.thumbnail)
                    .clipShape(RoundedRectangle(cornerRadius: OceanRadius.thumbnail, style: .continuous))
            } else {
                Spacer(minLength: 0)
            }
            Text(fragment.title)
                .oceanText(OceanType.cardTitle)
                .foregroundStyle(OceanTheme.foam)
                .lineLimit(showsPicture ? 2 : 3)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            if showsAge {
                Label(fragment.ageDescription, systemImage: fragment.symbol)
                    .oceanText(OceanType.meta)
                    .foregroundStyle(OceanTheme.mist)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ fragment: ResurfacingEntry.Fragment) -> some View {
        VStack(alignment: .leading, spacing: OceanSpacing.gap) {
            header
            HStack(alignment: .top, spacing: OceanSpacing.item) {
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: OceanSpacing.snug) {
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

    /// The content sits right under the header row, whose 44 pt Ask target
    /// leaves the label's gap (design/tokens/README.md). The excerpt gives up
    /// its lines, then itself, before the title loses one.
    private func large(_ fragment: ResurfacingEntry.Fragment) -> some View {
        let excerptLines = typeSize.isAccessibilitySize ? 2 : (fragment.thumbnailData == nil ? 4 : 1)
        return VStack(alignment: .leading, spacing: 0) {
            readingHeader
            VStack(alignment: .leading, spacing: OceanSpacing.gap) {
                if !typeSize.isAccessibilitySize, let data = fragment.thumbnailData {
                    OceanWidgetImage(data: data)
                        .frame(maxWidth: .infinity)
                        .frame(height: OceanSize.banner)
                        .clipShape(RoundedRectangle(cornerRadius: OceanRadius.media, style: .continuous))
                }
                ViewThatFits(in: .vertical) {
                    ForEach((1...excerptLines).reversed(), id: \.self) { lines in
                        VStack(alignment: .leading, spacing: OceanSpacing.snug) {
                            title(fragment)
                            excerpt(fragment, lines: lines)
                        }
                    }
                    title(fragment)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                metadata(fragment)
                OceanWidgetActions()
                    .unredacted()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        OceanWidgetHeader(title: "Resurfacing", symbol: "arrow.up.heart")
    }

    private var readingHeader: some View {
        HStack(spacing: OceanSpacing.item) {
            // The word keeps its line; Ask gives way first.
            header
                .layoutPriority(1)
            Spacer(minLength: OceanSpacing.gap)
            // The app's quiet Link, which the widget cannot import: a way on
            // beside a section label, never louder than it.
            Link(destination: URL(string: "oryne://ask")!) {
                HStack(spacing: OceanSpacing.snug) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .accessibilityHidden(true)
                    Text("Ask")
                }
                .oceanText(OceanType.control)
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
            .oceanText(titleRole)
            .foregroundStyle(OceanTheme.foam)
            .lineLimit(family == .systemLarge ? 3 : 2)
            .minimumScaleFactor(0.9)
            .layoutPriority(1)
    }

    /// A thought's name on the stage's steps, sized by the widget: the large
    /// one at the long step, the medium a step down. The families stop at
    /// xxxLarge, so at accessibility sizes the name keeps its xxxLarge size,
    /// never smaller than at the default size.
    private var titleRole: OceanTextRole {
        family == .systemLarge ? OceanType.thoughtTitleLong : OceanType.thoughtTitleLongest
    }

    @ViewBuilder
    private func excerpt(_ fragment: ResurfacingEntry.Fragment, lines: Int) -> some View {
        if !fragment.words.isEmpty {
            Text(fragment.words)
                .oceanText(fragment.wordsAreOwn ? OceanType.cardWords : OceanType.secondary)
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
        .oceanText(OceanType.meta)
        .foregroundStyle(OceanTheme.mist)
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
                    .oceanText(OceanType.sectionLabel)
                    .widgetAccentable()
                Text(entry.isUnavailable ? "Open Oryne to reconnect" : "Nothing resurfacing yet")
                    .oceanText(OceanType.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        } else {
            // The explanation goes where it does not fit; the line stays. The
            // small widget's line stops at xLarge, where its longest word
            // still fits the narrowest small widget; the others stop with
            // the content.
            ViewThatFits(in: .vertical) {
                emptyStack(explains: true)
                emptyStack(explains: false)
            }
            .dynamicTypeSize(...(family == .systemSmall ? DynamicTypeSize.xLarge : .xxxLarge))
        }
    }

    private func emptyStack(explains: Bool) -> some View {
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
                .oceanText(OceanType.statement)
                .foregroundStyle(OceanTheme.foam)
                .lineLimit(family == .systemSmall ? 3 : 2)
                .minimumScaleFactor(0.9)
                .layoutPriority(1)
            if explains {
                Text(entry.isUnavailable
                     ? "Your thoughts will be here when your Ocean is available."
                     : "Your thoughts need a little time to drift back.")
                    .oceanText(OceanType.secondary)
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
