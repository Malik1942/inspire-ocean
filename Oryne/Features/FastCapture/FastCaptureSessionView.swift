import SwiftUI
import SwiftData

/// The one capture surface. Every entry point (the floating button, the
/// Action Button, Control Center, the widget, Siri, a share, a current's +)
/// lands here.
///
/// Tap the button to type; hold it to whisper. While the finger is down the
/// words land on the water as subtitles and the button breathes with the
/// microphone. Lift, and the words settle into the Ocean: saved first, then
/// the chime, then the card that names what the Ocean understood. No review
/// beat, no mode picker (docs/plans/phone-refocus/SPEC.md, Phase 1).
struct FastCaptureSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.oceanAI) private var ai
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calmAccessibility) private var calm
    @Environment(CaptureControl.self) private var control

    let request: FastCaptureRequest
    var onFinish: () -> Void
    /// Wired by the host so "See in Ocean" can focus the fragment after the
    /// overlay dismisses (the overlay sits outside AppState's environment).
    var onOpenNode: ((UUID) -> Void)? = nil
    /// Presented as a sheet (from inside a current) rather than over the
    /// tabs: no dim backdrop, and the button is the sheet's own.
    var asSheet = false

    private enum Phase: Equatable {
        /// Typing, or waiting for a hold.
        case composing
        /// A take is live under the finger (or locked).
        case listening
        /// The finger lifted: the words sink while the save is verified.
        case settling
        /// Saved. The card names what the Ocean understood.
        case moment
        /// The card is gone; only the way back remains until the undo
        /// window closes.
        case linger
    }

    @State private var phase: Phase = .composing
    @State private var text: String
    @State private var imageData: Data?
    @State private var session = CaptureSession()
    /// Words of the take that just ended, held for the settle animation.
    @State private var settlingWords = ""
    @State private var settled = false
    /// A take the store refused, or one taken back: its audio rides along
    /// with the next release so nothing recorded is lost.
    @State private var heldDraft: CaptureDraft?
    @State private var message: String?
    @State private var isSaving = false
    @State private var hasStarted = false
    @State private var moment: PostCaptureMoment?
    @State private var fadeTask: Task<Void, Never>?
    @FocusState private var textFocused: Bool

    init(
        request: FastCaptureRequest,
        onFinish: @escaping () -> Void,
        onOpenNode: ((UUID) -> Void)? = nil,
        asSheet: Bool = false
    ) {
        self.request = request
        self.onFinish = onFinish
        self.onOpenNode = onOpenNode
        self.asSheet = asSheet
        _text = State(initialValue: request.seedText)
        _imageData = State(initialValue: request.imageData)
    }

    private var listening: Bool { phase == .listening }

    var body: some View {
        GeometryReader { geo in
        // With the keyboard up the bottom safe area is the keyboard itself,
        // so the card sits right on it; otherwise it clears the tab bar.
        let keyboardUp = geo.safeAreaInsets.bottom > 120
        ZStack(alignment: .bottom) {
            backdrop

            VStack(alignment: .leading, spacing: 14) {
                switch phase {
                case .composing:
                    composer
                case .listening, .settling:
                    // One subtitle block across the take and its settle, so
                    // the words that were spoken are the words that sink.
                    WhisperSubtitles(
                        text: listening ? session.transcriber.partial : settlingWords,
                        showsPlaceholder: listening && !wordsDelayed
                    )
                    .modifier(SettleIntoWater(progress: phase == .settling && settled ? 1 : 0, stilled: stilled))
                    .animation(
                        stilled ? .easeOut(duration: 0.2) : .timingCurve(0.45, 0, 0.75, 1, duration: 0.5),
                        value: settled
                    )
                    if listening {
                        listeningRow
                    }
                case .moment:
                    if let moment {
                        PostCaptureMomentView(
                            moment: moment,
                            onSeeInOcean: request.anchorThemeKey == nil ? { seeInOcean(moment) } : nil,
                            onUndo: session.undoAvailable(for: moment.id) ? { undoFromMoment() } : nil
                        )
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                case .linger:
                    undoPill
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, phase == .linger ? 24 : (asSheet || keyboardUp ? 12 : FastCaptureLayout.tabBarClearance))
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: phase)
        }
        }
        .task {
            control.overlayOpen = true
            session.configure(context: context, ai: ai)
            session.onUnderstood = { nodeID, title in
                advanceMoment(nodeID: nodeID, title: title)
            }
            guard !hasStarted else { return }
            hasStarted = true
            if control.touch != .up {
                // The hold began on the floating button: keep listening.
                await startListening()
            } else if request.inputPreference == .voiceFirst {
                // A widget, the Action Button, Control Center: no finger to
                // hold, so the take locks and runs until Stop.
                control.touch = .locked
                await startListening()
            } else {
                textFocused = true
            }
        }
        .onDisappear {
            control.overlayOpen = false
            control.isListening = false
            control.level = 0
            if control.touch == .locked { control.touch = .up }
        }
        .onChange(of: control.touch) { old, new in
            switch new {
            case .held, .locked:
                if phase == .composing { Task { await startListening() } }
            case .up:
                if case .held = old, listening { Task { await catchTake() } }
            }
        }
        .onChange(of: control.stopCount) { _, _ in
            if listening { Task { await catchTake() } }
        }
        .onChange(of: control.tapCount) { _, _ in
            if phase == .composing { textFocused = true }
        }
        .onChange(of: session.transcriber.level) { _, level in
            control.level = listening ? level : 0
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            finishInterruptedCapture()
        }
    }

    // MARK: Pieces

    private var backdrop: some View {
        Color.black.opacity(asSheet || phase == .linger ? 0 : 0.24)
            .ignoresSafeArea()
            .allowsHitTesting(phase != .linger)
            .contentShape(Rectangle())
            .onTapGesture {
                // Open water: fold the keyboard, or leave if nothing is here.
                if phase == .composing, text.trimmed.isEmpty, imageData == nil, heldDraft == nil {
                    cancel()
                } else {
                    textFocused = false
                }
            }
    }

    private var composer: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // The way out stands just above the card's corner, off its body,
            // so it never reads as a badge on the words.
            closeButton
                .padding(.trailing, -4)
            composerCard
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var composerCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                if let imageData, let uiImage = UIImage(data: imageData) {
                    screenshotPreview(uiImage)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    TextField("What are you noticing?", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .lineLimit(1...6)
                        .lineSpacing(2)
                        .focused($textFocused)
                        .foregroundStyle(OceanTheme.foam)
                        .tint(OceanTheme.accent)
                        .submitLabel(.return)
                        .padding(.vertical, 6)
                        .padding(.leading, 4)

                    if canRelease {
                        Button(action: saveTyped) {
                            Image(systemName: "arrow.up")
                                .font(.subheadline.weight(.bold))
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(ReleasePillStyle())
                        .disabled(isSaving)
                        .accessibilityLabel("Release into the Ocean")
                        .transition(.scale.combined(with: .opacity))
                    }

                    overlayDisc
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(OceanTheme.mist)
                }

                if let anchor = request.anchorThemeKey {
                    Text(String(localized: "Flows into “\(OceanLayoutEngine.displayLabel(for: anchor))”"))
                        .font(.caption2)
                        .foregroundStyle(OceanTheme.faint)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: canRelease)
        }
        // A lifted glass body: the depth shadow gives it presence over the
        // water, no rim or glow (Philosophy §4).
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }

    /// Under the subtitles while listening: a note already typed stays
    /// visible (it releases with the whisper), and the one honest line when
    /// no live words are coming.
    private var listeningRow: some View {
        HStack(alignment: .center, spacing: 10) {
            // The way out mid-take: cancels, nothing is saved yet. On the
            // far side from the button, so the finger sliding up to lock
            // never crosses it.
            closeButton
                .padding(.leading, -4)
            listeningNotes
            Spacer(minLength: 8)
            overlayDisc
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    /// The overlay's own disc, in the composer row and the listening row.
    /// While the hold that opened this overlay still has its finger on the
    /// capture bar's disc, that disc owns the gesture and this one stays
    /// out of the way (the bar is still drawn beneath the backdrop).
    private var overlayDisc: some View {
        CaptureHoldButton(size: FastCaptureLayout.buttonSize)
            .allowsHitTesting(asSheet || control.touch == .up)
            .opacity(asSheet || control.touch == .up ? 1 : 0.35)
    }

    private var listeningNotes: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !text.trimmed.isEmpty {
                // The typed note riding along with the whisper.
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(OceanTheme.mist)
                    .lineLimit(2)
            }
            if wordsDelayed {
                Text("Words will follow.")
                    .font(.footnote)
                    .foregroundStyle(OceanTheme.hint)
            }
        }
        // Depth, not glow: keeps small words legible over a body behind them.
        .shadow(color: .black.opacity(0.55), radius: 8)
    }

    /// No live words are coming for this take (recognition preparing or
    /// unavailable): the subtitle area stays empty and one line says so.
    private var wordsDelayed: Bool {
        session.transcriber.speechAvailability == .preparing
            || session.transcriber.speechAvailability == .unavailable
    }

    private var stilled: Bool { reduceMotion || calm }

    /// Mid-take it cancels (nothing is saved yet); composing it closes. A
    /// small glass body like the capture button, not a badge on the card.
    private var closeButton: some View {
        Button(action: cancel) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OceanTheme.mist)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 0.5
                    )
                )
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(listening ? Text("Cancel whisper") : Text("Close"))
    }

    private var undoPill: some View {
        HStack {
            Spacer()
            Button(action: undoFromMoment) {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(OceanTheme.mist)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .accessibilityLabel("Undo capture")
            Spacer()
        }
        .transition(.opacity)
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

    private var canRelease: Bool {
        !text.trimmed.isEmpty || imageData != nil || heldDraft?.audioData != nil
    }

    // MARK: Listening

    private func startListening() async {
        guard phase == .composing, !session.transcriber.isRecording else { return }
        textFocused = false
        message = nil
        let started = await session.startRecording(onInterruption: { [self] in
            // A call, Siri, a lost mic: the take ends as a lift would.
            Task { await catchTake() }
        })
        guard started == .started else {
            control.touch = .up
            control.isListening = false
            if started == .permissionDenied {
                message = String(localized: "Typing is ready.")
            }
            textFocused = true
            return
        }
        control.isListening = true
        // The finger left while permission was being asked (or the take was
        // started without one): the take runs until Stop.
        if control.touch == .up { control.touch = .locked }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { phase = .listening }
    }

    /// Lift = catch. Saved before anything says so; the settle is the
    /// confirmation and only runs once the save is verified.
    @MainActor
    private func catchTake() async {
        guard listening else { return }
        let elapsed = session.transcriber.elapsed
        let (url, transcript) = await session.stopRecording()
        control.isListening = false
        control.level = 0
        if control.touch == .locked { control.touch = .up }

        let note = text.trimmed
        let words = transcript.trimmed

        // A press just past the hold threshold with nothing said: not a
        // thought. Back to the field, keyboard up, nothing minted.
        if words.isEmpty, note.isEmpty, imageData == nil, heldDraft == nil, elapsed < 1 {
            if let url { try? FileManager.default.removeItem(at: url) }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { phase = .composing }
            textFocused = true
            return
        }

        var draft = heldDraft ?? CaptureDraft()
        draft.kind = .voice
        draft.text = note
        draft.transcript = [draft.transcript, words].map(\.trimmed).filter { !$0.isEmpty }.joined(separator: " ")
        if let url, let data = CaptureSession.readAudio(url) {
            draft.audioData = data
            draft.audioTempURL = url
        }
        draft.imageData = imageData
        draft.anchorThemeKey = request.anchorThemeKey
        heldDraft = nil

        settlingWords = words.isEmpty ? note : words
        settled = false
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { phase = .settling }

        guard let nodeID = session.release(draft) else {
            // The store refused: the words come back to the field, the audio
            // rides along with the next release. Never a silent loss.
            heldDraft = draft
            text = [note, words].filter { !$0.isEmpty }.joined(separator: " ")
            message = String(localized: "Couldn't save yet. Release tries again.")
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { phase = .composing }
            return
        }

        isSaving = true
        session.beginUnderstanding(nodeID: nodeID)
        CaptureFeedback.released()
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeIn(duration: 0.55)) { settled = true }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 520))
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            moment = .received(for: nodeID)
            phase = .moment
        }
        scheduleFinish(after: 2.4)
    }

    // MARK: Typed release

    private func saveTyped() {
        guard !isSaving, canRelease else { return }
        let trimmed = text.trimmed
        var draft = heldDraft ?? CaptureDraft()
        if draft.audioData != nil {
            draft.kind = .voice
            // The words in the field are the whisper's words, possibly
            // corrected; the field is the transcript now.
            draft.transcript = trimmed
            draft.text = ""
        } else {
            draft.kind = (imageData != nil && trimmed.isEmpty) ? .image : .text
            draft.text = trimmed
        }
        draft.imageData = imageData
        draft.anchorThemeKey = request.anchorThemeKey
        guard let nodeID = session.release(draft) else {
            message = String(localized: "Couldn't save yet. Release tries again.")
            return
        }
        heldDraft = nil
        isSaving = true
        message = nil
        session.beginUnderstanding(nodeID: nodeID)
        textFocused = false
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            moment = .received(for: nodeID)
            phase = .moment
        }
        CaptureFeedback.released()
        scheduleFinish(after: 2.4)
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
            await MainActor.run { finishOrLinger() }
        }
    }

    /// The card's beat is over. If the thought can still be taken back, the
    /// overlay shrinks to a quiet Undo pill (backdrop gone) and finishes
    /// only when the undo window actually closes.
    @MainActor
    private func finishOrLinger() {
        guard let nodeID = moment?.id, session.undoAvailable(for: nodeID) else {
            onFinish()
            return
        }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            phase = .linger
            moment = nil
        }
        fadeTask = Task {
            while !Task.isCancelled, session.undoAvailable(for: nodeID) {
                try? await Task.sleep(for: .seconds(0.5))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { onFinish() }
        }
    }

    /// Take the released thought back: it returns to the field, words,
    /// recording and image intact, and never entered the Ocean.
    private func undoFromMoment() {
        fadeTask?.cancel()
        guard let draft = session.undoLastRelease() else {
            if phase == .linger { onFinish() }
            return
        }
        isSaving = false
        heldDraft = draft.audioData != nil ? draft : nil
        text = [draft.text, draft.transcript].map(\.trimmed).filter { !$0.isEmpty }.joined(separator: " ")
        imageData = draft.imageData
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            moment = nil
            phase = .composing
        }
        textFocused = true
    }

    private func seeInOcean(_ moment: PostCaptureMoment) {
        fadeTask?.cancel()
        onOpenNode?(moment.id)
        onFinish()
    }

    /// The X. Mid-take it cancels the take (nothing is saved yet); after a
    /// release it only closes, never deletes. Deleting is Undo's job.
    private func cancel() {
        fadeTask?.cancel()
        if listening {
            Task { await session.transcriber.cancel() }
            control.isListening = false
            control.level = 0
            control.touch = .up
            onFinish()
            return
        }
        if let url = heldDraft?.audioTempURL {
            try? FileManager.default.removeItem(at: url)
        }
        onFinish()
    }

    private func finishInterruptedCapture() {
        if listening {
            Task { await catchTake() }
        }
    }
}

