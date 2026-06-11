import SwiftUI
import SwiftData

/// The inside of one current: a stream of every thought that expresses the
/// concept, newest first. Tapping a current in the Ocean opens this; each row
/// opens the familiar thought detail.
///
/// Membership is by *meaning*, not by storage: any thought whose themes
/// include the concept appears here, so a thought can surface in more than
/// one current — conceptual regions overlap, folders don't.
struct ClusterStreamView: View {
    let theme: String

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Node> { !$0.isArchived }, sort: \Node.createdAt, order: .reverse)
    private var allNodes: [Node]

    private var members: [Node] {
        theme == OceanLayoutEngine.adriftKey
            ? allNodes.filter { $0.themes.isEmpty }
            : allNodes.filter { $0.themes.contains(theme) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    ForEach(members) { node in
                        NavigationLink { NodeDetailContent(node: node) } label: {
                            NodeRow(node: node)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .padding(.bottom, 32)
            }
            .background(OceanBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.clear)
    }

    /// Just the concept and how much drifts in it — no decorative placeholder.
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(OceanLayoutEngine.displayLabel(for: theme))
                .font(.title3.weight(.semibold))
                .foregroundStyle(OceanTheme.foam)
            Text("\(members.count) thought\(members.count == 1 ? "" : "s") drift here")
                .font(.caption)
                .foregroundStyle(OceanTheme.mist)
        }
        .padding(.bottom, 6)
    }
}
