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

/// All currents, readable and searchable. Each current is its name, set as
/// a heading in New York italic with a ›, and its two newest thoughts as
/// tiles under it. The name opens the whole current; a tile opens its
/// thought, and swiping it left archives or deletes it. No cards around
/// currents, no counts, no expanding in place.
struct CurrentsPage: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<Node> { !$0.isArchived }, sort: \Node.createdAt, order: .reverse)
    private var nodes: [Node]
    @Query private var currentRows: [Current]

    @State private var search = ""
    @State private var stream: StreamSelection?
    /// Thoughts opened from this page. A path, not `NavigationLink`s: a
    /// link in a `List` draws a chevron the tiles don't wear.
    @State private var path: [Node] = []
    /// The way back from a swiped delete or archive.
    @State private var removals = ThoughtRemovals()

    /// Rename and merge, from a current's context menu.
    @State private var renaming: CurrentGroup?
    @State private var newName = ""
    @State private var merging: CurrentGroup?
    /// Suggestions the user sent away this session; the rest persist.
    @State private var dismissedMerges = CurrentRegistry.dismissedMerges()

    /// Chinese and English currents the thoughts say are one topic, offered
    /// for the user to merge (SPEC decision 2: never silently).
    private var mergeSuggestions: [CurrentRegistry.MergeSuggestion] {
        let keys = Set(currentRows.map(\.key))
        let members = nodes.filter { !$0.isExample }.compactMap { node -> (currentKey: String, themeKey: String?)? in
            node.currentKey.map { ($0, node.themeKeys.first) }
        }
        return CurrentRegistry.suggestions(currentKeys: keys, members: members)
            .filter { !dismissedMerges.contains($0.id) }
    }

    private func row(forKey key: String) -> Current? {
        currentRows.first { $0.key == key }
    }

    /// Newest thoughts previewed under each current's name.
    private static let previewCount = 2
    /// From one current's last tile to the next current's name.
    private static let currentGap: CGFloat = OceanSpacing.section - 8

    private var groups: [CurrentGroup] { CurrentGroup.build(from: nodes) }

    private var query: String { search.trimmed }

    /// Searching: a current stays when its name or one of its thoughts
    /// matches, and shows only the matching thoughts, open.
    private var visible: [(group: CurrentGroup, rows: [Node], forced: Bool)] {
        guard !query.isEmpty else {
            return groups.map { ($0, $0.members, false) }
        }
        return groups.compactMap { group in
            let nameHit = group.label.localizedCaseInsensitiveContains(query)
            let hits = group.members.filter { $0.searchableText.localizedCaseInsensitiveContains(query) }
            if nameHit && hits.isEmpty { return (group, group.members, false) }
            if hits.isEmpty { return nil }
            return (group, hits, true)
        }
    }

    var body: some View {
        let entries = visible
        NavigationStack(path: $path) {
            ZStack {
                OceanBackground(animated: false)
                List {
                    if entries.isEmpty {
                        Text("Nothing drifts near this yet")
                            .font(.subheadline)
                            .foregroundStyle(OceanTheme.mist)
                            .frame(maxWidth: .infinity)
                            .tileRow(top: OceanSpacing.block)
                    }
                    let suggesting = query.isEmpty && !mergeSuggestions.isEmpty
                    if suggesting {
                        suggestions.tileRow(top: 8)
                    }
                    ForEach(entries, id: \.group.id) { entry in
                        current(entry.group, rows: entry.rows, forced: entry.forced,
                                isFirst: !suggesting && entry.group.id == entries.first?.group.id)
                    }
                }
                .tileList()
                .contentMargins(.bottom, OceanSpacing.section, for: .scrollContent)
                .thoughtRemovalToast(removals)
            }
            // The page as one container, for UI tests and pointing tools.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("currents.page")
            // No custom bar background: it would swap in its own appearance
            // and drop the New York large title Library wears.
            .navigationTitle("Currents")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $search, prompt: "Search currents and thoughts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .navigationDestination(for: Node.self) { node in
                NodeDetailContent(node: node)
            }
            .sheet(item: $stream) { selection in
                ClusterStreamView(theme: selection.theme)
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
            // A summary or a question opens in Ask: step out of the way so
            // the answer is what you see.
            .onChange(of: appState.selectedTab) { _, tab in
                if tab == .ask { dismiss() }
            }
        }
        .settlesThoughtRemovals(removals)
    }

    // MARK: Current

    /// One current, as rows: its name and a › open the whole current
    /// (Summarize and Add a thought at the top, every thought below); its
    /// two newest thoughts sit under the name as a preview, each a way into
    /// that thought, and each swipes away. Searching, every match is listed.
    @ViewBuilder
    private func current(_ group: CurrentGroup, rows: [Node], forced: Bool, isFirst: Bool) -> some View {
        let shown = forced ? rows : Array(rows.prefix(Self.previewCount))
        Button { stream = StreamSelection(theme: group.key) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.label)
                    .font(OceanType.sectionLabel)
                    .foregroundStyle(group.isAdrift ? OceanTheme.mist : OceanTheme.foam)
                    .lineLimit(1)
                    .padding(.leading, 2)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OceanTheme.mist)
            }
            .frame(minHeight: OceanControlSize.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        .tileRow(top: isFirst ? 8 : Self.currentGap - OceanSpacing.item / 2)

        ForEach(shown) { node in
            Button { path.append(node) } label: { NodeRow(node: node, showsCurrent: false) }
                .buttonStyle(.plain)
                .opacity(group.isAdrift ? 0.75 : 1)
                .thoughtSwipeActions(node, removals: removals)
                .tileRow()
        }
    }
}

extension CurrentsPage {
    /// Pairs the thoughts say are one topic across languages, each with
    /// Merge and Not now. Confirmed merges keep the second current's key.
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.item) {
            Text("Suggested merges")
                .font(OceanType.sectionLabel)
                .foregroundStyle(OceanTheme.mist)
                .padding(.leading, 2)
            ForEach(mergeSuggestions) { suggestion in
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
