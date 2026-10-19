import SwiftUI
import SwiftData

/// Ask the Ocean: one question in, one grounded answer out. The four lenses
/// (Search, Synthesis, Expansion, Research) are gone from the phone; every
/// answer has the same shape: what was found (chips), what it means (one
/// short paragraph), and, only when the water was thin, a marked note from
/// beyond the Ocean (docs/plans/phone-refocus/SPEC.md, "Ask: one mode").
///
/// Summarize is a verb: a current's stream or a Library search arrives here
/// as a gathered set and is read across with a fixed question.
struct AskView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.oceanAI) private var ai
    @Environment(AppState.self) private var appState

    @Query(filter: #Predicate<Node> { !$0.isArchived }) private var nodes: [Node]

    /// The visible "ask → find → answer" beat: the Ocean is read, then the
    /// find is named, then the reply lands.
    private enum SearchPhase: Equatable {
        case reading
        case found(Int)
    }

    /// The one lens left. Stored on messages for continuity with older
    /// conversations; never shown.
    private static let mode: DialogueMode = .synthesis

    @State private var conversation: Conversation?
    @State private var input: String = ""
    @State private var searchPhase: SearchPhase?
    @FocusState private var inputFocused: Bool

    @State private var openedNode: Node?

    private var messages: [ChatMessage] { conversation?.orderedMessages ?? [] }

    var body: some View {
        NavigationStack {
            ZStack {
                PageBackground()
                transcript
                ShoreGradient()
            }
            .contentShape(Rectangle())
            // Tapping open water folds the keyboard. Buttons, rows, and the
            // input bar sit above this gesture, so their taps still win.
            .onTapGesture { inputFocused = false }
            .navigationTitle("Ask")
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { inputBar }
            .sheet(item: $openedNode) { ExpandedNodeView(node: $0) }
            .onAppear {
                consumePendingPrompt()
                consumePendingSummary()
            }
            .onChange(of: appState.pendingAskPrompt) { _, _ in consumePendingPrompt() }
            .onChange(of: appState.pendingSummary?.title) { _, _ in consumePendingSummary() }
        }
    }

    // MARK: Transcript

    /// The page reads like Tide: the title row, then each question in New
    /// York with its answer under it as plain text. No bubbles, no boxes.
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // No gear here: Ask is for asking. Settings live on Tide
                    // and the Library.
                    PageTitleRow(title: "Ask")
                    if messages.isEmpty && searchPhase == nil { emptyState }
                    ForEach(messages) { message in
                        messageView(message).id(message.id)
                    }
                    if let searchPhase { searchLine(searchPhase).id("searching") }
                }
                .padding(.horizontal, OceanSpacing.gutter)
                .padding(.top, 0)
                .padding(.bottom, OceanSpacing.block)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: searchPhase) { _, phase in
                if phase != nil { withAnimation { proxy.scrollTo("searching", anchor: .bottom) } }
            }
        }
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        if message.role == .user {
            // The question is the heading of what follows it.
            Text(message.text)
                .font(OceanType.subjectTitle)
                .foregroundStyle(OceanTheme.foam)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, message.id == messages.first?.id ? 32 : OceanSpacing.section + 8)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(AnswerMarkdown.attributed(message.text))
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(OceanTheme.foam)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if let note = provenanceNote(message) {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(OceanTheme.mist)
                        .padding(.top, 10)
                }
                // Found: the thoughts the answer drew from, each a line that
                // opens the real thing.
                if !message.referencedNodeIDs.isEmpty {
                    sources(for: message)
                        .padding(.top, OceanSpacing.block)
                }
                if let outward = message.outwardText, !outward.isEmpty {
                    outwardView(outward)
                        .padding(.top, OceanSpacing.block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
        }
    }

    /// Quiet provenance, only where silence would mislead: a cloud answer that
    /// actually came from the device, or a reply with nothing nearby behind it.
    private func provenanceNote(_ message: ChatMessage) -> String? {
        switch message.provenanceRaw.flatMap(ResponseProvenance.init(rawValue:)) {
        case .offlineFallback: String(localized: "Composed offline")
        case .noSources: String(localized: "Nothing in your Ocean matches this yet")
        case .degraded: String(localized: "Your note was long, so I worked from a shortened version")
        case .cloud, .onDevice, nil: nil
        }
    }

    /// Knowledge from beyond the user's notes, set apart by its warm label
    /// alone: lit from the open sea, not their water.
    private func outwardView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Beyond your Ocean", systemImage: "sparkles")
                .font(OceanType.eyebrow)
                .foregroundStyle(OceanTheme.glowWarm)
            Text(AnswerMarkdown.attributed(text))
                .font(.subheadline)
                .lineSpacing(4)
                .foregroundStyle(OceanTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sources(for message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Drawn from")
                .font(OceanType.eyebrow)
                .foregroundStyle(OceanTheme.mist)
                .padding(.bottom, 4)
            ForEach(sourceNodes(message), id: \.id) { node in
                Button { openedNode = node } label: {
                    ThoughtLine(node: node, showsChevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The finding, made visible where the answer will land: the Ocean read
    /// under a breathing lamp, then the find named for a beat.
    private func searchLine(_ phase: SearchPhase) -> some View {
        HStack(spacing: 8) {
            switch phase {
            case .reading:
                ThinkingText(text: String(localized: "Reading your Ocean…"))

            case .found(let count):
                Image(systemName: "water.waves")
                    .font(.footnote)
                    .foregroundStyle(OceanTheme.mist)
                Text(foundLabel(count))
                    .font(.subheadline)
                    .foregroundStyle(OceanTheme.mist)
            }
        }
        .padding(.vertical, 8)
        .background(alignment: .leading) {
            if case .reading = phase { ThinkingLamp().offset(x: -60) }
        }
        .padding(.top, 14)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: phase)
    }

    private func foundLabel(_ count: Int) -> String {
        switch count {
        case 0:  String(localized: "Nothing drifts near this yet")
        case 1:  String(localized: "Found one fragment that drifts near this")
        default: String(localized: "Found \(count) fragments that drift near this")
        }
    }

    /// One line on what Ask is for, then three questions to start from, as
    /// lines of text that fill the field.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Find a thought, or ask what a few of them mean together.")
                .font(.body)
                .foregroundStyle(OceanTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Text("Try asking")
                .font(OceanType.sectionLabel)
                .foregroundStyle(OceanTheme.mist)
                .padding(.leading, 2)
                .padding(.top, OceanSpacing.section)
                .padding(.bottom, 4)

            ForEach(samplePrompts, id: \.self) { prompt in
                Button {
                    input = prompt
                    inputFocused = true
                } label: {
                    // The same line as an answer's sources: a quiet glyph in
                    // a fixed slot, the words a step below content.
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "text.bubble")
                            .font(.footnote)
                            .foregroundStyle(OceanTheme.mist)
                            .frame(width: 18)
                        Text(prompt)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(OceanTheme.text)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: OceanControlSize.height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Puts this question in the field.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var samplePrompts: [String] {
        [String(localized: "That idea I had about water"),
         String(localized: "What patterns keep resurfacing?"),
         String(localized: "What tension am I circling?")]
    }

    // MARK: Input

    /// The capture bar's twin: the same capsule, material, height and place
    /// above the tab bar, the send disc where the capture disc sits. It grows
    /// into a rounded rectangle with the same end radius past one line.
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Ask the Ocean", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($inputFocused)
                .foregroundStyle(OceanTheme.foam)
                .tint(OceanTheme.accent)
                .lineLimit(1...4)
                .padding(.vertical, 17)

            Button(action: send) {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(OceanSendDiscStyle())
            .disabled(!canSend)
            .padding(.bottom, FastCaptureLayout.discInset)
            .accessibilityLabel("Ask")
        }
        .padding(.leading, FastCaptureLayout.barHeight / 2 - 8)
        .padding(.trailing, FastCaptureLayout.discInset)
        .frame(minHeight: FastCaptureLayout.barHeight)
        .background(OceanBarBackground(cornerRadius: FastCaptureLayout.barHeight / 2))
        .padding(.horizontal, OceanSpacing.gutter)
        .padding(.bottom, FastCaptureLayout.insetBarLift)
    }

    private var canSend: Bool { !input.trimmed.isEmpty && searchPhase == nil }

    // MARK: Logic

    private func consumePendingPrompt() {
        if let prompt = appState.pendingAskPrompt {
            input = prompt
            appState.pendingAskPrompt = nil
        }
    }

    private func consumePendingSummary() {
        guard let pending = appState.pendingSummary else { return }
        appState.pendingSummary = nil
        let wanted = Set(pending.nodeIDs)
        let set = nodes.filter { wanted.contains($0.id) }
        guard !set.isEmpty else { return }
        run(userText: String(localized: "Summarize “\(pending.title)”")) {
            await ai.summarize(set)
        }
    }

    private func ensureConversation() -> Conversation {
        if let conversation { return conversation }
        let c = Conversation(title: "Dialogue")
        context.insert(c)
        conversation = c
        return c
    }

    private func send() {
        let query = input.trimmed
        guard !query.isEmpty else { return }

        // Prior turns (before this one), for follow-up continuity.
        let history = messages.suffix(4).map {
            DialogueTurn(isUser: $0.role == .user, text: $0.text)
        }
        let snapshot = nodes
        input = ""
        // The answer is what to look at now; the keyboard would cover it.
        inputFocused = false
        run(userText: query) {
            await ai.respond(to: query, history: history, mode: Self.mode, nodes: snapshot)
        }
    }

    /// One beat for every answer: the user's line lands, the Ocean is read,
    /// the find is named, the reply arrives.
    private func run(userText: String, _ answer: @escaping () async -> OceanResponse) {
        guard searchPhase == nil else { return }
        let convo = ensureConversation()

        let userMessage = ChatMessage(role: .user, text: userText, mode: Self.mode)
        userMessage.conversation = convo
        context.insert(userMessage)
        convo.updatedAt = .now
        try? context.save()

        withAnimation { searchPhase = .reading }

        Task {
            let started = ContinuousClock.now
            let response = await answer()

            // Let the reading beat breathe even when retrieval is instant,
            // then name the find for a beat before the reply lands.
            let readingFloor: Duration = .milliseconds(500)
            let elapsed = started.duration(to: .now)
            if elapsed < readingFloor {
                try? await Task.sleep(for: readingFloor - elapsed)
            }
            await MainActor.run {
                withAnimation { searchPhase = .found(response.sourceNodeIDs.count) }
            }
            try? await Task.sleep(for: .milliseconds(700))

            await MainActor.run {
                let oceanMessage = ChatMessage(
                    role: .ocean,
                    text: composeText(response),
                    referencedNodeIDs: response.sourceNodeIDs,
                    mode: Self.mode,
                    outwardText: response.outwardNote,
                    provenanceRaw: response.provenance.rawValue
                )
                oceanMessage.conversation = convo
                context.insert(oceanMessage)
                convo.updatedAt = .now
                try? context.save()
                withAnimation { searchPhase = nil }
            }
        }
    }

    /// The answer is the reflection alone; the recurring-threads line that
    /// used to ride under it is noise on a phone (SPEC, Ask: one mode).
    private func composeText(_ response: OceanResponse) -> String {
        response.reflection
    }

    private func sourceNodes(_ message: ChatMessage) -> [Node] {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        return message.referencedNodeIDs.compactMap { byID[$0] }
    }
}

// MARK: - Thinking

/// The Ocean reading: a warm light passes slowly through the words, the
/// way light moves through water. No dots, no spinner. Still under Reduce
/// Motion and Calm Accessibility Mode.
private struct ThinkingText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calmAccessibility) private var calm

    var body: some View {
        if reduceMotion || calm {
            Text(text).font(.subheadline).foregroundStyle(OceanTheme.mist)
        } else {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                // One sweep every 1.8 s, left to right, a soft band.
                let x = CGFloat((t.truncatingRemainder(dividingBy: 1.8)) / 1.8) * 1.6 - 0.3
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(OceanTheme.mist)
                    .overlay {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(OceanTheme.glowWarm)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: max(0, x - 0.25)),
                                        .init(color: .white, location: x),
                                        .init(color: .clear, location: min(1, x + 0.25))
                                    ],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                    }
            }
        }
    }
}

/// The lamp behind the reading line, breathing: the same light Tide
/// gives its resurfacing thought, here telling you the water is awake.
private struct ThinkingLamp: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calmAccessibility) private var calm

    var body: some View {
        if reduceMotion || calm {
            lamp(0.07)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                lamp(0.075 + 0.025 * sin(t * (2 * .pi / 2.4)))
            }
        }
    }

    private func lamp(_ opacity: Double) -> some View {
        RadialGradient(
            colors: [OceanTheme.glowWarm.opacity(opacity), OceanTheme.glowWarm.opacity(opacity * 0.35), .clear],
            center: .center, startRadius: 0, endRadius: 140
        )
        .frame(width: 320, height: 200)
        .allowsHitTesting(false)
    }
}
