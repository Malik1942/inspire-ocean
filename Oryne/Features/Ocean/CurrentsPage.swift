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

/// All currents, readable and searchable. Each current is a card: collapsed
/// it shows the name and its newest thought in full; tapped, it opens in
/// place to every thought as a full-width row. Any thought is two taps away.
struct CurrentsPage: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Node> { !$0.isArchived }, sort: \Node.createdAt, order: .reverse)
    private var nodes: [Node]

    @State private var search = ""
    @State private var expanded: String?
    @State private var stream: StreamSelection?

    /// Rows shown inside an expanded current before "Open current".
    private static let expandedLimit = 8

    private var groups: [CurrentGroup] { CurrentGroup.build(from: nodes) }

    private var query: String { search.trimmed }

    /// Searching: a current stays when its name or one of its thoughts
    /// matches, and shows only the matching thoughts, expanded.
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
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if visible.isEmpty {
                            Text("Nothing drifts near this yet")
                                .font(.subheadline)
                                .foregroundStyle(OceanTheme.mist)
                                .padding(.top, 24)
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(visible, id: \.group.id) { entry in
                            card(entry.group, rows: entry.rows, forced: entry.forced)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Currents")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
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

    // MARK: Card

    private func card(_ group: CurrentGroup, rows: [Node], forced: Bool) -> some View {
        let isOpen = forced || expanded == group.key
        return GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Button {
                        guard !forced else { return }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            expanded = isOpen ? nil : group.key
                        }
                    } label: {
                        HStack {
                            Text(group.label)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(group.isAdrift ? OceanTheme.mist : OceanTheme.foam)
                                .lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(isOpen ? Text("Collapses this current.") : Text("Shows every thought in this current."))

                    Button { stream = StreamSelection(theme: group.key) } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.oceanIcon)
                    .accessibilityLabel("Open current")
                }

                if isOpen {
                    ForEach(Array(rows.prefix(Self.expandedLimit).enumerated()), id: \.element.id) { index, node in
                        if index > 0 { Divider().overlay(Color.white.opacity(0.08)) }
                        row(node)
                    }
                    if rows.count > Self.expandedLimit {
                        Divider().overlay(Color.white.opacity(0.08))
                        Button { stream = StreamSelection(theme: group.key) } label: {
                            HStack(spacing: 4) {
                                Text("Open current")
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OceanTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                } else if let newest = group.newest {
                    row(newest)
                }
            }
        }
        .opacity(group.isAdrift ? 0.7 : 1)
    }

    /// A thought as one full-width row: glyph and the whole title, two lines
    /// at most. The complete title, never a clipped chip.
    private func row(_ node: Node) -> some View {
        NavigationLink(value: node) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: node.kind.symbol)
                    .font(.caption2)
                    .foregroundStyle(OceanTheme.mist)
                    .frame(width: 14)
                Text(node.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A current chosen for its stream sheet.
struct StreamSelection: Identifiable {
    let theme: String
    var id: String { theme }
}
