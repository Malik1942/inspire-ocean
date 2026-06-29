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

    @State private var session = CaptureSession()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var imageDatas: [Data] = []
    /// Brief "only added N — 10 max" note when a batch would overflow the cap.
    @State private var imageNotice: String?

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
    /// The moment fades light and early; this keeps a quiet Undo pill behind
    /// it until the session's undo window (~10 s after save) actually closes.
    @State private var lingeringUndoID: UUID?
    @State private var lingeringTask: Task<Void, Never>?
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
                            onSeeInOcean: { seeInOcean(moment) },
                            onUndo: session.undoAvailable(for: moment.id)
                                ? { undoFromMoment() } : nil
                        )
                        .padding(.bottom, 40)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else if let id = lingeringUndoID, session.undoAvailable(for: id) {
                    // The moment is gone but the thought can still come back.
                    VStack {
                        Spacer()
                        Button(action: undoFromMoment) {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(OceanTheme.mist)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .accessibilityLabel("Undo capture")
                        .padding(.bottom, 40)
                    }
                    .transition(.opacity)
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
            .onChange(of: photoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task { await addPickedImages(newItems) }
            }
            .onAppear {
                session.configure(context: context, ai: ai)
                session.onUnderstood = { nodeID, title in
                    advanceMoment(nodeID: nodeID, title: title)
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
            if session.transcriber.isRecording { Task { await captureWhisper() } }
        }
        .onDisappear {
            if session.transcriber.isRecording { Task { await captureWhisper() } }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            if session.transcriber.isRecording { Task { await captureWhisper() } }
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

            if !imageDatas.isEmpty { imageRow }

            HStack(spacing: 10) {
                if imageDatas.count < Node.maxImages {
                    PhotosPicker(
                        selection: $photoItems,
                        maxSelectionCount: Node.maxImages - imageDatas.count,
                        matching: .images
                    ) {
                        attachLabel(imageDatas.isEmpty
                                    ? String(localized: "Image")
                                    : String(localized: "Add image"),
                                    system: "photo")
                    }
                }
                Button { withAnimation { showLinkField.toggle() } } label: {
                    attachLabel(linkText.trimmed.isEmpty
                                ? String(localized: "Link")
                                : String(localized: "Edit link"),
                                system: "link")
                }
                Spacer()
            }

            if let imageNotice {
                Text(imageNotice).font(.caption2).foregroundStyle(OceanTheme.faint)
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

                if !imageDatas.isEmpty { imageRow }
                if imageDatas.count < Node.maxImages {
                    PhotosPicker(
                        selection: $photoItems,
                        maxSelectionCount: Node.maxImages - imageDatas.count,
                        matching: .images
                    ) {
                        attachLabel(imageDatas.isEmpty
                                    ? String(localized: "Add image")
                                    : String(localized: "Add image"),
                                    system: "photo")
                    }
                }
                if let imageNotice {
                    Text(imageNotice).font(.caption2).foregroundStyle(OceanTheme.faint)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220)
        .animation(.snappy, value: whisperPhase)
    }

    private var whisperRecording: some View {
        VStack(spacing: 16) {
            Text((whisperPhase == .recording ? "Listening…" : "Catch a whisper") as LocalizedStringKey)
                .font(.subheadline).foregroundStyle(OceanTheme.mist)

            WaveformView(level: session.transcriber.level, active: whisperPhase == .recording)
                .frame(height: 56)

            // elapsed survives stop() — show it only while it's this take's.
            Text(timeString(whisperPhase == .recording ? session.transcriber.elapsed : 0))
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(OceanTheme.foam)

            // The words land as they're spoken — the whole point of looking
            // at the card while whispering.
            if whisperPhase == .recording, session.transcriber.speechAvailability == .live {
                TranscriptEditor(
                    text: .constant(session.transcriber.partial),
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

                if session.transcriber.speechAvailability == .unavailable, reviewText.trimmed.isEmpty {
                    Text("Live transcription is off: type the words, or keep just the audio.")
                        .font(.caption2).foregroundStyle(OceanTheme.faint)
                }

                HStack {
                    if let recordedAudioData {
                        ListenChip(data: recordedAudioData)
                    }
                    Spacer()
                    Button {
                        finalizeReview()
                    } label: {
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
                    placeholder: "No words caught, tap to add them",
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

    /// Horizontal row of attached-image thumbnails, each removable. Shared by
    /// the Thought and Whisper capture paths.
    private var imageRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(imageDatas.enumerated()), id: \.offset) { index, data in
                    if let ui = UIImage(data: data) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: ui)
                                .resizable().scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Button {
                                withAnimation { removeImage(at: index) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3).symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.white)
                                    .padding(4)
                            }
                            .accessibilityLabel("Remove image")
                        }
                    }
                }
            }
        }
    }

    /// Load picked items through the one shared downsample path, clamped to the
    /// per-node cap; tell the user if a batch overflowed rather than dropping
    /// silently. Clears the picker selection so the next pick fires `onChange`.
    private func addPickedImages(_ items: [PhotosPickerItem]) async {
        let loaded = await ImageDownsampler.attachmentData(from: items)
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

    private func removeImage(at index: Int) {
        guard imageDatas.indices.contains(index) else { return }
        imageDatas.remove(at: index)
        imageNotice = nil
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
        return !text.trimmed.isEmpty || !imageDatas.isEmpty || !linkText.trimmed.isEmpty
    }

    // MARK: Whisper actions

    private func toggleRecording() async {
        if session.transcriber.isRecording {
            await captureWhisper()
        } else {
            // A call, Siri, or a vanished mic ends the take like a tap on
            // stop — capture what was caught, never stay stuck "Listening…".
            let started = await session.startRecording(onInterruption: { [self] in
                Task { await captureWhisper() }
            })
            if started == .started {
                whisperPhase = .recording
            }
        }
    }

    /// Stop = captured. The node is saved here, before any review — the
    /// capsule that follows edits a thought that is already safe.
    private func captureWhisper() async {
        let elapsed = session.transcriber.elapsed
        let (url, transcript) = await session.stopRecording()
        let trimmed = transcript.trimmed

        // A reflexive double-tap shouldn't mint an empty thought.
        if trimmed.isEmpty, elapsed < 1, imageDatas.isEmpty {
            if let url { try? FileManager.default.removeItem(at: url) }
            whisperPhase = .idle
            return
        }

        recordedURL = url
        recordedAudioData = CaptureSession.readAudio(url)
        let draft = CaptureDraft(kind: .voice,
                                 transcript: trimmed,
                                 audioData: recordedAudioData,
                                 audioTempURL: url,
                                 imageDatas: imageDatas)
        reviewText = trimmed
        imageDatas = []
        photoItems = []
        imageNotice = nil

        if let nodeID = session.release(draft) {
            reviewNodeID = nodeID
            reviewPaused = false
            withAnimation(.snappy) { whisperPhase = .reviewing }
            scheduleAutoRelease()
        } else {
            // The store refused the save: hold the words on the surface,
            // paused — Keep retries the release. Never a silent loss.
            reviewNodeID = nil
            reviewPaused = true
            withAnimation(.snappy) { whisperPhase = .reviewing }
        }
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
        // Deliberately no auto-focus: the keyboard transaction it triggers
        // can eat the very next tap (Keep, Listen) — a second tap on the now-
        // editable words focuses natively when the user actually wants to type.
    }

    /// The capsule resolves: apply any edits to the saved node (or release a
    /// restored draft), then let understanding run on the words the user kept.
    private func finalizeReview() {
        autoReleaseTask?.cancel()
        autoReleaseTask = nil

        let nodeID: UUID
        if let existing = reviewNodeID {
            session.applyReviewEdits(nodeID: existing, transcript: reviewText)
            nodeID = existing
        } else {
            // A restored (undone) or save-failed draft — release it now.
            let draft = CaptureDraft(kind: .voice,
                                     transcript: reviewText.trimmed,
                                     audioData: recordedAudioData,
                                     audioTempURL: recordedURL)
            guard let id = session.release(draft) else { return }   // words stay on the surface
            nodeID = id
        }

        session.beginUnderstanding(nodeID: nodeID)

        withAnimation(.spring) { moment = .received(for: nodeID) }
        scheduleFade(after: 4.0)
        keepUndoReachable(for: nodeID)
        resetReview()
    }

    /// The moment fades on its own rhythm; the way back stays open until the
    /// session's undo window closes.
    private func keepUndoReachable(for nodeID: UUID) {
        lingeringUndoID = nodeID
        lingeringTask?.cancel()
        lingeringTask = Task {
            try? await Task.sleep(for: .seconds(CaptureSession.undoWindow + 0.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if lingeringUndoID == nodeID {
                    withAnimation { lingeringUndoID = nil }
                }
            }
        }
    }

    private func discardCapture() {
        autoReleaseTask?.cancel()
        autoReleaseTask = nil
        if reviewNodeID != nil {
            _ = session.undoLastRelease()
        } else if let recordedURL {
            // Never-released draft (restored or save-failed): just the file.
            try? FileManager.default.removeItem(at: recordedURL)
        }
        resetReview()
    }

    /// A late Undo from the moment (or its lingering pill): the thought comes
    /// back to the surface, held — words, recording and all.
    private func undoFromMoment() {
        lingeringTask?.cancel()
        lingeringUndoID = nil
        guard let draft = session.undoLastRelease() else {
            dismissMoment()
            return
        }
        dismissMoment()
        if draft.kind == .voice {
            kind = .voice
            reviewNodeID = nil
            reviewText = draft.transcript
            recordedAudioData = draft.audioData
            recordedURL = nil
            imageDatas = draft.imageDatas   // attached images come back too
            reviewPaused = true
            withAnimation(.snappy) { whisperPhase = .reviewing }
        } else {
            kind = .text
            text = draft.text
            imageDatas = draft.imageDatas
            linkText = draft.linkURLString ?? ""
        }
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
        let draft = CaptureDraft(kind: .text, text: text.trimmed,
                                 imageDatas: imageDatas, linkURLString: link)
        guard let nodeID = session.release(draft) else { return }   // draft stays on the surface
        session.beginUnderstanding(nodeID: nodeID)
        // A link drifts in bare; enrichment makes it a rich card and folds what
        // it's about into the understanding pipeline (best-effort, async).
        if link != nil {
            LinkEnrichmentService.shared.enrich(nodeID: nodeID, context: context, ai: ai)
        }

        // Phase 1: received — visually identical to the old confirmation.
        withAnimation(.spring) { moment = .received(for: nodeID) }
        scheduleFade(after: 4.0)
        keepUndoReachable(for: nodeID)
        reset()
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
        imageDatas = []
        photoItems = []
        imageNotice = nil
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
