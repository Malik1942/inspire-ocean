import SwiftUI
import SwiftData

/// The Ocean on the phone: a surface to glance at, not a map to explore
/// (docs/plans/phone-refocus/SPEC.md, decision 5).
///
/// Top to bottom: today's resurfacing thought as the one lit card (the only
/// warm color on the page), the newest thoughts as the Library's own cards,
/// and the four most recently active currents with a way to all of them.
/// Everything here is the app's existing material: GlassCard, NodeCard,
/// chips. No orbs, no counts, no ambient motion.
struct OceanFieldView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.oceanAI) private var ai
    @Environment(\.calmAccessibility) private var calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Node> { !$0.isArchived }, sort: \Node.createdAt, order: .reverse)
    private var nodes: [Node]

    @State private var sheet: OceanSheet?
    @State private var showSettings = false
    /// The resurfacing card's back is up: "Drifts near".
    @State private var flipped = false
    @State private var nearby: [Node] = []
    /// A text thought peeked: its body shown in full on the card.
    @State private var peekingText = false
    /// Bumped by "Let it rest" so today's pick recomputes.
    @State private var restTick = 0

    private static let newestLimit = 5
    private static let currentLimit = 4

    private enum OceanSheet: Identifiable {
        case thought(Node)
        case stream(theme: String)
        case currents
        case image(Data)

        var id: String {
            switch self {
            case .thought(let node): return node.id.uuidString
            case .stream(let theme): return "stream·\(theme)"
            case .currents: return "currents"
            case .image: return "image"
            }
        }
    }

    private var still: Bool { reduceMotion || calm }

    // MARK: Derived

    private var resurfacing: Node? {
        _ = restTick
        return Resurfacing.pick(from: nodes)
    }

    /// The newest thoughts, the resurfacing one aside. A brand-new Ocean
    /// shows the starter examples so the surface is never bare.
    private var newest: [Node] {
        let own = nodes.filter { !$0.isExample && $0.id != resurfacing?.id }
        let pool = own.isEmpty ? nodes.filter { $0.isExample } : own
        return Array(pool.prefix(Self.newestLimit))
    }

    private var currents: [CurrentGroup] {
        CurrentGroup.build(from: nodes).filter { !$0.isAdrift }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                OceanBackground()
                if nodes.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if let resurfacing { resurfacingCard(resurfacing) }
                            newestSection
                            if !currents.isEmpty { currentsSection }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, FastCaptureLayout.contentClearance)
                    }
                }
            }
            .navigationTitle("Ocean")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsGearButton(isPresented: $showSettings)
                }
            }
            .onAppear(perform: consumePendingFocus)
            .onChange(of: appState.pendingFocusNodeID) { _, _ in consumePendingFocus() }
            .onChange(of: resurfacing?.id) { _, _ in
                flipped = false
                peekingText = false
                nearby = []
            }
            .sheet(item: $sheet) { item in
                switch item {
                case .thought(let node):
                    ExpandedNodeView(node: node)
                case .stream(let theme):
                    ClusterStreamView(theme: theme)
                case .currents:
                    CurrentsPage()
                case .image(let data):
                    ImagePeek(data: data)
                }
            }
            .sheet(isPresented: $showSettings) {
                OceanSettingsView()
            }
            .onChange(of: sheet?.id) { _, _ in updateOceanSheetPresence() }
            .onChange(of: showSettings) { _, _ in updateOceanSheetPresence() }
        }
    }

    // MARK: Resurfacing card

    /// The one lit object: the page's only warm color is this card's hairline
    /// and label. The disc on the left is a handle: tap flips the card to
    /// what drifts near; a long press peeks (plays a whisper, opens an image,
    /// unfolds a text). The words on the right open the thought.
    private func resurfacingCard(_ node: Node) -> some View {
        ZStack {
            resurfacingFront(node)
                .opacity(flipped ? 0 : 1)
                .rotation3DEffect(.degrees(flipped && !still ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            resurfacingBack(node)
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(flipped || still ? 0 : -180), axis: (x: 0, y: 1, z: 0))
        }
        .animation(still ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.85), value: flipped)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)
                .strokeBorder(OceanTheme.glowWarm.opacity(0.28), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
    }

    private func resurfacingFront(_ node: Node) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ResurfacingDisc(node: node, flipped: false) {
                flip(node)
            } onPeek: {
                peek(node)
            }

            Button {
                open(node)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Resurfacing · \(node.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .kerning(0.4)
                        .foregroundStyle(OceanTheme.glowWarm)
                        .lineLimit(1)
                    Text(node.displayTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(OceanTheme.foam)
                        .lineLimit(peekingText ? nil : 3)
                        .multilineTextAlignment(.leading)
                    if !node.snippet.isEmpty {
                        Text(peekingText ? node.rawContent : node.snippet)
                            .font(.caption)
                            .foregroundStyle(OceanTheme.mist)
                            .lineLimit(peekingText ? nil : 2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the thought.")
        }
        .padding(14)
    }

    private func resurfacingBack(_ node: Node) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ResurfacingDisc(node: node, flipped: true) {
                flip(node)
            } onPeek: {
                peek(node)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Drifts near")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.4)
                    .foregroundStyle(OceanTheme.glowWarm)
                if nearby.isEmpty {
                    Text("Nothing drifts nearby yet.")
                        .font(.subheadline)
                        .foregroundStyle(OceanTheme.mist)
                } else {
                    ForEach(nearby) { near in
                        Button { open(near) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: near.kind.symbol)
                                    .font(.caption2)
                                    .foregroundStyle(OceanTheme.mist)
                                Text(near.displayTitle)
                                    .font(.subheadline)
                                    .foregroundStyle(OceanTheme.foam)
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !Resurfacing.Rest.restedToday {
                    Button("Let it rest") { rest(node) }
                        .buttonStyle(.oceanSecondary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
    }

    // MARK: Newest

    private var newestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Newest")
            MasonryColumns(items: newest, columns: 2, spacing: 12,
                           estimatedHeight: estimatedCardHeight) { node in
                Button { open(node) } label: {
                    NodeCard(node: node)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func estimatedCardHeight(_ node: Node) -> CGFloat {
        let banner: CGFloat = (node.kind == .image || node.kind == .link || node.hasRichLink) ? 120 : 0
        return 110 + banner + CGFloat(min(node.snippet.count, 160)) * 0.35
    }

    // MARK: Currents

    private var currentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("Currents")
                Spacer()
                Button {
                    sheet = .currents
                } label: {
                    HStack(spacing: 3) {
                        Text("All currents")
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OceanTheme.accent)
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(currents.prefix(Self.currentLimit)) { group in
                    Button { sheet = .stream(theme: group.key) } label: {
                        GlassCard(padding: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(OceanTheme.foam)
                                    .lineLimit(1)
                                Text(group.newest?.displayTitle ?? "")
                                    .font(.caption)
                                    .foregroundStyle(OceanTheme.mist)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(OceanTheme.mist)
            .padding(.leading, 4)
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

    // MARK: Interaction

    private func flip(_ node: Node) {
        if !flipped {
            let ids = ai.relatedNodeIDs(to: node, among: nodes, limit: 3)
            let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
            nearby = ids.compactMap { byID[$0] }
        }
        flipped.toggle()
    }

    private func peek(_ node: Node) {
        switch node.kind {
        case .voice:
            if let data = node.audioData { AudioPlayback.shared.toggle(data: data) }
        case .image, .link:
            if let data = node.imageDatas.first ?? node.linkImageData { sheet = .image(data) }
        case .text:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { peekingText.toggle() }
        }
    }

    /// Today's thought sinks; another rises. It counts as met, so it rests.
    private func rest(_ node: Node) {
        Resurfacing.markMet(node, context: context)
        Resurfacing.Rest.rest(node.id)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            flipped = false
            restTick += 1
        }
    }

    /// Opens a thought; meeting today's resurfaced fragment rests it, so the
    /// rhythm moves on to another memory tomorrow.
    private func open(_ node: Node) {
        if node.id == resurfacing?.id {
            Resurfacing.markMet(node, context: context)
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

    /// A deep link (the Resurfacing widget) queued a node: open it.
    private func consumePendingFocus() {
        guard let id = appState.pendingFocusNodeID else { return }
        appState.pendingFocusNodeID = nil
        guard let node = nodes.first(where: { $0.id == id }) else { return }
        open(node)
    }
}

// MARK: - Disc

/// The flat disc on the resurfacing card: the thought's image, or its kind
/// glyph. Tap flips the card; a long press peeks. While a whisper plays, a
/// thin arc around the disc shows how far along it is. The arc is a fact,
/// not a glow, and is absent when nothing plays.
private struct ResurfacingDisc: View {
    let node: Node
    let flipped: Bool
    let onFlip: () -> Void
    let onPeek: () -> Void

    private let size: CGFloat = 104

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let playing = node.audioData.map { AudioPlayback.shared.isPlaying($0) } ?? false
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))

                if flipped {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(OceanTheme.mist)
                } else if let data = node.imageDatas.first ?? node.linkImageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    Image(systemName: node.kind.symbol)
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(OceanTheme.foam)
                }

                if playing {
                    Circle()
                        .trim(from: 0, to: max(0.02, AudioPlayback.shared.progress))
                        .stroke(OceanTheme.glowWarm, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(-5)
                }
            }
            .frame(width: size, height: size)
        }
        .contentShape(Circle())
        .onTapGesture(perform: onFlip)
        .onLongPressGesture(minimumDuration: 0.4, perform: onPeek)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(flipped ? Text("Flip back") : Text("What drifts near"))
        .accessibilityHint(Text("Double tap to flip. Hold to peek."))
        .accessibilityAddTraits(.isButton)
    }
}

/// A full-screen look at an image thought's picture, from a long press on
/// the disc.
private struct ImagePeek: View {
    let data: Data
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            OceanTheme.abyss.ignoresSafeArea()
            if let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.oceanIcon)
                .padding(12)
        }
    }
}
