import SwiftUI

/// Thoughts on the depth ladder (design/identity-2.1.md): the newest just
/// under the surface, each older one a step smaller and dimmer, the way a
/// thing sinks. Titles only, in the serif, since a thought's name is the
/// user's, with a small picture at the end of any line that has one. No
/// dates: depth is the time, and the thought's page has the day.
///
/// Every line a person can tap holds 4.5:1 against the water. With Increase
/// Contrast every line is foam and depth is size alone.
///
/// When a thought drifts in, it enters at the top from just above, and every
/// older line steps one level down; the caller animates the change (Tide
/// keys it on the ids). Calm and Reduce Motion: lines take their places and
/// the new one fades in.
struct DepthList: View {
    let nodes: [Node]
    /// Where the list enters the ladder: Tide's column starts at the
    /// surface; Nearby starts two levels down, so a neighbour never
    /// outranks the thought it sits under.
    var startLevel = 0
    let open: (Node) -> Void
    /// The Library's long-press menu on each line, when the list offers it.
    var archive: ((Node) -> Void)?
    var delete: ((Node) -> Void)?

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.calmAccessibility) private var calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Level {
        let role: OceanTextRole
        let ink: Color
        /// A line's picture sinks with it.
        let picture: Double
    }

    private static var ladder: [Level] {
        [
            Level(role: OceanType.depth0, ink: OceanTheme.depthInk0, picture: 0.9), // art-directed: the picture sinks with its line
            Level(role: OceanType.depth1, ink: OceanTheme.depthInk1, picture: 0.76), // art-directed
            Level(role: OceanType.depth2, ink: OceanTheme.depthInk2, picture: 0.64), // art-directed
            Level(role: OceanType.depth3, ink: OceanTheme.depthInk3, picture: 0.56), // art-directed
            Level(role: OceanType.depth4, ink: OceanTheme.depthInk4, picture: 0.52) // art-directed
        ]
    }

    /// The type of a level on the ladder, the deepest for anything below
    /// it, so a page can measure the space a line's 44 pt row leaves
    /// (`OceanTextRole.rowSlack`) where the list starts or ends a section.
    static func role(atLevel level: Int) -> OceanTextRole {
        let ladder = Self.ladder
        return ladder[min(max(level, 0), ladder.count - 1)].role
    }

    /// How far a new line rises as it arrives: the line's own travel, so it
    /// keeps today's distance whatever the spacing tokens become.
    private static let arrivalRise: CGFloat = 16 // art-directed: a new line's rise

    var body: some View {
        let ladder = Self.ladder
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                if node.modelContext != nil {
                    line(node, at: ladder[min(startLevel + index, ladder.count - 1)])
                        .transition(arrival)
                }
            }
        }
    }

    /// A new line comes in from just above the surface; one that leaves
    /// fades. Stilled, both only fade.
    private var arrival: AnyTransition {
        if calm || reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -Self.arrivalRise)).animation(OceanMotion.gentle),
            removal: .opacity
        )
    }

    @ViewBuilder
    private func line(_ node: Node, at level: Level) -> some View {
        let button = Button { open(node) } label: {
            HStack(spacing: OceanSpacing.item) {
                // The font stays on the Text itself, at this text size, so
                // the step between levels still interpolates as a line sinks.
                // Its 8 pt floor inside the 44 pt row keeps a line that wraps
                // at accessibility sizes off its neighbour; on the words, not
                // the row, so a line's picture never makes it taller.
                Text(node.displayTitle)
                    .font(level.role.font(at: typeSize))
                    .foregroundStyle(contrast == .increased ? OceanTheme.foam : level.ink)
                    .oceanLineLimit(1)
                    .contentTransition(.interpolate)
                    .padding(.vertical, OceanSpacing.gap)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if node.hasImages || node.linkImageData != nil {
                    DepthThumb(node: node)
                        .opacity(contrast == .increased ? 1 : level.picture)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: OceanControlSize.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if archive != nil || delete != nil {
            button
                .contextMenu {
                    if let archive {
                        Button { archive(node) } label: { Label("Archive", systemImage: "archivebox") }
                    }
                    if let delete {
                        Button(role: .destructive) { delete(node) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                .accessibilityActions {
                    if let delete { Button("Delete") { delete(node) } }
                    if let archive { Button("Archive") { archive(node) } }
                }
        } else {
            button
        }
    }
}

/// A line's small picture: the thought's first picture, else its link's
/// image, read once and decoded off the main thread at the size it shows.
/// Kept by the thought and its last edit, so a list redrawn on every save,
/// or a line that comes back, shows it at once instead of decoding a
/// stored picture again. The square stands before the picture lands, so a
/// line never shifts.
private struct DepthThumb: View {
    let node: Node
    /// The thought and its last edit: an edit that changes its pictures
    /// is read afresh. Taken where the line is built, so this view never
    /// reads the thought while it draws.
    private let key: String

    @State private var picture: UIImage?

    /// The square at 3x, on the picture's short edge, so any shape fills
    /// it without upscaling.
    private static let pixels = OceanSize.depthThumb * 3
    /// A few screens of lines; each picture is small.
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 32
        return cache
    }()

    init(node: Node) {
        self.node = node
        key = "\(node.id.uuidString) \(node.updatedAt.timeIntervalSinceReferenceDate)"
    }

    var body: some View {
        Color.clear
            .frame(width: OceanSize.depthThumb, height: OceanSize.depthThumb)
            .overlay {
                if let shown = Self.cache.object(forKey: key as NSString) ?? picture {
                    Image(uiImage: shown).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: OceanRadius.thumbnail, style: .continuous))
            .task(id: key) { await load() }
    }

    /// Reads only the first picture's bytes, on the main actor where the
    /// thought lives, never the whole set.
    private func load() async {
        if let known = Self.cache.object(forKey: key as NSString) {
            picture = known
            return
        }
        guard node.modelContext != nil,
              let data = node.orderedImages.lazy.compactMap(\.data).first ?? node.imageData ?? node.linkImageData
        else { return }
        let side = Self.pixels
        let decoded = await Task.detached(priority: .utility) {
            ImageDownsampler.image(data, fillingSquare: side)
        }.value
        if let decoded { Self.cache.setObject(decoded, forKey: key as NSString) }
        guard !Task.isCancelled else { return }
        picture = decoded
    }
}
