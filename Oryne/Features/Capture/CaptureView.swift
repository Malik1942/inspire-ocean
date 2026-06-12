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

    @State private var transcriber = LiveTranscriber()
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?

    /// Whisper flow: record (watching the words land) → stop = captured.
    /// The node is saved the moment recording ends; the review capsule that
    /// follows is a safety net over an already-safe thought, auto-releasing
    /// after a beat unless the user taps the words to keep editing.
    private enum WhisperPhase { case idle, recording, reviewing }
    @State private var whisperPhase: WhisperPhase = .idle
    @State private var reviewNodeID: UUID?
    @State private var reviewText: String = ""
    @State private var reviewPaused = false
    @State private var autoReleaseTask: Task<Void, Never>?
    @State private var recordedAudioData: Data?
    @State private var recordedURL: URL?
    @FocusState private var reviewFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

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

            // Whispers save themselves on stop; only thoughts need a button.
            if kind != .voice { saveButton }
            Spacer()
        }
        .padding(.top, 8)
        .animation(.snappy, value: kind)
        .onChange(of: kind) { _, _ in
            // Switching modes mid-recording must not leave a hot mic behind:
            // stop = captured, exactly as if the user had tapped stop.
            if transcriber.isRecording { Task { await captureWhisper() } }
        }
        .onDisappear {
            if transcriber.isRecording { Task { await captureWhisper() } }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            if transcriber.isRecording { Task { await captureWhisper() } }
        }
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
            if whisperPhase == .reviewing {
                whisperReview
            } else {
                whisperRecording

                if let imageData, let ui = UIImage(data: imageData) {
                    imagePreview(ui)
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    attachLabel(imageData == nil ? "Add image" : "Replace image", system: "photo")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220)
        .animation(.snappy, value: whisperPhase)
    }

    private var whisperRecording: some View {
        VStack(spacing: 16) {
            Text(whisperPhase == .recording ? "Listening…" : "Catch a whisper")
                .font(.subheadline).foregroundStyle(OceanTheme.mist)

            WaveformView(level: transcriber.level, active: whisperPhase == .recording)
                .frame(height: 56)

            // elapsed survives stop() — show it only while it's this take's.
            Text(timeString(whisperPhase == .recording ? transcriber.elapsed : 0))
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(OceanTheme.foam)

            // The words land as they're spoken — the whole point of looking
            // at the card while whispering.
            if whisperPhase == .recording, transcriber.speechAvailability == .live {
                TranscriptEditor(
                    text: .constant(transcriber.partial),
                    isEditable: false,
                    placeholder: "Words appear as you speak…",
                    minHeight: 60,
                    maxHeight: 120
                )
            }

            Button { Task { await toggleRecording() } } label: {
                Image(systemName: whisperPhase == .recording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 58))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(whisperPhase == .recording ? .red : OceanTheme.accent)
            }
        }
    }

    /// The thought is already captured — this capsule is the safety net.
    /// Untouched, it releases itself; tapping the words pauses and edits the
    /// saved node in place.
    private var whisperReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Captured", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(OceanTheme.mist)
                Spacer()
                // One explicit way back, named for what it does — never a
                // bare X that quietly means delete.
                Button(action: discardCapture) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .foregroundStyle(OceanTheme.mist)
                }
                .accessibilityLabel("Undo capture")
            }

            if !reviewPaused {
                Text("Tap words to keep editing")
                    .font(.caption2).foregroundStyle(OceanTheme.faint)
            }

            if reviewPaused {
                TranscriptEditor(
                    text: $reviewText,
                    isEditable: true,
                    placeholder: "What did you say?",
                    minHeight: 96,
                    maxHeight: 180,
                    focus: $reviewFocused
                )

                if transcriber.speechAvailability == .unavailable, reviewText.trimmed.isEmpty {
                    Text("Live transcription is off — type the words, or keep just the audio.")
                        .font(.caption2).foregroundStyle(OceanTheme.faint)
                }

                HStack {
                    if let recordedAudioData {
                        ListenChip(data: recordedAudioData)
                    }
                    Spacer()
                    Button(action: finalizeReview) {
                        Text("Keep")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(OceanTheme.accent.opacity(0.9), in: Capsule())
                            .foregroundStyle(OceanTheme.abyss)
                    }
                }
            } else {
                TranscriptEditor(
                    text: .constant(reviewText),
                    isEditable: false,
                    placeholder: "No words caught — tap to add them",
                    minHeight: 60,
                    maxHeight: 140
                )
                .contentShape(Rectangle())
                .onTapGesture { pauseReview() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        // Whispers save themselves on stop; the button belongs to thoughts.
        guard kind != .voice else { return false }
        return !text.trimmed.isEmpty || imageData != nil || !linkText.trimmed.isEmpty
    }

    // MARK: Whisper actions

    private func toggleRecording() async {
        if transcriber.isRecording {
            await captureWhisper()
        } else {
            guard await transcriber.requestMicPermission() else { return }
            // A call, Siri, or a vanished mic ends the take like a tap on
            // stop — capture what was caught, never stay stuck "Listening…".
            transcriber.onInterruption = { [self] in
                Task { await captureWhisper() }
            }
            let url = AudioRecorder.url(for: "drift-\(UUID().uuidString).m4a")
            if await transcriber.start(writingTo: url) {
                whisperPhase = .recording
            }
        }
    }

    /// Stop = captured. The node is saved here, before any review — the
    /// capsule that follows edits a thought that is already safe.
    private func captureWhisper() async {
        let elapsed = transcriber.elapsed
        let (url, transcript) = await transcriber.stop()
        let trimmed = transcript.trimmed

        // A reflexive double-tap shouldn't mint an empty thought.
        if trimmed.isEmpty, elapsed < 1, imageData == nil {
            if let url { try? FileManager.default.removeItem(at: url) }
            whisperPhase = .idle
            return
        }

        recordedURL = url
        recordedAudioData = url.flatMap { try? Data(contentsOf: $0) }
        let node = NodeComposer.make(kind: .voice,
                                     transcription: trimmed.isEmpty ? nil : trimmed,
                                     audioData: recordedAudioData,
                                     imageData: imageData,
                                     detectThemes: !trimmed.isEmpty)
        context.insert(node)
        try? context.save()

        reviewNodeID = node.id
        reviewText = trimmed
        reviewPaused = false
        imageData = nil
        photoItem = nil
        withAnimation(.snappy) { whisperPhase = .reviewing }
        scheduleAutoRelease()
    }

    private func scheduleAutoRelease() {
        autoReleaseTask?.cancel()
        autoReleaseTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run { finalizeReview() }
        }
    }

    private func pauseReview() {
        autoReleaseTask?.cancel()
        autoReleaseTask = nil
        withAnimation(.snappy) { reviewPaused = true }
        // Focus lands after the editable editor exists in the hierarchy.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            reviewFocused = true
        }
    }

    /// The capsule resolves: apply any edits to the saved node, then let
    /// understanding run on the words the user actually kept.
    private func finalizeReview() {
        autoReleaseTask?.cancel()
        autoReleaseTask = nil
        guard let nodeID = reviewNodeID else { return }
        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == nodeID })
        guard let node = try? context.fetch(descriptor).first else {
            resetReview()
            return
        }

        let edited = reviewText.trimmed
        if edited != (node.transcription ?? "") {
            node.transcription = edited.isEmpty ? nil : edited
            node.transcriptEditedByUser = true
            node.updatedAt = .now
            try? context.save()
        }

        if !(node.transcription ?? "").isEmpty {
            // A confirmed transcript wins — no post-hoc re-transcription.
            if let recordedURL { try? FileManager.default.removeItem(at: recordedURL) }
            Task { await generateTitle(nodeID: nodeID) }
        } else if let recordedURL {
            // Speech was off and nothing was typed: the post-hoc pass is the
            // fallback; it reclaims the temp file.
            Task { await transcribeAndEnrich(nodeID: nodeID, url: recordedURL) }
        }

        withAnimation(.spring) { moment = .received(for: nodeID) }
        scheduleFade(after: 1.6)
        resetReview()
    }

    private func discardCapture() {
        autoReleaseTask?.cancel()
        autoReleaseTask = nil
        if let nodeID = reviewNodeID {
            let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == nodeID })
            if let node = try? context.fetch(descriptor).first {
                context.delete(node)
                try? context.save()
            }
        }
        if let recordedURL { try? FileManager.default.removeItem(at: recordedURL) }
        resetReview()
    }

    private func resetReview() {
        reviewNodeID = nil
        reviewText = ""
        reviewPaused = false
        recordedURL = nil
        recordedAudioData = nil
        whisperPhase = .idle
    }

    // MARK: Thought actions

    private func save() {
        let link = linkText.trimmed.isEmpty ? nil : normalizedLink
        let node = NodeComposer.make(kind: .text, text: text.trimmed,
                                     linkURLString: link, imageData: imageData)
        context.insert(node)
        try? context.save()

        let nodeID = node.id
        Task { await generateTitle(nodeID: nodeID) }

        // Phase 1: received — visually identical to the old confirmation.
        // If understanding never lands, this fades exactly like before.
        withAnimation(.spring) { moment = .received(for: nodeID) }
        scheduleFade(after: 1.6)
        reset()
    }

    private func transcribeAndEnrich(nodeID: UUID, url: URL) async {
        // The audio is already saved in the node; the temp file only exists for
        // on-device transcription, so reclaim it on every exit path.
        defer { try? FileManager.default.removeItem(at: url) }
        guard let transcript = await ai.transcribe(audioURL: url) else { return }
        let understanding = await ai.understand(transcript)
        await MainActor.run {
            let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == nodeID })
            guard let node = try? context.fetch(descriptor).first else { return }
            // Ownership: never overwrite words the user has touched.
            guard !node.transcriptEditedByUser else { return }
            node.transcription = transcript
            NodeComposer.applyUnderstanding(understanding, to: node)
            try? context.save()
            advanceMoment(nodeID: nodeID, title: understanding.essence)
        }
    }

    private func generateTitle(nodeID: UUID) async {
        let raw: String = await MainActor.run {
            let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == nodeID })
            return (try? context.fetch(descriptor).first)?.rawContent ?? ""
        }
        guard !raw.isEmpty else { return }
        let understanding = await ai.understand(raw)
        await MainActor.run {
            let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == nodeID })
            guard let node = try? context.fetch(descriptor).first else { return }
            NodeComposer.applyUnderstanding(understanding, to: node)
            try? context.save()
            advanceMoment(nodeID: nodeID, title: understanding.essence)
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
