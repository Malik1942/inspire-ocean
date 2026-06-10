import SwiftUI
import SwiftData

/// Manual branching (§10): grow a connected fragment from an existing one.
/// The original is never edited — a new child `Node` is created and linked.
struct BranchComposer: View {
    let parent: Node
    /// Optional pre-filled text (e.g. accepting a suggested branch from Ask).
    var prefill: String = ""
    var prefillType: BranchType = .concept

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var type: BranchType = .concept
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Branching from").font(.caption).foregroundStyle(OceanTheme.mist)
                            Text(parent.displayTitle)
                                .font(.subheadline.weight(.medium)).foregroundStyle(OceanTheme.foam)
                                .lineLimit(2)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Branch type").font(.headline).foregroundStyle(OceanTheme.foam)
                        FlowLayout(spacing: 10) {
                            ForEach(BranchType.allCases) { bt in
                                branchChip(bt)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(type.prompt).font(.subheadline).foregroundStyle(OceanTheme.mist)
                        GlassCard {
                            TextEditor(text: $text)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 140)
                                .foregroundStyle(OceanTheme.foam)
                                .focused($focused)
                        }
                    }
                }
                .padding()
            }
            .background(OceanBackground())
            .navigationTitle("Grow a branch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Grow") { grow() }
                        .disabled(text.trimmed.isEmpty)
                }
            }
            .onAppear {
                if !prefill.isEmpty { text = prefill; type = prefillType }
                focused = true
            }
        }
    }

    private func branchChip(_ bt: BranchType) -> some View {
        Button { type = bt } label: {
            Label(bt.label, systemImage: bt.symbol)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(
                    Capsule().fill(type == bt ? OceanTheme.accent.opacity(0.9) : Color.white.opacity(0.08))
                )
                .foregroundStyle(type == bt ? OceanTheme.abyss : OceanTheme.foam)
        }
        .buttonStyle(.plain)
    }

    private func grow() {
        let child = NodeComposer.make(
            kind: .text,
            text: text.trimmed,
            branchType: type,
            parent: parent
        )
        // Branches inherit a little of the parent's hue so clusters stay coherent.
        child.hue = (parent.hue + child.hue) / 2
        context.insert(child)
        try? context.save()
        dismiss()
    }
}
