import SwiftUI
import SwiftData

/// Where an archived thought waits, newest archived first: the Library's
/// Archived, the way Recently Deleted closes Notes' folders. Opened from the
/// end of the Library's Currents, it reads like a current's stream: its
/// name in New York, then rows. A thought swipes back with Restore, or away
/// for good with Delete, which keeps the same ten seconds of Undo as a
/// delete anywhere else.
struct ArchivedThoughtsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<Node> { $0.isArchived }, sort: \Node.updatedAt, order: .reverse)
    private var archived: [Node]

    /// Thoughts opened from here. A path, not `NavigationLink`s: a link in a
    /// `List` draws a chevron the tiles don't wear.
    @State private var path: [Node] = []
    /// The way back from a delete. A delete only archives until the window
    /// closes, so the row it took is left out meanwhile.
    @State private var removals = ThoughtRemovals()

    var body: some View {
        let shown = archived.filter { !(removals.pending?.deletes($0) ?? false) }
        NavigationStack(path: $path) {
            List {
                Text("Archived")
                    .font(OceanType.subjectTitle)
                    .foregroundStyle(OceanTheme.foam)
                    .accessibilityAddTraits(.isHeader)
                    .tileRow(top: OceanSpacing.tight, bottom: OceanSpacing.block - OceanSpacing.item / 2)
                if shown.isEmpty {
                    Text("Nothing archived")
                        .font(OceanType.secondary)
                        .foregroundStyle(OceanTheme.mist)
                        .frame(maxWidth: .infinity)
                        .tileRow(top: OceanSpacing.block)
                }
                ForEach(shown) { node in
                    Button { path.append(node) } label: { NodeRow(node: node) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { removals.delete(node) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                            Button { restore(node) } label: {
                                Label("Restore", systemImage: "arrow.up.bin")
                            }
                            .tint(.gray)
                        }
                        // Read last first, as with the discs: Restore, then Delete.
                        .accessibilityActions {
                            Button("Delete") { removals.delete(node) }
                            Button("Restore") { restore(node) }
                        }
                        .tileRow()
                }
            }
            .tileList()
            .contentMargins(.bottom, OceanSpacing.section, for: .scrollContent)
            .thoughtRemovalToast(removals)
            .background(OceanBackground())
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Node.self) { node in
                NodeDetailContent(node: node)
            }
        }
        .settlesThoughtRemovals(removals)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        // A summary or a question opens in Ask: step out of the way.
        .onChange(of: appState.selectedTab) { _, tab in
            if tab == .ask { dismiss() }
        }
    }

    /// Back among the live thoughts, where it was. Its branches never left.
    private func restore(_ node: Node) {
        withAnimation(OceanMotion.standard) {
            node.isArchived = false
            node.updatedAt = .now
        }
        try? context.save()
    }
}