// MARK: - Subtitles

/// The words of a live take, laid on the water: large, unframed, the newest
/// at the bottom, the oldest fading out above. Only the tail is kept so the
/// block never grows past a few lines. Each word surfaces: it rises a little
/// out of a soft blur, the way something comes up through water.
struct WhisperSubtitles: View {
    let text: String
    var maxWords = 32
    /// "Listening" while waiting for the first word. Off when no live words
    /// are coming (the area stays empty) and while the words settle.
    var showsPlaceholder = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calmAccessibility) private var calm

    private var stilled: Bool { reduceMotion || calm }

    private var words: [(id: Int, word: String)] {
        let all = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let start = max(0, all.count - maxWords)
        return all.enumerated().dropFirst(start).map { ($0.offset, $0.element) }
    }

    /// Brightness carries recency: the last few words are foam, older ones
    /// ease back toward mist before the top mask takes them.
    private func opacity(for id: Int, newest: Int) -> Double {
        let age = Double(newest - id)
        return max(0.6, 1 - max(0, age - 5) * 0.03)
    }

    private var surfacing: AnyTransition {
        guard !stilled else { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: Surfacing(progress: 0),
                identity: Surfacing(progress: 1)
            ),
            removal: .opacity
        )
    }

    var body: some View {
        let entries = words
        let newest = entries.last?.id ?? 0
        Group {
            if entries.isEmpty {
                if showsPlaceholder {
                    Text("Listening")
                        .font(.title2)
                        .foregroundStyle(OceanTheme.hint)
                        .transition(.opacity)
                }
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(entries, id: \.id) { entry in
                        Text(entry.word)
                            .font(.title.weight(.medium))
                            .foregroundStyle(OceanTheme.foam)
                            .opacity(opacity(for: entry.id, newest: newest))
                            .transition(surfacing)
                    }
                }
                .animation(stilled ? .easeOut(duration: 0.2) : .easeOut(duration: 0.42), value: entries.map(\.id))
            }
        }
        // Words lie on open water, unframed; a soft dark depth under them
        // (never a glow) keeps them legible over the field's bodies.
        .shadow(color: .black.opacity(0.55), radius: 10)
        .frame(maxWidth: .infinity, maxHeight: 220, alignment: .bottomLeading)
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.32), .init(color: .black, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.isEmpty ? Text("Listening") : Text(text))
    }
}

