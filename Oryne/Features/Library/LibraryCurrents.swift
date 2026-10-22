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
/// name in New York italic with how many thoughts it holds and a ›, then
/// its two newest thoughts as rows. The name opens the whole current; a
/// row opens its thought, and swiping it left archives or deletes it.
/// Adrift comes last, then Archived, the way Recently Deleted closes Notes'
/// folders. Searching or filtering lists every match under its current,
/// without counts. No cards around currents, no expanding in place.
///
/// The page's header (title, search, the switch) is the list's first row,
/// so it scrolls with the currents the way it scrolls with Recent's grid.
struct LibraryCurrents<Header: View, Empty: View, Lead: View>: View {
    /// Every thought, archived ones too: the live ones make the currents,
    /// the archived ones only the Archived count.
    let nodes: [Node]
    let search: String
    let kind: LibraryKind
    @Binding var path: NavigationPath
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
    @Query private var currentRows: [Current]

    @State private var stream: StreamSelection?
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
    /// From one current's last row to the next current's name.
    private static var currentGap: CGFloat { OceanSpacing.section - 8 }
    /// From the header to the first current's name: the first name sits
    /// where Recent's first time section does.
    private static var firstGap: CGFloat { 19 }
    private static var topID: String { "library.currents.top" }

    /// One current as the list shows it: a preview (its newest two and its
    /// count), or, while searching or filtering, every match.
    private struct Entry {
        let group: CurrentGroup
        let rows: [Node]
        let isPreview: Bool
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
            List {
                header
                    .id(Self.topID)
                    .tileRow(top: 0, bottom: 0)
                if entries.isEmpty {
                    empty.tileRow(top: 16, bottom: 0)
                }
                lead.tileRow(top: 0, bottom: 0)
                if !suggestions.isEmpty {
                    suggestionsCard(suggestions)
                        .tileRow(top: Self.firstGap)
                }
                ForEach(entries, id: \.group.id) { entry in
                    current(entry, isFirst: suggestions.isEmpty && entry.group.id == entries.first?.group.id)
                }
                if archived > 0 {
                    archivedLine(count: archived)
                        .tileRow(top: OceanSpacing.section - OceanSpacing.item / 2)
                }
            }
            .tileList()
            .contentMargins(.bottom, FastCaptureLayout.pageClearance + 8, for: .scrollContent)
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
    /// thought, and each swipes away.
    @ViewBuilder
    private func current(_ entry: Entry, isFirst: Bool) -> some View {
        let group = entry.group
        let shown = entry.isPreview ? Array(entry.rows.prefix(Self.previewCount)) : entry.rows
        Button { stream = StreamSelection(theme: group.key) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.label)
                    .font(OceanType.sectionLabel)
                    .foregroundStyle(group.isAdrift ? OceanTheme.mist : OceanTheme.foam)
                    .lineLimit(1)
                    .padding(.leading, 2)
                Spacer(minLength: 8)
                if entry.isPreview {
                    Text(group.members.count, format: .number)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(OceanTheme.mist)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OceanTheme.mist)
            }
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
        .opacity(group.isAdrift ? 0.75 : 1)
        .tileRow(top: isFirst ? Self.firstGap : Self.currentGap - OceanSpacing.item / 2)

        ForEach(shown) { node in
            Button { path.append(node) } label: { NodeRow(node: node, showsCurrent: false) }
                .buttonStyle(.plain)
                .opacity(group.isAdrift ? 0.75 : 1)
                .thoughtSwipeActions(node, removals: removals)
                .tileRow()
        }
    }

    /// The archive's way in, closing the list: a name like a current's, in
    /// the quiet tone, with the archive's glyph so it never reads as one.
    private func archivedLine(count: Int) -> some View {
        Button { showsArchived = true } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "archivebox")
                    .font(.body)
                    .foregroundStyle(OceanTheme.mist)
                Text("Archived")
                    .font(OceanType.sectionLabel)
                    .foregroundStyle(OceanTheme.mist)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(count, format: .number)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(OceanTheme.mist)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OceanTheme.mist)
            }
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
    private func suggestionsCard(_ suggestions: [CurrentRegistry.MergeSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: OceanSpacing.item) {
            Text("Suggested merges")
                .font(OceanType.sectionLabel)
                .foregroundStyle(OceanTheme.mist)
                .padding(.leading, 2)
            ForEach(suggestions) { suggestion in
                let fromName = OceanLayoutEngine.displayLabel(for: suggestion.fromKey)
                let intoName = OceanLayoutEngine.displayLabel(for: suggestion.intoKey)
                VStack(alignment: .leading, spacing: 10) {
                    Text("“\(fromName)” and “\(intoName)” look like one current.")
                        .font(.subheadline)
                        .foregroundStyle(OceanTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
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
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OceanSurface(shape: RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)))
            }
        }
    }
}

/// Which current another one flows into.
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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Its thoughts move over, and “\(from.label)” goes.")
                            .font(.footnote)
                            .foregroundStyle(OceanTheme.mist)
                            .padding(.bottom, 2)
                        ForEach(groups) { group in
                            Button {
                                onMerge(group)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(group.label)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(OceanTheme.foam)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(group.members.count)")
                                        .font(.footnote)
                                        .foregroundStyle(OceanTheme.mist)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(Text("Merge “\(from.label)” into"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A current chosen for its stream sheet.
struct StreamSelection: Identifiable {
    let theme: String
    var id: String { theme }
}
