import SwiftUI
import SwiftData

/// Corrects a captured fragment: title, body (or voice transcript), themes.
/// The audio, when present, is the immutable source of truth — only its
/// interpretation is edited here.
///
/// Edits land on draft copies, not live bindings, so Cancel is a true no-op
/// and CloudKit never sees half-edited state. Saving bumps `updatedAt`, which
/// is also what carries the correction to other devices.
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
    @State private var newTheme = ""
    @State private var isTranscribing = false
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    titleSection
                    bodySection
                    if hasNote { noteSection }
                    if let audioData = node.audioData {
                        audioSection(audioData)
                    }
                    themesSection
                }
                .padding()
                .padding(.bottom, 30)
            }
            .background(OceanBackground())
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear(perform: loadDrafts)
    }

    // MARK: Sections

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Title")
            TextField("A few words it goes by", text: $titleDraft)
                .textFieldStyle(.plain)
                .foregroundStyle(OceanTheme.foam)
                .padding(.vertical, 10).padding(.horizontal, 12)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                Label("Edited transcript — original audio preserved", systemImage: "waveform")
                    .font(.caption2).foregroundStyle(OceanTheme.faint)
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Note")
            TranscriptEditor(
                text: $noteDraft,
                isEditable: true,
                minHeight: 60,
                maxHeight: 120
            )
        }
    }

    private func audioSection(_ data: Data) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Recording")
            AudioPlayerView(data: data)

            Button {
                Task { await retranscribe(data) }
            } label: {
                HStack(spacing: 6) {
                    if isTranscribing {
                        ProgressView().controlSize(.small)
                        Text("Listening again…")
                    } else {
                        Label("Re-transcribe", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
                .foregroundStyle(OceanTheme.foam)
            }
            .disabled(isTranscribing)
        }
    }

    private var themesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Themes")
            if !themesDraft.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(themesDraft, id: \.self) { theme in
                        editableThemeChip(theme)
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Add a theme", text: $newTheme)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(OceanTheme.foam)
                    .onSubmit(addTheme)
                Button(action: addTheme) {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(OceanTheme.accent)
                }
                .disabled(newTheme.trimmed.isEmpty)
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func editableThemeChip(_ theme: String) -> some View {
        HStack(spacing: 5) {
            Text(theme)
            Button {
                themesDraft.removeAll { $0 == theme }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .accessibilityLabel("Remove theme \(theme)")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(OceanTheme.foam)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(OceanTheme.color(forHue: node.hue).opacity(0.20)))
        .overlay(Capsule().strokeBorder(OceanTheme.color(forHue: node.hue).opacity(0.30), lineWidth: 0.5))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline).foregroundStyle(OceanTheme.foam)
    }

    // MARK: Actions

    private func loadDrafts() {
        guard !loaded else { return }
        loaded = true
        titleDraft = node.title
        bodyDraft = isVoice ? (node.transcription ?? "") : node.text
        noteDraft = hasNote ? node.text : ""
        themesDraft = node.themes
        if focusBodyOnAppear { bodyFocused = true }
    }

    /// Same normalization the capture pipeline applies: lowercase, trimmed,
    /// deduplicated (against the chips already present).
    private func addTheme() {
        let tidied = SemanticThemes.tidyThemeList(newTheme)
        for theme in tidied where !themesDraft.contains(theme) {
            themesDraft.append(theme)
        }
        newTheme = ""
    }

    private func retranscribe(_ data: Data) async {
        isTranscribing = true
        defer { isTranscribing = false }
        // The post-hoc recognizer still wants a file URL; the bytes in the
        // model are written out briefly and reclaimed.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("retranscribe-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? data.write(to: url)) != nil else { return }
        if let transcript = await ai.transcribe(audioURL: url), !transcript.isEmpty {
            bodyDraft = transcript   // a draft — Save still decides
        }
    }

    private func save() {
        node.title = titleDraft.trimmed
        if isVoice {
            let body = bodyDraft.trimmed
            node.transcription = body.isEmpty ? nil : body
            if hasNote { node.text = noteDraft.trimmed }
        } else {
            node.text = bodyDraft.trimmed
        }
        node.themes = themesDraft
        // Deliberately NOT recomputing hue/fieldX/fieldY — a correction
        // shouldn't teleport the node across the Ocean. (Future: offer a
        // "re-place" action when themes change substantially.)
        node.updatedAt = .now
        try? context.save()
        dismiss()
    }
}
