import SwiftUI
import SwiftData

struct FastCaptureSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.oceanAI) private var ai
    @Environment(\.scenePhase) private var scenePhase

    let request: FastCaptureRequest
    var onFinish: () -> Void
    /// Wired by the host so "See in Ocean" can focus the fragment after the
    /// overlay dismisses (the overlay sits outside AppState's environment).
    var onOpenNode: ((UUID) -> Void)? = nil

    @State private var mode: FastCaptureInputPreference
    @State private var text: String
    @State private var imageData: Data?
    @State private var transcriber = LiveTranscriber()
    @State private var recordedURL: URL?
    @State private var recordedAudioData: Data?
    @State private var transcriptDraft: String = ""
    /// Stop = captured: the node is saved the moment recording ends. The
    /// review beat that follows edits an already-safe thought and releases
    /// itself after a moment unless the user reaches for the words.
    @State private var savedNodeID: UUID?
    @State private var isReviewing = false
    @State private var autoReleaseTask: Task<Void, Never>?
    @State private var message: String?
    @State private var isSaving = false
    @State private var hasStarted = false
    @State private var moment: PostCaptureMoment?
    @State private var fadeTask: Task<Void, Never>?
    @State private var questionTarget: Node?
    @FocusState private var textFocused: Bool
    @FocusState private var transcriptFocused: Bool

    init(
        request: FastCaptureRequest,
        onFinish: @escaping () -> Void,
        onOpenNode: ((UUID) -> Void)? = nil
    ) {
        self.request = request
        self.onFinish = onFinish
        self.onOpenNode = onOpenNode
        _mode = State(initialValue: request.inputPreference)
        _text = State(initialValue: request.seedText)
        _imageData = State(initialValue: request.imageData)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.24)
                .ignoresSafeArea()

            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if let moment {
                        // Post-release: the card becomes the understanding moment.
                        PostCaptureMomentView(
                            moment: moment,
                            onTurnIntoQuestion: { turnIntoQuestion(moment) },
                            onSeeInOcean: { seeInOcean(moment) }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        if let imageData, let uiImage = UIImage(data: imageData) {
                            screenshotPreview(uiImage)
                        }

                        if isReviewing {
                            reviewCapture
                        } else if mode == .voiceFirst {
                            voiceCapture
                        } else {
                            typingCapture
                        }

                        if let message {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(OceanTheme.mist)
                        }

                        controls
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            if mode == .voiceFirst {
                await startRecording()
            } else {
                textFocused = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            finishInterruptedCapture()
        }
        .sheet(item: $questionTarget, onDismiss: { onFinish() }) { parent in
            BranchComposer(
                parent: parent,
                prefill: moment?.title ?? "",
                prefillType: .question
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(OceanTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Fast Capture")
                    .font(.headline)
                    .foregroundStyle(OceanTheme.foam)
                Text(request.source.label)
                    .font(.caption)
                    .foregroundStyle(OceanTheme.mist)
            }

            Spacer()

            Button(action: cancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(OceanTheme.mist)
            }
            .accessibilityLabel(
                transcriber.isRecording ? "Cancel recording"
                    : isReviewing ? "Close — keeps the capture"
                    : "Close Fast Capture"
            )
        }
    }

    private var voiceCapture: some View {
        VStack(spacing: 12) {
            FastCaptureWaveform(level: transcriber.level, active: transcriber.isRecording)
                .frame(height: 42)

            HStack {
                Text(transcriber.isRecording ? "Listening" : "Whisper held")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OceanTheme.foam)

                Spacer()

                Text(timeString(transcriber.elapsed))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(OceanTheme.mist)
            }

            if transcriber.isRecording, transcriber.speechAvailability == .live {
                // The words land while speaking; the note field returns in
                // the review beat (and stays for the speech-off path).
                TranscriptEditor(
                    text: .constant(transcriber.partial),
                    isEditable: false,
                    placeholder: "Words appear as you speak…",
                    minHeight: 54,
                    maxHeight: 88
                )
            } else {
                noteEditor
            }
        }
    }

    private var noteEditor: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 54, maxHeight: 88)
            .focused($textFocused)
            .foregroundStyle(OceanTheme.foam)
            .overlay(alignment: .topLeading) {
                if text.trimmed.isEmpty {
                    Text("A few words, if needed")
                        .font(.subheadline)
                        .foregroundStyle(OceanTheme.faint)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The brief post-stop beat: the thought is already saved; the words sit
    /// visible for a moment and release themselves unless tapped.
    private var reviewCapture: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Captured", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OceanTheme.foam)
                Spacer()
                // The explicit way back — X above only closes; this deletes.
                Button(action: undoCapture) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .foregroundStyle(OceanTheme.mist)
                }
                .accessibilityLabel("Undo capture")
            }

            if autoReleaseTask != nil {
                Text("Tap words to keep editing")
                    .font(.caption2)
                    .foregroundStyle(OceanTheme.faint)
            }

            if autoReleaseTask == nil {
                TranscriptEditor(
                    text: $transcriptDraft,
                    isEditable: true,
                    placeholder: transcriber.speechAvailability == .unavailable
                        ? "Transcription is off — type the words, if you like"
                        : "What did you say?",
                    minHeight: 54,
                    maxHeight: 110,
                    focus: $transcriptFocused
                )
            } else {
                TranscriptEditor(
                    text: .constant(transcriptDraft),
                    isEditable: false,
                    placeholder: "No words caught — tap to add them",
                    minHeight: 54,
                    maxHeight: 110
                )
                .contentShape(Rectangle())
                .onTapGesture { pauseAutoRelease(focus: true) }
            }

            // The typed note releases with the thought — it stays visible
            // and editable here; a review that hides content isn't a review.
            if !text.trimmed.isEmpty {
                noteEditor
            }

            if autoReleaseTask == nil, let recordedAudioData {
                ListenChip(data: recordedAudioData)
            }
        }
        .onChange(of: transcriptFocused) { _, focused in
            if focused { pauseAutoRelease(focus: false) }
        }
    }

    private var typingCapture: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 116, maxHeight: 170)
            .focused($textFocused)
            .foregroundStyle(OceanTheme.foam)
            .overlay(alignment: .topLeading) {
                if text.trimmed.isEmpty {
                    Text("What are you noticing?")
                        .font(.subheadline)
                        .foregroundStyle(OceanTheme.faint)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if isReviewing {
                if autoReleaseTask != nil {
                    // The pause on Fast Capture's zero-friction path: hold the
                    // fragment back and fix the words.
                    Button {
                        pauseAutoRelease(focus: true)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(OceanTheme.accent)
                }
            } else if mode == .voiceFirst {
                Button {
                    Task { await toggleRecording() }
                } label: {
                    Label(transcriber.isRecording ? "Stop" : "Record", systemImage: transcriber.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(transcriber.isRecording ? .red.opacity(0.8) : OceanTheme.accent)
            } else {
                Button {
                    withAnimation(.snappy) { mode = .voiceFirst }
                    Task { await startRecording() }
                } label: {
                    Label("Voice", systemImage: "waveform")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(OceanTheme.accent)
            }

            Spacer()

            if isReviewing {
                if autoReleaseTask == nil {
                    // Paused for editing: the only forward action is "keep".
                    Button(action: finalizeReview) {
                        Label("Keep", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OceanTheme.accent)
                    .foregroundStyle(OceanTheme.abyss)
                    .disabled(isSaving)
                }
            } else {
                Button(action: releaseNow) {
                    Label("Release", systemImage: "arrow.up.forward.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(OceanTheme.accent)
                .foregroundStyle(OceanTheme.abyss)
                .disabled(!canSave || isSaving)
                .opacity(canSave ? 1 : 0.45)
            }
        }
    }

    private func screenshotPreview(_ uiImage: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(height: 116)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )

            Button {
                withAnimation(.snappy) { imageData = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding(6)
            }
            .accessibilityLabel("Remove screenshot")
        }
    }

    private var canSave: Bool {
        transcriber.isRecording
        || isReviewing
        || !text.trimmed.isEmpty
        || imageData != nil
    }

    private func toggleRecording() async {
        if transcriber.isRecording {
            await captureNow()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        guard !transcriber.isRecording else { return }
        guard await transcriber.requestMicPermission() else {
            await MainActor.run { fallBackToTyping() }
            return
        }
        let url = AudioRecorder.url(for: "drift-\(UUID().uuidString).m4a")
        await MainActor.run {
            recordedURL = nil
            recordedAudioData = nil
            transcriptDraft = ""
            savedNodeID = nil
            isReviewing = false
            // System interruptions end the take like a tap on Stop: capture
            // what was caught and show the review, never a stuck "Listening".
            transcriber.onInterruption = { [self] in
                Task { await captureNow() }
            }
        }
        if !(await transcriber.start(writingTo: url)) {
            await MainActor.run { fallBackToTyping() }
        }
    }

    private func fallBackToTyping() {
        withAnimation(.snappy) {
            mode = .typingFirst
            message = "Typing is ready."
        }
        textFocused = true
    }

    /// Stop = captured. The node is saved here, before the review beat — the
    /// beat edits a thought that is already safe, then releases itself.
    @MainActor
    private func captureNow() async {
        guard !isSaving, savedNodeID == nil else { return }
        let elapsed = transcriber.elapsed
        let (url, transcript) = await transcriber.stop()
        let trimmedNote = text.trimmed
        let trimmedTranscript = transcript.trimmed

        // A pocket press or reflexive tap shouldn't mint an empty thought.
        if trimmedTranscript.isEmpty, trimmedNote.isEmpty, imageData == nil, elapsed < 1 {
            if let url { try? FileManager.default.removeItem(at: url) }
            return
        }

        recordedURL = url
        recordedAudioData = url.flatMap { try? Data(contentsOf: $0) }
        let node = NodeComposer.make(
            kind: .voice,
            text: trimmedNote,
            transcription: trimmedTranscript.isEmpty ? nil : trimmedTranscript,
            audioData: recordedAudioData,
            imageData: imageData,
            detectThemes: !trimmedNote.isEmpty || !trimmedTranscript.isEmpty
        )
        context.insert(node)
        try? context.save()

        savedNodeID = node.id
        transcriptDraft = trimmedTranscript
        withAnimation(.snappy) { isReviewing = true }
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

    private func pauseAutoRelease(focus: Bool) {
        autoReleaseTask?.cancel()
        autoReleaseTask = nil
        if focus {
            // Focus lands after the editable editor exists in the hierarchy.
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                transcriptFocused = true
            }
        }
    }

    /// The review resolves: apply any edits to the saved node, then let
    /// understanding run on the words the user actually kept.
    @MainActor
    private func finalizeReview() {
        guard !isSaving, let nodeID = savedNodeID else { return }
        isSaving = true
        autoReleaseTask?.cancel()
        autoReleaseTask = nil

        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == nodeID })
        guard let node = try? context.fetch(descriptor).first else {
            isSaving = false
            onFinish()
            return
        }

        let editedTranscript = transcriptDraft.trimmed
        if editedTranscript != (node.transcription ?? "") {
            node.transcription = editedTranscript.isEmpty ? nil : editedTranscript
            node.transcriptEditedByUser = true
        }
        let editedNote = text.trimmed
        if editedNote != node.text {
            node.text = editedNote
        }
        node.updatedAt = .now
        try? context.save()

        if !(node.transcription ?? "").isEmpty {
            // A confirmed transcript wins — no post-hoc re-transcription.
            if let recordedURL { try? FileManager.default.removeItem(at: recordedURL) }
            if !node.rawContent.isEmpty {
                Task { await generateTitle(nodeID: nodeID) }
            }
        } else if let recordedURL {
            // Speech was off and nothing typed: the post-hoc pass is the
            // fallback; it reclaims the temp file.
            Task { await transcribeAndEnrich(nodeID: nodeID, url: recordedURL) }
        } else if !node.rawContent.isEmpty {
            Task { await generateTitle(nodeID: nodeID) }
        }

        textFocused = false
        transcriptFocused = false
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            isReviewing = false
            moment = .received(for: nodeID)
        }
        scheduleFinish(after: 1.2)
    }

    /// The prominent Release button: while recording it stops *and* releases
    /// in one gesture; in typing mode it saves the typed thought as before.
    private func releaseNow() {
        if transcriber.isRecording {
            Task {
                await captureNow()
                await MainActor.run { finalizeReview() }
            }
        } else if isReviewing {
            finalizeReview()
        } else {
            saveTyped()
        }
    }

    private func saveTyped() {
        guard !isSaving, canSave else { return }
        isSaving = true

        let trimmed = text.trimmed
        let kind: NodeKind = (imageData != nil && trimmed.isEmpty) ? .image : .text
        let node = NodeComposer.make(kind: kind, text: trimmed, imageData: imageData)
        context.insert(node)
        try? context.save()

        let nodeID = node.id
        if !node.rawContent.isEmpty {
            Task { await generateTitle(nodeID: nodeID) }
        }

        // Received. If the interpreted title lands quickly (the common case for
        // text), the card morphs into the understanding moment and lingers
        // briefly; otherwise it dismisses almost as fast as before.
        textFocused = false
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            moment = .received(for: nodeID)
        }
        scheduleFinish(after: 1.2)
    }

    // MARK: Understanding moment

    @MainActor
    private func advanceMoment(nodeID: UUID, title: String) {
        guard moment?.id == nodeID else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            moment?.title = title
        }
        scheduleFinish(after: 3.6)

        if let hint = PostCaptureMoment.strongRelatedHint(for: nodeID, context: context, ai: ai),
           moment?.id == nodeID {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                moment?.related = hint
            }
            scheduleFinish(after: 4.2)
        }
    }

    private func scheduleFinish(after seconds: Double) {
        fadeTask?.cancel()
        fadeTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await MainActor.run { onFinish() }
        }
    }

    private func turnIntoQuestion(_ moment: PostCaptureMoment) {
        fadeTask?.cancel()
        let id = moment.id
        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == id })
        guard let node = try? context.fetch(descriptor).first else { return }
        questionTarget = node
    }

    private func seeInOcean(_ moment: PostCaptureMoment) {
        fadeTask?.cancel()
        onOpenNode?(moment.id)
        onFinish()
    }

    /// The header X. Consistent close semantics: after capture it only
    /// closes — committing what's already safe — and never deletes. Deleting
    /// is Undo's job, and it says so. Mid-recording, nothing is saved yet, so
    /// X cancels the take.
    private func cancel() {
        fadeTask?.cancel()
        if moment != nil {
            // Post-release: the fragment is already saved — just close.
            autoReleaseTask?.cancel()
            onFinish()
            return
        }
        if transcriber.isRecording {
            Task { await transcriber.cancel() }
            onFinish()
            return
        }
        if isReviewing {
            // Close = keep: commit drafts and dismiss without the moment beat.
            finalizeReview()
            fadeTask?.cancel()
            onFinish()
            return
        }
        if let recordedURL {
            try? FileManager.default.removeItem(at: recordedURL)
        }
        onFinish()
    }

    /// The explicit take-it-back: deletes the captured node and closes.
    private func undoCapture() {
        autoReleaseTask?.cancel()
        autoReleaseTask = nil
        fadeTask?.cancel()
        if let nodeID = savedNodeID {
            let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == nodeID })
            if let node = try? context.fetch(descriptor).first {
                context.delete(node)
                try? context.save()
            }
        }
        if let recordedURL { try? FileManager.default.removeItem(at: recordedURL) }
        onFinish()
    }

    private func finishInterruptedCapture() {
        if transcriber.isRecording {
            // The overlay is going away — capture what we have and release;
            // no review beat to show.
            Task {
                await captureNow()
                await MainActor.run { finalizeReview() }
            }
        } else if isReviewing, moment == nil {
            // Backgrounded mid-review — paused or not, the thought is already
            // safe and any edits made so far go with it.
            finalizeReview()
        }
    }

    private func transcribeAndEnrich(nodeID: UUID, url: URL) async {
        // Audio already lives in the node; the temp file is only for on-device
        // transcription, so reclaim it on every exit path.
        defer { try? FileManager.default.removeItem(at: url) }
        guard let transcript = await ai.transcribe(audioURL: url) else { return }
        let combined: String = await MainActor.run {
            let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == nodeID })
            guard let node = try? context.fetch(descriptor).first else { return transcript }
            // Ownership: never overwrite words the user has touched.
            guard !node.transcriptEditedByUser else { return node.rawContent }
            node.transcription = transcript
            node.updatedAt = .now
            try? context.save()
            return [node.text, transcript].filter { !$0.isEmpty }.joined(separator: "\n")
        }

        let understanding = await ai.understand(combined)
        await MainActor.run {
            let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == nodeID })
            guard let node = try? context.fetch(descriptor).first else { return }
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

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%01d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

private struct FastCaptureWaveform: View {
    let level: Double
    let active: Bool

    var body: some View {
        TimelineView(.animation(paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<22, id: \.self) { index in
                    let phase = Double(index) * 0.58
                    let base = active ? (0.26 + 0.74 * abs(sin(t * 4.4 + phase))) : 0.16
                    let height = max(4, base * (active ? (8 + level * 42) : 8))
                    Capsule()
                        .fill(OceanTheme.accent.opacity(active ? 0.88 : 0.36))
                        .frame(width: 4, height: height)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
