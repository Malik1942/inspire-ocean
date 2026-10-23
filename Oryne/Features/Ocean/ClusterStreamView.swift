import SwiftUI
import SwiftData

/// The inside of one current: its name, what can be done with all of it
/// (labelled, not bare glyphs), then every thought that expresses the
/// concept, newest first. Each tile opens the familiar thought page;
/// swiping it left archives or deletes it, a long press selects it. The
/// name renames the current. A pull-up sheet: no bar, no close; it swipes
/// away.
///
/// Membership is by *meaning*, not by storage: any thought whose themes
/// include the concept appears here, so a thought can surface in more than
/// one current. Conceptual regions overlap; folders don't.
struct ClusterStreamView: View {
    let theme: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var showCapture = false
    /// Thoughts opened from this stream, crossfaded in place on the sheet.
    @State private var path: [Node] = []
    /// The way back from a swiped delete or archive.
    @State private var removals = ThoughtRemovals()
    @Query(filter: #Predicate<Node> { !$0.isArchived }, sort: \Node.createdAt, order: .reverse)
    private var allNodes: [Node]
    @Query private var currentRows: [Current]

    /// Rename, and the split: pick thoughts, move them somewhere else.
    @State private var renaming = false
    @State private var newName = ""
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var moving = false

    private var isAdrift: Bool { theme == OceanLayoutEngine.adriftKey }

    /// The adrift gathering current is app-generated, so its name is
    /// localized; real currents wear their names (`CurrentDirectory`).
    private var title: String {
        isAdrift ? String(localized: "Adrift") : OceanLayoutEngine.displayLabel(for: theme)
    }

    /// `theme` is a current's key, or a theme's key from a thought's chips:
    /// the current's own thoughts, plus any thought whose theme keys name it.
    private var members: [Node] {
        isAdrift
            ? allNodes.filter { $0.currentKey == nil }
            : allNodes.filter { $0.currentKey == theme || $0.themeKeys.contains(theme) || $0.themes.contains(theme) }
    }

    private var currentRow: Current? { currentRows.first { $0.key == theme } }
    private var selectedNodes: [Node] { members.filter { selected.contains($0.id) } }

    var body: some View {
        NavigationStack {
            OceanFadeStack(path: $path) {
            List {
                header
                    .tileRow(top: Self.titleTop, bottom: OceanSpacing.block - OceanSpacing.item / 2)
                ForEach(members) { node in
                    if selecting {
                        // No swipes while picking.
                        Button {
                            if selected.contains(node.id) { selected.remove(node.id) } else { selected.insert(node.id) }
                        } label: {
                            HStack(spacing: OceanSpacing.item) {
                                Image(systemName: selected.contains(node.id) ? "checkmark.circle.fill" : "circle")
                                    .font(OceanType.glyph)
                                    .foregroundStyle(selected.contains(node.id) ? OceanTheme.accent : OceanTheme.mist)
                                NodeRow(node: node, showsCurrent: false)
                            }
                        }
                        .buttonStyle(.plain)
                        .tileRow()
                    } else {
                        Button { path.append(node) } label: { NodeRow(node: node, showsCurrent: false) }
                            .buttonStyle(.plain)
                            .thoughtSwipeActions(node, removals: removals)
                            // The split starts from a thought: a long press
                            // picks it, then others join with a tap.
                            .contextMenu {
                                if !isAdrift {
                                    Button {
                                        selected = [node.id]
                                        withAnimation(OceanMotion.quick) { selecting = true }
                                    } label: { Label("Select", systemImage: "checkmark.circle") }
                                }
                            }
                            .tileRow()
                    }
                }
            }
            .tileList()
            .contentMargins(.bottom, OceanSpacing.section, for: .scrollContent)
            .thoughtRemovalToast(removals)
            .background(OceanBackground())
            // Nothing in the bar: the sheet's grabber is its top edge, and a
            // pushed thought brings its own bar with the back button.
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if selecting, !selected.isEmpty {
                    Button { moving = true } label: {
                        Text("Move \(selected.count) to a current")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.oceanSecondary)
                    .padding(.horizontal, OceanSpacing.gutter)
                    .padding(.vertical, OceanSpacing.item)
                }
            }
            .alert("Rename current", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    if let currentRow { CurrentRegistry.rename(currentRow, to: newName, context: context) }
                }
            }
            .sheet(isPresented: $moving, onDismiss: { selecting = false; selected = [] }) {
                MoveToCurrentSheet(nodes: selectedNodes)
            }
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

    /// From the sheet's top edge to the current's name, clear of the grabber.
    private static let titleTop: CGFloat = OceanSpacing.sheetTop

    /// The current's name in New York with its + on the same line, a tool
    /// like a page's (the capture opens into this current); under it,
    /// Summarize as the one quiet verb: the whole stream goes to Ask as
    /// one grounded answer (SPEC, Ask: one mode). The name renames the
    /// current (Adrift has no name of its own to change, and nothing is
    /// added into it: its membership is having no current). While picking
    /// thoughts, Done takes the verb's place.
    private var header: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.inset) {
            HStack(alignment: .center, spacing: OceanSpacing.item) {
                if isAdrift {
                    titleText
                } else {
                    Button {
                        newName = title
                        renaming = true
                    } label: { titleText }
                    .buttonStyle(.plain)
                    .accessibilityHint("Renames this current.")
                }
                if !isAdrift, !selecting {
                    Button { showCapture = true } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.oceanIcon)
                    .accessibilityLabel("Add a thought")
                }
            }
            .frame(minHeight: OceanControlSize.height)
            if selecting {
                Button("Done") {
                    withAnimation(OceanMotion.quick) {
                        selecting = false
                        selected = []
                    }
                }
                .buttonStyle(.oceanSecondary)
            } else if members.count >= 2 {
                Button {
                    let ids = members.map(\.id)
                    dismiss()
                    appState.summarize(ids, title: title)
                } label: {
                    Label("Summarize", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .buttonStyle(.oceanSecondary)
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .font(OceanType.subjectTitle)
            .foregroundStyle(isAdrift ? OceanTheme.mist : OceanTheme.foam)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityAddTraits(.isHeader)
    }
}
