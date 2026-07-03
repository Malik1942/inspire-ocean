import SwiftUI
import SwiftData

/// Ocean Field (§8), cluster-first.
///
/// Three layers, cleanly separated:
///  1. **Atmosphere**: `OceanBackground` plus a static depth fog
///     (non-interactive, purely decorative).
///  2. **Structure**: a cached layout (`OceanLayoutEngine`) whose large
///     objects are *currents*: labeled conceptual regions sized by how many
///     thoughts they hold. Member thoughts orbit them as small motes.
///  3. **Interaction**: tap a current to open its stream of thoughts; tap a
///     mote to open that single thought. Nothing on screen is unlabeled, so
///     there is no reveal-first friction.
///
/// The water itself is a SpriteKit scene (`OceanScene` in `OceanSceneView`):
/// resting places come from the layout engine, and all per-frame life (drift,
/// breathing, energy, ambient bubbles) runs in the scene's update loop, never
/// through SwiftUI state.
struct OceanFieldView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.calmAccessibility) private var calm
    @Query(filter: #Predicate<Node> { !$0.isArchived }, sort: \Node.createdAt)
    private var nodes: [Node]

    @State private var layout = OceanLayout()
    @State private var sheet: OceanSheet?
    @State private var showSettings = false

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
            ZStack {
                OceanBackground()
                oceanFog

                if nodes.isEmpty {
                    emptyState
                } else {
                    field
                }
            }
            .onAppear {
                recompute()
                consumePendingFocus()
            }
            .onChange(of: layoutKey) { _, _ in recompute() }
            .onChange(of: appState.pendingFocusNodeID) { _, _ in consumePendingFocus() }
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

    private var field: some View {
        OceanSceneView(
            layout: layout,
            fragments: fragmentSnapshots,
            onTapFragment: { id in
                if let node = nodeByID[id] { open(node) }
            },
            onTapCluster: { theme in
                sheet = .stream(theme: theme)
            }
        )
    }

    /// Value snapshots for the scene: model objects stay on this side of the
    /// boundary.
    private var fragmentSnapshots: [FragmentSnapshot] {
        nodes.map {
            FragmentSnapshot(id: $0.id, createdAt: $0.createdAt, title: $0.displayTitle)
        }
    }

    /// Depth fog: faint brightening near the surface, darkening toward the
    /// abyss. Static on purpose; the living water is the scene's job.
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

    /// Layout depends only on the data, never the viewport: the world keeps
    /// its shape across rotation and resize, and the camera does the rest.
    private var layoutKey: String {
        OceanLayoutEngine.signature(nodes: nodes, resurfacingID: resurfacing?.id)
    }

    private func recompute() {
        // Passing the previous layout keeps settled water in place: only
        // currents whose membership changed repack, everything else stays
        // exactly where the user left it.
        let next = OceanLayoutEngine.compute(
            nodes: nodes,
            resurfacingID: resurfacing?.id,
            previous: layout.signature.isEmpty ? nil : layout
        )
        guard next.signature != layout.signature else { return }
        // The scene animates the transition (settle or crossfade); no
        // SwiftUI animation wraps the swap anymore.
        layout = next
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
