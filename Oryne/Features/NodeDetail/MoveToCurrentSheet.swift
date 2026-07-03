import SwiftUI
import SwiftData

/// The quiet escape hatch: a picker of existing currents for the moment the
/// Ocean filed a thought somewhere it does not belong.
///
/// Choosing a current sets the node's `anchorThemeKey`, which is both the
/// move and the lock: `OceanLayoutEngine.currentKey` prefers the anchor over
/// the primary theme, and no understanding pass ever writes the anchor, so
/// the pipeline can never re-file this one thought. Everything else stays
/// fully AI managed, and moving again simply overwrites the anchor.
///
/// Deliberately minimal: existing currents only, no creation, no renaming,
/// no search. Selecting a row moves the thought and dismisses.
struct MoveToCurrentSheet: View {
    let node: Node

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Node> { !$0.isArchived }, sort: \Node.createdAt)
    private var allNodes: [Node]

    private struct CurrentChoice: Identifiable {
        let id: String        // concept key ("water & ocean")
        let label: String     // what the user reads ("Water & Ocean")
        let hue: Double
        let newestMember: Date
    }

    /// Existing currents, the most recently alive first: the same recency
    /// that drives prominence in the field and the Resurfacing rhythm.
    private var currents: [CurrentChoice] {
        var newest: [String: Date] = [:]
        for member in allNodes {
            guard let key = OceanLayoutEngine.currentKey(for: member) else { continue }
            newest[key] = max(newest[key] ?? .distantPast, member.createdAt)
        }
        return newest
            .map { key, date in
                CurrentChoice(
                    id: key,
                    label: OceanLayoutEngine.displayLabel(for: key),
                    hue: NodeComposer.hue(for: key),
                    newestMember: date
                )
            }
            .sorted { a, b in
                if a.newestMember != b.newestMember { return a.newestMember > b.newestMember }
                return a.id < b.id
            }
    }

    /// Where the thought lives right now, so the picker can say so.
    private var homeKey: String? { OceanLayoutEngine.currentKey(for: node) }

    var body: some View {
        NavigationStack {
            ZStack {
                OceanBackground(animated: false)
                if currents.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Move to a current")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("It will stay where you put it.")
                    .font(.footnote)
                    .foregroundStyle(OceanTheme.mist)
                    .padding(.bottom, 2)
                ForEach(currents) { current in
                    row(current)
                }
            }
            .padding()
            .padding(.bottom, 32)
        }
    }

    private func row(_ current: CurrentChoice) -> some View {
        Button {
            move(to: current.id)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(OceanTheme.color(forHue: current.hue, brightness: 0.85).opacity(0.30))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                    .frame(width: 14, height: 14)
                Text(current.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OceanTheme.foam)
                    .lineLimit(1)
                Spacer()
                if current.id == homeKey {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OceanTheme.mist)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Color.white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(current.id == homeKey ? [.isSelected] : [])
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "water.waves")
                .font(.system(size: 34))
                .foregroundStyle(OceanTheme.surface)
            Text("No currents yet")
                .font(.subheadline)
                .foregroundStyle(OceanTheme.mist)
        }
    }

    /// The move and the lock in one write. `updatedAt` is stamped the way
    /// every other user change stamps it; the Ocean's layout signature sees
    /// the new membership and the field re-forms on its own.
    private func move(to key: String) {
        node.anchorThemeKey = key
        node.updatedAt = .now
        try? context.save()
        dismiss()
    }
}
