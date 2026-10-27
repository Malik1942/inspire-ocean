import SwiftUI
import SwiftData
import AVFoundation
import WidgetKit

/// Tide: where the Ocean meets you. What rose today, what just drifted
/// in, which currents are moving (docs/plans/phone-refocus/SPEC.md,
/// decision 5). The Ocean is the whole water; this is its surface, and the
/// Library is the depth.
///
/// Three sections with one grammar: a quiet label, then content. Only the
/// Resurfacing section is lit, by one lamp in the water, and its label is
/// the page's only warm color. Text sits directly on the water; cards are
/// fills without borders; the type is the system's throughout.
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
    /// "Nearby" is open under the resurfacing thought.
    @State private var nearbyOpen = false
    @State private var nearby: [Node] = []
    /// Bumped by "Let it rest" so today's pick recomputes.
    @State private var restTick = 0
    /// The Resurfacing widget was reloaded since Tide first appeared.
    @State private var widgetReloaded = false
    /// The lamp's extra warmth while a new thought rises; 0 at rest.
    @State private var lampLift: Double = 0
    /// The lamp dims while a thought sinks.
    @State private var lampDim: Double = 1
    /// "Let it rest": today's thought is going under.
    @State private var lettingGo = false
    /// The thought being let go stays on screen until it has gone under;
    /// resting it re-picks today's thought at once.
    @State private var goingUnder: Node?
    /// A thought a card's menu asked to delete, waiting on the alert.
    @State private var pendingDelete: Node?

    private var stilled: Bool { calm || reduceMotion }

    private static let newestLimit = 5
    private static let currentLimit = 4
    private static let currentTileHeight: CGFloat = 72

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
                PageBackground(lampLift: lampLift, lampDim: lampDim)
                if nodes.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OceanSpacing.section) {
                            if let shown = goingUnder ?? resurfacing {
                                // One thought goes under, then the next comes
                                // up: never both on screen at once.
                                resurfacingSection(shown)
                                    .opacity(lettingGo ? 0 : 1)
                                    .offset(y: stilled || !lettingGo ? 0 : OceanSpacing.tight)
                            }
                            newestSection
                            if !currents.isEmpty { currentsSection }
                        }
                        .padding(.horizontal, OceanSpacing.gutter)
                        // Under the large title, the first label keeps the
                        // distance it had from the old title row.
                        .padding(.top, OceanSpacing.block + OceanSpacing.snug)
                        .padding(.bottom, FastCaptureLayout.contentClearance)
                    }
                    .modifier(CaptureComposerEdge())
                }
                ShoreGradient()
            }
            // The system's large title, in New York (`applyLargeTitleAppearance`),
            // folds into the bar as the page scrolls; the gear stays pinned
            // in the bar's own glass.
            .navigationTitle(OceanTab.homeTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Ocean settings")
                }
            }
            .onAppear(perform: consumePendingFocus)
            .onChange(of: appState.pendingFocusNodeID) { _, _ in consumePendingFocus() }
            .onChange(of: resurfacing?.id) { _, _ in
                nearbyOpen = false
                nearby = []
            }
            // The Resurfacing widget shows this same pick: reload it when the
            // pick changes, and once when Tide first appears, for a change made
            // while the app was closed (a sync, a reseed). `initial` runs again
            // on every return to this tab; those reload nothing.
            .onChange(of: resurfacing?.id, initial: true) { old, new in
                guard old != new || !widgetReloaded else { return }
                widgetReloaded = true
                WidgetCenter.shared.reloadTimelines(ofKind: Resurfacing.widgetKind)
            }
            .sheet(item: $sheet) { item in
                switch item {
                case .thought(let node): ExpandedNodeView(node: node)
                case .stream(let theme): ClusterStreamView(theme: theme)
                }
            }
            .sheet(isPresented: $showSettings) { OceanSettingsView() }
            // The system alert, as on a thought's page and in the Library.
            .alert(
                "Delete this thought?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let node = pendingDelete { context.deleteNodeSafely(node) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("This drifts out of the Ocean for good.")
            }
            .onChange(of: sheet?.id) { _, _ in updateOceanSheetPresence() }
            .onChange(of: showSettings) { _, _ in updateOceanSheetPresence() }
        }
    }

    // MARK: Resurfacing

    private func resurfacingSection(_ node: Node) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Resurfacing", warm: true)
                .padding(.bottom, OceanSpacing.gap)

            Button { open(node) } label: {
                VStack(alignment: .leading, spacing: OceanSpacing.gap) {
                    Text(node.displayTitle)
                        .font(OceanType.resurfacingTitle)
                        .foregroundStyle(OceanTheme.foam)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if !node.snippet.isEmpty, node.snippet != node.displayTitle {
                        Text(node.snippet)
                            .font(OceanType.secondary)
                            .foregroundStyle(OceanTheme.text)
                            .lineSpacing(OceanType.secondaryLeading)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    NodeMeta(node: node, detail: whisperLength(node), showsCurrent: false)
                        .padding(.top, OceanSpacing.hairline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the thought.")

            if let data = node.imageDatas.first ?? node.linkImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: OceanSize.hero)
                    .clipShape(RoundedRectangle(cornerRadius: OceanRadius.media, style: .continuous))
                    .padding(.top, OceanSpacing.inset)
                    .onTapGesture { open(node) }
            }

            HStack(spacing: OceanSpacing.gap) {
                Button(nearbyOpen ? "Nearby" : "Nearby") { toggleNearby(node) }
                    .buttonStyle(.oceanSecondary)
                    .opacity(nearbyOpen ? 1 : 0.9)
                if !Resurfacing.Rest.restedToday || goingUnder != nil {
                    Button("Let it rest") { rest(node) }
                        .buttonStyle(.oceanSecondary)
                }
                if node.kind == .voice, let data = node.audioData {
                    PlayWhisperButton(data: data)
                }
            }
            .padding(.top, OceanSpacing.inset)

            if nearbyOpen {
                VStack(alignment: .leading, spacing: 0) {
                    if nearby.isEmpty {
                        Text("Nothing drifts nearby yet.")
                            .font(OceanType.secondary)
                            .foregroundStyle(OceanTheme.mist)
                            .padding(.vertical, OceanSpacing.gap)
                    } else {
                        ForEach(nearby) { near in
                            Button { open(near) } label: { ThoughtLine(node: near) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, OceanSpacing.gap)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func whisperLength(_ node: Node) -> String? {
        guard node.kind == .voice, let data = node.audioData,
              let seconds = AudioDurations.seconds(for: data, id: node.id) else { return nil }
        return AudioDurations.format(seconds)
    }

    // MARK: Drifted in

    private var newestSection: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.afterLabel) {
            sectionLabel("Drifted in")
            MasonryColumns(items: newest, columns: 2, spacing: OceanSpacing.item,
                           estimatedHeight: estimatedCardHeight) { node in
                Button { open(node) } label: { GlanceCard(node: node) }
                    .buttonStyle(.plain)
                    // The Library's long-press menu: a card half the page
                    // wide has no room for a swipe.
                    .contextMenu {
                        Button { archive(node) } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        Button(role: .destructive) { pendingDelete = node } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .accessibilityActions {
                        Button("Delete") { pendingDelete = node }
                        Button("Archive") { archive(node) }
                    }
            }
        }
    }

    private func estimatedCardHeight(_ node: Node) -> CGFloat {
        let banner: CGFloat = node.hasImages || node.linkImageData != nil ? OceanSize.banner : 0
        return 92 + banner + (node.displayTitle.count > 22 ? 22 : 0)
    }

    // MARK: Currents

    private var currentsSection: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.afterLabel) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("Currents")
                Spacer()
                // Every current is in the Library, under Currents.
                Button {
                    appState.showAllCurrents()
                } label: {
                    // A quiet accessory to the section label, never louder
                    // than it: a Link in the label's mist.
                    HStack(spacing: OceanSpacing.tight) {
                        Text("All currents")
                        Image(systemName: "chevron.right").font(OceanType.glyphSmall)
                    }
                }
                .buttonStyle(.oceanLink(.quiet))
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: OceanSpacing.item), GridItem(.flexible(), spacing: OceanSpacing.item)], spacing: OceanSpacing.item) {
                ForEach(currents.prefix(Self.currentLimit)) { group in
                    Button { sheet = .stream(theme: group.key) } label: {
                        VStack(alignment: .leading, spacing: OceanSpacing.snug) {
                            Text(group.label)
                                .font(OceanType.tileTitle)
                                .foregroundStyle(OceanTheme.foam)
                                .lineLimit(1)
                            Text(group.newest?.displayTitle ?? "")
                                .font(OceanType.meta)
                                .foregroundStyle(OceanTheme.mist)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(OceanSpacing.inset)
                        // Two lines and the inset: every current tile the same height.
                        .frame(height: Self.currentTileHeight)
                        .background(OceanSurface(shape: RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionLabel(_ key: LocalizedStringKey, warm: Bool = false) -> some View {
        Text(key)
            .font(OceanType.sectionLabel)
            .foregroundStyle(warm ? OceanTheme.glowWarm : OceanTheme.mist)
            .padding(.leading, OceanSpacing.hairline)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: OceanSpacing.item) {
            Image(systemName: "water.waves")
                .font(OceanType.glyphHero)
                .foregroundStyle(OceanTheme.surface)
            Text("The Ocean is still")
                .font(OceanType.subjectTitle)
                .foregroundStyle(OceanTheme.foam)
            Text("Capture a thought and watch it drift in.")
                .font(OceanType.secondary)
                .foregroundStyle(OceanTheme.mist)
        }
    }

    // MARK: Interaction

    /// The Library's archive: out of Tide and every current, kept in the
    /// Library under Show archived.
    private func archive(_ node: Node) {
        ThoughtRemoval.archive(node)
        try? context.save()
    }

    private func toggleNearby(_ node: Node) {
        if !nearbyOpen {
            let ids = ai.relatedNodeIDs(to: node, among: nodes, limit: 3)
            let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
            nearby = ids.compactMap { byID[$0] }
        }
        withAnimation(OceanMotion.standard) { nearbyOpen.toggle() }
    }

    /// Today's thought goes under; the next one surfaces. It counts as met,
    /// so it rests. Three steps, one at a time: the thought fades and sinks
    /// 4 pt while the lamp lowers a little; only once it is gone is the rest
    /// written, so the page never reloads mid-motion, and the next thought
    /// takes its place unseen while the page eases to its height; then it
    /// rises from those 4 pt on a long ease-out as the lamp warms a touch.
    /// Calm and Reduce Motion: a plain fade.
    private func rest(_ node: Node) {
        guard goingUnder == nil else { return }
        goingUnder = node
        let stilled = self.stilled
        Task { @MainActor in
            withAnimation(stilled ? OceanMotion.quick : .easeInOut(duration: 0.45)) { // art-directed: the lamp
                nearbyOpen = false
                lettingGo = true
                if !stilled { lampDim = 0.6 }
            }
            try? await Task.sleep(for: .milliseconds(stilled ? 180 : 450))
            Resurfacing.markMet(node, context: context)
            Resurfacing.Rest.rest(node.id)
            withAnimation(OceanMotion.standard) {
                goingUnder = nil
                restTick += 1
            }
            try? await Task.sleep(for: .milliseconds(stilled ? 0 : 320))
            withAnimation(stilled ? OceanMotion.quick : OceanMotion.gentle) {
                lettingGo = false
                lampDim = 1
                if !stilled { lampLift = 0.04 }
            }
            guard !stilled else { return }
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(.easeInOut(duration: 1.4)) { lampLift = 0 } // art-directed: the lamp
        }
    }

    /// Opens a thought; meeting today's resurfaced fragment rests it, so the
    /// rhythm moves on to another memory tomorrow.
    private func open(_ node: Node) {
        if node.id == resurfacing?.id {
            Resurfacing.markMet(node, context: context)
            // Seeded examples are a tour, not the promise paying off.
            if !ReviewPrompt.shared.hasRequested, !node.isExample {
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

// MARK: - Glance card

/// A thought at a glance: what it is, not what it says. Title and one meta
/// line; an image thought shows its picture above. A fill, no border.
private struct GlanceCard: View {
    let node: Node

    var body: some View {
        if node.modelContext == nil {
            Color.clear.frame(width: 0, height: 0)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Full-bleed at the top, as in the Library: the card's corner
                // rounds the picture.
                if let data = node.imageDatas.first ?? node.linkImageData, let ui = UIImage(data: data) {
                    Color.clear
                        .frame(height: OceanSize.banner)
                        .frame(maxWidth: .infinity)
                        .overlay { Image(uiImage: ui).resizable().scaledToFill() }
                        .clipped()
                }
                VStack(alignment: .leading, spacing: OceanSpacing.snug) {
                    Text(node.displayTitle)
                        .font(OceanType.tileTitle)
                        .foregroundStyle(OceanTheme.foam)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    NodeMeta(node: node, detail: duration ?? node.linkDomain, showsCurrent: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OceanSpacing.inset)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous))
            .background(OceanSurface(shape: RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)))
            .contentShape(RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous))
        }
    }

    private var duration: String? {
        guard node.kind == .voice, let data = node.audioData,
              let seconds = AudioDurations.seconds(for: data, id: node.id) else { return nil }
        return AudioDurations.format(seconds)
    }
}

/// Plays the resurfacing whisper from its action row; the label is the
/// duration, the glyph the state.
private struct PlayWhisperButton: View {
    let data: Data

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let playing = AudioPlayback.shared.isPlaying(data)
            Button {
                AudioPlayback.shared.toggle(data: data)
            } label: {
                Label(AudioDurations.format(AudioDurations.seconds(for: data, id: nil) ?? 0),
                      systemImage: playing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.oceanSecondary)
            .accessibilityLabel(playing ? Text("Pause whisper") : Text("Play whisper"))
        }
    }
}

/// Recording lengths, read once per thought and cached.
enum AudioDurations {
    private static var cache: [UUID: TimeInterval] = [:]

    static func seconds(for data: Data, id: UUID?) -> TimeInterval? {
        if let id, let cached = cache[id] { return cached }
        guard let player = try? AVAudioPlayer(data: data) else { return nil }
        let seconds = player.duration
        if let id { cache[id] = seconds }
        return seconds
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
