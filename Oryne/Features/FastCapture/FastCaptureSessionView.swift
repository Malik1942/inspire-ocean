import SwiftUI
import SwiftData
import PhotosUI

/// The one capture surface. Every entry point (the floating button, the
/// Action Button, Control Center, the widget, Siri, a share, a current's +)
/// lands here.
///
/// Tap the bar's words to type. Tap its disc to whisper and tap Stop to
/// keep it, or hold the disc and lift. While a take is live the words land
/// on the water as subtitles and the disc breathes with the microphone.
/// Then the words settle into the Ocean: saved first, then the chime, then
/// one toast above the bar with the way back. No review beat, no mode
/// picker (docs/plans/phone-refocus/SPEC.md, Phase 1).
struct FastCaptureSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.oceanAI) private var ai
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calmAccessibility) private var calm
    @Environment(CaptureControl.self) private var control

    let request: FastCaptureRequest
    var onFinish: () -> Void
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
        /// Saved. The overlay is only its toast, above the bar, until the
        /// undo window closes or the next capture starts.
        case linger
    }

    @State private var phase: Phase = .composing
    @State private var text: String
    /// The pictures on the card, in the order they were added.
    @State private var images: [CaptureImage]
    /// Pictures picked but still loading: a quiet tile each.
    @State private var pendingImages = 0
    /// The send was tapped while pictures were still loading: it goes once
    /// they are in, so a release never leaves one behind.
    @State private var releaseWhenLoaded = false
    /// The + panel stands in the keyboard's place: the latest photos,
    /// Camera, All Photos.
    @State private var attachPanelShown = false
    @State private var cameraShown = false
    @State private var libraryShown = false
    @State private var libraryItems: [PhotosPickerItem] = []
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
    @State private var fadeTask: Task<Void, Never>?
    /// The composer's card is open: two rows. It is drawn closed first, at
    /// the bar's capsule, and unfolds from there; closing folds it back.
    @State private var cardOpen = false
    /// Where the keyboard is headed, in screen points, from its own
    /// notifications. Only consulted when the safe area missed it.
    @State private var keyboardFrame: CGRect?
    @FocusState private var textFocused: Bool

    init(
        request: FastCaptureRequest,
        onFinish: @escaping () -> Void,
        asSheet: Bool = false
    ) {
        self.request = request
        self.onFinish = onFinish
        self.asSheet = asSheet
        _text = State(initialValue: request.seedText)
        // The Action Button's screenshot joins in `.task`: this view is
        // rebuilt whenever the tabs redraw, and a decode here would rerun.
        _images = State(initialValue: [])
    }

    private var listening: Bool { phase == .listening }

    var body: some View {
        GeometryReader { geo in
        // With the keyboard up the bottom safe area is the keyboard itself,
        // so the card sits right on it; otherwise it clears the tab bar.
        // Whatever of the keyboard SwiftUI missed lifts the card on top.
        let missed = missedKeyboard(in: geo)
        let keyboardUp = geo.safeAreaInsets.bottom + missed > 120
        ZStack(alignment: .bottom) {
            backdrop

            if attachPanelShown, phase == .composing {
                CaptureAttachPanel(
                    showsStrip: !asSheet,
                    onPick: { item in
                        attach([item])
                        textFocused = true
                    },
                    onCamera: {
                        closePanel()
                        cameraShown = true
                    },
                    onLibrary: {
                        closePanel()
                        libraryShown = true
                    }
                )
                .frame(height: panelHeight)
                .padding(.horizontal, OceanSpacing.gutter)
                .transition(stilled ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }

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
                    .opacity(phase == .settling && settled ? 0 : 1)
                    .offset(y: phase == .settling && settled ? 24 : 0)
                    .animation(.easeIn(duration: 0.3), value: settled)
                    if listening {
                        listeningRow
                    }
                case .linger:
                    HStack {
                        Spacer(minLength: 0)
                        CaptureToast(onUndo: undoCapture)
                        Spacer(minLength: 0)
                    }
                    .transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
            .padding(.horizontal, OceanSpacing.gutter)
            .padding(.bottom, bottomPadding(keyboardUp: keyboardUp) + missed)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: phase)
            .animation(.easeOut(duration: 0.25), value: missed)
        }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            keyboardFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        }
        .task {
            control.overlayID = request.id
            control.overlayOpen = true
            // A panel an earlier overlay left open is not this one's.
            control.attachPanelOpen = false
            session.configure(context: context, ai: ai)
            guard !hasStarted else { return }
            hasStarted = true
            // The Action Button's screenshot is the card's first picture,
            // decoded once, off the main actor.
            if let screenshot = request.imageData {
                let shot = await CaptureImage.make(from: [screenshot])
                withAnimation(motion) { images.insert(contentsOf: shot, at: 0) }
            }
            // Opened to type: a draft put away earlier is back in the field
            // (before the bar's send below looks for it).
            if control.touch == .up, request.inputPreference != .voiceFirst,
               request.seedText.isEmpty, request.imageData == nil, request.anchorThemeKey == nil {
                takeBackParked()
            }
            if control.touch != .up {
                // The hold began on the floating button: keep listening.
                await startListening()
            } else if request.inputPreference == .voiceFirst {
                // A widget, the Action Button, Control Center: no finger to
                // hold, so the take locks and runs until Stop.
                control.touch = .locked
                await startListening()
            } else if control.releaseParked {
                // The bar's send: the parked draft goes straight in.
                control.releaseParked = false
                if canRelease { saveTyped() } else { openCard(); textFocused = true }
            } else {
                textFocused = true
            }
        }
        .onDisappear {
            // A take still live here ends with the overlay (a sheet swiped
            // away mid-take): nothing records in a view that is gone.
            if session.transcriber.isRecording { Task { await session.transcriber.cancel() } }
            releaseControl()
        }
        .onChange(of: control.touch) { old, new in
            guard ownsControl else { return }
            switch new {
            case .held, .locked:
                // A tap or a hold on the bar's disc while the toast shows
                // starts the next take.
                if phase == .linger { beginNextCapture() }
                if phase == .composing { Task { await startListening() } }
            case .up:
                guard case .held(let since) = old, listening else { break }
                if Date.now.timeIntervalSince(since) < 0.4, session.transcriber.partial.trimmed.isEmpty {
                    // Let go before a word, just past the hold threshold:
                    // a slow tap, so the take runs on until Stop or ✕.
                    control.touch = .locked
                } else {
                    Task { await catchTake() }
                }
            }
        }
        .onChange(of: control.stopCount) { _, _ in
            if ownsControl, listening { Task { await catchTake() } }
        }
        .onChange(of: control.releaseParked) { _, release in
            // The bar's send while the toast shows: the next release.
            guard ownsControl, release, phase == .linger else { return }
            control.releaseParked = false
            beginNextCapture()
            saveTyped()
        }
        .onChange(of: control.tapCount) { _, _ in
            // A tap on the bar while the toast shows starts the next thought.
            guard ownsControl else { return }
            if phase == .linger { beginNextCapture() }
            if phase == .composing { textFocused = true }
        }
        .onChange(of: session.transcriber.level) { _, level in
            if ownsControl { control.level = listening ? level : 0 }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            finishInterruptedCapture()
        }
        // Focusing the words (a tap on the field, the + again, a photo
        // picked) brings the keys back and the panel steps aside; so does
        // anything that ends composing.
        .onChange(of: textFocused) { _, focused in
            if focused { closePanel() }
        }
        .onChange(of: phase) { _, phase in
            if phase != .composing { attachPanelShown = false }
        }
        .onChange(of: attachPanelShown) { _, shown in
            // The tab bar steps away under the panel, as under the keys. A
            // composer in a sheet leaves the page behind it alone.
            if ownsControl, !asSheet { withAnimation(motion) { control.attachPanelOpen = shown } }
        }
        .fullScreenCover(isPresented: $cameraShown, onDismiss: { textFocused = true }) {
            CameraPicker(onFinish: attachShot)
                .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $libraryShown,
            selection: $libraryItems,
            maxSelectionCount: max(room, 1),
            selectionBehavior: .ordered,
            matching: .images
        )
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            libraryItems = []
            attach(items)
        }
        .onChange(of: libraryShown) { _, shown in
            if !shown { textFocused = true }
        }
    }

    // MARK: Pieces

    private var backdrop: some View {
        Color.black.opacity(asSheet || phase == .linger ? 0 : 0.24)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                // Open water puts the card away; anything in it waits in
                // the bar. In a sheet (no bar) it only folds the keyboard
                // while there is something to keep; the sheet swipes away.
                // Pictures still loading keep the card out until they land:
                // the bar can't hold a picture that hasn't arrived.
                if phase == .composing, pendingImages == 0, !(asSheet && canRelease) {
                    putAway()
                } else {
                    textFocused = false
                    closePanel()
                }
            }
            // Outermost, so the content shape steps aside with it: while
            // only the toast shows, every other tap reaches the tabs.
            .allowsHitTesting(phase != .linger)
    }

    /// Typing: the bar's capsule unfolds into a card on two rows. The words
    /// on top, across the whole card; under them one disc at the trailing
    /// end, which whispers while the field is empty and sends once there
    /// are words. The disc sits where the bar's disc sits, so the card
    /// grows up from it and it never moves. There is no close: open water
    /// folds the card back into the bar, and what was typed waits there.
    /// Both rows stay for the whole session, empty or not.
    private var composer: some View {
        VStack(alignment: .leading, spacing: cardInset) {
            // What rides along sits above the words, only while the card
            // is open, so the fold still lands on the bar's one line.
            if cardShown, !images.isEmpty || pendingImages > 0 {
                CaptureAttachments(images: images, pending: pendingImages, onRemoveImage: removeImage)
                    .transition(.opacity)
            }
            // Closed, the actions lie over the field's row, as on the bar.
            VStack(alignment: .leading, spacing: cardShown ? 8 : -FastCaptureLayout.buttonSize) {
                composerField
                actionRow
            }
        }
        // Open, one inset on every side: the lines start and wrap where the
        // disc's edges are. Closed, the bar's own geometry.
        .padding(cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Everything in the card rides with it while it folds and the
        // keyboard drops; nothing inside jumps ahead to where it will end.
        .geometryGroup()
        .background(OceanBarBackground(
            cornerRadius: cardShown ? FastCaptureLayout.cardRadius : FastCaptureLayout.endRadius,
            style: .continuous
        ))
        // Reduce Motion: nothing unfolds; the open card fades in instead.
        .opacity(stilled && !cardOpen ? 0 : 1)
        // Folding away, it takes no more touches: a hold on the disc now
        // would start a take the closing overlay then drops.
        .allowsHitTesting(cardShown)
        // A new line grows the card upward at once, as in Messages: an
        // animated resize lets the field scroll its words up and back.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            // The card and the 12 pt gap under it (bottomPadding).
            if !asSheet { control.composerHeight = height + 12 }
        }
        .onAppear(perform: openCard)
        .onDisappear {
            cardOpen = false
            control.composerHeight = 0
        }
        .transition(.opacity)
    }

    /// The bar's own words in its own color, so opening the keyboard
    /// changes nothing but the cursor. Open, the field spans the card and
    /// grows to six lines, then scrolls; closed, it is the bar's one line,
    /// clear of the disc.
    private var composerField: some View {
        TextField(
            "What are you noticing?",
            text: $text,
            prompt: Text("What are you noticing?").foregroundStyle(OceanTheme.hint),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.body)
        .lineLimit(cardShown ? 1...6 : 1...1)
        .lineSpacing(2)
        .focused($textFocused)
        .foregroundStyle(OceanTheme.foam)
        .tint(OceanTheme.accent)
        .submitLabel(.return)
        // Folded, the card reads exactly as the bar does: its question, or
        // the first line of the words, cut with an ellipsis.
        .opacity(cardShown ? 1 : 0)
        .overlay(alignment: .topLeading) {
            CaptureBarWords(draft: hasDraft ? ParkedCapture(text: text, images: images, heldDraft: heldDraft).line : nil)
                .opacity(cardShown ? 0 : 1)
                .accessibilityHidden(true)
        }
        // Open, the first line keeps a fixed place under the top edge and
        // the lines span the card's inset. Closed, the field is the bar's
        // one line: where its placeholder sits, centered, clear of the disc.
        .padding(.vertical, cardShown ? 2 : 10)
        .padding(.leading, cardShown ? 0 : FastCaptureLayout.fieldLeading - FastCaptureLayout.discInset)
        .padding(.trailing, cardShown ? 0 : FastCaptureLayout.buttonSize + 8)
        .frame(maxWidth: .infinity, minHeight: cardShown ? nil : FastCaptureLayout.buttonSize, alignment: .leading)
        .accessibilityIdentifier("composer.field")
    }

    /// The card's padding: its one inset open, the bar's disc inset closed.
    private var cardInset: CGFloat {
        cardShown ? FastCaptureLayout.cardInset : FastCaptureLayout.discInset
    }

    /// The card's second row, at its foot: the + at the leading end, the
    /// disc at the trailing end, and between them what the card has to
    /// say. Folded, only the disc shows, as on the bar.
    private var actionRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Group {
                attachButton
                composerCaptions
            }
            .opacity(cardShown ? 1 : 0)
            Spacer(minLength: 0)
            overlayDisc(inComposer: true, send: canRelease ? saveTyped : nil)
        }
        .frame(minHeight: FastCaptureLayout.buttonSize)
    }

    /// The card's +, the send disc's twin: it swaps the keyboard for the
    /// panel (the latest photos, Camera, All Photos), and back again.
    /// Dimmed once the thought holds all the pictures it can.
    private var attachButton: some View {
        Button {
            if attachPanelShown {
                textFocused = true
            } else {
                openPanel()
            }
        } label: {
            Image(systemName: "plus")
        }
        .buttonStyle(.oceanIcon)
        .disabled(room == 0)
        .opacity(room == 0 ? 0.4 : 1)
        .accessibilityLabel(attachPanelShown ? Text("Show keyboard") : Text("Add image"))
        .accessibilityIdentifier("composer.attach")
    }

    /// A refusal, and the current a thought added from a stream flows
    /// into: in the action row before the disc, inside the card.
    private var composerCaptions: some View {
        VStack(alignment: .leading, spacing: 2) {
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
        .lineLimit(2)
    }

    private var cardShown: Bool { cardOpen || stilled }

    /// The card unfolds from the bar's capsule as the keyboard rises. With
    /// Reduce Motion it is open from the start and fades in instead. Not
    /// for the bar's send: that draft goes straight in, the card unopened.
    private func openCard() {
        guard phase == .composing, !control.releaseParked else { return }
        withAnimation(motion) { cardOpen = true }
    }

    /// Open water: the card folds back into the bar. Anything in it waits
    /// there, its first line showing, until the bar is tapped again.
    private func putAway() {
        fadeTask?.cancel()
        textFocused = false
        closePanel()
        // A send waiting on pictures goes no further: the draft waits instead.
        releaseWhenLoaded = false
        if hasDraft, !asSheet {
            control.parked = ParkedCapture(text: text, images: images, heldDraft: heldDraft)
        }
        closeCard()
    }

    /// A draft put away earlier comes back to the field.
    private func takeBackParked() {
        guard !asSheet, let parked = control.parked else { return }
        control.parked = nil
        text = parked.text
        images = parked.images
        heldDraft = parked.heldDraft
    }

    /// This overlay holds the shared capture state (the bar's taps, the
    /// take's level) until it finishes or a newer overlay takes over.
    private var ownsControl: Bool { control.overlayID == request.id }

    /// Done: hand the bar back first, then close. A tap on the disc while
    /// this overlay still fades out opens the next one at once instead of
    /// landing here.
    private func finish() {
        releaseControl()
        onFinish()
    }

    /// Lets go of the shared capture state, unless a newer overlay has
    /// already taken it.
    private func releaseControl() {
        guard ownsControl else { return }
        control.overlayID = nil
        control.overlayOpen = false
        control.composerHeight = 0
        control.attachPanelOpen = false
        control.toastShowing = false
        control.isListening = false
        control.level = 0
        if control.touch == .locked { control.touch = .up }
    }

    /// The card folds back into the bar's capsule before the bar takes over,
    /// so the way out is the way in reversed. Reduce Motion and the sheet
    /// only fade.
    private func closeCard() {
        guard phase == .composing, cardOpen, !stilled, !asSheet else {
            finish()
            return
        }
        withAnimation(OceanMotion.standard) {
            cardOpen = false
        } completion: {
            finish()
        }
    }

    /// Listening: the same capsule in the same frame. The way out (cancel,
    /// nothing is saved yet) is a glass disc at the leading end mirroring
    /// the record disc, so Stop (keep) and ✕ (let go) sit at opposite ends.
    /// Between them, a note already typed (it releases with the whisper)
    /// and the one honest line when no live words come.
    private var listeningRow: some View {
        CaptureCapsule {
            HStack(alignment: .center, spacing: 10) {
                closeButton
                listeningNotes
                Spacer(minLength: 8)
                overlayDisc()
            }
        }
        .transition(.opacity)
    }

    /// The overlay's own disc, in the composer and the listening capsule.
    /// While the hold that opened this overlay still has its finger on the
    /// capture bar's disc (invisible, in the same frame), that disc owns
    /// the gesture; once the take locks this one is the Stop. In the
    /// composer it is the send once there are words.
    private func overlayDisc(inComposer: Bool = false, send: (() -> Void)? = nil) -> some View {
        CaptureHoldButton(size: FastCaptureLayout.buttonSize, inComposer: inComposer, send: send)
            .allowsHitTesting(asSheet || !control.isHeld)
            .accessibilityIdentifier(inComposer ? "composer.action" : "capture.overlayDisc")
    }

    private var listeningNotes: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !text.trimmed.isEmpty {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(OceanTheme.mist)
                    .lineLimit(1)
            }
            if wordsDelayed {
                Text("Words will follow.")
                    .font(.footnote)
                    .foregroundStyle(OceanTheme.hint)
            }
        }
    }

    /// No live words are coming for this take (recognition preparing or
    /// unavailable): the subtitle area stays empty and one line says so.
    private var wordsDelayed: Bool {
        session.transcriber.speechAvailability == .preparing
            || session.transcriber.speechAvailability == .unavailable
    }

    private var stilled: Bool { reduceMotion || calm }

    /// The listening capsule's way out: it cancels the take (nothing is
    /// saved yet). A small glass body like the capture button, not a badge
    /// on the card. The composer has none; open water puts it away.
    private var closeButton: some View {
        Button(action: cancel) {
            Image(systemName: "xmark")
        }
        .buttonStyle(.oceanIcon)
        .accessibilityLabel(listening ? Text("Cancel whisper") : Text("Close"))
        .accessibilityIdentifier("capture.close")
    }

    /// Composing and listening clear the tab bar (or sit on the keyboard);
    /// the toast sits above the capture bar, which stays usable under it.
    private func bottomPadding(keyboardUp: Bool) -> CGFloat {
        if phase == .linger {
            if asSheet { return 24 }
            // Above the bar on Tide; in the bar's own spot where there is none.
            return FastCaptureLayout.tabBarClearance
                + (control.barOnTab ? FastCaptureLayout.barHeight + 12 : 0)
        }
        if attachPanelShown { return panelHeight + 12 }
        return asSheet || keyboardUp ? 12 : FastCaptureLayout.tabBarClearance
    }

    /// The panel stands where the keys stood, so the card stays put when +
    /// swaps them: the keyboard's height less the home indicator's inset,
    /// which the panel keeps clear of. Inside a current's sheet it is only
    /// its rows (no strip there).
    private var panelHeight: CGFloat {
        let least = CaptureAttachPanel.leastHeight(showsStrip: !asSheet)
        guard !asSheet else { return least }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let resting = scene?.keyWindow?.safeAreaInsets.bottom ?? 0
        let keys = keyboardFrame?.height ?? CaptureAttachPanel.usualKeyboardHeight
        return max(keys - resting, least)
    }

    /// The card's and the panel's one motion; Reduce Motion takes the
    /// quick one.
    private var motion: Animation { stilled ? OceanMotion.quick : OceanMotion.standard }

    private func openPanel() {
        textFocused = false
        withAnimation(motion) { attachPanelShown = true }
    }

    private func closePanel() {
        guard attachPanelShown else { return }
        withAnimation(motion) { attachPanelShown = false }
    }

    /// The part of the keyboard the safe area left out. SwiftUI can miss a
    /// keyboard that rises while a pushed thought page pops (Undo from the
    /// page, or the bar tapped as the page closes): the overlay keeps only
    /// the home indicator inset and the card sits under the keys until the
    /// keyboard next moves. Usually the safe area already ends at the
    /// keyboard's top and this is nothing.
    private func missedKeyboard(in geo: GeometryProxy) -> CGFloat {
        guard let keyboardFrame else { return 0 }
        let frame = geo.frame(in: .global)
        // A floating or split keyboard (iPad) never pushes content up.
        guard keyboardFrame.maxY >= frame.maxY + geo.safeAreaInsets.bottom - 1 else { return 0 }
        return max(0, frame.maxY - keyboardFrame.minY)
    }

    /// Something to release: what the card holds, or pictures on their way.
    private var canRelease: Bool { hasDraft || pendingImages > 0 }

    /// What the card holds now, which open water parks in the bar.
    private var hasDraft: Bool {
        !text.trimmed.isEmpty || !images.isEmpty || heldDraft?.audioData != nil
    }

    /// Pictures the thought can still take (`Node.maxImages` in all).
    private var room: Int { max(0, Node.maxImages - images.count - pendingImages) }

    /// A picture's ✕.
    private func removeImage(_ id: CaptureImage.ID) {
        withAnimation(.snappy) { images.removeAll { $0.id == id } }
    }

    /// Picked photos join the card in the order picked, each shrunk to the
    /// attachment size first, as many as the thought has room for; a quiet
    /// tile holds each one's place meanwhile.
    private func attach(_ items: [PhotosPickerItem]) {
        let fits = Array(items.prefix(room))
        if fits.count < items.count {
            message = String(localized: "Only added \(fits.count), \(Node.maxImages) images max.")
        }
        guard !fits.isEmpty else { return }
        pendingImages += fits.count
        Task {
            let datas = await ImageDownsampler.attachmentData(from: fits)
            await add(datas, standingIn: fits.count)
        }
    }

    /// The camera's shot, shrunk off the main actor like a picked photo.
    private func attachShot(_ shot: UIImage?) {
        cameraShown = false
        guard let shot, room > 0 else { return }
        pendingImages += 1
        Task {
            let data = await Task.detached {
                shot.jpegData(compressionQuality: 0.9).flatMap {
                    ImageDownsampler.downsample($0, maxPixel: ImageDownsampler.Size.attachment)
                }
            }.value
            await add([data].compactMap { $0 }, standingIn: 1)
        }
    }

    /// Loaded pictures take their tiles' places. A send tapped meanwhile
    /// goes now.
    @MainActor
    private func add(_ datas: [Data], standingIn placeholders: Int) async {
        let fresh = await CaptureImage.make(from: datas)
        pendingImages = max(0, pendingImages - placeholders)
        withAnimation(.snappy) { images.append(contentsOf: fresh) }
        // Only while this overlay still holds the card: a send that waited
        // here and was put away since stays put away.
        if releaseWhenLoaded, pendingImages == 0, phase == .composing, ownsControl {
            releaseWhenLoaded = false
            saveTyped()
        }
    }

    // MARK: Listening

    private func startListening() async {
        guard phase == .composing, !session.transcriber.isRecording else { return }
        textFocused = false
        closePanel()
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

        // Under a second with nothing said: not a thought, nothing minted.
        // Opened to whisper (the disc, a widget), it was a change of mind
        // and the overlay closes; opened to type, the field comes back.
        if words.isEmpty, note.isEmpty, images.isEmpty, heldDraft == nil, elapsed < 1 {
            if let url { try? FileManager.default.removeItem(at: url) }
            if request.inputPreference == .voiceFirst, !asSheet {
                finish()
                return
            }
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
        draft.imageDatas = images.map(\.data)
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
        withAnimation(.easeIn(duration: 0.3)) { settled = true }
        try? await Task.sleep(for: .milliseconds(300))
        showToast(for: nodeID)
    }

    // MARK: Typed release

    private func saveTyped() {
        guard !isSaving, canRelease else { return }
        // Pictures still loading go too: the send waits for them.
        guard pendingImages == 0 else {
            releaseWhenLoaded = true
            return
        }
        let trimmed = text.trimmed
        var draft = heldDraft ?? CaptureDraft()
        if draft.audioData != nil {
            draft.kind = .voice
            // The words in the field are the whisper's words, possibly
            // corrected; the field is the transcript now.
            draft.transcript = trimmed
            draft.text = ""
        } else {
            // `release` names a thought of only pictures (NodeKind.captured).
            draft.kind = .text
            draft.text = trimmed
        }
        draft.imageDatas = images.map(\.data)
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
        showToast(for: nodeID)
        CaptureFeedback.released()
    }

    // MARK: Toast

    /// Saved. The overlay becomes its toast for as long as the thought can
    /// be taken back, then closes. The capture bar is back the whole time.
    @MainActor
    private func showToast(for nodeID: UUID) {
        control.toastShowing = true
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { phase = .linger }
        fadeTask?.cancel()
        fadeTask = Task {
            while !Task.isCancelled, session.undoAvailable(for: nodeID) {
                try? await Task.sleep(for: .seconds(0.5))
            }
            // A tap that started the next thought cancels this; check again
            // right where the overlay would close.
            guard !Task.isCancelled, phase == .linger else { return }
            finish()
        }
    }

    /// The bar was tapped or held while the toast showed: the toast steps
    /// aside and the same overlay takes the next thought, empty, or the
    /// draft the bar was holding.
    private func beginNextCapture() {
        fadeTask?.cancel()
        isSaving = false
        text = ""
        images = []
        heldDraft = nil
        message = nil
        settlingWords = ""
        settled = false
        takeBackParked()
        control.toastShowing = false
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { phase = .composing }
    }

    /// Take the released thought back: it returns to the field, words,
    /// recording and image intact, and never entered the Ocean.
    private func undoCapture() {
        fadeTask?.cancel()
        guard let draft = session.undoLastRelease() else {
            if phase == .linger { finish() }
            return
        }
        isSaving = false
        heldDraft = draft.audioData != nil ? draft : nil
        text = [draft.text, draft.transcript].map(\.trimmed).filter { !$0.isEmpty }.joined(separator: " ")
        // The pictures come back through their loading tiles, decoded off
        // the main actor; a send meanwhile waits for them.
        images = []
        if !draft.imageDatas.isEmpty {
            pendingImages += draft.imageDatas.count
            Task { await add(draft.imageDatas, standingIn: draft.imageDatas.count) }
        }
        control.toastShowing = false
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { phase = .composing }
        textFocused = true
    }

    /// The X. Mid-take it cancels the take (nothing is saved yet); after a
    /// release it only closes, never deletes. Deleting is Undo's job.
    private func cancel() {
        fadeTask?.cancel()
        textFocused = false
        releaseWhenLoaded = false
        if listening {
            Task { await session.transcriber.cancel() }
            control.isListening = false
            control.level = 0
            control.touch = .up
            finish()
            return
        }
        if let url = heldDraft?.audioTempURL {
            try? FileManager.default.removeItem(at: url)
        }
        closeCard()
    }

    private func finishInterruptedCapture() {
        if listening {
            Task { await catchTake() }
        }
    }
}

// MARK: - Subtitles

/// The words of a live take, laid on the water: plain, unframed, newest at
/// the bottom, the oldest fading out above. They appear as they are heard
/// and leave in one piece when the take ends. Nothing performs.
struct WhisperSubtitles: View {
    let text: String
    var maxWords = 40
    /// "Listening" while waiting for the first word; off when no live words
    /// are coming and while the words settle.
    var showsPlaceholder = true

    private var tail: String {
        let all = text.split(whereSeparator: \.isWhitespace)
        return all.suffix(maxWords).joined(separator: " ")
    }

    var body: some View {
        Group {
            if tail.isEmpty {
                if showsPlaceholder {
                    Text("Listening")
                        .font(.title2)
                        .foregroundStyle(OceanTheme.hint)
                }
            } else {
                Text(tail)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(OceanTheme.foam)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .animation(.easeOut(duration: 0.15), value: tail)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 220, alignment: .bottomLeading)
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.3), .init(color: .black, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .shadow(color: .black.opacity(0.5), radius: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.isEmpty ? Text("Listening") : Text(text))
    }
}
