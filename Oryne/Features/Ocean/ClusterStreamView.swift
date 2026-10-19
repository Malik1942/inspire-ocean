import SwiftUI
import SwiftData

/// The inside of one current: its name, what can be done with all of it
/// (labelled, not bare glyphs), then every thought that expresses the
/// concept, newest first. Each tile opens the familiar thought page.
///
/// Membership is by *meaning*, not by storage: any thought whose themes
/// include the concept appears here, so a thought can surface in more than
/// one current. Conceptual regions overlap; folders don't.
struct ClusterStreamView: View {
    let theme: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var showCapture = false
    @Query(filter: #Predicate<Node> { !$0.isArchived }, sort: \Node.createdAt, order: .reverse)
    private var allNodes: [Node]

    private var isAdrift: Bool { theme == OceanLayoutEngine.adriftKey }

    /// The adrift gathering current is app-generated, so its name is
    /// localized; real currents wear their concept keys.
    private var title: String {
        isAdrift ? String(localized: "Adrift") : OceanLayoutEngine.displayLabel(for: theme)
    }

    private var members: [Node] {
        isAdrift
            ? allNodes.filter { $0.themes.isEmpty && $0.anchorThemeKey == nil }
            // Meaning match, plus thoughts anchored here: an edited thought
            // stays in its current even when its themes moved on.
            : allNodes.filter { $0.themes.contains(theme) || $0.anchorThemeKey == theme }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OceanSpacing.item) {
                    header
                        .padding(.bottom, OceanSpacing.block - OceanSpacing.item)
                    ForEach(members) { node in
                        NavigationLink { NodeDetailContent(node: node) } label: {
                            NodeRow(node: node)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, OceanSpacing.gutter)
                .padding(.top, 4)
                .padding(.bottom, OceanSpacing.section)
            }
            .background(OceanBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.clear)
        // A summary or a question opens in Ask: step out of the way.
        .onChange(of: appState.selectedTab) { _, tab in
            if tab == .ask { dismiss() }
        }
        // The one capture surface, opened into this current: the saved node
        // is anchored here (CaptureSession.release), so the live @Query drops
        // it at the top of this stream on save. Sheet-over-sheet, fine on 17+.
        .sheet(isPresented: $showCapture) {
            FastCaptureSessionView(
                request: FastCaptureRequest(
                    source: .inApp,
                    inputPreference: .typingFirst,
                    anchorThemeKey: theme
                ),
                onFinish: { showCapture = false },
                asSheet: true
            )
            .presentationDetents([.large])
            .presentationBackground(.clear)
        }
    }

    /// The current's name in New York, then its two verbs as Secondary
    /// buttons: read it all as one answer, or add a thought into it.
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(OceanType.subjectTitle)
                .foregroundStyle(isAdrift ? OceanTheme.mist : OceanTheme.foam)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if members.count >= 2 || !isAdrift {
                HStack(spacing: 8) {
                    // Summarize is a verb, not a mode: the whole stream goes
                    // to Ask as one grounded answer (SPEC, Ask: one mode).
                    if members.count >= 2 {
                        Button {
                            let ids = members.map(\.id)
                            dismiss()
                            appState.summarize(ids, title: title)
                        } label: {
                            Label("Summarize", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        .buttonStyle(.oceanSecondary)
                    }
                    // No adding into Adrift: its membership is having no
                    // current, so adding into it would be a contradiction.
                    if !isAdrift {
                        Button { showCapture = true } label: {
                            Label("Add a thought", systemImage: "plus")
                        }
                        .buttonStyle(.oceanSecondary)
                    }
                }
            }
        }
    }
}
