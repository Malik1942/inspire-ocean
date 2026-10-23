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

    /// The tab's path, so a thought opens as a pushed page.
    @Binding var path: NavigationPath
    /// The way back from a delete. A delete only archives until the window
    /// closes, so the row it took is left out meanwhile.
    @State private var removals = ThoughtRemovals()

    var body: some View {
        let shown = archived.filter { !(removals.pending?.deletes($0) ?? false) }
        List {
            Text("Archived")
                .font(OceanType.subjectTitle)
                .foregroundStyle(OceanTheme.foam)
                .accessibilityAddTraits(.isHeader)
                .tileRow(top: OceanSpacing.gap, bottom: OceanSpacing.block - OceanSpacing.item / 2)
            if shown.isEmpty {
                Text("Nothing archived")
                    .font(OceanType.secondary)
                    .foregroundStyle(OceanTheme.mist)
                    .frame(maxWidth: .infinity)
                    .tileRow(top: OceanSpacing.block)
            }
            ForEach(shown) { node in
                Button { path.append(OceanDestination.thought(node)) } label: { NodeRow(node: node) }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { removals.delete(node) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .labelStyle(.iconOnly)
                        .tint(SwipeTint.delete)
                        Button { restore(node) } label: {
                            Label("Restore", systemImage: "arrow.up.bin")
                        }
                        .labelStyle(.iconOnly)
                        .tint(SwipeTint.archive)
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
        // A place: pushed, with the system's back button and the tab
        // bar stepped away, as a current.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .settlesThoughtRemovals(removals)
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