/// A word coming up through the water: from a little below, out of a soft
/// blur, into focus.
private struct Surfacing: ViewModifier {
    var progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 6)
            .offset(y: (1 - progress) * 10)
            .scaleEffect(0.96 + 0.04 * progress, anchor: .bottom)
    }
}

/// The words settling into the Ocean after release. They sink a short way
/// and lose focus while a waterline rises through them from below, so the
/// last line goes under first. Stilled (Reduce Motion, Calm Accessibility
/// Mode) it is a plain fade.
private struct SettleIntoWater: ViewModifier, Animatable {
    var progress: Double
    var stilled: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        if stilled {
            content.opacity(1 - progress)
        } else {
            let line = 1 - 1.3 * progress
            let edge = min(1, max(0, line))
            let feather = min(1, max(edge, line + 0.28))
            content
                .scaleEffect(1 - 0.04 * progress, anchor: .bottom)
                .offset(y: 30 * progress)
                .blur(radius: 7 * progress)
                .opacity(1 - 0.35 * progress)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: edge),
                            .init(color: .clear, location: feather)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

/// The Release button. Ready, it is the accent with abyss ink, the same
/// pairing the Ocean uses for landing; while saving it steps back to a
/// readable grey. Pressed, it sinks a touch rather than dimming.
struct ReleasePillStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isEnabled ? OceanTheme.accent : Color.white.opacity(0.12), in: Circle())
            .foregroundStyle(isEnabled ? OceanTheme.abyss : Color.white.opacity(0.62))
            .shadow(color: .black.opacity(isEnabled && !configuration.isPressed ? 0.3 : 0), radius: 6, y: 3)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isEnabled)
    }
}
