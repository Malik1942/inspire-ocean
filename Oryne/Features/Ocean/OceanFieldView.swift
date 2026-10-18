import SwiftUI
import SwiftData

/// The Ocean on the phone: a surface, not a map
/// (docs/plans/phone-refocus/SPEC.md, decision 5).
///
/// People glance at a phone; they do not explore it. So the Ocean reads top
/// to bottom in one look, every title legible on the water itself:
///  1. **Today's resurfacing**: the one lit object, a large glass orb with
///     its title, when it was caught, and a small "Resurfacing" label.
///  2. **Newest**: the five most recent thoughts as smaller orbs drifting
///     near the surface, each titled beneath, in a stable arrangement.
///  3. **Currents**: a row of readable chips; each opens the current's
///     stream.
///
/// No pan, no zoom, no counts (§8). The orbs breathe and drift a few points
/// over tens of seconds; the titles never move, and motion carries nothing
/// a label doesn't (§4). Reduce Motion and Calm Accessibility Mode still it
/// completely.
struct OceanFieldView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.calmAccessibility) private var calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Node> { !$0.isArchived }, sort: \Node.createdAt)
    private var nodes: [Node]

    @State private var sheet: OceanSheet?
    @State private var showSettings = false

    /// How many of the newest thoughts float near the surface.
    private static let newestLimit = 5
    /// How many currents get a chip.
    private static let currentLimit = 8
    /// Clear water under the content, so the capture bar that sits above the
    /// tab bar never covers a title.
    private static let captureBarClearance: CGFloat = 96

    private var nodeByID: [UUID: Node] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    }

    private enum OceanSheet: Identifiable {
        case thought(Node)
        case stream(theme: String)

        var id: String {
            switch self {
            case .thought(let node): return node.id.uuidString
            case .stream(let theme): return "stream·\(theme)"
            }
        }
    }

    /// Ambient motion's one off-switch (§4).
    private var still: Bool { reduceMotion || calm }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                OceanBackground()
                oceanFog

                if nodes.isEmpty {
                    VStack(spacing: 0) {
                        header
                        Spacer()
                        emptyState
                        Spacer()
                        Spacer().frame(height: Self.captureBarClearance)
                    }
                } else {
                    surface
                }
            }
            .onAppear { consumePendingFocus() }
            .onChange(of: appState.pendingFocusNodeID) { _, _ in consumePendingFocus() }
            .navigationBarHidden(true)
            .sheet(item: $sheet) { item in
                switch item {
                case .thought(let node):
                    ExpandedNodeView(node: node)
                case .stream(let theme):
                    ClusterStreamView(theme: theme)
                }
            }
            .sheet(isPresented: $showSettings) {
                OceanSettingsView()
            }
            // Reported so the root view can hold back anything (the review
            // ask) that must never appear over a sheet.
            .onChange(of: sheet?.id) { _, _ in updateOceanSheetPresence() }
            .onChange(of: showSettings) { _, _ in updateOceanSheetPresence() }
        }
    }

    // MARK: Surface

    private var surface: some View {
        // A just-deleted node can linger for one render pass; reading any
        // attribute on a detached object faults, so only attached ones render.
        let live = nodes.filter { $0.modelContext != nil }
        let lit = Resurfacing.pick(from: live)
        let newest = newestThoughts(in: live, excluding: lit?.id)
        let currents = currentKeys(in: live)

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 18)

                if let lit {
                    resurfacingRow(lit)
                        .padding(.horizontal)
                        .padding(.bottom, 34)
                }

                if !newest.isEmpty {
                    sectionLabel("Newest")
                        .padding(.horizontal)
                        .padding(.bottom, 14)
                    DriftLayout(count: newest.count) {
                        ForEach(Array(newest.enumerated()), id: \.element.id) { index, node in
                            newestItem(node, rank: index)
                                .layoutValue(key: DriftSeed.self, value: NodeComposer.stableHash(node.id.uuidString))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }

                if !currents.isEmpty {
                    sectionLabel("Currents")
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                    currentChips(currents)
                }
            }
            .padding(.bottom, Self.captureBarClearance)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }

    /// The newest thoughts near the surface: the user's own captures, newest
    /// first, minus today's resurfacing (it already has the lit place). A
    /// brand-new Ocean that holds only the starter examples shows those, so
    /// the first look is never bare water.
    private func newestThoughts(in live: [Node], excluding litID: UUID?) -> [Node] {
        let candidates = live.filter { $0.id != litID }
        let own = candidates.filter { !$0.isExample }
        let pool = own.isEmpty ? candidates : own
        return Array(pool.sorted { $0.createdAt > $1.createdAt }.prefix(Self.newestLimit))
    }

    /// One chip per current, the most recently fed current first. Thoughts
    /// with no current are not a chip.
    private func currentKeys(in live: [Node]) -> [String] {
        var newestByKey: [String: Date] = [:]
        for node in live {
            guard let key = OceanLayoutEngine.currentKey(for: node) else { continue }
            if let seen = newestByKey[key], seen >= node.createdAt { continue }
            newestByKey[key] = node.createdAt
        }
        return newestByKey
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(Self.currentLimit)
            .map(\.key)
    }

    // MARK: Resurfacing

    private func resurfacingRow(_ node: Node) -> some View {
        Button {
            open(node)
        } label: {
            HStack(alignment: .center, spacing: 20) {
                DriftingOrb(
                    diameter: 132,
                    tint: OceanTheme.glowWarm,
                    lit: true,
                    symbol: glyph(for: node),
                    seed: NodeComposer.stableHash(node.id.uuidString),
                    still: still
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text("Resurfacing")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(OceanTheme.glowWarm)
                    Text(node.displayTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(OceanTheme.foam)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(node.createdAt.formatted(.relative(presentation: .named)))
                        .font(.footnote)
                        .foregroundStyle(calm ? OceanTheme.foam : OceanTheme.mist)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SurfacePressStyle(still: still))
        .accessibilityElement(children: .combine)
    }

    // MARK: Newest

    private func newestItem(_ node: Node, rank: Int) -> some View {
        Button {
            open(node)
        } label: {
            VStack(spacing: 9) {
                DriftingOrb(
                    // Size eases down with age: 72 for the newest, 56 by the fifth.
                    diameter: 72 - CGFloat(rank) * 4,
                    tint: OceanTheme.color(forHue: node.hue, brightness: 0.86),
                    lit: false,
                    symbol: glyph(for: node),
                    seed: NodeComposer.stableHash(node.id.uuidString),
                    still: still
                )
                Text(node.displayTitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(OceanTheme.foam)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SurfacePressStyle(still: still))
        .accessibilityElement(children: .combine)
        .accessibilityValue(node.kind == .text ? Text(verbatim: "") : Text(node.kind.label))
    }

    /// A voice, image, or link thought shows what it is; a plain thought
    /// needs no glyph.
    private func glyph(for node: Node) -> String? {
        node.kind == .text ? nil : node.kind.symbol
    }

    // MARK: Currents

    private func currentChips(_ keys: [String]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(keys, id: \.self) { key in
                    Button {
                        sheet = .stream(theme: key)
                    } label: {
                        Text(OceanLayoutEngine.displayLabel(for: key))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(OceanTheme.foam)
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 5)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(SurfacePressStyle(still: still))
                }
            }
            .padding(.vertical, 6)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(calm ? OceanTheme.foam : OceanTheme.mist)
            .accessibilityAddTraits(.isHeader)
    }

    /// Depth fog: faint brightening near the surface, darkening toward the
    /// abyss. Static on purpose; the water's own life is the background's.
    private var oceanFog: some View {
        LinearGradient(
            colors: [
                OceanTheme.surface.opacity(0.05),
                .clear,
                OceanTheme.abyss.opacity(0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    // MARK: Interaction

    /// Opens a thought; meeting today's resurfaced fragment rests it, so the
    /// rhythm moves on to another memory tomorrow.
    private func open(_ node: Node) {
        if node.id == resurfacing?.id {
            Resurfacing.markMet(node, context: context)
            // The core promise just paid off: arm the review ask once the old
            // thought has had a couple of seconds to land, never during the open.
            if !ReviewPrompt.shared.hasRequested {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    ReviewPrompt.shared.recordResurfacedOpen()
                }
            }
        }
        sheet = .thought(node)
    }

    private func updateOceanSheetPresence() {
        appState.isPresentingOceanSheet = sheet != nil || showSettings
    }

    /// A deep link (e.g. the Resurfacing widget) queued a node: open it.
    private func consumePendingFocus() {
        guard let id = appState.pendingFocusNodeID else { return }
        appState.pendingFocusNodeID = nil
        guard let node = nodeByID[id] else { return }
        open(node)
    }

    // MARK: Resurfacing (ambient rediscovery)

    private var resurfacing: Node? { Resurfacing.pick(from: nodes) }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Ocean")
                .font(.largeTitle.bold())
                .foregroundStyle(OceanTheme.foam)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.subheadline)
                    .foregroundStyle(OceanTheme.mist)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Ocean settings")
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "water.waves")
                .font(.system(size: 48))
                .foregroundStyle(OceanTheme.surface)
            Text("The Ocean is still")
                .font(.title3.weight(.semibold))
                .foregroundStyle(OceanTheme.foam)
            Text("Capture a thought and watch it drift in.")
                .font(.subheadline)
                .foregroundStyle(OceanTheme.mist)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Glass orb

/// A lifted glass body on the water (§4): frosted glass tinted by the
/// thought, light caught softly across its upper face, and a soft depth
/// shadow beneath. No halo, no luminous core, no rim.
private struct GlassOrb: View {
    let diameter: CGFloat
    let tint: Color
    let lit: Bool
    let symbol: String?

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            // Body tint: lit from above, sinking toward the water.
            Circle().fill(
                LinearGradient(
                    colors: [tint.opacity(lit ? 0.56 : 0.20), tint.opacity(lit ? 0.10 : 0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // Soft sheen where the glass catches the light.
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(lit ? 0.32 : 0.20), Color.white.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: diameter * 0.64, height: diameter * 0.38)
                .offset(y: -diameter * 0.22)
                .blur(radius: diameter * 0.035)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: diameter * (lit ? 0.22 : 0.28), weight: .medium))
                    .foregroundStyle(OceanTheme.foam.opacity(0.85))
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .compositingGroup()
        .shadow(
            color: .black.opacity(lit ? 0.55 : 0.45),
            radius: diameter * (lit ? 0.16 : 0.14),
            y: diameter * (lit ? 0.13 : 0.11)
        )
        .accessibilityHidden(true)
    }
}

/// A glass orb that breathes and drifts by a few points over tens of
/// seconds, phase and period from its id hash. Its title sits outside, so
/// words never move. Completely still when `still` is set.
private struct DriftingOrb: View {
    let diameter: CGFloat
    let tint: Color
    let lit: Bool
    let symbol: String?
    let seed: Int
    let still: Bool

    var body: some View {
        TimelineView(.animation(paused: still)) { timeline in
            let t = still ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let motion = drift(at: t)
            GlassOrb(diameter: diameter, tint: tint, lit: lit, symbol: symbol)
                .scaleEffect(motion.scale)
                .offset(motion.offset)
        }
        .frame(width: diameter, height: diameter)
    }

    private func drift(at t: TimeInterval) -> (offset: CGSize, scale: CGFloat) {
        guard !still else { return (.zero, 1) }
        let unit = { (salt: Int) -> Double in Double((seed / salt) % 1000) / 1000 }
        let phase = unit(1) * 2 * .pi
        // Periods of 22 to 40 seconds: atmosphere, never a signal.
        let swayPeriod = 22 + unit(7) * 18
        let bobPeriod = 26 + unit(13) * 14
        let breathPeriod = 9 + unit(17) * 5
        let dx = sin(t * 2 * .pi / swayPeriod + phase) * 3
        let dy = cos(t * 2 * .pi / bobPeriod + phase * 1.3) * 3.5
        let breath = 1 + sin(t * 2 * .pi / breathPeriod + phase) * 0.018
        return (CGSize(width: dx, height: dy), breath)
    }
}

/// A gentle press: the orb or chip settles a touch under the finger.
private struct SurfacePressStyle: ButtonStyle {
    let still: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !still ? 0.97 : 1)
            .animation(still ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Drift arrangement

/// Each newest thought's id hash, for its small stable offset from its slot.
private struct DriftSeed: LayoutValueKey {
    static let defaultValue = 0
}

/// The newest thoughts, placed as if drifting near the surface: three loose
/// columns, the middle one riding lower, each thought nudged a few points by
/// its id hash so the water never reads as a grid. Deterministic, so the
/// arrangement is the same on every launch, and never overlapping: columns
/// own disjoint widths and rows are spaced by the tallest item.
private struct DriftLayout: Layout {
    let count: Int

    /// (column center as a fraction of width, row in units of item height).
    private var slots: [(x: CGFloat, y: CGFloat)] {
        switch count {
        case 1: return [(0.5, 0)]
        case 2: return [(0.27, 0), (0.73, 0.34)]
        default:
            return [(1.0 / 6, 0), (5.0 / 6, 0.16), (0.5, 0.6), (1.0 / 6, 1.06), (5.0 / 6, 1.22)]
        }
    }

    /// Maximum hash nudge, in points, each way.
    private let jitter: CGFloat = 5

    private func columnWidth(_ width: CGFloat) -> CGFloat {
        // Column cells are width / 3; leave room for the nudge on both sides.
        max(60, width / 3 - 2 * jitter - 4)
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let colW = columnWidth(width)
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: colW, height: nil)) }
        let tallest = sizes.map(\.height).max() ?? 0
        let unit = tallest + 22
        return subviews.indices.map { index in
            let slot = slots[min(index, slots.count - 1)]
            let seed = subviews[index][DriftSeed.self]
            let dx = CGFloat(seed % 11) - jitter
            let dy = CGFloat((seed / 11) % 11) - jitter
            let size = sizes[index]
            let centerX = slot.x * width + dx
            let top = slot.y * unit + dy + jitter
            return CGRect(x: centerX - size.width / 2, y: top, width: size.width, height: size.height)
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 360
        let height = frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height + jitter)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let colW = columnWidth(bounds.width)
        for (index, frame) in frames(width: bounds.width, subviews: subviews).enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: min(colW, frame.width), height: frame.height)
            )
        }
    }
}
