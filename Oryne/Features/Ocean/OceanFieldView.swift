import SwiftUI
import SwiftData
import AVFoundation

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
    /// The lamp's extra warmth while a new thought rises; 0 at rest.
    @State private var lampLift: Double = 0
    /// The lamp dims while a thought sinks.
    @State private var lampDim: Double = 1
    /// "Let it rest": today's thought is going under.
    @State private var lettingGo = false
    /// The thought being let go stays on screen until it has gone under;
    /// resting it re-picks today's thought at once.
    @State private var goingUnder: Node?

    private var stilled: Bool { calm || reduceMotion }

    private static let newestLimit = 5
    private static let currentLimit = 4

    private enum OceanSheet: Identifiable {
        case thought(Node)
        case stream(theme: String)
        case currents

        var id: String {
            switch self {
            case .thought(let node): return node.id.uuidString
            case .stream(let theme): return "stream·\(theme)"
            case .currents: return "currents"
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
                        VStack(alignment: .leading, spacing: 32) {
                            pageTitle
                            if let shown = goingUnder ?? resurfacing {
                                // One thought goes under, then the next comes
                                // up: never both on screen at once.
                                resurfacingSection(shown)
                                    .opacity(lettingGo ? 0 : 1)
                                    .offset(y: stilled || !lettingGo ? 0 : 4)
                            }
                            newestSection
                            if !currents.isEmpty { currentsSection }
                        }
                        .padding(.horizontal, OceanSpacing.gutter)
                        .padding(.top, 0)
                        .padding(.bottom, FastCaptureLayout.contentClearance)
                    }
                }
                ShoreGradient()
            }
            .navigationTitle(OceanTab.homeTitle)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: consumePendingFocus)
            .onChange(of: appState.pendingFocusNodeID) { _, _ in consumePendingFocus() }
            .onChange(of: resurfacing?.id) { _, _ in
                nearbyOpen = false
                nearby = []
            }
            .sheet(item: $sheet) { item in
                switch item {
                case .thought(let node): ExpandedNodeView(node: node)
                case .stream(let theme): ClusterStreamView(theme: theme)
                case .currents: CurrentsPage()
                }
            }
            .sheet(isPresented: $showSettings) { OceanSettingsView() }
            .onChange(of: sheet?.id) { _, _ in updateOceanSheetPresence() }
            .onChange(of: showSettings) { _, _ in updateOceanSheetPresence() }
        }
    }

    /// The page title in the brand's display face, with the gear beside it
    /// (the system bar is hidden here so the title can wear the serif).
    private var pageTitle: some View {
        PageTitleRow(title: OceanTab.homeTitle, showSettings: $showSettings)
            .padding(.bottom, -4)
    }

    // MARK: Resurfacing

    private func resurfacingSection(_ node: Node) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Resurfacing", warm: true)
                .padding(.bottom, 8)

            Button { open(node) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(node.displayTitle)
                        .font(OceanType.resurfacingTitle)
                        .foregroundStyle(OceanTheme.foam)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if !node.snippet.isEmpty, node.snippet != node.displayTitle {
                        Text(node.snippet)
                            .font(.subheadline)
                            .foregroundStyle(OceanTheme.text)
                            .lineSpacing(3)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    NodeMeta(node: node, detail: whisperLength(node), showsCurrent: false)
                        .padding(.top, 2)
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
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: OceanRadius.media, style: .continuous))
                    .padding(.top, 14)
                    .onTapGesture { open(node) }
            }

            HStack(spacing: 8) {
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
            .padding(.top, 18)

            if nearbyOpen {
                VStack(alignment: .leading, spacing: 0) {
                    if nearby.isEmpty {
                        Text("Nothing drifts nearby yet.")
                            .font(.subheadline)
                            .foregroundStyle(OceanTheme.mist)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(nearby) { near in
                            Button { open(near) } label: { ThoughtLine(node: near) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 8)
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
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Drifted in")
            MasonryColumns(items: newest, columns: 2, spacing: 12,
                           estimatedHeight: estimatedCardHeight) { node in
                Button { open(node) } label: { GlanceCard(node: node) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func estimatedCardHeight(_ node: Node) -> CGFloat {
        let banner: CGFloat = node.hasImages || node.linkImageData != nil ? 120 : 0
        return 92 + banner + (node.displayTitle.count > 22 ? 22 : 0)
    }

    // MARK: Currents

    private var currentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("Currents")
                Spacer()
                Button {
                    sheet = .currents
                } label: {
                    // A quiet accessory to the section label, never louder
                    // than it: the label's mist, regular weight.
                    HStack(spacing: 3) {
                        Text("All currents")
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .font(.subheadline)
                    .foregroundStyle(OceanTheme.mist)
                    .frame(minHeight: OceanControlSize.height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(currents.prefix(Self.currentLimit)) { group in
                    Button { sheet = .stream(theme: group.key) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.label)
                                .font(OceanType.tileTitle)
                                .foregroundStyle(OceanTheme.foam)
                                .lineLimit(1)
                            Text(group.newest?.displayTitle ?? "")
                                .font(.footnote)
                                .foregroundStyle(OceanTheme.mist)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .frame(height: 72)
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
            .padding(.leading, 2)
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
            withAnimation(stilled ? OceanMotion.quick : .easeInOut(duration: 0.45)) {
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
            withAnimation(.easeInOut(duration: 1.4)) { lampLift = 0 }
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
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .overlay { Image(uiImage: ui).resizable().scaledToFill() }
                        .clipped()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(node.displayTitle)
                        .font(OceanType.tileTitle)
                        .foregroundStyle(OceanTheme.foam)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    NodeMeta(node: node, detail: duration ?? node.linkDomain, showsCurrent: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
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
