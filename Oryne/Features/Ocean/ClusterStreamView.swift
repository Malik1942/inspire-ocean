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
    @State private var showCapture = false
    @Query(filter: #Predicate<Node> { !$0.isArchived }, sort: \Node.createdAt, order: .reverse)
    private var allNodes: [Node]

    private var members: [Node] {
        theme == OceanLayoutEngine.adriftKey
            ? allNodes.filter { $0.themes.isEmpty && $0.anchorThemeKey == nil }
            // Meaning match, plus thoughts spatially anchored here — an edited
            // thought stays in its current even when its chips moved on, and
            // the stream must agree with what the field shows.
            : allNodes.filter { $0.themes.contains(theme) || $0.anchorThemeKey == theme }
    }

    /// Currents this one overlaps by shared thoughts: the same relation the
    /// field lights on a long-press, made legible here too.
    private var related: [CurrentKinship] {
        OceanLayoutEngine.relatedCurrents(to: theme, among: allNodes)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    if !related.isEmpty { relatedRow }
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
                // No + for Adrift: its membership is defined by having no anchor
                // and no themes, so adding *into* it would be a contradiction.
                if theme != OceanLayoutEngine.adriftKey {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showCapture = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add a thought to this current")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.clear)
        // The familiar capture surface, opened into this current: the saved
        // node is anchored here (see CaptureView / CaptureSession.release), so
        // the live @Query drops it at the top of this stream on save. CaptureView
        // brings its own NavigationStack and, given the anchor context, its own
        // Done button — so it's presented directly. Sheet-over-sheet, fine on 17+.
        .sheet(isPresented: $showCapture) {
            CaptureView(intoCurrentThemeKey: theme)
        }
    }

    /// Just the concept and how much drifts in it — no decorative placeholder.
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            // The adrift gathering current is app-generated, so its name is
            // localized; real currents wear their concept keys.
            Text(theme == OceanLayoutEngine.adriftKey
                ? String(localized: "Adrift")
                : OceanLayoutEngine.displayLabel(for: theme))
                .font(.title3.weight(.semibold))
                .foregroundStyle(OceanTheme.foam)
            Text("\(members.count) thoughts drift here")
                .font(.caption)
                .foregroundStyle(OceanTheme.mist)
        }
        .padding(.bottom, 6)
    }

    /// The currents that share thoughts with this one, as quiet chips. No
    /// count, no line, just the names, so the overlap is legible without the
    /// field.
    private var relatedRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Related currents")
                .font(.caption)
                .foregroundStyle(OceanTheme.mist)
            FlowLayout(spacing: 8) {
                ForEach(related, id: \.key) { kin in
                    Text(OceanLayoutEngine.displayLabel(for: kin.key))
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .foregroundStyle(OceanTheme.foam)
                }
            }
        }
        .padding(.bottom, 4)
    }
}
