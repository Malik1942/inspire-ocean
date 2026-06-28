import SwiftUI
import SwiftData

/// Expanded Node View (§9): a lightweight contextual layer around a single
/// fragment — "zooming into the atmosphere around an idea."
struct ExpandedNodeView: View {
    let node: Node

    var body: some View {
        NavigationStack {
            // Presented as a sheet root: it owns a leading "Close" to dismiss,
            // so the trailing slot is free for the destructive action.
            NodeDetailContent(node: node, isSheetRoot: true)
        }
        .presentationDetents([.large])
        .presentationBackground(.clear)
    }
}

struct NodeDetailContent: View {
    let node: Node
    /// True only when this is the root of a presented sheet (so it shows its
    /// own leading "Close"). When pushed onto a navigation stack the system
    /// supplies a back button, so the leading slot is left to it.
    var isSheetRoot: Bool = false

    @Environment(\.modelContext) private var context
    @Environment(\.oceanAI) private var ai
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Node> { !$0.isArchived }) private var allNodes: [Node]

    @State private var showBranchComposer = false
    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false
    @State private var editFocusesBody = false
    @State private var relatedIDs: [UUID] = []

    private var related: [Node] {
        let byID = Dictionary(uniqueKeysWithValues: allNodes.map { ($0.id, $0) })
        return relatedIDs.compactMap { byID[$0] }
    }

    private var children: [Node] {
        (node.children ?? []).filter { !$0.isArchived }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                contentCard
                whyItMattered
                if !node.themes.isEmpty { themesSection }
                if !children.isEmpty { branchesSection }
                relatedSection
                actions
            }
            .padding()
            .padding(.bottom, 40)
        }
        .background(OceanBackground())
        .navigationTitle(node.kind.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Only a sheet root needs its own dismiss control; a pushed view
            // already has the system back button on the leading side.
            if isSheetRoot {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editFocusesBody = false
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit thought")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        // The original system confirmation (the chat-bubble popover). A Liquid
        // Glass alternative is kept in OceanConfirmationDialog.swift — to switch,
        // replace this whole modifier with:
        //   .oceanConfirmationDialog(
        //       isPresented: $showDeleteConfirm,
        //       title: "Delete this thought?",
        //       message: "This drifts out of the Ocean for good.",
        //       confirmTitle: "Delete", onConfirm: deleteNode)
        .confirmationDialog(
            "Delete this thought?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteNode() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This drifts out of the Ocean for good.")
        }
        .sheet(isPresented: $showBranchComposer) {
            BranchComposer(parent: node)
        }
        .sheet(isPresented: $showEditSheet) {
            NodeEditSheet(node: node, focusBodyOnAppear: editFocusesBody)
        }
        .task(id: node.id) {
            relatedIDs = ai.relatedNodeIDs(to: node, among: allNodes, limit: 4)
        }
    }

    /// Removes the fragment and leaves this view (pops if pushed, dismisses the
    /// sheet if presented). `deleteNodeSafely` archives the subtree out of every
    /// query before detaching it, so neither this view nor a Library row / Ocean
    /// mote faults on a deleted node (see its doc); dismissing alongside is then
    /// purely cosmetic.
    private func deleteNode() {
        context.deleteNodeSafely(node)
        dismiss()
    }

    // MARK: Sections

    private var contentCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                if let data = node.imageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                if let transcription = node.transcription, !transcription.isEmpty {
                    HStack {
                        Label("Transcript", systemImage: "waveform")
                            .font(.caption).foregroundStyle(OceanTheme.mist)
                        Spacer()
                        // The transcript is the thought; the recording is a
                        // quiet receipt, present only while it's retained.
                        if let data = node.audioData, !data.isEmpty {
                            ListenChip(data: data)
                        }
                    }
                    Text(transcription).foregroundStyle(OceanTheme.foam)
                } else if node.kind == .voice {
                    HStack {
                        // Honest about state: "transcribing" only while a pass
                        // can plausibly still be running; after that, the words
                        // are simply missing and the recovery is one tap away.
                        Label(
                            node.createdAt.timeIntervalSinceNow > -120 ? "Transcribing…" : "No words yet",
                            systemImage: "waveform"
                        )
                        .font(.caption).foregroundStyle(OceanTheme.mist)
                        Spacer()
                        if let data = node.audioData, !data.isEmpty {
                            ListenChip(data: data)
                        }
                    }
                    if node.createdAt.timeIntervalSinceNow <= -120 {
                        Text("Tap to type the words or re-transcribe.")
                            .font(.caption2).foregroundStyle(OceanTheme.faint)
                    }
                }
                if !node.text.isEmpty {
                    Text(node.text)
                        .font(.body).foregroundStyle(OceanTheme.foam)
                }
                if let url = node.linkURL {
                    Link(destination: url) {
                        Label(url.absoluteString, systemImage: "link")
                            .font(.callout).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Tapping the words themselves is how corrections will actually be
        // discovered — same sheet as the toolbar pencil, text focused.
        .onTapGesture {
            editFocusesBody = true
            showEditSheet = true
        }
    }

    private var whyItMattered: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Captured")
                    .font(.caption2).foregroundStyle(OceanTheme.faint)
                Text(node.createdAt.formatted(.relative(presentation: .named)))
                    .font(.subheadline).foregroundStyle(OceanTheme.foam)
            }
            if let branchType = node.branchType {
                Divider().frame(height: 28).overlay(OceanTheme.faint)
                Label(branchType.label, systemImage: branchType.symbol)
                    .font(.caption).foregroundStyle(OceanTheme.accent)
            }
            if let mood = node.mood {
                Divider().frame(height: 28).overlay(OceanTheme.faint)
                Label(mood, systemImage: mood == "bright" ? "sun.max" : "moon.stars")
                    .font(.caption).foregroundStyle(OceanTheme.glowWarm)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var themesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Themes")
            FlowLayout(spacing: 8) {
                ForEach(node.themes, id: \.self) { ThemeTag(text: $0, hue: node.hue) }
            }
        }
    }

    private var branchesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Branches grown from this")
            ForEach(children) { child in
                NavigationLink { NodeDetailContent(node: child) } label: {
                    NodeRow(node: child)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Nearby thoughts")
            if related.isEmpty {
                Text("Nothing drifts nearby yet.")
                    .font(.subheadline).foregroundStyle(OceanTheme.faint)
            } else {
                ForEach(related) { other in
                    NavigationLink { NodeDetailContent(node: other) } label: {
                        NodeRow(node: other)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button { showBranchComposer = true } label: {
                Label("Grow a branch", systemImage: "arrow.triangle.branch")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .background(OceanTheme.accent.opacity(0.9), in: Capsule())
            .foregroundStyle(OceanTheme.abyss)

            Button {
                appState.ask("About “\(node.displayTitle)” — ")
                dismiss()
            } label: {
                Label("Ask Ocean", systemImage: "quote.bubble")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .background(Color.white.opacity(0.10), in: Capsule())
            .foregroundStyle(OceanTheme.foam)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline).foregroundStyle(OceanTheme.foam)
    }
}
