import SwiftUI
import SwiftData
import PhotosUI

/// Drift Capture (§7): catch inspiration with minimal friction.
///
/// Two modes — **Thought** (text, with optional image + link) and **Whisper**
/// (voice, with optional image). Images and links are attachments blended into a
/// thought/whisper rather than separate kinds. Capture stays under two seconds.
struct CaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.oceanAI) private var ai
    @Environment(AppState.self) private var appState

    @State private var kind: NodeKind = .text   // .text = Thought, .voice = Whisper
    @State private var text: String = ""
    @State private var linkText: String = ""
    @State private var showLinkField = false

    @State private var recorder = AudioRecorder()
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var lastRecordedFile: String?

    @State private var moment: PostCaptureMoment?
    @State private var fadeTask: Task<Void, Never>?
    @State private var questionTarget: Node?
    @State private var showFastCaptureSettings = false
    @FocusState private var textFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                OceanBackground()
                content
                if let moment {
                    VStack {
                        Spacer()
                        PostCaptureMomentView(
                            moment: moment,
                            onTurnIntoQuestion: { turnIntoQuestion(moment) },
                            onSeeInOcean: { seeInOcean(moment) }
                        )
                        .padding(.bottom, 40)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFastCaptureSettings = true
                    } label: {
                        Image(systemName: "bolt.circle")
                    }
                    .accessibilityLabel("Fast Capture settings")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showFastCaptureSettings) {
                FastCaptureSettingsView()
            }
            .sheet(item: $questionTarget, onDismiss: { dismissMoment() }) { parent in
                BranchComposer(
                    parent: parent,
                    prefill: moment?.title ?? "",
                    prefillType: .question
                )
            }
            .onChange(of: photoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        imageData = data
                    }
                }
            }
        }
    }

    private var content: some View {
        VStack(spacing: 20) {
            Picker("Type", selection: $kind) {
                Label("Thought", systemImage: "text.alignleft").tag(NodeKind.text)
                Label("Whisper", systemImage: "waveform").tag(NodeKind.voice)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            GlassCard(padding: 18) {
                if kind == .voice { whisperCapture } else { thoughtCapture }
            }
            .padding(.horizontal)

            saveButton
            Spacer()
        }
        .padding(.top, 8)
        .animation(.snappy, value: kind)
    }

    // MARK: Thought

    private var thoughtCapture: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What just drifted by?")
                .font(.subheadline).foregroundStyle(OceanTheme.mist)
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .focused($textFocused)
                .foregroundStyle(OceanTheme.foam)
                .overlay {
                    // Tap the field to raise the keyboard; tap again to fold it.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { textFocused.toggle() }
                }

            if let imageData, let ui = UIImage(data: imageData) {
                imagePreview(ui)
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    attachLabel(imageData == nil ? "Image" : "Replace", system: "photo")
                }
                Button { withAnimation { showLinkField.toggle() } } label: {
                    attachLabel(linkText.trimmed.isEmpty ? "Link" : "Edit link", system: "link")
                }
                Spacer()
            }

            if showLinkField || !linkText.trimmed.isEmpty {
                linkField
            }
        }
        .frame(minHeight: 200)
    }

    // MARK: Whisper

    private var whisperCapture: some View {
        VStack(spacing: 16) {
            Text(recorder.isRecording ? "Listening…" : "Catch a whisper")
                .font(.subheadline).foregroundStyle(OceanTheme.mist)

            WaveformView(level: recorder.level, active: recorder.isRecording)
                .frame(height: 56)

            Text(timeString(recorder.elapsed))
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(OceanTheme.foam)

            Button { Task { await toggleRecording() } } label: {
                Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 58))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(recorder.isRecording ? .red : OceanTheme.accent)
            }

            if let imageData, let ui = UIImage(data: imageData) {
                imagePreview(ui)
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                attachLabel(imageData == nil ? "Add image" : "Replace image", system: "photo")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220)
    }

    // MARK: Shared attachment views

    private func imagePreview(_ ui: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: ui)
                .resizable().scaledToFit()
                .frame(maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button {
                imageData = nil
                photoItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding(6)
            }
        }
    }

    private var linkField: some View {
        TextField("https://…", text: $linkText)
            .textFieldStyle(.plain)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .foregroundStyle(OceanTheme.foam)
            .padding(.vertical, 10).padding(.horizontal, 12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func attachLabel(_ title: String, system: String) -> some View {
        Label(title, systemImage: system)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: Capsule())
            .foregroundStyle(OceanTheme.foam)
    }

    private var saveButton: some View {
        Button(action: save) {
            Text("Release into the Ocean")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .background(
            LinearGradient(colors: [OceanTheme.accent, OceanTheme.surface],
                           startPoint: .leading, endPoint: .trailing),
            in: Capsule()
        )
        .foregroundStyle(OceanTheme.abyss)
        .padding(.horizontal)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.4)
    }

    private var canSave: Bool {
        switch kind {
        case .voice:
            return recorder.isRecording || lastRecordedFile != nil || imageData != nil
        default:
            return !text.trimmed.isEmpty || imageData != nil || !linkText.trimmed.isEmpty
        }
    }

    // MARK: Actions

    private func toggleRecording() async {
        if recorder.isRecording {
            lastRecordedFile = recorder.stop()
        } else {
            guard await recorder.requestPermission() else { return }
            lastRecordedFile = nil
            recorder.start()
        }
    }

    private func save() {
        if recorder.isRecording { lastRecordedFile = recorder.stop() }

        let link = linkText.trimmed.isEmpty ? nil : normalizedLink
        let node: Node
        switch kind {
        case .voice:
            node = NodeComposer.make(kind: .voice, audioFileName: lastRecordedFile,
                                     imageData: imageData, detectThemes: false)
        default:
            node = NodeComposer.make(kind: .text, text: text.trimmed,
                                     linkURLString: link, imageData: imageData)
        }

        context.insert(node)
        try? context.save()

        let nodeID = node.id
        if kind == .voice, let file = lastRecordedFile {
            let url = AudioRecorder.url(for: file)
            Task { await transcribeAndEnrich(nodeID: nodeID, url: url) }
        } else {
            Task { await generateTitle(nodeID: nodeID) }
        }

        // Phase 1: received — visually identical to the old confirmation.
        // If understanding never lands, this fades exactly like before.
        withAnimation(.spring) { moment = .received(for: nodeID) }
        scheduleFade(after: 1.6)
        reset()
    }

    private func transcribeAndEnrich(nodeID: UUID, url: URL) async {
        guard let transcript = await ai.transcribe(audioURL: url) else { return }
        let themes = ai.detectThemes(for: transcript)
        let title = await ai.conciseTitle(for: transcript)
        await MainActor.run {
            let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == nodeID })
            guard let node = try? context.fetch(descriptor).first else { return }
            node.transcription = transcript
            node.themes = themes
            node.title = title
            node.updatedAt = .now
            try? context.save()
            advanceMoment(nodeID: nodeID, title: title)
        }
    }

    private func generateTitle(nodeID: UUID) async {
        let raw: String = await MainActor.run {
            let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == nodeID })
            return (try? context.fetch(descriptor).first)?.rawContent ?? ""
        }
        guard !raw.isEmpty else { return }
        let title = await ai.conciseTitle(for: raw)
        await MainActor.run {
            let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == nodeID })
            guard let node = try? context.fetch(descriptor).first else { return }
            node.title = title
            node.updatedAt = .now
            try? context.save()
            advanceMoment(nodeID: nodeID, title: title)
        }
    }

    // MARK: Understanding moment

    /// Phase 2: the interpreted title landed — show it, and look for one
    /// strong nearby fragment. Stale results (a newer capture replaced the
    /// moment) are dropped silently.
    @MainActor
    private func advanceMoment(nodeID: UUID, title: String) {
        guard moment?.id == nodeID else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            moment?.title = title
        }
        scheduleFade(after: 4.0)

        if let hint = PostCaptureMoment.strongRelatedHint(for: nodeID, context: context, ai: ai),
           moment?.id == nodeID {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                moment?.related = hint
            }
            scheduleFade(after: 4.5)
        }
    }

    private func scheduleFade(after seconds: Double) {
        fadeTask?.cancel()
        fadeTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await MainActor.run { dismissMoment() }
        }
    }

    private func dismissMoment() {
        fadeTask?.cancel()
        withAnimation { moment = nil }
    }

    private func turnIntoQuestion(_ moment: PostCaptureMoment) {
        fadeTask?.cancel()
        let id = moment.id
        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == id })
        guard let node = try? context.fetch(descriptor).first else { return }
        questionTarget = node
    }

    private func seeInOcean(_ moment: PostCaptureMoment) {
        dismissMoment()
        appState.pendingFocusNodeID = moment.id
        appState.selectedTab = .ocean
    }

    private func reset() {
        text = ""
        linkText = ""
        showLinkField = false
        imageData = nil
        photoItem = nil
        lastRecordedFile = nil
    }

    private var normalizedLink: String {
        let t = linkText.trimmed
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return t }
        return "https://" + t
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%01d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - Small subviews

private struct WaveformView: View {
    let level: Double
    let active: Bool

    var body: some View {
        TimelineView(.animation(paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<28, id: \.self) { i in
                    let phase = Double(i) * 0.5
                    let base = active ? (0.3 + 0.7 * abs(sin(t * 4 + phase))) : 0.15
                    let h = max(4, base * (active ? (8 + level * 56) : 8))
                    Capsule()
                        .fill(OceanTheme.accent.opacity(active ? 0.9 : 0.4))
                        .frame(width: 4, height: h)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
