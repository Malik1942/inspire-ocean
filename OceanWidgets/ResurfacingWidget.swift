import WidgetKit
import SwiftUI
import SwiftData

/// The same held daily thought as Tide, as one card: its picture fills the
/// card edge to edge, or, for a thought without one, Tide's warm Reading
/// light does; a small Resurfacing label sits top left, and the title and one
/// line of its words stand at the card's foot, bottom left (Malik, 2026-11-12:
/// the earlier header, picture tile, meta row and buttons were too dense, and
/// the large size too big, so it is gone).
/// Designed as the medium (4x2) card; the small slot wears the same card.
/// Existing kind and node links preserve widgets already on the Home Screen.
struct ResurfacingWidget: Widget {
    let kind = Resurfacing.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ResurfacingProvider()) { entry in
            ResurfacingView(entry: entry)
        }
        .configurationDisplayName("Resurfacing")
        .description("A thought drifts back, with the words and pictures you saved.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        // The picture reaches the card's edges; the words keep the margins.
        .contentMarginsDisabled()
    }
}

struct ResurfacingEntry: TimelineEntry {
    let date: Date
    let fragment: Fragment?
    var isUnavailable = false

    /// A value snapshot: views never reach back into SwiftData or decode an
    /// original image. The provider crops the picture to the card first.
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
        /// The thought's first picture (or link image), cropped to this card.
        var picture: WidgetPicture.Card?
    }

    static var preview: Self {
        Self(date: .now, fragment: .init(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: String(localized: "A tool that listens"),
            words: String(localized: "What if a tool made room for a thought before asking what to do with it?"),
            wordsAreOwn: true
        ))
    }
}

