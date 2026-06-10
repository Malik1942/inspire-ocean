import SwiftUI
import SwiftData

/// Ocean Field (§8).
///
/// Three layers, cleanly separated:
///  1. **Atmosphere** — `OceanBackground` + `AtmosphereView` (non-interactive,
///     purely decorative).
///  2. **Structure** — a cached force-relaxation layout (`OceanLayoutEngine`)
///     that clusters related fragments, floats newer ones up, and guarantees
///     breathing room.
///  3. **Interaction** — tappable glass nodes with progressive labels and
///     focus-isolation (neighbours part softly when a node is focused).
///
/// Animation design:
/// - `TimelineView(.animation)` with **no** minimum-interval floor — ProMotion
///   devices run at their full 120 Hz.
/// - Drift amplitudes are deliberately small (≤ 3 pt) so motion is noticed only
///   when stared at — like a floating object, not a jitter.
/// - Compound sine terms give each axis an independent, organic rhythm.
struct OceanFieldView: View {
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<Node> { !$0.isArchived }, sort: \Node.createdAt)
    private var nodes: [Node]

    @State private var layout    = OceanLayout()
    @State private var focusedID: UUID?
    @State private var selected:  Node?

    private var nodeByID: [UUID: Node] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
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
                        // Tap empty water to release focus.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { setFocus(nil) }

                        field(in: geo.size)
                    }
                }
                .onAppear   { recompute(geo.size) }
                .onChange(of: key) { _, _ in recompute(geo.size) }
            }
            .overlay(alignment: .top) { header }
            .ignoresSafeArea(edges: .bottom)
            .navigationBarHidden(true)
            .sheet(item: $selected, onDismiss: { setFocus(nil) }) { node in
                ExpandedNodeView(node: node)
            }
        }
    }

    // MARK: Field

    private func field(in size: CGSize) -> some View {
        // No minimumInterval — ProMotion drives this at full refresh rate.
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(layout.order, id: \.self) { id in
                    if let node = nodeByID[id], let placement = layout.placements[id] {
                        // Phase used for the ambient pulse — slow, independent per node.
                        let phase = (sin(t * 0.55 + Double(placement.base.x) * 0.018) + 1) / 2
                        OceanNodeView(
                            node: node,
                            placement: placement,
                            isFocused: focusedID == id,
                            isDimmed:  focusedID != nil && focusedID != id,
                            pulse:     phase
                        )
                        .position(position(for: placement, t: t))
                        .zIndex(focusedID == id ? 10 : Double(placement.prominence))
                        .onTapGesture { handleTap(node: node, placement: placement) }
                    }
                }
            }
        }
    }

    // MARK: Position — base + ambient drift + focus isolation

    private func position(for placement: OceanPlacement, t: Double) -> CGPoint {
        let drift = driftOffset(placement, t: t)
        let iso   = isolationOffset(placement)
        return CGPoint(
            x: placement.base.x + drift.width  + iso.width,
            y: placement.base.y + drift.height + iso.height
        )
    }

    /// Per-kind ambient drift — clearly visible, but slow and smooth so it reads
    /// as floating, not jittering. (Smoothness comes from the uncapped frame
    /// rate, not from a tiny amplitude.)
    ///
    /// Two independent sine terms per axis (different frequencies) produce an
    /// organic, Lissajous-like float rather than a simple back-and-forth.
    /// Background nodes move at 70 % to recede slightly.
    private func driftOffset(_ p: OceanPlacement, t: Double) -> CGSize {
        // Deterministic per-node seed so every fragment has its own rhythm.
        let seed  = Double(NodeComposer.stableHash(p.id.uuidString) % 1000) / 1000
        let ph    = seed * 6.2831
        let scale = p.tier == .background ? 0.70 : 1.0

        switch p.kind {

        case .image:
            // Images are heavy — broad, slow swells.
            let x = sin(t * 0.085 + ph) * 6.0 + sin(t * 0.052 + ph * 0.6) * 2.0
            let y = cos(t * 0.067 + ph) * 5.0
            return CGSize(width: x * scale, height: y * scale)

        case .voice:
            // Voice sways more expressively, like a waveform settling.
            let x = sin(t * 0.18 + ph) * 7.0 + sin(t * 0.30 + ph * 1.5) * 2.5
            let y = cos(t * 0.12 + ph) * 4.5
            return CGSize(width: x * scale, height: y * scale)

        default:
            // Text drifts on broad, gentle swells with a non-repeating feel.
            let amp = 6.0 + p.prominence * 3.0   // 6 – 9 pt; larger = more prominent
            let x = sin(t * 0.115 + ph) * amp + sin(t * 0.072 + ph * 0.7) * 2.5
            let y = cos(t * 0.095 + ph * 1.2) * (amp * 0.85)
                  + cos(t * 0.058 + ph) * 1.8
            return CGSize(width: x * scale, height: y * scale)
        }
    }

    /// When a node is focused, nearby nodes part gently to reduce accidental taps.
    private func isolationOffset(_ p: OceanPlacement) -> CGSize {
        guard let fid = focusedID, fid != p.id,
              let f = layout.placements[fid] else { return .zero }
        let dx   = p.base.x - f.base.x
        let dy   = p.base.y - f.base.y
        let dist = max(0.001, (dx * dx + dy * dy).squareRoot())
        let influence: CGFloat = 150
        guard dist < influence else { return .zero }
        let push = (influence - dist) / influence * 48
        return CGSize(width: dx / dist * push, height: dy / dist * push)
    }

    // MARK: Interaction

    private func handleTap(node: Node, placement: OceanPlacement) {
        if focusedID == node.id {
            selected = node                      // already focused → open
        } else if placement.tier == .background {
            setFocus(node.id)                    // background: reveal first
        } else {
            setFocus(node.id)
            selected = node                      // foreground: focus + open
        }
    }

    private func setFocus(_ id: UUID?) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            focusedID = id
        }
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

    private var resurfacing: Node? {
        guard nodes.count > 3 else { return nil }
        let older = nodes
            .filter { Date.now.timeIntervalSince($0.createdAt) > 60 * 60 * 24 * 2 }
            .sorted { $0.createdAt < $1.createdAt }
        guard !older.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        return older[day % older.count]
    }

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
                    .foregroundStyle(OceanTheme.faint)
                    .padding(.bottom, 4)
            }

            if let resurfacing {
                Button {
                    setFocus(resurfacing.id)
                    selected = resurfacing
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.heart.fill")
                            .foregroundStyle(OceanTheme.glowWarm)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Resurfacing")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(OceanTheme.glowWarm)
                            Text(resurfacing.displayTitle)
                                .font(.caption)
                                .foregroundStyle(OceanTheme.foam)
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
