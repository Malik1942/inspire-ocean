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
    @State private var recorder = AudioRecorder()
    @State private var lastRecordedFile: String?
    @State private var message: String?
    @State private var isSaving = false
    @State private var hasStarted = false
    @State private var moment: PostCaptureMoment?
    @State private var fadeTask: Task<Void, Never>?
    @State private var questionTarget: Node?
    @FocusState private var textFocused: Bool

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

                        if mode == .voiceFirst {
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
            .accessibilityLabel("Cancel Fast Capture")
        }
    }

    private var voiceCapture: some View {
        VStack(spacing: 12) {
            FastCaptureWaveform(level: recorder.level, active: recorder.isRecording)
                .frame(height: 42)

            HStack {
                Text(recorder.isRecording ? "Listening" : "Whisper held")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OceanTheme.foam)

                Spacer()

                Text(timeString(recorder.elapsed))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(OceanTheme.mist)
            }

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
            if mode == .voiceFirst {
                Button {
                    Task { await toggleRecording() }
                } label: {
                    Label(recorder.isRecording ? "Stop" : "Record", systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(recorder.isRecording ? .red.opacity(0.8) : OceanTheme.accent)
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

            Button(action: save) {
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
        recorder.isRecording
        || lastRecordedFile != nil
        || !text.trimmed.isEmpty
        || imageData != nil
    }

    private func toggleRecording() async {
        if recorder.isRecording {
            lastRecordedFile = recorder.stop()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        guard !recorder.isRecording else { return }
        guard await recorder.requestPermission() else {
            await MainActor.run {
                withAnimation(.snappy) {
                    mode = .typingFirst
                    message = "Typing is ready."
                }
                textFocused = true
            }
            return
        }
        await MainActor.run {
            lastRecordedFile = nil
            if !recorder.start() {
                withAnimation(.snappy) {
                    mode = .typingFirst
                    message = "Typing is ready."
                }
                textFocused = true
            }
        }
    }

    private func save() {
        guard !isSaving, canSave else { return }
        isSaving = true

        if recorder.isRecording {
            lastRecordedFile = recorder.stop()
        }

        let trimmed = text.trimmed
        let kind: NodeKind
        if lastRecordedFile != nil {
            kind = .voice
        } else if imageData != nil && trimmed.isEmpty {
            kind = .image
        } else {
            kind = .text
        }

        // Audio is read into the model so it syncs through CloudKit; the temp
        // file is reclaimed after transcription (which still needs a file URL).
        let audioData = lastRecordedFile
            .map { AudioRecorder.url(for: $0) }
            .flatMap { try? Data(contentsOf: $0) }
        let node = NodeComposer.make(
            kind: kind,
            text: trimmed,
            audioData: audioData,
            imageData: imageData,
            detectThemes: kind != .voice || !trimmed.isEmpty
        )
        context.insert(node)
        try? context.save()

        let nodeID = node.id
        if let file = lastRecordedFile {
            let url = AudioRecorder.url(for: file)
            Task { await transcribeAndEnrich(nodeID: nodeID, url: url) }
        } else if !node.rawContent.isEmpty {
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

    private func cancel() {
        fadeTask?.cancel()
        if moment != nil {
            // Post-release: the fragment is already saved — just close.
            onFinish()
            return
        }
        if recorder.isRecording {
            recorder.cancel()
        } else if let lastRecordedFile {
            try? FileManager.default.removeItem(at: AudioRecorder.url(for: lastRecordedFile))
        }
        onFinish()
    }

    private func finishInterruptedCapture() {
        guard recorder.isRecording else { return }
        lastRecordedFile = recorder.stop()
        if canSave {
            save()
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