struct ResurfacingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ResurfacingEntry {
        .preview
    }

    func getSnapshot(in context: Context, completion: @escaping (ResurfacingEntry) -> Void) {
        completion(context.isPreview ? .preview : load(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ResurfacingEntry>) -> Void) {
        let entry = load(in: context)
        let nextMidnight = Calendar.current.nextDate(
            after: .now, matching: DateComponents(hour: 0, minute: 5), matchingPolicy: .nextTime
        ) ?? .now.addingTimeInterval(60 * 60 * 6)
        // A temporarily unreadable store should recover during the day too.
        let nextRefresh = entry.isUnavailable ? entry.date.addingTimeInterval(60 * 30) : nextMidnight
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func load(in context: Context) -> ResurfacingEntry {
        let now = Date.now
        let store = ModelContext(Persistence.shared)
        let descriptor = FetchDescriptor<Node>(
            predicate: #Predicate<Node> { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        do {
            let nodes = try store.fetch(descriptor)
            guard let node = Resurfacing.pick(from: nodes, now: now) else {
                return ResurfacingEntry(date: now, fragment: nil)
            }
            let title = node.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = node.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            let own = node.ownWords
            // Take only the first attachment. Reading imageDatas would load
            // every image in a ten-picture thought into the widget process.
            let image = node.orderedImages.first?.data ?? node.imageData ?? node.linkImageData
            // The Lock Screen card shows words only.
            let picture = context.family == .accessoryRectangular ? nil : image.flatMap {
                WidgetPicture.card(from: $0, pixelSize: Self.pixelSize(of: context.displaySize))
            }
            return ResurfacingEntry(date: now, fragment: .init(
                id: node.id,
                title: title,
                words: own ?? (snippet == title ? "" : snippet),
                wordsAreOwn: own != nil,
                picture: picture
            ))
        } catch {
            return ResurfacingEntry(date: now, fragment: nil, isUnavailable: true)
        }
    }

    /// The card in pixels at the screen's scale: as sharp as the card can
    /// show and no larger, since WidgetKit refuses to archive an image much
    /// larger than its widget.
    private static func pixelSize(of points: CGSize) -> CGSize {
        let scale = max(2, UITraitCollection.current.displayScale)
        return CGSize(width: points.width * scale, height: points.height * scale)
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
            } else if let picture = entry.fragment?.picture {
                PictureBackground(picture: picture)
            } else {
                OceanWidgetStyle.readingLight
            }
        }
    }

    @ViewBuilder
    private func content(_ fragment: ResurfacingEntry.Fragment) -> some View {
        if family == .accessoryRectangular {
            // The title keeps two lines where they fit under the label and
            // drops to one where the text size leaves room for only one.
            ViewThatFits(in: .vertical) {
                lockScreen(fragment, titleLines: 2)
                lockScreen(fragment, titleLines: 1)
            }
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .accessibilityElement(children: .combine)
        } else {
            // A Home Screen slot cannot grow, so its words stop at the largest
            // standard size; typeSize is read above the cap, so the card
            // still makes room at accessibility sizes.
            VStack(alignment: .leading, spacing: 0) {
                label
                Spacer(minLength: OceanSpacing.gap)
                foot(title: fragment.title, words: fragment.words, wordsAreOwn: fragment.wordsAreOwn,
                     onPicture: fragment.picture != nil)
            }
            .padding(OceanSpacing.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityElement(children: .combine)
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

    /// The word Resurfacing, small, in the stage label's italic serif, laid
    /// over the card with an overlay blend, so it reads as a translucent mark
    /// of the picture's or the light's own color rather than ink on top
    /// (Malik, 2026-11-12). Kept to the small text sizes, a quiet mark beside
    /// the title.
    private var label: some View {
        Text("Resurfacing")
            .oceanText(OceanType.stageLabel)
            .foregroundStyle(OceanTheme.stageInk)
            .blendMode(.overlay) // art-directed: the translucent mark
            .lineLimit(1)
            // Outside the role, so the role reads the capped size.
            .dynamicTypeSize(...DynamicTypeSize.small)
            .widgetAccentable()
            .accessibilityAddTraits(.isHeader)
    }

    /// The card's words at its foot: the title, and under it one line of the
    /// thought's words. The words give way before the title loses a line.
    private func foot(title: String, words: String, wordsAreOwn: Bool, onPicture: Bool) -> some View {
        ViewThatFits(in: .vertical) {
            if !typeSize.isAccessibilitySize {
                stack(title: title, words: words, wordsAreOwn: wordsAreOwn)
            }
            stack(title: title, words: "", wordsAreOwn: wordsAreOwn)
        }
        .oceanShadow(OceanShadow.text, enabled: onPicture)
    }

    private func stack(title: String, words: String, wordsAreOwn: Bool) -> some View {
        VStack(alignment: .leading, spacing: OceanSpacing.tight) {
            Text(title)
                .oceanText(titleRole)
                .foregroundStyle(OceanTheme.stageInk)
                .lineLimit(titleLines)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
            if !words.isEmpty {
                Text(words)
                    .oceanText(wordsAreOwn ? OceanType.cardWords : OceanType.secondary)
                    .foregroundStyle(OceanTheme.stageWords)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A thought's name at the stage's smallest step on the medium card;
    /// the small card takes a card's title.
    private var titleRole: OceanTextRole {
        family == .systemMedium ? OceanType.thoughtTitleLongest : OceanType.cardTitle
    }

    private var titleLines: Int {
        family == .systemSmall ? 3 : 2
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
            // small card's line stops at xLarge, where its longest word still
            // fits the narrowest small widget.
            ViewThatFits(in: .vertical) {
                emptyStack(explains: true)
                emptyStack(explains: false)
            }
            .padding(OceanSpacing.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .dynamicTypeSize(...(family == .systemSmall ? DynamicTypeSize.xLarge : .xxxLarge))
        }
    }

    private func emptyStack(explains: Bool) -> some View {
        VStack(alignment: .leading, spacing: OceanSpacing.tight) {
            Text(entry.isUnavailable ? "Open Oryne to reconnect" : "Nothing resurfacing yet")
                .oceanText(OceanType.statement)
                .foregroundStyle(OceanTheme.stageInk)
                .lineLimit(family == .systemSmall ? 3 : 2)
                .minimumScaleFactor(0.9)
            if explains {
                Text(entry.isUnavailable
                     ? "Your thoughts will be here when your Ocean is available."
                     : "Your thoughts need a little time to drift back.")
                    .oceanText(OceanType.secondary)
                    .foregroundStyle(OceanTheme.stageWords)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The thought's picture filling the card, as the stage on Tide: sharp at the
/// top and dissolving into a darkened blur of itself at its foot, where the
/// words stand; on a light picture the water rises behind the words, only as
/// much as the picture's light needs (`WidgetPicture.scrimStrength`).
private struct PictureBackground: View {
    let picture: WidgetPicture.Card

    var body: some View {
        ZStack {
            OceanWidgetImage(data: picture.data)
                .blur(radius: 14, opaque: true) // art-directed: the card's blurred foot
                .colorMultiply(Color(white: 0.64)) // art-directed: darkened under the words, as on the stage
            OceanWidgetImage(data: picture.data)
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0.42), .init(color: .clear, location: 0.92)], // art-directed: the dissolve
                                   startPoint: .top, endPoint: .bottom)
                }
            if picture.scrimStrength > 0 {
                LinearGradient(stops: Self.scrim(strength: picture.scrimStrength), startPoint: .top, endPoint: .bottom)
            }
        }
    }

    /// The water rising from the card's top, eased, to its full strength where
    /// the words' ground begins, then holding to the foot: the stage's
    /// caption scrim, so the picture keeps its light above the words.
    private static func scrim(strength: CGFloat) -> [Gradient.Stop] {
        let full = 1 - WidgetPicture.ground
        let steps = 8
        let rise = (0...steps).map { step -> Gradient.Stop in
            let t = CGFloat(step) / CGFloat(steps)
            let eased = pow(t * t * (3 - 2 * t), 1.6) // art-directed: the scrim's rise, as on the stage
            return .init(color: OceanTheme.abyss.opacity(strength * eased), location: full * t)
        }
        return rise + [.init(color: OceanTheme.abyss.opacity(strength), location: 1)]
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
