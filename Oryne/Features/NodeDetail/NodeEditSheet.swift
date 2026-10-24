import SwiftUI
import SwiftData
import PhotosUI

/// Corrects a captured fragment: title, body (or voice transcript), themes.
/// The audio, when present, is a temporary substrate for understanding —
/// only its interpretation is edited here, and the transcript is the artifact.
///
/// Edits land on draft copies, not live bindings, so Cancel is a true no-op
/// and CloudKit only ever sees saved state. Saving marks the touched fields
/// as user-owned — from then on the system fills blanks but never overwrites
/// them — and anchors the thought in its current so corrections don't move it.
struct NodeEditSheet: View {
    let node: Node
    /// Set when the sheet is opened by tapping the text itself — the body
    /// field comes up focused, ready to fix the misheard word.
    var focusBodyOnAppear = false

    @Environment(\.modelContext) private var context
    @Environment(\.oceanAI) private var ai
    @Environment(\.dismiss) private var dismiss

    @State private var titleDraft = ""
    @State private var bodyDraft = ""
    @State private var noteDraft = ""
    @State private var themesDraft: [String] = []
    @State private var linkDraft = ""
    @State private var newTheme = ""
    @State private var themeInputNotice: String?

    // Images edited on a draft array (like the link), so Cancel is a true no-op.
    // `imageChanged` is the dirty flag — any add/remove flips it; Save replaces
    // the node's image set only when it's set.
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var imageDrafts: [Data] = []
    @State private var imageChanged = false
    @State private var imageNotice: String?

    @State private var originalTitle = ""
    @State private var originalBody = ""
    @State private var originalNote = ""
    @State private var originalThemes: [String] = []
    @State private var originalLink = ""

    @State private var isTranscribing = false
    @State private var retranscribeFailed = false
    @State private var bodyBeforeRetranscribe: String?
    @State private var showReplaceConfirm = false
    @State private var isRederiving = false

    @State private var loaded = false
    @FocusState private var bodyFocused: Bool

    private var isVoice: Bool { node.kind == .voice }

    /// Voice drifts can carry a typed note alongside the transcript
    /// (Fast Capture's "a few words, if needed").
    private var hasNote: Bool { isVoice && !node.text.isEmpty }

    /// Whether the draft moved away from the last machine transcription.
    private var transcriptDiverged: Bool {
        isVoice && bodyDraft.trimmed != (node.transcription ?? "").trimmed
    }

    private var hasChanges: Bool {
        titleDraft != originalTitle
            || bodyDraft != originalBody
            || noteDraft != originalNote
            || themesDraft != originalThemes
            || normalizedLinkDraft != originalLink
            || imageChanged
    }

