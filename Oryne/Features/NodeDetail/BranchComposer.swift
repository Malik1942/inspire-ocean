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
                VStack(alignment: .leading, spacing: OceanSpacing.block) {
                    OceanSheetHeader(title: Text("Grow a branch")) {
                        Button("Grow") { grow() }
                            .buttonStyle(.oceanPrimary)
                            .disabled(text.trimmed.isEmpty && linkText.trimmed.isEmpty && imageDatas.isEmpty)
                    }
                    // Where the branch grows from: a tile, as the thought is
                    // shown everywhere else.
                    VStack(alignment: .leading, spacing: OceanSpacing.snug) {
                        Text("Branching from").font(OceanType.eyebrow).foregroundStyle(OceanTheme.mist)
                        Text(parent.displayTitle)
                            .font(OceanType.tileTitle).foregroundStyle(OceanTheme.foam)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OceanSpacing.inset)
                    .background(OceanSurface(shape: RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)))

                    VStack(alignment: .leading, spacing: OceanSpacing.gap) {
                        sectionTitle(Text("Branch type"))
                        FlowLayout(spacing: OceanSpacing.gap) {
                            ForEach(BranchType.allCases) { bt in
                                branchChip(bt)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: OceanSpacing.gap) {
                        sectionTitle(Text(type.prompt))
                        TranscriptEditor(text: $text, isEditable: true, minHeight: 140, maxHeight: 240, focus: $focused)
                    }

                    VStack(alignment: .leading, spacing: OceanSpacing.gap) {
                        sectionTitle(Text("Link"))
                        TextField("https://…", text: $linkText)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .oceanField()
                    }

                    VStack(alignment: .leading, spacing: OceanSpacing.gap) {
                        sectionTitle(Text("Image"))
                        if !imageDatas.isEmpty {
                            OceanPictureStrip(datas: imageDatas) { index in
                                withAnimation(OceanMotion.standard) {
                                    guard imageDatas.indices.contains(index) else { return }
                                    imageDatas.remove(at: index)
                                    imageNotice = nil
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
                            }
                            .buttonStyle(.oceanSecondary)
                        }
                        if let imageNotice {
                            Text(imageNotice).font(OceanType.note).foregroundStyle(OceanTheme.faint)
                        }
                    }
                }
                .padding(.horizontal, OceanSpacing.gutter)
                .padding(.top, OceanSpacing.gap)
                .padding(.bottom, OceanSpacing.section)
            }
            .background(OceanBackground())
            .contentShape(Rectangle())
            // Tapping outside the editor folds the keyboard; the editor and
            // the chips have their own gestures, so their taps still win.
            .onTapGesture { focused = false }
            .toolbar(.hidden, for: .navigationBar)
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

    /// A field's name: an eyebrow right above what it names, as in the
    /// edit sheet.
    private func sectionTitle(_ text: Text) -> some View {
        text
            .font(OceanType.eyebrow).foregroundStyle(OceanTheme.mist)
    }

    /// One branch type among several: a Secondary chip, selected when it
    /// is the one.
    private func branchChip(_ bt: BranchType) -> some View {
        Button { type = bt } label: {
            Label(bt.label, systemImage: bt.symbol)
        }
        .buttonStyle(.oceanSecondary(selected: type == bt))
        .accessibilityAddTraits(type == bt ? .isSelected : [])
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
        if !imageDatas.isEmpty {
            PictureEnrichmentService.shared.enrich(nodeID: child.id, context: context, ai: ai)
        }
        dismiss()
    }

    private var normalizedLink: String {
        let t = linkText.trimmed
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return t }
        return "https://" + t
    }
}
