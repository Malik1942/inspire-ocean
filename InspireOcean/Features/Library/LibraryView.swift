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
        return [("Today", today), ("This week", week), ("Earlier", earlier)].filter { !$0.nodes.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OceanBackground(animated: false)
                Group {
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $search, prompt: "Search the Ocean")
            .toolbar {
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
            .task { await backfillUnderstanding() }
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

    private var list: some View {
        List {
            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.nodes) { node in
                        NodeRow(node: node)
                            .overlay {
                                // List draws its own disclosure chevron for a
                                // visible NavigationLink — outside the card,
                                // doubling the card's internal one. Hidden
                                // this way, the row still navigates and the
                                // card keeps the full width.
                                NavigationLink(value: node) { EmptyView() }
                                    .opacity(0)
                            }
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(node) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { archive(node) } label: {
                                Label(node.isArchived ? "Restore" : "Archive",
                                      systemImage: node.isArchived ? "arrow.up.bin" : "archivebox")
                            }.tint(OceanTheme.surface)
                        }
                    }
                } header: {
                    Text(group.title).foregroundStyle(OceanTheme.mist)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 48)).foregroundStyle(OceanTheme.surface)
            Text(search.isEmpty ? "Nothing here yet" : "No fragments match")
                .font(.title3.weight(.semibold)).foregroundStyle(OceanTheme.foam)
        }
    }

    private func archive(_ node: Node) {
        node.isArchived.toggle()
        node.updatedAt = .now
        try? context.save()
    }

    private func delete(_ node: Node) {
        context.delete(node)
        try? context.save()
    }
}
