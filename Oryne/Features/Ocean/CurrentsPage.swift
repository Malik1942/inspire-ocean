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
/// a heading in New York italic, and its newest thought as a tile under it.
/// Tapping the name opens the current in place to its newest eight; "Open
/// current" goes to all of it. No cards around currents, no counts.
struct CurrentsPage: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Node> { !$0.isArchived }, sort: \Node.createdAt, order: .reverse)
    private var nodes: [Node]

    @State private var search = ""
    @State private var expanded: String?
    @State private var stream: StreamSelection?

    /// Thoughts shown inside an open current before "Open current".
    private static let expandedLimit = 8

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
        NavigationStack {
            ZStack {
                OceanBackground(animated: false)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: OceanSpacing.section - 8) {
                        if visible.isEmpty {
                            Text("Nothing drifts near this yet")
                                .font(.subheadline)
                                .foregroundStyle(OceanTheme.mist)
                                .padding(.top, OceanSpacing.block)
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(visible, id: \.group.id) { entry in
                            current(entry.group, rows: entry.rows, forced: entry.forced)
                        }
                    }
                    .padding(.horizontal, OceanSpacing.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, OceanSpacing.section)
                }
            }
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
        }
    }

    // MARK: Current

    private func current(_ group: CurrentGroup, rows: [Node], forced: Bool) -> some View {
        let isOpen = forced || expanded == group.key
        let shown = Array(rows.prefix(isOpen ? Self.expandedLimit : 1))
        return VStack(alignment: .leading, spacing: OceanSpacing.item) {
            Button {
                guard !forced else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    expanded = isOpen ? nil : group.key
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.label)
                        .font(OceanType.sectionLabel)
                        .foregroundStyle(group.isAdrift ? OceanTheme.mist : OceanTheme.foam)
                        .lineLimit(1)
                        .padding(.leading, 2)
                    Spacer(minLength: 8)
                    if !forced, group.members.count > 1 {
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OceanTheme.mist)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? Text("Collapses this current.") : Text("Shows every thought in this current."))

            ForEach(shown) { node in
                NavigationLink(value: node) { NodeRow(node: node) }
                    .buttonStyle(.plain)
            }

            if isOpen {
                Button { stream = StreamSelection(theme: group.key) } label: {
                    HStack(spacing: 4) {
                        Text("Open current")
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OceanTheme.accent)
                    .padding(.vertical, 6)
                    .padding(.leading, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(group.isAdrift ? 0.75 : 1)
    }
}

/// A current chosen for its stream sheet.
struct StreamSelection: Identifiable {
    let theme: String
    var id: String { theme }
}
