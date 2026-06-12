import SwiftUI
import SwiftData

/// Ocean Field (§8) — cluster-first.
///
/// Three layers, cleanly separated:
///  1. **Atmosphere** — `OceanBackground` + `AtmosphereView` (non-interactive,
///     purely decorative).
///  2. **Structure** — a cached layout (`OceanLayoutEngine`) whose large
///     objects are *currents*: labeled conceptual regions sized by how many
///     thoughts they hold. Member thoughts orbit them as small motes.
///  3. **Interaction** — tap a current to open its stream of thoughts; tap a
///     mote to open that single thought. Nothing on screen is unlabeled, so
///     there is no reveal-first friction.
///
/// Animation design is unchanged: `TimelineView(.animation)` with no minimum
/// interval (full ProMotion), small compound-sine drift so motion reads as
/// floating, not jitter.
struct OceanFieldView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.calmAccessibility) private var calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Node> { !$0.isArchived }, sort: \Node.createdAt)
    private var nodes: [Node]

    @State private var layout = OceanLayout()
    @State private var sheet: OceanSheet?
    @State private var showSettings = false

    /// Calm Accessibility Mode or the system Reduce Motion setting holds the
    /// water still: same layout, same light, no drift. The Ocean's positions
    /// are atmosphere, not information — stillness costs nothing but motion.
    private var still: Bool { calm || reduceMotion }

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

    // MARK: Body

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let key = OceanLayoutEngine.signature(
                    nodes: nodes, size: geo.size, resurfacingID: resurfacing?.id)
                ZStack {
                    OceanBackground()
                    AtmosphereView()

                    if nodes.isEmpty {
                        emptyState
                    } else {
                        field(in: geo.size)
                    }
                }
                .onAppear {
                    recompute(geo.size)
                    consumePendingFocus()
                }
                .onChange(of: key) { _, _ in recompute(geo.size) }
                .onChange(of: appState.pendingFocusNodeID) { _, _ in consumePendingFocus() }
            }
            .overlay(alignment: .top) { header }
            .ignoresSafeArea(edges: .bottom)
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
        }
    }

    // MARK: Field

    private func field(in size: CGSize) -> some View {
        // No minimumInterval — ProMotion drives this at full refresh rate.
        // Stilled, the field keeps its full layout at each thought's resting
        // place; only the drift (and its battery cost) goes quiet.
        TimelineView(.animation(paused: still)) { timeline in
            let t = still ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                // Currents first (beneath their particles), least prominent at the back.
                ForEach(layout.clusters.sorted { $0.prominence < $1.prominence }) { cluster in
                    let phase = still ? 0 : (sin(t * 0.5 + Double(cluster.center.x) * 0.02) + 1) / 2
                    ClusterOrbView(placement: cluster, pulse: phase)
                        .position(clusterPosition(cluster, t: t))
                        .onTapGesture {
                            sheet = .stream(theme: cluster.id)
                        }
                }

                ForEach(layout.motes) { mote in
                    let phase = still ? 0 : (sin(t * 0.6 + Double(mote.base.y) * 0.02) + 1) / 2
                    ThoughtMoteView(mote: mote, pulse: phase)
                        .position(motePosition(mote, t: t, in: size))
                        .onTapGesture {
                            if let node = nodeByID[mote.id] { open(node) }
                        }
                }
            }
        }
    }

    // MARK: Drift — currents sway slowly; particles orbit and float

    /// The sway a current applies to itself — particles orbiting that current
    /// track the same offset so the whole region moves as one body of water.
    private func clusterSway(key: String, t: Double) -> CGSize {
        let seed = Double(NodeComposer.stableHash(key) % 1000) / 1000
        let ph = seed * 6.2831
        let x = sin(t * 0.07 + ph) * 3.5 + sin(t * 0.045 + ph * 0.6) * 1.5
        let y = cos(t * 0.055 + ph * 1.2) * 3.0
        return CGSize(width: x, height: y)
    }

    private func clusterPosition(_ c: ClusterPlacement, t: Double) -> CGPoint {
        let sway = clusterSway(key: c.id, t: t)
        return CGPoint(x: c.center.x + sway.width, y: c.center.y + sway.height)
    }

    /// Orbiting particles sway gently along their ring — a slow pendulum
    /// around their resting slot rather than a full revolution, so a particle
    /// can never wander across its current's label (the layout reserves the
    /// label arc). Standalone thoughts only float.
    private func motePosition(_ m: MotePlacement, t: Double, in size: CGSize) -> CGPoint {
        let seed = Double(NodeComposer.stableHash(m.id.uuidString) % 1000) / 1000
        let ph = seed * 6.2831

        var p: CGPoint
        if let key = m.orbitKey {
            // Each particle swings on its own rhythm — amplitude and tempo
            // vary per thought (≈±3°–8°), so no two move in step.
            let seed2 = Double(NodeComposer.stableHash(m.id.uuidString + "v") % 1000) / 1000
            let angle = m.baseAngle + sin(t * (0.08 + seed2 * 0.09) + ph) * (0.05 + seed * 0.09)
            let sway = clusterSway(key: key, t: t)
            p = CGPoint(
                x: m.orbitCenter.x + sway.width + CGFloat(cos(angle)) * m.orbitRadius,
                y: m.orbitCenter.y + sway.height + CGFloat(sin(angle)) * m.orbitRadius
            )
        } else {
            p = m.base
        }

        let amp = m.isResurfacing ? 3.0 : (m.orbitKey == nil ? 6.0 : 2.5)
        p.x += sin(t * 0.14 + ph) * amp + sin(t * 0.09 + ph * 0.7) * 1.5
        p.y += cos(t * 0.11 + ph * 1.3) * (amp * 0.85) + cos(t * 0.06 + ph) * 1.4

        p.x = min(size.width - 12, max(12, p.x))
        p.y = min(size.height - 96, max(132, p.y))
        return p
    }

    // MARK: Interaction

    /// Opens a thought; meeting today's resurfaced fragment rests it, so the
    /// rhythm moves on to another memory tomorrow.
    private func open(_ node: Node) {
        if node.id == resurfacing?.id {
            Resurfacing.markMet(node, context: context)
        }
        sheet = .thought(node)
    }

    /// A deep link (e.g. the Resurfacing widget) queued a node: open it.
    private func consumePendingFocus() {
        guard let id = appState.pendingFocusNodeID else { return }
        appState.pendingFocusNodeID = nil
        guard let node = nodeByID[id] else { return }
        open(node)
    }

    private func recompute(_ size: CGSize) {
        let next = OceanLayoutEngine.compute(
            nodes: nodes, size: size, resurfacingID: resurfacing?.id)
        guard next.signature != layout.signature else { return }
        withAnimation(.spring(response: 0.70, dampingFraction: 0.85)) {
            layout = next
        }
    }

    // MARK: Resurfacing (ambient rediscovery)

    private var resurfacing: Node? { Resurfacing.pick(from: nodes) }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ocean")
                    .font(.largeTitle.bold())
                    .foregroundStyle(OceanTheme.foam)
                Spacer()
                Text("\(nodes.count) fragments")
                    .font(.caption2)
                    .foregroundStyle(calm ? OceanTheme.mist : OceanTheme.faint)
                    .padding(.bottom, 4)
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

            if let resurfacing {
                Button {
                    open(resurfacing)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.heart.fill")
                            .foregroundStyle(OceanTheme.glowWarm)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Resurfacing")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(OceanTheme.glowWarm)
                            Text("Catching a thought that drifted away")
                                .font(.caption)
                                .foregroundStyle(OceanTheme.mist)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(OceanTheme.faint)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
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
    }
}
