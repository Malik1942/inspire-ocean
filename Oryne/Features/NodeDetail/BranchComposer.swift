import SwiftUI
import SwiftData
import PhotosUI

/// Manual branching (§10): grow a connected fragment from an existing one.
/// The original is never edited — a new child `Node` is created and linked.
struct BranchComposer: View {
    let parent: Node
    /// Optional pre-filled text (e.g. accepting a suggested branch from Ask).
    var prefill: String = ""
    var prefillType: BranchType = .concept

    @Environment(\.modelContext) private var context
    @Environment(\.oceanAI) private var ai
    @Environment(\.dismiss) private var dismiss

    @State private var type: BranchType = .concept
    @State private var text: String = ""
    @State private var linkText: String = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var imageDatas: [Data] = []
    @State private var imageNotice: String?
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Link (optional)").font(.subheadline).foregroundStyle(OceanTheme.mist)
                        TextField("https://…", text: $linkText)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .foregroundStyle(OceanTheme.foam)
                            .padding(.vertical, 10).padding(.horizontal, 12)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Image (optional)").font(.subheadline).foregroundStyle(OceanTheme.mist)
                        if !imageDatas.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(imageDatas.enumerated()), id: \.offset) { index, data in
                                        if let ui = UIImage(data: data) {
                                            ZStack(alignment: .topTrailing) {
                                                Image(uiImage: ui)
                                                    .resizable().scaledToFill()
                                                    .frame(width: 84, height: 84)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                Button {
                                                    withAnimation {
                                                        guard imageDatas.indices.contains(index) else { return }
                                                        imageDatas.remove(at: index)
                                                        imageNotice = nil
                                                    }
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .symbolRenderingMode(.hierarchical)
                                                        .font(.title3)
                                                        .foregroundStyle(.white)
                                                        .padding(3)
                                                }
                                                .accessibilityLabel("Remove image")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if imageDatas.count < Node.maxImages {
                            PhotosPicker(
                                selection: $photoItems,
                                maxSelectionCount: Node.maxImages - imageDatas.count,
                                matching: .images
                            ) {
                                Label("Add image", systemImage: "photo")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Color.white.opacity(0.08), in: Capsule())
                                    .foregroundStyle(OceanTheme.foam)
                            }
                        }
                        if let imageNotice {
                            Text(imageNotice).font(.caption2).foregroundStyle(OceanTheme.faint)
                        }
                    }
                }
                .padding()
            }
            .background(OceanBackground())
            .contentShape(Rectangle())
            // Tapping outside the editor folds the keyboard; the editor and
            // the chips have their own gestures, so their taps still win.
            .onTapGesture { focused = false }
            .navigationTitle("Grow a branch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Grow") { grow() }
                        .disabled(text.trimmed.isEmpty && linkText.trimmed.isEmpty && imageDatas.isEmpty)
                }
            }
            .onAppear {
                if !prefill.isEmpty { text = prefill; type = prefillType }
                focused = true
            }
            .onChange(of: photoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    // Same shared downsample path as capture (1600px, off-main).
                    let loaded = await ImageDownsampler.attachmentData(from: newItems)
                    await MainActor.run {
                        let room = Node.maxImages - imageDatas.count
                        let accepted = Array(loaded.prefix(max(0, room)))
                        imageDatas.append(contentsOf: accepted)
                        imageNotice = loaded.count > accepted.count
                            ? String(localized: "Only added \(accepted.count), \(Node.maxImages) images max.")
                            : nil
                        photoItems = []
                    }
                }
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
        let link = linkText.trimmed.isEmpty ? nil : normalizedLink
        let kind: NodeKind = {
            if !text.trimmed.isEmpty { return .text }
            if !imageDatas.isEmpty { return .image }
            if link != nil { return .link }
            return .text
        }()
        let child = NodeComposer.make(
            kind: kind,
            text: text.trimmed,
            linkURLString: link,
            imageDatas: imageDatas,   // already downsampled on pick
            branchType: type,
            parent: parent
        )
        // Branches inherit a little of the parent's hue so clusters stay coherent.
        child.hue = (parent.hue + child.hue) / 2
        context.insert(child)
        try? context.save()
        if link != nil {
            LinkEnrichmentService.shared.enrich(nodeID: child.id, context: context, ai: ai)
        }
        dismiss()
    }

    private var normalizedLink: String {
        let t = linkText.trimmed
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return t }
        return "https://" + t
    }
}
