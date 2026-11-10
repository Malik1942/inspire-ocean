import SwiftUI
import SwiftData

/// One current: its concept key, label, and members newest first.
struct CurrentGroup: Identifiable {
    let key: String
    let label: String
    let members: [Node]
    var id: String { key }
    var newest: Node? { members.first }
    var isAdrift: Bool { key == OceanLayoutEngine.adriftKey }

    /// Every current with at least one thought, newest activity first, Adrift
    /// (thoughts with no current) last.
    static func build(from nodes: [Node]) -> [CurrentGroup] {
        var byKey: [String: [Node]] = [:]
        var adrift: [Node] = []
        for node in nodes where !node.isArchived {
            if let key = OceanLayoutEngine.currentKey(for: node) {
                byKey[key, default: []].append(node)
            } else {
                adrift.append(node)
            }
        }
        var groups = byKey.map { key, members in
            CurrentGroup(key: key, label: OceanLayoutEngine.displayLabel(for: key),
                         members: members.sorted { $0.createdAt > $1.createdAt })
        }
        groups.sort { ($0.newest?.createdAt ?? .distantPast) > ($1.newest?.createdAt ?? .distantPast) }
        if !adrift.isEmpty {
            groups.append(CurrentGroup(key: OceanLayoutEngine.adriftKey, label: String(localized: "Adrift"),
                                       members: adrift.sorted { $0.createdAt > $1.createdAt }))
        }
        return groups
    }
}

