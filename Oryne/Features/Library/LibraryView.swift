import SwiftUI
import SwiftData

/// Library (§13): a structured, legible fallback over the whole Ocean — search,
/// filter, and browse by time or by current. "Library exists as a structured
/// fallback for accessibility and trust."
///
/// One header for both ways of looking: the page's tools pinned in its own
/// bar (search; the switch between Recent, time sections in a waterfall of
/// cards, and Currents, each current with its newest rows; then the Kind
/// filter), the title in New York, and the filter as a chip while one is
/// on. Search is a state of its own: the tools grow into the field and the
/// title folds away until its ✕.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(\.oceanAI) private var ai
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Node.createdAt, order: .reverse) private var allNodes: [Node]

    @State private var search = ""
    @State private var kind: LibraryKind = .all
    @State private var backfilling = false
    @State private var pendingDelete: Node?

    /// Recent or Currents, kept across launches. `columns` is the single
    /// density source Handoffs 2 and 3 read (pinch density, related-focus
    /// reorder).
    @AppStorage("library.segment") private var segment: Segment = .recent
    @AppStorage("library.columns") private var columns: Int = 2

    /// Handoff 2 "Show related" focus. Stored as a UUID, never a `Node?`: a
    /// deleted anchor detaches, and reading any attribute off a detached `@Model`
    /// faults. `focusRelatedRank` maps a related node's id to its 0-based
    /// relatedness rank, driving both the in-column pull-to-top and the decaying
    /// glow; it is empty while the anchor pins and the off-main ranking runs.
    @State private var focusedAnchorID: UUID?
    @State private var focusRelatedRank: [UUID: Int] = [:]

    @FocusState private var searchFocused: Bool
    /// Searching: the tools grow into the search field and the title folds
    /// away, until the field's ✕ puts them back.
    @State private var searching = false
    /// The tools and the search field are one glass shape that changes.
    @Namespace private var searchGlass
    /// The Library's navigation.
    @State private var path = NavigationPath()
    /// A thought opened from the Library: it rises, as from Tide.
    @State private var openedNode: Node?
    /// The way back from a row swiped away in Currents.
    @State private var removals = ThoughtRemovals()
    /// Bumped to bring the page back to its top (Tide's "All currents").
    @State private var topRequest = 0

    #if DEBUG
    /// One-shot for `OCEAN_SHOW_RELATED_TITLE` (marketing recapture).
    @State private var didEngageScreenshotRelated = false
    #endif

    /// True only while a focus reorder is animating, so cards drop their blurred
    /// glow/anchor shadow during the move (the shadow re-rasterizes the image
    /// every frame) and restore it on settle.
    @State private var reordering = false

    /// Drives the Clear settle-dissolve: fade the grid out, restore base order
    /// and sections with animation disabled, fade back in. Never animates the
    /// structural section rebuild, which was the source of the Clear chaos.
    @State private var gridOpacity: Double = 1

    /// Scroll target at the top of the grid, so engage/clear can steer there.
    private static let gridTopID = "library.grid.top"

    enum Segment: String { case recent, currents }

    /// What the page can show: thoughts not archived, of the filter's kind,
    /// matching the search. Archived ones wait under Currents › Archived.
    private var filtered: [Node] {
        let query = search.trimmed
        return allNodes.filter { node in
            !node.isArchived
            && kind.admits(node)
            && (query.isEmpty || node.searchableText.localizedCaseInsensitiveContains(query))
        }
    }

    /// Today, the seven days before it, and everything earlier. A rolling
    /// week, not a calendar one, so it is named the way Notes names it.
    private func timeSections(_ nodes: [Node]) -> [(title: String, nodes: [Node])] {
        let cal = Calendar.current
        var today: [Node] = [], week: [Node] = [], earlier: [Node] = []
        for node in nodes {
            if cal.isDateInToday(node.createdAt) { today.append(node) }
            else if let days = cal.dateComponents([.day], from: node.createdAt, to: .now).day, days < 7 { week.append(node) }
            else { earlier.append(node) }
        }
        return [(String(localized: "Today"), today),
                (String(localized: "Previous 7 Days"), week),
                (String(localized: "Earlier"), earlier)].filter { !$0.nodes.isEmpty }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                PageBackground()
                switch segment {
                case .recent: grid
                case .currents: currents
                }
                ShoreGradient()
            }
            // A tap in open space folds the search keyboard, as open water
            // does in the capture overlay. Cards and buttons keep their taps.
            .contentShape(Rectangle())
            .onTapGesture { searchFocused = false }
            .modifier(TopBar { topBar })
            .navigationTitle("Library")
            // The page draws its own bar, so the tools and the search field
            // can be one shape that changes (Tide keeps the system's).
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $openedNode) { ExpandedNodeView(node: $0) }
            // The system alert, as on a thought's page.
            .alert(
                "Delete this thought?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let node = pendingDelete { delete(node) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("This drifts out of the Ocean for good.")
            }
            .task { await backfillUnderstanding() }
            .task { await prewarmEmbedding() }
            .onChange(of: filtered.map(\.id)) { _, ids in
                // The anchor left the visible set (deleted, archived, filtered, or
                // searched away): drop focus and restore the base order.
                if let anchor = focusedAnchorID, !ids.contains(anchor) { clearFocus() }
            }
            // "Show related" belongs to Recent's grid.
            .onChange(of: segment) { _, _ in
                focusedAnchorID = nil
                focusRelatedRank = [:]
            }
            // The search bar stays reachable while the page is scrolled:
            // what it finds is shown from the top, not where the page was.
            .onChange(of: search) { _, _ in topRequest += 1 }
            .onAppear(perform: consumeAllCurrents)
            .onChange(of: appState.pendingAllCurrents) { _, _ in consumeAllCurrents() }
            #if DEBUG
            .onAppear { LibraryPerf.beginColdOpen() }
            .task { await engageScreenshotRelatedIfNeeded() }
            #endif
        }
        .settlesThoughtRemovals(removals)
    }

    /// Tide's "All currents": Currents, from the top, with nothing searched
    /// or filtered and no thought left open over it.
    private func consumeAllCurrents() {
        guard appState.pendingAllCurrents else { return }
        appState.pendingAllCurrents = false
        search = ""
        searching = false
        kind = .all
        searchFocused = false
        path = NavigationPath()
        segment = .currents
        topRequest += 1
    }

    /// Set once this install's one-time semantic re-theme has run. It only
    /// ever re-themes thoughts captured before the semantic layer existed
    /// (`UnderstandingBackfill.semanticLayerLanded`); every later thought was
    /// understood at capture and keeps its current.
    private static let semanticThemesMigrationKey = "ocean.semanticThemes.v1"

    /// Interpret fragments that haven't been understood yet: untitled ones,
    /// plus, once, any fragment captured before the semantic layer (themed by
    /// the old keyword extractor). Both join existing currents the way a
    /// capture does, rather than founding a current of their own.
    private func backfillUnderstanding() async {
        guard !backfilling else { return }
        backfilling = true
        defer { backfilling = false }

        let migrate = !UserDefaults.standard.bool(forKey: Self.semanticThemesMigrationKey)
        let modelReady = OnDeviceModel.isReadyCached

        // Pictures that the current reader has not read yet (share-sheet
        // captures, thoughts from before pictures were read, a bumped reader):
        // read first, newest first, so many per open, so the understanding
        // below sees the words in them. A thought already understood is
        // re-derived with its picture once it has one to add.
        var pictureRead = Set<UUID>()
        let unreadPictures = allNodes
            .filter { $0.needsPictureReading && !$0.isExample }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(UnderstandingBackfill.picturesPerOpen)
        for node in unreadPictures {
            if await PictureEnrichmentService.shared.read(nodeID: node.id, context: context) {
                pictureRead.insert(node.id)
            }
        }

        let all = allNodes.compactMap { node -> (node: Node, work: UnderstandingBackfill.Work)? in
            let work = UnderstandingBackfill.work(
                isExample: node.isExample,
                hasTitle: !node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                createdAt: node.createdAt,
                migrating: migrate,
                understandingVersion: node.understandingVersion,
                modelAvailable: modelReady
            )
            return work.map { (node, $0) }
        }
        // Naming and re-theming come first; enrichment of the understanding
        // record runs newest first and only so many per open.
        let enrichment = all.filter { $0.work == .enrich }
            .sorted { $0.node.createdAt > $1.node.createdAt }
            .prefix(UnderstandingBackfill.enrichmentPerOpen)
        let pending = all.filter { $0.work != .enrich } + enrichment
        // A keyword-era thought still waiting for its new themes is no
        // current to join; it becomes one once re-themed.
        var keywordEra = Set(pending.filter { $0.work == .retheme }.map(\.node.id))

        for (node, work) in pending {
            defer { keywordEra.remove(node.id) }

            let raw = node.rawContent
            if raw.isEmpty {
                if work == .understand {
                    // A voice thought gets "Whisper" here: a placeholder, not
                    // a name. Every language's form of this label must be in
                    // `VoiceUnderstanding.whisperPlaceholders`, or a late
                    // understanding keeps it as the title and the watch shows
                    // it as the thought's name.
                    node.title = node.kind.label
                    try? context.save()
                }
                continue
            }

            // An enriched thought already has its place: no current to join.
            let currents = work == .enrich ? [] : CurrentSnap.candidates(
                in: allNodes.filter { !keywordEra.contains($0.id) },
                excluding: node.id,
                forEntry: raw,
                names: CurrentDirectory.shared.names
            )
            let understanding = await ai.understand(raw, currents: currents)
            NodeComposer.applyUnderstanding(
                understanding, to: node,
                preserveTitle: work != .understand,
                preserveThemes: work == .enrich
            )
            try? context.save()
        }

        // A titled, understood thought whose picture was just read: its
        // record learns the picture now (the loop above left it alone).
        let understood = Set(pending.map(\.node.id))
        for id in pictureRead where !understood.contains(id) {
            await PictureEnrichmentService.rederive(nodeID: id, context: context, ai: ai)
        }

        if migrate {
            UserDefaults.standard.set(true, forKey: Self.semanticThemesMigrationKey)
        }
        if !pending.isEmpty { CurrentRegistry.reconcile(context: context) }

        // Long whispers from before summaries existed get their reading now,
        // one at a time, in the background.
        for node in allNodes where node.kind == .voice && !node.isExample && node.summary == nil {
            guard let transcript = node.transcription, transcript.count >= CaptureSession.summaryThreshold else { continue }
            if let summary = await ai.summarizeTranscript(transcript) {
                node.summary = summary
                try? context.save()
            }
        }
    }

    // MARK: Recent

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OceanSpacing.inset) {
                    header
                        .id(Self.gridTopID)
                    let shown = filtered
                    if shown.isEmpty {
                        emptyState
                    }
                    if !search.trimmed.isEmpty, shown.count >= 2 {
                        summarizeLine(shown)
                    }
                    if focusedAnchorID == nil {
                        // Unfocused: the Today / Previous 7 Days / Earlier
                        // sections, one masonry each.
                        ForEach(timeSections(shown), id: \.title) { section in
                            sectionHeader(section.title)
                            MasonryColumns(items: section.nodes, columns: columns, spacing: OceanSpacing.item,
                                           estimatedHeight: estimatedCardHeight,
                                           frontRank: focusFrontRank) { node in
                                cell(node)
                            }
                        }
                    } else {
                        // Focused (sections dropped): one masonry over the
                        // newest-first order, pulling the anchor and related
                        // cards to the top of their columns.
                        MasonryColumns(items: shown, columns: columns, spacing: OceanSpacing.item,
                                       estimatedHeight: estimatedCardHeight,
                                       frontRank: focusFrontRank) { node in
                            cell(node)
                        }
                    }
                }
                .padding(.horizontal, OceanSpacing.gutter)
                .padding(.bottom, OceanSpacing.gap)
                .padding(.bottom, FastCaptureLayout.pageClearance)
            }
            .opacity(gridOpacity)
            .scrollDismissesKeyboard(.immediately)
            .modifier(CaptureComposerEdge())
            // Engage and clear put the front at offset 0. Focus does not reset
            // scroll; steer explicitly or the viewport strands past realized
            // content (the spike's mid-reorder gap). Same transaction as the
            // reorder so they move together.
            .onChange(of: focusedAnchorID) { _, _ in
                withAnimation(OceanMotion.lift) { proxy.scrollTo(Self.gridTopID, anchor: .top) }
            }
            .onChange(of: topRequest) { _, _ in
                withAnimation(OceanMotion.standard) { proxy.scrollTo(Self.gridTopID, anchor: .top) }
            }
        }
        // The pinned "Related to ..." chip rides above the scroll while focused.
        .safeAreaInset(edge: .top) {
            if focusedAnchorID != nil { focusChip }
        }
    }

    // MARK: Currents

    private var currents: some View {
        LibraryCurrents(nodes: allNodes, search: search, kind: kind, open: { openedNode = $0 },
                        removals: removals, topRequest: topRequest) {
            header
        } empty: {
            emptyState
        } lead: {
            let shown = filtered
            if !search.trimmed.isEmpty, shown.count >= 2 {
                summarizeLine(shown)
                    .padding(.top, OceanSpacing.inset)
            }
        }
        .modifier(CaptureComposerEdge())
        .thoughtRemovalToast(removals)
    }

    /// A search that found more than one thought can be read across in one
    /// tap: the result set goes to Ask as a summary (SPEC, Ask: one mode).
    /// One quiet line, as on a thought's page beside Nearby: how many were
    /// found, then Summarize.
    private func summarizeLine(_ shown: [Node]) -> some View {
        HStack(spacing: OceanSpacing.gap) {
            Text("\(shown.count) thoughts")
                .font(OceanType.meta)
                .foregroundStyle(OceanTheme.mist)
            Spacer(minLength: 0)
            Button {
                appState.summarize(shown.map(\.id), title: search.trimmed)
            } label: {
                Label("Summarize", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .buttonStyle(.oceanSecondary)
        }
    }

    // MARK: Search

    /// The page's bar, pinned on the line where Tide's gear sits: the tools
    /// at rest; while searching, the field and its ✕. The group's glass
    /// grows into the field and the ✕ separates from it, so opening and
    /// closing is one shape changing on one spring.
    private var topBar: some View {
        SearchGlassContainer {
            HStack(spacing: OceanSpacing.item) {
                if searching {
                    OceanSearchField(text: $search, prompt: "Search the Ocean",
                                     focused: $searchFocused, glass: true)
                        .searchGlassID("search", in: searchGlass)
                        .onAppear { searchFocused = true }
                    Button(action: endSearch) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.oceanIcon)
                    .searchGlassID("close", in: searchGlass)
                    .accessibilityLabel("Cancel")
                } else {
                    Spacer(minLength: 0)
                    toolGroup
                        .searchGlassID("search", in: searchGlass)
                }
            }
        }
        .frame(height: OceanControlSize.height)
        .padding(.horizontal, OceanSpacing.gutter)
        .padding(.bottom, OceanSpacing.gap)
    }

    /// Opening and closing share one spring, the floating layer's, so the
    /// glass, the title and the page move together. Reduce Motion crossfades.
    private var searchMotion: Animation {
        reduceMotion ? OceanMotion.quick : OceanMotion.lift
    }

    private func startSearch() {
        withAnimation(searchMotion) { searching = true }
    }

    /// The keyboard leaves as the field folds back, not after it.
    private func endSearch() {
        searchFocused = false
        withAnimation(searchMotion) {
            searching = false
            search = ""
        }
    }

    /// The focused anchor resolved to a live node, or nil once it leaves the set.
    private var focusedAnchor: Node? {
        guard let id = focusedAnchorID else { return nil }
        return filtered.first { $0.id == id }
    }

    /// Focus ordering for the masonry: 0 for the anchor, 1...K for related cards
    /// by descending relatedness, nil for everything else (kept in base order).
    private func focusFrontRank(_ node: Node) -> Int? {
        guard focusedAnchorID != nil else { return nil }
        if node.id == focusedAnchorID { return 0 }
        if let rank = focusRelatedRank[node.id] { return rank + 1 }
        return nil
    }

    /// Rank-based glow, 1.0 for the closest related card fading to a 0.2 floor at
    /// the cap. Capped to the top few so the number of live blur-shadows during a
    /// reorder stays bounded; the anchor uses a steady accent instead (glow 0).
    private func focusGlow(_ node: Node) -> Double {
        guard node.id != focusedAnchorID, let rank = focusRelatedRank[node.id] else { return 0 }
        let cap = 8
        guard rank < cap else { return 0 }
        return 1.0 - (Double(rank) / Double(cap - 1)) * 0.8
    }

    private var focusChip: some View {
        let title = focusedAnchor?.displayTitle ?? ""
        // The floating layer's own glass (the bars' material), 44 pt, with
        // Clear as a Link beside the words, as Undo sits in a toast.
        return HStack(spacing: OceanSpacing.gap) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(OceanType.meta).foregroundStyle(OceanTheme.glowWarm)
            Text("Related to \"\(title)\"")
                .font(OceanType.control).foregroundStyle(OceanTheme.foam)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: OceanSpacing.tight)
            Button("Clear") { clearFocus() }
                .buttonStyle(.oceanLink)
        }
        .padding(.leading, OceanSpacing.inset).padding(.trailing, OceanSpacing.gap)
        .frame(height: OceanControlSize.height)
        .background(OceanBarBackground())
        .padding(.horizontal, OceanSpacing.gutter).padding(.bottom, OceanSpacing.snug)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Warm the on-device embedding model off-main once the Library appears, so
    /// the first "Show related" ranking is not cold (a cold model pushed engage
    /// over the 500ms budget; warm it is well under).
    private func prewarmEmbedding() async {
        await Task.detached(priority: .utility) {
            _ = EmbeddingService.shared.vector(for: "ocean")
        }.value
    }

    #if DEBUG
    /// Marketing recapture: `OCEAN_SHOW_RELATED_TITLE` engages Show Related once
    /// the named card is in the Library. Waits for seed + embedding warm-up.
    private func engageScreenshotRelatedIfNeeded() async {
        let title = ProcessInfo.processInfo.environment["OCEAN_SHOW_RELATED_TITLE"] ?? ""
        guard !title.isEmpty, !didEngageScreenshotRelated else { return }
        await prewarmEmbedding()
        for _ in 0..<40 {
            if let node = filtered.first(where: { $0.displayTitle == title }) {
                didEngageScreenshotRelated = true
                segment = .recent
                try? await Task.sleep(for: .milliseconds(500))
                showRelated(to: node)
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
    #endif

    /// Engage "Show related": pin the anchor and chip instantly (and scroll to
    /// the top via the grid's onChange), then rank off-main and let the related
    /// cards surface a beat later.
    private func showRelated(to node: Node) {
        let anchorID = node.id
        reordering = true
        withAnimation(OceanMotion.lift) {
            focusedAnchorID = anchorID
            focusRelatedRank = [:]
        }
        // TODO: reorder feedback — soft swell via CaptureFeedback, not a tap.
        let inputs = filtered.map(FocusInput.init)
        #if DEBUG
        let signpost = LibraryPerf.signposter.beginInterval("related.engage")
        let started = CFAbsoluteTimeGetCurrent()
        #endif
        Task {
            let ranked = await Task.detached(priority: .userInitiated) {
                rankRelated(anchorID: anchorID, among: inputs)
            }.value
            guard focusedAnchorID == anchorID else { reordering = false; return }
            withAnimation(OceanMotion.lift) {
                focusRelatedRank = Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($1, $0) })
            } completion: {
                // Snap the shadows back once the cards have settled. Animating the
                // blur radius back would re-rasterize the blur every frame of the
                // fade, re-introducing the very cost suppressShadow removed.
                reordering = false
            }
            #if DEBUG
            LibraryPerf.signposter.endInterval("related.engage", signpost)
            LibraryPerf.log.notice("related.engage \((CFAbsoluteTimeGetCurrent() - started) * 1000, format: .fixed(precision: 1))ms related=\(ranked.count) budget=500")
            #endif
        }
    }

    private func clearFocus() {
        guard focusedAnchorID != nil else { return }
        #if DEBUG
        let signpost = LibraryPerf.signposter.beginInterval("related.clear")
        let started = CFAbsoluteTimeGetCurrent()
        #endif
        // Settle-dissolve, not a glide: fade the grid out, restore base order and
        // sections with animation disabled (never animate the structural section
        // rebuild + full-store realization, which reads as chaos), then fade back
        // in. Engage surfaces (in-column glide); Clear is the tide settling.
        reordering = true
        withAnimation(OceanMotion.quick) {
            gridOpacity = 0
        } completion: {
            var restore = Transaction()
            restore.disablesAnimations = true
            withTransaction(restore) {
                focusedAnchorID = nil
                focusRelatedRank = [:]
            }
            reordering = false
            withAnimation(OceanMotion.quick) { gridOpacity = 1 }
        }
        #if DEBUG
        LibraryPerf.signposter.endInterval("related.clear", signpost)
        LibraryPerf.log.notice("related.clear \((CFAbsoluteTimeGetCurrent() - started) * 1000, format: .fixed(precision: 1))ms budget=500")
        #endif
    }

    /// A cheap balance estimate for the masonry's shortest-column packing; only
    /// column assignment depends on it, so being roughly right is enough. It
    /// deliberately avoids walking the images relationship for every node (the
    /// kind is the hint for a banner), because this runs over the whole set.
    private func estimatedCardHeight(_ node: Node) -> CGFloat {
        var height: CGFloat = 92
        if node.kind == .image || node.linkImageData != nil { height += OceanSize.banner }
        if !node.snippet.isEmpty { height += CGFloat(min(2, node.snippet.count / 24)) * 20 }
        return height
    }

    // MARK: Header

    /// The page's title in New York, as Tide's sits under its bar, and,
    /// while a filter is on, the filter as a chip that clears it. The title
    /// folds away while searching, so the results start under the field.
    private var header: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.inset) {
            if !searching {
                Text("Library")
                    .font(OceanType.pageTitle)
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    // Where the system's large title stands on Tide and Ask,
                    // and as far from the first section.
                    .padding(.top, OceanSpacing.hairline)
                    .padding(.bottom, OceanSpacing.snug)
                    // It rises into the bar as the page rises after it,
                    // so the two never overlap.
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if kind != .all {
                filterChip
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One glass group: search, how the page is arranged (Recent, Currents),
    /// then what kind of thought it shows. Settings live on Tide.
    private var toolGroup: some View {
        OceanToolGroup {
            Button(action: startSearch) {
                OceanToolGlyph(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")
            OceanToolDivider()
            OceanSegmentedSwitch(selection: $segment, options: [
                (value: .recent, title: "Recent", systemImage: "square.grid.2x2"),
                (value: .currents, title: "Currents", systemImage: "water.waves")
            ])
            OceanToolDivider()
            Menu {
                Picker("Kind", selection: $kind.animation(OceanMotion.quick)) {
                    ForEach(LibraryKind.allCases) { option in
                        Label(option.label, systemImage: option.symbol).tag(option)
                    }
                }
            } label: {
                OceanToolGlyph(systemName: "line.3.horizontal.decrease")
            }
            // Its cell alone, without the bar's own button padding.
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("Filter")
            .accessibilityIdentifier("library.filter")
        }
        .fixedSize()
    }

    /// The filter that is on, under the search where the eye already is;
    /// tapping it takes it off.
    private var filterChip: some View {
        Button {
            withAnimation(OceanMotion.quick) { kind = .all }
        } label: {
            HStack(spacing: OceanSpacing.snug) {
                Image(systemName: kind.symbol)
                Text(kind.label)
                Image(systemName: "xmark")
                    .font(OceanType.glyphSmall)
                    .foregroundStyle(OceanTheme.mist)
            }
        }
        .buttonStyle(.oceanSecondary)
        .accessibilityLabel(Text("Clear filter"))
        .accessibilityValue(Text(kind.label))
        .transition(.opacity)
    }

    /// Time sections wear Tide's labels: New York italic, mist.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(OceanType.sectionLabel)
            .foregroundStyle(OceanTheme.mist)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, OceanSpacing.hairline)
            .padding(.top, OceanSpacing.item)
    }

    /// A grid cell: the card, a tap that opens the thought as a sheet, and
    /// Show related, Archive and Delete in a context menu. Delete still routes through `pendingDelete` and the
    /// confirmation dialog.
    private func cell(_ node: Node) -> some View {
        Button { openedNode = node } label: {
            NodeCard(node: node,
                     glow: focusGlow(node),
                     isAnchor: node.id == focusedAnchorID,
                     suppressShadow: reordering)
        }
        .buttonStyle(.plain)
        // Visible cards glide in place on a focus reorder (in-column, stable id);
        // cards realizing fresh at a column top surface from the deep.
        .transition(.opacity.combined(with: .offset(y: OceanSpacing.block)).combined(with: .scale(scale: 0.96)))
        .contextMenu {
            if node.id == focusedAnchorID {
                Button { clearFocus() } label: {
                    Label("Clear related", systemImage: "xmark.circle")
                }
            } else {
                Button { showRelated(to: node) } label: {
                    Label("Show related", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
            Button { archive(node) } label: {
                Label("Archive", systemImage: "archivebox")
            }
            Button(role: .destructive) { pendingDelete = node } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        // VoiceOver: the menu's removals as actions on the card.
        .accessibilityActions {
            Button("Delete") { pendingDelete = node }
            Button("Archive") { archive(node) }
        }
    }

    // MARK: Empty

    /// Nothing to show. With a filter on, it says what the filter left out
    /// and offers to take it off; otherwise the Ocean is empty, or the search
    /// found nothing.
    @ViewBuilder
    private var emptyState: some View {
        let searching = !search.trimmed.isEmpty
        VStack(spacing: OceanSpacing.inset) {
            Text(emptyMessage(searching: searching))
                .font(OceanType.secondary)
                .foregroundStyle(OceanTheme.mist)
                .multilineTextAlignment(.center)
            if kind != .all {
                Button("Clear filter") {
                    withAnimation(OceanMotion.quick) { kind = .all }
                }
                .buttonStyle(.oceanSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, OceanSpacing.block)
    }

    private func emptyMessage(searching: Bool) -> LocalizedStringKey {
        switch kind {
        case .all: searching ? "No fragments match" : "Nothing here yet"
        case .text: searching ? "No text matches" : "No text yet"
        case .voice: searching ? "No whispers match" : "No whispers yet"
        case .image: searching ? "No images match" : "No images yet"
        case .link: searching ? "No links match" : "No links yet"
        }
    }

    // MARK: Removing

    private func archive(_ node: Node) {
        node.isArchived = true
        node.updatedAt = .now
        try? context.save()
    }

    private func delete(_ node: Node) {
        // Clear focus BEFORE detaching if this is the anchor: the order recompute
        // reads meaningText / estimatedCardHeight, which are not behind NodeCard's
        // detached guard and would fault on a detached anchor. Clear, then delete.
        if node.id == focusedAnchorID {
            withAnimation(OceanMotion.lift) {
                focusedAnchorID = nil
                focusRelatedRank = [:]
            }
        }
        // Archive-then-detach (see deleteNodeSafely): a direct delete of a node
        // with branches cascades and faults a row still rendering a child.
        context.deleteNodeSafely(node)
    }
}

/// The page's own bar at the top. On iOS 26 the page scrolls under it with
/// the system's soft edge, as under a navigation bar; earlier, a plain inset.
private struct TopBar<Bar: View>: ViewModifier {
    @ViewBuilder var bar: () -> Bar

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.safeAreaBar(edge: .top, content: bar)
        } else {
            content.safeAreaInset(edge: .top, spacing: 0, content: bar)
        }
    }
}

/// Lets the bar's glass shapes morph into each other on iOS 26; earlier
/// they crossfade.
private struct SearchGlassContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}

private extension View {
    /// The identity a glass shape keeps while it morphs into another.
    @ViewBuilder
    func searchGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

/// A Sendable snapshot of the fields relatedness needs, built on the main actor
/// so ranking can then run in a detached task (`Node` is not Sendable, and
/// reading its attributes off its context's thread is unsafe).
private struct FocusInput: Sendable {
    let id: UUID
    let text: String
    let themes: [String]
    let mood: String?
    let parentID: UUID?
    let isArchived: Bool

    init(_ node: Node) {
        id = node.id
        text = node.meaningText
        themes = node.themes
        mood = node.mood
        parentID = node.parent?.id
        isArchived = node.isArchived
    }
}

/// Off-main relatedness ranking, mirroring LocalOceanAIService.relatedNodeIDs on
/// the Sendable snapshot: single-source cosine + theme + mood blend, a parent
/// bonus, and the ambient relatedness floor. Returns ids, most related first.
/// A free function (nonisolated) so it is safe to call from `Task.detached`;
/// `SemanticThemes.relatedness` and `EmbeddingService` are already thread-safe.
private func rankRelated(anchorID: UUID, among inputs: [FocusInput]) -> [UUID] {
    guard let anchor = inputs.first(where: { $0.id == anchorID }) else { return [] }
    let scored = inputs.compactMap { other -> (id: UUID, score: Double)? in
        guard other.id != anchorID, !other.isArchived else { return nil }
        var score = SemanticThemes.relatedness(
            textA: anchor.text, themesA: anchor.themes, moodA: anchor.mood,
            textB: other.text, themesB: other.themes, moodB: other.mood
        )
        if other.parentID == anchorID || anchor.parentID == other.id { score += 0.15 }
        guard score >= SemanticThemes.relatednessFloor else { return nil }
        return (other.id, score)
    }
    return scored.sorted { $0.score > $1.score }.map(\.id)
}
