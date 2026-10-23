import SwiftUI
import SwiftData

/// The quiet escape hatch: a picker of currents for the moment the Ocean
/// filed a thought somewhere it does not belong, and the way a current is
/// split: pick thoughts in a current's stream, move them here into another
/// current or into a new one named on the spot.
///
/// Choosing a current writes `anchorThemeKey` and the pin on every thought
/// (`CurrentRegistry.move`): the move is the lock, and no understanding pass
/// re-files a pinned thought. Moving again simply overwrites it.
struct MoveToCurrentSheet: View {
    let nodes: [Node]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Node> { !$0.isArchived }, sort: \Node.createdAt)
    private var allNodes: [Node]

    @State private var naming = false
    @State private var newName = ""

    init(node: Node) { self.nodes = [node] }
    init(nodes: [Node]) { self.nodes = nodes }

    private struct CurrentChoice: Identifiable {
        let id: String        // the key ("light-and-color")
        let label: String     // what the user reads ("Light and Color")
        let hue: Double
        let newestMember: Date
    }

    /// Existing currents, the most recently alive first: the same recency
    /// that drives Tide and the Resurfacing rhythm.
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

    /// Where the thought lives right now, so the picker can say so. Only
    /// when every thought moved shares a home.
    private var homeKey: String? {
        let keys = Set(nodes.compactMap { OceanLayoutEngine.currentKey(for: $0) })
        return keys.count == 1 ? keys.first : nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OceanBackground(animated: false)
                list
            }
            .navigationTitle(nodes.count == 1 ? Text("Move to a current") : Text("Move \(nodes.count) to a current"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New current", isPresented: $naming) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { newName = "" }
                Button("Move") { moveToNew() }
            } message: {
                Text("The thoughts you chose start it.")
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
                newCurrentRow
                ForEach(currents) { current in
                    row(current)
                }
            }
            .padding()
            .padding(.bottom, 32)
        }
    }

    /// A split, or a home that does not exist yet: name it, and the chosen
    /// thoughts found it.
    private var newCurrentRow: some View {
        Button { naming = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OceanTheme.mist)
                    .frame(width: 14)
                Text("New current…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OceanTheme.foam)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
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

    private func move(to key: String) {
        CurrentRegistry.move(nodes, toKey: key, context: context)
        dismiss()
    }

    private func moveToNew() {
        let name = newName.trimmed
        newName = ""
        guard !name.isEmpty else { return }
        CurrentRegistry.move(nodes, toKey: ThoughtReading.slug(name), name: name, context: context)
        dismiss()
    }
}