/// The Library's Currents: every current, newest activity first, each its
/// name in New York with how many thoughts it holds and a ›, then
/// its two newest thoughts as rows. The name opens the whole current; a
/// row opens its thought, and swiping it left archives or deletes it.
/// Adrift comes last, then Archived, the way Recently Deleted closes Notes'
/// folders. Searching or filtering lists every match under its current,
/// without counts. No expanding in place.
///
/// On a phone they are rows across the page, no card around a current. A
/// big screen (iPad, iPhone Duo's inner display) has the room for cards in
/// columns instead (Malik, 2026-11-10): each current one card, its name,
/// count and › on top, its newest thoughts as lines under them.
///
/// The page's header (the filter chip while one is on) is the list's first
/// row, so it scrolls with the currents the way it scrolls with Recent's grid.
struct LibraryCurrents<Header: View, Empty: View, Lead: View>: View {
    /// Every thought, archived ones too: the live ones make the currents,
    /// the archived ones only the Archived count.
    let nodes: [Node]
    let search: String
    let kind: LibraryKind
    /// Opens a thought (as a sheet over the Library).
    let open: (Node) -> Void
    /// Opens a whole current beside the page (a split iPhone Duo); nil opens
    /// it as this list's own sheet.
    var openStream: ((String) -> Void)? = nil
    /// The way back from a swiped delete or archive, the page's own.
    let removals: ThoughtRemovals
    /// Changes when the list should go back to its top.
    let topRequest: Int
    @ViewBuilder var header: Header
    /// What the list says when nothing is left to show.
    @ViewBuilder var empty: Empty
    /// Under the header while searching: the summary of what was found.
    @ViewBuilder var lead: Lead

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.isBigScreen) private var isBigScreen
    @Query private var currentRows: [Current]

    @State private var stream: StreamSelection?
    /// The cards' width inside the gutters, read for how many columns fit.
    @State private var cardsWidth: CGFloat = 0
    @State private var showsArchived = false

    /// Rename and merge, from a current's context menu.
    @State private var renaming: CurrentGroup?
    @State private var newName = ""
    @State private var merging: CurrentGroup?
    /// Suggestions the user sent away this session; the rest persist.
    @State private var dismissedMerges = CurrentRegistry.dismissedMerges()

    // Computed, not stored: a generic type can't store statics.

    /// Newest thoughts previewed under each current's name.
    private static var previewCount: Int { 2 }
    private static var topID: String { "library.currents.top" }
    /// The narrowest a current's card stands, as a Recent card does on a
    /// big screen.
    private static var cardLeast: CGFloat { 240 }

    /// From the header to the first current's name: a block to the name's
    /// words, as Recent's first time section stands, less the slack its
    /// 44 pt row leaves above them at this text size.
    private var firstTop: CGFloat {
        OceanSpacing.block - OceanType.currentName.rowSlack(at: typeSize)
    }

    /// From a group's last tile to the next name (a current's, or
    /// Archived): a group apart, to what you see, less the tile row's own
    /// half gap below it and the name row's slack above its words.
    private var groupTop: CGFloat {
        OceanSpacing.group - OceanSpacing.item / 2 - OceanType.currentName.rowSlack(at: typeSize)
    }

    /// One current as the list shows it: a preview (its newest two and its
    /// count), or, while searching or filtering, every match.
    private struct Entry: Identifiable {
        let group: CurrentGroup
        let rows: [Node]
        let isPreview: Bool
        var id: String { group.id }
    }

    /// The cards' columns: as many as fit `cardLeast` wide, one at
    /// accessibility sizes.
    private var cardColumns: Int {
        guard !typeSize.isAccessibilitySize, cardsWidth > 0 else { return 1 }
        return max(1, Int((cardsWidth + OceanSpacing.item) / (Self.cardLeast + OceanSpacing.item)))
    }

    private var query: String { search.trimmed }
    private var narrowing: Bool { !query.isEmpty || kind != .all }

    var body: some View {
        let live = nodes.filter { !$0.isArchived }
        let groups = CurrentGroup.build(from: live)
        let entries = entries(of: groups)
        let suggestions = narrowing ? [] : mergeSuggestions(among: live)
        let archived = narrowing ? 0 : nodes.filter { $0.isArchived && !(removals.pending?.deletes($0) ?? false) }.count
        ScrollViewReader { proxy in
            Group {
                if isBigScreen {
                    cards(entries, suggestions: suggestions, archived: archived)
                } else {
                    List {
                        header
                            .id(Self.topID)
                            .tileRow(top: 0, bottom: 0)
                        if entries.isEmpty {
                            empty.tileRow(top: OceanSpacing.block, bottom: 0)
                        }
                        lead.tileRow(top: 0, bottom: 0)
                        if !suggestions.isEmpty {
                            suggestionsCard(suggestions)
                                .tileRow(top: OceanSpacing.block)
                        }
                        ForEach(entries, id: \.group.id) { entry in
                            current(entry, isFirst: suggestions.isEmpty && entry.group.id == entries.first?.group.id)
                        }
                        if archived > 0 {
                            archivedLine(count: archived)
                                .tileRow(top: groupTop)
                        }
                    }
                    .tileList()
                }
            }
            .contentMargins(.bottom, FastCaptureLayout.pageClearance + OceanSpacing.gap, for: .scrollContent)
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: topRequest) { _, _ in
                withAnimation(OceanMotion.standard) { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
        .sheet(item: $stream) { selection in
            ClusterStreamView(theme: selection.theme)
        }
        .sheet(isPresented: $showsArchived) {
            ArchivedThoughtsView()
        }
        .sheet(item: $merging) { group in
            MergeCurrentSheet(from: group, groups: groups.filter { $0.key != group.key && !$0.isAdrift }) { into in
                if let fromRow = row(forKey: group.key), let intoRow = row(forKey: into.key) {
                    CurrentRegistry.merge(fromRow, into: intoRow, context: context)
                }
            }
        }
        .alert("Rename current", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let group = renaming, let current = row(forKey: group.key) {
                    CurrentRegistry.rename(current, to: newName, context: context)
                }
                renaming = nil
            }
        }
    }

    /// Without a search or a filter, each current is its preview. A name
    /// that matches the search keeps the current whole; otherwise only its
    /// matching thoughts show, all of them.
    private func entries(of groups: [CurrentGroup]) -> [Entry] {
        groups.compactMap { group in
            let ofKind = kind == .all ? group.members : group.members.filter(kind.admits)
            guard !ofKind.isEmpty else { return nil }
            if query.isEmpty || group.label.localizedCaseInsensitiveContains(query) {
                return Entry(group: group, rows: ofKind, isPreview: kind == .all)
            }
            let hits = ofKind.filter { $0.searchableText.localizedCaseInsensitiveContains(query) }
            return hits.isEmpty ? nil : Entry(group: group, rows: hits, isPreview: false)
        }
    }

    private func row(forKey key: String) -> Current? {
        currentRows.first { $0.key == key }
    }

    // MARK: Current

    /// One current, as rows: its name, its count and a › open the whole
    /// current (Summarize and Add a thought at the top, every thought
    /// below); its newest thoughts sit under the name, each a way into that
    /// thought, and each swipes away. The name's 44 pt row is the gap to
    /// its first tile, so the rows sit right under it. Adrift is quieter in
    /// its inks, never in an opacity, so its words keep their contrast.
    @ViewBuilder
    private func current(_ entry: Entry, isFirst: Bool) -> some View {
        let group = entry.group
        let shown = entry.isPreview ? Array(entry.rows.prefix(Self.previewCount)) : entry.rows
        name(entry)
            .tileRow(top: isFirst ? firstTop : groupTop, bottom: 0)

        ForEach(shown) { node in
            Button { open(node) } label: { NodeRow(node: node, showsCurrent: false, quiet: group.isAdrift) }
                .buttonStyle(.plain)
                .thoughtSwipeActions(node, removals: removals)
                .tileRow(top: node.id == shown.first?.id ? 0 : OceanSpacing.item / 2)
        }
    }

    /// Opens the whole current: beside the page where it splits, else as
    /// this list's sheet.
    private func openCurrent(_ key: String) {
        if let openStream { openStream(key) } else { stream = StreamSelection(theme: key) }
    }

    /// A current's name with its count and ›, opening the whole current; its
    /// context menu renames or merges it. A row of the list, or a card's top.
    private func name(_ entry: Entry) -> some View {
        let group = entry.group
        return Button { openCurrent(group.key) } label: {
            HStack(alignment: .firstTextBaseline, spacing: OceanSpacing.gap) {
                Text(group.label)
                    .oceanText(OceanType.currentName)
                    .foregroundStyle(group.isAdrift ? OceanTheme.mist : OceanTheme.foam)
                    .oceanLineLimit(1)
                    .padding(.leading, OceanSpacing.hairline)
                Spacer(minLength: OceanSpacing.gap)
                if entry.isPreview {
                    Text(group.members.count, format: .number)
                        .monospacedDigit()
                        .oceanText(OceanType.secondary)
                        .foregroundStyle(OceanTheme.mist)
                }
                Image(systemName: "chevron.right")
                    .font(OceanType.glyphDisclosure)
                    .foregroundStyle(OceanTheme.mist)
            }
            // A line row's floor, so a name wrapping at accessibility
            // sizes never touches the row's edge.
            .padding(.vertical, OceanSpacing.gap)
            .frame(minHeight: OceanControlSize.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(group.label))
        .accessibilityValue(entry.isPreview ? Text(group.members.count, format: .number) : Text(verbatim: ""))
        .accessibilityHint("Opens every thought in this current.")
        .contextMenu {
            if !group.isAdrift {
                Button {
                    newName = group.label
                    renaming = group
                } label: { Label("Rename", systemImage: "pencil") }
                Button {
                    merging = group
                } label: { Label("Merge into…", systemImage: "arrow.triangle.merge") }
            }
        }
    }

    // MARK: Cards

    /// The currents as cards in columns, a big screen's way: the header, the
    /// summary while searching and the suggested merges across the top as in
    /// the list, the cards a block under them, Archived a group below.
    private func cards(_ entries: [Entry], suggestions: [CurrentRegistry.MergeSuggestion], archived: Int) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                    .id(Self.topID)
                if entries.isEmpty {
                    empty.padding(.top, OceanSpacing.block)
                }
                lead
                if !suggestions.isEmpty {
                    suggestionsCard(suggestions)
                        .padding(.top, OceanSpacing.block)
                }
                MasonryColumns(items: entries, columns: cardColumns, spacing: OceanSpacing.item,
                               estimatedHeight: estimatedCardHeight) { entry in
                    card(entry)
                }
                .padding(.top, OceanSpacing.block)
                if archived > 0 {
                    archivedLine(count: archived)
                        .padding(.top, OceanSpacing.group - OceanType.currentName.rowSlack(at: typeSize))
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardsWidth = $0 }
            .padding(.horizontal, OceanSpacing.gutter)
        }
    }

    /// One current's card: its name row on top, then its thoughts as lines,
    /// no card inside the card. A line opens its thought; a long press
    /// archives or deletes it, as a row's swipe does in the list.
    private func card(_ entry: Entry) -> some View {
        let group = entry.group
        let shown = entry.isPreview ? Array(entry.rows.prefix(Self.previewCount)) : entry.rows
        return VStack(alignment: .leading, spacing: 0) {
            name(entry)
            ForEach(shown) { node in
                Button { open(node) } label: { line(node, quiet: group.isAdrift) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { removals.archive(node) } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        Button(role: .destructive) { removals.delete(node) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .accessibilityActions {
                        Button("Delete") { removals.delete(node) }
                        Button("Archive") { removals.archive(node) }
                    }
            }
        }
        .padding(.horizontal, OceanSpacing.inset)
        .padding(.vertical, OceanSpacing.gap)
        .background(OceanSurface(shape: RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)))
    }

    /// A thought inside a current's card: its title and its meta line, as a
    /// row says them, without the row's own tile.
    @ViewBuilder
    private func line(_ node: Node, quiet: Bool) -> some View {
        // A just-deleted thought can linger a pass before the query drops
        // it; its detached attributes would fault (NodeRow does the same).
        if node.modelContext != nil {
            VStack(alignment: .leading, spacing: OceanSpacing.snug) {
                Text(node.displayTitle)
                    .oceanText(OceanType.cardTitle)
                    .foregroundStyle(quiet ? OceanTheme.text : OceanTheme.foam)
                    .oceanLineLimit(2)
                    .multilineTextAlignment(.leading)
                NodeMeta(node: node, detail: node.linkDomain,
                         siteIcon: node.linkDomain.flatMap { SiteIcons.shared.icon(for: $0) }, showsCurrent: false)
            }
            .padding(.vertical, OceanSpacing.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    /// A card's height before it is measured, for balancing the columns: the
    /// name's row, then a line per thought shown.
    private func estimatedCardHeight(_ entry: Entry) -> CGFloat {
        let lines = entry.isPreview ? min(entry.rows.count, Self.previewCount) : entry.rows.count
        return OceanControlSize.height + 2 * OceanSpacing.gap + CGFloat(lines) * 64 // the line's two text rows and its padding
    }

    /// The archive's way in, closing the list a group after the last
    /// current: a name like a current's, in the quiet tone, with the
    /// archive's glyph so it never reads as one. The glyph takes the name's
    /// role, so it grows with it; the count and the › sit where a current's
    /// do.
    private func archivedLine(count: Int) -> some View {
        Button { showsArchived = true } label: {
            HStack(alignment: .firstTextBaseline, spacing: OceanSpacing.gap) {
                HStack(alignment: .firstTextBaseline, spacing: OceanSpacing.snug) {
                    Image(systemName: "archivebox")
                        .oceanText(OceanType.currentName)
                        .imageScale(.small)
                        .foregroundStyle(OceanTheme.mist)
                    Text("Archived")
                        .oceanText(OceanType.currentName)
                        .foregroundStyle(OceanTheme.mist)
                        .oceanLineLimit(1)
                }
                Spacer(minLength: OceanSpacing.gap)
                Text(count, format: .number)
                    .monospacedDigit()
                    .oceanText(OceanType.secondary)
                    .foregroundStyle(OceanTheme.mist)
                Image(systemName: "chevron.right")
                    .font(OceanType.glyphDisclosure)
                    .foregroundStyle(OceanTheme.mist)
            }
            .padding(.vertical, OceanSpacing.gap)
            .frame(minHeight: OceanControlSize.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Archived"))
        .accessibilityValue(Text(count, format: .number))
        .accessibilityHint("Opens your archived thoughts.")
    }

    // MARK: Suggested merges

    /// Chinese and English currents the thoughts say are one topic, offered
    /// for the user to merge (SPEC decision 2: never silently).
    private func mergeSuggestions(among live: [Node]) -> [CurrentRegistry.MergeSuggestion] {
        let keys = Set(currentRows.map(\.key))
        let members = live.filter { !$0.isExample }.compactMap { node -> (currentKey: String, themeKey: String?)? in
            node.currentKey.map { ($0, node.themeKeys.first) }
        }
        return CurrentRegistry.suggestions(currentKeys: keys, members: members)
            .filter { !dismissedMerges.contains($0.id) }
    }

    /// Pairs the thoughts say are one topic across languages, each with
    /// Merge and Not now. Confirmed merges keep the second current's key.
    /// The label stands its gap above the first tile, the tiles an item
    /// apart.
    private func suggestionsCard(_ suggestions: [CurrentRegistry.MergeSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OceanSectionLabel("Suggested merges")
            VStack(alignment: .leading, spacing: OceanSpacing.item) {
                ForEach(suggestions) { suggestion in
                    let fromName = OceanLayoutEngine.displayLabel(for: suggestion.fromKey)
                    let intoName = OceanLayoutEngine.displayLabel(for: suggestion.intoKey)
                    VStack(alignment: .leading, spacing: OceanSpacing.gap) {
                        Text("“\(fromName)” and “\(intoName)” look like one current.")
                            .oceanText(OceanType.secondary)
                            .foregroundStyle(OceanTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: OceanSpacing.gap) {
                            Button {
                                if let from = row(forKey: suggestion.fromKey), let into = row(forKey: suggestion.intoKey) {
                                    CurrentRegistry.merge(from, into: into, context: context)
                                }
                            } label: { Label("Merge", systemImage: "arrow.triangle.merge") }
                            .buttonStyle(.oceanSecondary)
                            Button {
                                CurrentRegistry.dismiss(suggestion)
                                dismissedMerges.insert(suggestion.id)
                            } label: { Text("Not now") }
                            .buttonStyle(.oceanSecondary)
                        }
                    }
                    .padding(OceanSpacing.inset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OceanSurface(shape: RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)))
                }
            }
            .padding(.top, OceanSpacing.afterLabel)
        }
    }
}

/// Which current another one flows into. It opens as Move to a current
/// does: the header; a block below it, the consequence, a sentence someone
/// must read before choosing; an inset below that, the choices.
struct MergeCurrentSheet: View {
    let from: CurrentGroup
    let groups: [CurrentGroup]
    let onMerge: (CurrentGroup) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                OceanBackground(animated: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        OceanSheetHeader(title: Text("Merge “\(from.label)” into"))
                        Text("Its thoughts move over, and “\(from.label)” goes.")
                            .oceanText(OceanType.secondary)
                            .foregroundStyle(OceanTheme.text)
                            .padding(.top, OceanSpacing.block)
                        VStack(alignment: .leading, spacing: OceanSpacing.item) {
                            ForEach(groups) { group in
                                Button {
                                    onMerge(group)
                                    dismiss()
                                } label: {
                                    // A choice is a tile, as in Move to a current.
                                    HStack(spacing: OceanSpacing.item) {
                                        Text(group.label)
                                            .oceanText(OceanType.cardTitle)
                                            .foregroundStyle(OceanTheme.foam)
                                            .oceanLineLimit(1)
                                        Spacer()
                                        Text("\(group.members.count)")
                                            .monospacedDigit()
                                            .oceanText(OceanType.secondary)
                                            .foregroundStyle(OceanTheme.mist)
                                    }
                                    .padding(.horizontal, OceanSpacing.inset)
                                    .padding(.vertical, OceanSpacing.item)
                                    .frame(minHeight: OceanControlSize.height)
                                    .background(OceanSurface(shape: RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)))
                                    .contentShape(RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, OceanSpacing.inset)
                    }
                    .padding(.horizontal, OceanSpacing.gutter)
                    .padding(.top, OceanSpacing.gap)
                    .padding(.bottom, OceanSpacing.section)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        // The header draws the sheet's grabber; the system's would be a second.
        .presentationDragIndicator(.hidden)
    }
}

/// A current chosen for its stream sheet.
struct StreamSelection: Identifiable {
    let theme: String
    var id: String { theme }
}
