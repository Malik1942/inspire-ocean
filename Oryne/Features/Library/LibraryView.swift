import SwiftUI
import SwiftData

/// Library (§13): a structured, legible fallback over the whole Ocean — search,
/// filter, and browse by time. "Library exists as a structured fallback for
/// accessibility and trust."
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.oceanAI) private var ai
    @Query(sort: \Node.createdAt, order: .reverse) private var allNodes: [Node]

    @State private var search = ""
    @State private var kindFilter: NodeKind?
    @State private var showArchived = false
    @State private var backfilling = false
    @State private var pendingDelete: Node?

    /// Recent (time sections) or Related (one semantic ribbon). Persisted so the
    /// choice survives launches. `columns` is the single density source Handoffs
    /// 2 and 3 read (pinch density, related-focus reorder).
    @AppStorage("library.arrangement") private var arrangement: Arrangement = .recent
    @AppStorage("library.columns") private var columns: Int = 2

    /// The Related ribbon's node order, computed off-main by SemanticOrder and
    /// cached here. Empty until the first arrangement lands, and Recent order
    /// shows as the placeholder meanwhile.
    @State private var relatedOrder: [UUID] = []

    /// Handoff 2 "Show related" focus. Stored as a UUID, never a `Node?`: a
    /// deleted anchor detaches, and reading any attribute off a detached `@Model`
    /// faults. `focusRelatedRank` maps a related node's id to its 0-based
    /// relatedness rank, driving both the in-column pull-to-top and the decaying
    /// glow; it is empty while the anchor pins and the off-main ranking runs.
    @State private var focusedAnchorID: UUID?
    @State private var focusRelatedRank: [UUID: Int] = [:]

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

    enum Arrangement: String { case recent, related }

    private var filtered: [Node] {
        allNodes.filter { node in
            (showArchived || !node.isArchived)
            && (kindFilter == nil || node.kind == kindFilter)
            && (search.trimmed.isEmpty || node.searchableText.localizedCaseInsensitiveContains(search.trimmed))
        }
    }

    private var groups: [(title: String, nodes: [Node])] {
        let cal = Calendar.current
        var today: [Node] = [], week: [Node] = [], earlier: [Node] = []
        for node in filtered {
            if cal.isDateInToday(node.createdAt) { today.append(node) }
            else if let days = cal.dateComponents([.day], from: node.createdAt, to: .now).day, days < 7 { week.append(node) }
            else { earlier.append(node) }
        }
        return [(String(localized: "Today"), today),
                (String(localized: "This week"), week),
                (String(localized: "Earlier"), earlier)].filter { !$0.nodes.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OceanBackground(animated: false)
                Group {
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        grid
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $search, prompt: "Search the Ocean")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Arrangement", selection: $arrangement) {
                            Label("Recent", systemImage: "clock").tag(Arrangement.recent)
                            Label("Related", systemImage: "point.3.connected.trianglepath.dotted")
                                .tag(Arrangement.related)
                        }
                    } label: {
                        Image(systemName: arrangement == .related
                            ? "point.3.connected.trianglepath.dotted"
                            : "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Kind", selection: $kindFilter) {
                            Text("All kinds").tag(NodeKind?.none)
                            ForEach(NodeKind.allCases) { k in
                                Label(k.label, systemImage: k.symbol).tag(NodeKind?.some(k))
                            }
                        }
                        Toggle("Show archived", isOn: $showArchived)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .navigationDestination(for: Node.self) { node in
                NodeDetailContent(node: node)
            }
            // The original system confirmation (the chat-bubble popover). Swap
            // for `.oceanConfirmationDialog` (OceanConfirmationDialog.swift) to
            // use the kept Liquid Glass alternative.
            .confirmationDialog(
                "Delete this thought?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
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
            .task(id: relatedTaskKey) { await refreshRelatedOrder() }
            .onChange(of: filtered.map(\.id)) { _, ids in
                // The anchor left the visible set (deleted, archived, filtered, or
                // searched away): drop focus and restore the base order.
                if let anchor = focusedAnchorID, !ids.contains(anchor) { clearFocus() }
            }
            #if DEBUG
            .onAppear { LibraryPerf.beginColdOpen() }
            #endif
        }
    }

    /// The marker for fragments themed before the semantic understanding
    /// layer existed; bump the suffix to re-run the migration after a
    /// meaningful change to theme generation.
    private static let semanticThemesMigrationKey = "ocean.semanticThemes.v1"

    /// Interpret fragments that haven't been understood yet: untitled ones
    /// (as before), plus — once — every fragment themed by the old keyword
    /// extractor, so the whole Ocean groups and matches by meaning.
    private func backfillUnderstanding() async {
        guard !backfilling else { return }
        backfilling = true
        defer { backfilling = false }

        let migrate = !UserDefaults.standard.bool(forKey: Self.semanticThemesMigrationKey)

        for node in allNodes {
            // Examples are curated: seeded with final titles and themes, and
            // re-localized wholesale on language change. Understanding must
            // never retitle or re-theme them, and they carry no user-edit
            // flags, so they are skipped here rather than protected per-field.
            guard !node.isExample else { continue }

            let needsTitle = node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard needsTitle || migrate else { continue }

            let raw = node.rawContent
            if raw.isEmpty {
                if needsTitle {
                    node.title = node.kind.label
                    try? context.save()
                }
                continue
            }

            let understanding = await ai.understand(raw)
            NodeComposer.applyUnderstanding(understanding, to: node, preserveTitle: !needsTitle)
            try? context.save()
        }

        if migrate {
            UserDefaults.standard.set(true, forKey: Self.semanticThemesMigrationKey)
        }
    }

    /// Recomputes the Related order only when it matters: the arrangement is
    /// Related and the visible set (or any node's content) changed. Recent mode
    /// contributes a stable key, so the off-main arrange never runs for it.
    private var relatedTaskKey: Int {
        var hasher = Hasher()
        hasher.combine(arrangement)
        if arrangement == .related {
            for node in filtered {
                hasher.combine(node.id)
                hasher.combine(node.updatedAt)
            }
        }
        return hasher.finalize()
    }

    /// The Related ribbon as nodes: the cached order re-mapped to the current
    /// set, with any not-yet-placed node appended in Recent order. Falls back to
    /// Recent order as the placeholder until the first arrange lands.
    private var orderedRelated: [Node] {
        guard !relatedOrder.isEmpty else { return filtered }
        let byID = Dictionary(filtered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        var result: [Node] = []
        result.reserveCapacity(filtered.count)
        for id in relatedOrder where !seen.contains(id) {
            if let node = byID[id] {
                seen.insert(id)
                result.append(node)
            }
        }
        for node in filtered where !seen.contains(node.id) { result.append(node) }
        return result
    }

    /// Snapshots the filtered nodes on the main actor, arranges them off-main
    /// (SemanticOrder is Sendable-safe and self-caching), then applies the order
    /// back on the main actor. Keeps the arrangement switch off the main thread.
    private func refreshRelatedOrder() async {
        guard arrangement == .related else { return }
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        #endif
        let items = filtered.map {
            SemanticOrder.Item(id: $0.id, text: $0.meaningText, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
        }
        #if DEBUG
        let t1 = CFAbsoluteTimeGetCurrent()
        #endif
        let ordered = await Task.detached(priority: .userInitiated) {
            SemanticOrder.arrange(items)
        }.value
        #if DEBUG
        let t2 = CFAbsoluteTimeGetCurrent()
        #endif
        relatedOrder = ordered
        #if DEBUG
        let t3 = CFAbsoluteTimeGetCurrent()
        LibraryPerf.arrangeSwitch(snapshotMs: (t1 - t0) * 1000,
                                  offMainMs: (t2 - t1) * 1000,
                                  applyMs: (t3 - t2) * 1000,
                                  cells: items.count)
        #endif
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Color.clear.frame(height: 0).id(Self.gridTopID)
                    if arrangement == .recent, focusedAnchorID == nil {
                        // Recent, unfocused: keep the Today / This week / Earlier
                        // sections, one masonry each.
                        ForEach(groups, id: \.title) { group in
                            sectionHeader(group.title)
                            MasonryColumns(items: group.nodes, columns: columns, spacing: 12,
                                           estimatedHeight: estimatedCardHeight,
                                           frontRank: focusFrontRank) { node in
                                cell(node)
                            }
                        }
                    } else {
                        // Related (always) and Recent-while-focused (sections
                        // dropped): one masonry over the base order. `focusFrontRank`
                        // is nil for every node when unfocused, so this is the plain
                        // ribbon; while focused it pulls the anchor and related cards
                        // to the top of their columns.
                        MasonryColumns(items: focusBase, columns: columns, spacing: 12,
                                       estimatedHeight: estimatedCardHeight,
                                       frontRank: focusFrontRank) { node in
                            cell(node)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            // Fresh scroll view per arrangement. Lazy columns realize cells
            // incrementally from the top; carrying a deep scroll offset across an
            // arrangement swap strands the viewport past everything realized and
            // the grid renders blank. A reordered ribbon starts at its newest
            // node anyway, so returning to the top is also the honest UX.
            .id(arrangement)
            .opacity(gridOpacity)
            // Engage and clear put the front at offset 0. Focus is not an
            // arrangement change, so `.id` does not reset scroll; steer explicitly
            // or the viewport strands past realized content (the spike's mid-reorder
            // gap). Same transaction as the reorder so they move together.
            .onChange(of: focusedAnchorID) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo(Self.gridTopID, anchor: .top) }
            }
        }
        // The pinned "Related to ..." chip rides above the scroll while focused.
        .safeAreaInset(edge: .top) {
            if focusedAnchorID != nil { focusChip }
        }
    }

    /// The base order the focused masonry reorders over: the Related ribbon keeps
    /// its ribbon order; Recent uses the flat filtered order (sections drop while
    /// focused). Column assignment comes from this order, so cards keep columns.
    private var focusBase: [Node] {
        arrangement == .related ? orderedRelated : filtered
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
        return HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.caption).foregroundStyle(OceanTheme.glowWarm)
            Text("Related to \"\(title)\"")
                .font(.caption).foregroundStyle(OceanTheme.foam)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Button { clearFocus() } label: {
                Text("Clear").font(.caption.weight(.semibold)).foregroundStyle(OceanTheme.glowWarm)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        .padding(.horizontal, 12).padding(.bottom, 6)
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

    /// Engage "Show related": pin the anchor and chip instantly (and scroll to
    /// the top via the grid's onChange), then rank off-main and let the related
    /// cards surface a beat later. Mirrors refreshRelatedOrder's snapshot pattern.
    private func showRelated(to node: Node) {
        let anchorID = node.id
        reordering = true
        withAnimation(.snappy) {
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
            withAnimation(.snappy) {
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
        withAnimation(.easeOut(duration: 0.16)) {
            gridOpacity = 0
        } completion: {
            var restore = Transaction()
            restore.disablesAnimations = true
            withTransaction(restore) {
                focusedAnchorID = nil
                focusRelatedRank = [:]
            }
            reordering = false
            withAnimation(.easeIn(duration: 0.22)) { gridOpacity = 1 }
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
        if node.kind == .image || node.linkImageData != nil { height += 140 }
        if !node.snippet.isEmpty { height += CGFloat(min(4, node.snippet.count / 32)) * 15 }
        if node.linkURLString != nil { height += 18 }
        if !node.themes.isEmpty || node.isExample { height += 24 }
        return height
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(OceanTheme.mist)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    /// A grid cell: the card, a value-based NavigationLink for tap (no List
    /// chevron to hide here), and the Archive/Delete actions that used to live
    /// in swipe actions, re-homed to a context menu. Delete still routes through
    /// `pendingDelete` and the confirmation dialog.
    private func cell(_ node: Node) -> some View {
        NavigationLink(value: node) {
            NodeCard(node: node,
                     glow: focusGlow(node),
                     isAnchor: node.id == focusedAnchorID,
                     suppressShadow: reordering)
        }
        .buttonStyle(.plain)
        // Visible cards glide in place on a focus reorder (in-column, stable id);
        // cards realizing fresh at a column top surface from the deep.
        .transition(.opacity.combined(with: .offset(y: 24)).combined(with: .scale(scale: 0.96)))
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
                Label((node.isArchived ? "Restore" : "Archive") as LocalizedStringKey,
                      systemImage: node.isArchived ? "arrow.up.bin" : "archivebox")
            }
            Button(role: .destructive) { pendingDelete = node } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 48)).foregroundStyle(OceanTheme.surface)
            Text((search.isEmpty ? "Nothing here yet" : "No fragments match") as LocalizedStringKey)
                .font(.title3.weight(.semibold)).foregroundStyle(OceanTheme.foam)
        }
    }

    private func archive(_ node: Node) {
        node.isArchived.toggle()
        node.updatedAt = .now
        try? context.save()
    }

    private func delete(_ node: Node) {
        // Clear focus BEFORE detaching if this is the anchor: the order recompute
        // reads meaningText / estimatedCardHeight, which are not behind NodeCard's
        // detached guard and would fault on a detached anchor. Clear, then delete.
        if node.id == focusedAnchorID {
            withAnimation(.snappy) {
                focusedAnchorID = nil
                focusRelatedRank = [:]
            }
        }
        // Archive-then-detach (see deleteNodeSafely): a direct delete of a node
        // with branches cascades and faults a row still rendering a child.
        context.deleteNodeSafely(node)
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