    /// The typed link, normalized the same way capture does (bare host → https),
    /// or "" when cleared. Compared against `originalLink` to detect a change.
    private var normalizedLinkDraft: String {
        let t = linkDraft.trimmed
        guard !t.isEmpty else { return "" }
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return t }
        return "https://" + t
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OceanSpacing.block) {
                    OceanSheetHeader(title: Text("Edit")) {
                        Button("Save", action: save)
                            .buttonStyle(.oceanPrimary)
                    }
                    titleSection
                    bodySection
                    if hasNote { noteSection }
                    if let audioData = node.audioData {
                        audioSection(audioData)
                    }
                    themesSection
                    rederiveSection
                    // Attachments live at the bottom, matching the read view's
                    // "Reference" grouping (below the thought's own fields).
                    imageSection
                    linkSection
                    AmbientHint(hint: .ownership)
                }
                .padding(.horizontal, OceanSpacing.gutter)
                .padding(.top, OceanSpacing.gap)
                .padding(.bottom, OceanSpacing.section)
            }
            .background(OceanBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear(perform: loadDrafts)
    }

    // MARK: Sections

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.gap) {
            sectionTitle("Title")
            TextField("A few words it goes by", text: $titleDraft)
                .textFieldStyle(.plain)
                .oceanField()
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.gap) {
            sectionTitle(isVoice ? "Transcript" : "Thought")
            TranscriptEditor(
                text: $bodyDraft,
                isEditable: true,
                placeholder: isVoice ? "What was said" : "What drifted by",
                minHeight: 120,
                maxHeight: 240,
                focus: $bodyFocused
            )
            if transcriptDiverged {
                Label("Edited transcript: the original words stay yours.", systemImage: "waveform")
                    .font(OceanType.note).foregroundStyle(OceanTheme.faint)
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.gap) {
            sectionTitle("Note")
            TranscriptEditor(
                text: $noteDraft,
                isEditable: true,
                minHeight: 60,
                maxHeight: 120
            )
        }
    }

    /// Quiet, not a player row: the recording is provenance, the transcript
    /// is the thought.
    private func audioSection(_ data: Data) -> some View {
        VStack(alignment: .leading, spacing: OceanSpacing.gap) {
            HStack(spacing: OceanSpacing.gap) {
                ListenChip(data: data)

                Button {
                    retranscribeTapped(data)
                } label: {
                    HStack(spacing: OceanSpacing.snug) {
                        if isTranscribing {
                            ProgressView().controlSize(.small)
                            Text("Listening again…")
                        } else {
                            Label("Re-transcribe", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }
                .buttonStyle(.oceanSecondary)
                .disabled(isTranscribing)

                if let previous = bodyBeforeRetranscribe {
                    Button {
                        bodyDraft = previous
                        bodyBeforeRetranscribe = nil
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.oceanSecondary)
                }
            }

            if retranscribeFailed {
                Text("Couldn't hear it again. Your words stay as they are.")
                    .font(OceanType.note).foregroundStyle(OceanTheme.faint)
            }

            Text("Original audio is temporarily preserved to improve understanding.")
                .font(OceanType.note).foregroundStyle(OceanTheme.faint)
        }
        .alert(
            "Replace your edited words?",
            isPresented: $showReplaceConfirm
        ) {
            Button("Re-transcribe and replace") {
                Task { await retranscribe(data) }
            }
            Button("Keep my words", role: .cancel) {}
        } message: {
            Text("A fresh transcription will replace the transcript you edited. You can restore it afterwards.")
        }
    }

    /// Add / remove the image on a draft (downsampled through the shared path,
    /// like capture), so Cancel is a true no-op. Pre-populated from the node's
    /// existing image.
    private var imageSection: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.gap) {
            sectionTitle("Images")
            if !imageDrafts.isEmpty {
                OceanPictureStrip(datas: imageDrafts) { index in
                    withAnimation(OceanMotion.standard) {
                        guard imageDrafts.indices.contains(index) else { return }
                        imageDrafts.remove(at: index)
                        imageChanged = true
                        imageNotice = nil
                    }
                }
            }
            if imageDrafts.count < Node.maxImages {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: Node.maxImages - imageDrafts.count,
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
        .onChange(of: photoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                // Same shared downsample path as capture (1600px, off-main).
                let loaded = await ImageDownsampler.attachmentData(from: newItems)
                await MainActor.run {
                    let room = Node.maxImages - imageDrafts.count
                    let accepted = Array(loaded.prefix(max(0, room)))
                    imageDrafts.append(contentsOf: accepted)
                    imageChanged = true
                    imageNotice = loaded.count > accepted.count
                        ? String(localized: "Only added \(accepted.count), \(Node.maxImages) images max.")
                        : nil
                    photoItems = []
                }
            }
        }
    }

    /// Add / replace / remove a link on a draft, so Cancel is a true no-op.
    /// Enrichment only fires on Save (against the committed node) — never from
    /// inside the draft.
    private var linkSection: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.gap) {
            sectionTitle("Link")
            if node.linkURLString != nil, normalizedLinkDraft == originalLink, !originalLink.isEmpty {
                // The committed link, untouched — show it as the rich card it is,
                // with a control to drift it off the thought.
                LinkCard(node: node, onRemove: { withAnimation { linkDraft = "" } })
            } else {
                TextField("https://…", text: $linkDraft)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .oceanField()
                if !normalizedLinkDraft.isEmpty, normalizedLinkDraft != originalLink {
                    Text("Saved links are read and summarized on-device for context.")
                        .font(OceanType.note).foregroundStyle(OceanTheme.faint)
                }
            }
        }
    }

    private var themesSection: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.gap) {
            sectionTitle("Themes")
            if !themesDraft.isEmpty {
                FlowLayout(spacing: OceanSpacing.gap) {
                    ForEach(themesDraft, id: \.self) { theme in
                        editableThemeChip(theme)
                    }
                }
            }
            OceanAddField(text: $newTheme, prompt: "Add a theme", onAdd: addTheme)

            if let themeInputNotice {
                Text(themeInputNotice)
                    .font(OceanType.note).foregroundStyle(OceanTheme.faint)
            }

            if themesDraft != originalThemes {
                AmbientHint(hint: .semanticDrift)
            }
        }
    }

    /// Regeneration is an offer, never an ambush: the system re-reads the
    /// words only when asked, and the result is still just a draft.
    private var rederiveSection: some View {
        Button {
            Task { await rederive() }
        } label: {
            HStack(spacing: OceanSpacing.snug) {
                if isRederiving {
                    ProgressView().controlSize(.small)
                    Text("Re-reading…")
                } else {
                    Label("Re-derive title & themes from the words", systemImage: "sparkles")
                }
            }
        }
        .buttonStyle(.oceanSecondary)
        .disabled(isRederiving || bodyDraft.trimmed.isEmpty)
    }

    /// A theme on the draft, the same Secondary chip as on the thought's
    /// page, with its ✕: tapping it takes the theme off.
    private func editableThemeChip(_ theme: String) -> some View {
        Button {
            themesDraft.removeAll { $0 == theme }
        } label: {
            HStack(spacing: OceanSpacing.snug) {
                Text(theme)
                Image(systemName: "xmark")
                    .font(OceanType.glyphSmall)
                    .foregroundStyle(OceanTheme.mist)
            }
        }
        .buttonStyle(.oceanSecondary)
        .accessibilityLabel("Remove theme \(theme)")
    }

    /// A field's name: an eyebrow right above what it names, as on a
    /// thought's page.
    private func sectionTitle(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(OceanType.eyebrow).foregroundStyle(OceanTheme.mist)
    }

    // MARK: Actions

    private func loadDrafts() {
        guard !loaded else { return }
        loaded = true
        titleDraft = node.title
        bodyDraft = isVoice ? (node.transcription ?? "") : node.text
        noteDraft = hasNote ? node.text : ""
        themesDraft = node.themes
        linkDraft = node.linkURLString ?? ""
        imageDrafts = node.imageDatas
        imageChanged = false
        originalTitle = titleDraft
        originalBody = bodyDraft
        originalNote = noteDraft
        originalThemes = themesDraft
        originalLink = node.linkURLString ?? ""
        if focusBodyOnAppear {
            // Focus can only land once the editor exists in the hierarchy.
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                bodyFocused = true
            }
        }
    }

    /// Same normalization the capture pipeline applies: lowercase, trimmed,
    /// deduplicated — and never a silent swallow.
    private func addTheme() {
        let raw = newTheme.trimmed
        guard !raw.isEmpty else { return }
        let tidied = SemanticThemes.tidyThemeList(raw)
        guard !tidied.isEmpty else {
            themeInputNotice = "Themes are a few short words. Try something briefer."
            return
        }
        themeInputNotice = nil
        for theme in tidied where !themesDraft.contains(theme) {
            themesDraft.append(theme)
        }
        newTheme = ""
    }

    private func retranscribeTapped(_ data: Data) {
        retranscribeFailed = false
        // Words the user has touched are never replaced without asking.
        if transcriptDiverged || node.transcriptEditedByUser {
            showReplaceConfirm = true
        } else {
            Task { await retranscribe(data) }
        }
    }

    private func retranscribe(_ data: Data) async {
        isTranscribing = true
        defer { isTranscribing = false }
        // The post-hoc recognizer still wants a file URL; the bytes in the
        // model are written out briefly and reclaimed.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("retranscribe-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? data.write(to: url)) != nil,
              let transcript = await ai.transcribe(audioURL: url),
              !transcript.isEmpty else {
            retranscribeFailed = true
            return
        }
        bodyBeforeRetranscribe = bodyDraft
        bodyDraft = transcript   // a draft — Save still decides
    }

    private func rederive() async {
        isRederiving = true
        defer { isRederiving = false }
        let basis = [bodyDraft.trimmed, noteDraft.trimmed]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !basis.isEmpty else { return }
        let understanding = await ai.understand(basis)
        if !understanding.essence.isEmpty { titleDraft = understanding.essence }
        if !understanding.themes.isEmpty { themesDraft = understanding.themes }
    }

    private func save() {
        let titleChanged = titleDraft != originalTitle
        let bodyChanged = bodyDraft != originalBody
        let noteChanged = noteDraft != originalNote
        let themesChanged = themesDraft != originalThemes
        let linkChanged = normalizedLinkDraft != originalLink
        guard titleChanged || bodyChanged || noteChanged || themesChanged || linkChanged || imageChanged else {
            dismiss()
            return
        }

        if titleChanged {
            node.title = titleDraft.trimmed
            node.titleEditedByUser = true
        }
        if bodyChanged {
            let body = bodyDraft.trimmed
            if isVoice {
                node.transcription = body.isEmpty ? nil : body
            } else {
                node.text = body
            }
            node.transcriptEditedByUser = true
        }
        if noteChanged, hasNote {
            node.text = noteDraft.trimmed
        }
        // The words the record was read from changed, so the reading is
        // stale: it is cleared here and re-read by the next enrichment pass.
        if bodyChanged || (noteChanged && hasNote) {
            NodeComposer.wordsChanged(on: node)
        }
        if themesChanged {
            node.themes = themesDraft
            node.themesEditedByUser = true
            node.themeKeys = ThoughtReading.keys(fromEnglish: [], fallbackLabels: themesDraft)
        }
        if linkChanged {
            // The URL is the source of truth; a changed (or removed) link drops
            // any stale card/summary so enrichment starts clean.
            node.linkURLString = normalizedLinkDraft.isEmpty ? nil : normalizedLinkDraft
            node.clearLinkEnrichment()
        }
        if imageChanged {
            // Replace the whole set: drop the old image children, write the draft
            // in order (already downsampled on pick), and clear the legacy field
            // so `images` is the single source of truth.
            node.orderedImages.forEach { context.delete($0) }
            node.images = imageDrafts.enumerated().map { NodeImage(data: $1, sortIndex: $0) }
            node.imageData = nil
            // A changed set is read afresh; a stale reading never lingers.
            node.clearPictureReading()
        }
        // An edited thought keeps its place: corrections change meaning
        // fields, never the spot in the Ocean the user knows it by.
        node.anchorInPlace()
        node.updatedAt = .now
        try? context.save()
        // Enrich the committed node (never the draft), now that the link is saved.
        if linkChanged, node.linkURLString != nil {
            LinkEnrichmentService.shared.enrich(nodeID: node.id, context: context, ai: ai)
        }
        if imageChanged, node.hasImages {
            PictureEnrichmentService.shared.enrich(nodeID: node.id, context: context, ai: ai)
        }
        dismiss()
    }
}
