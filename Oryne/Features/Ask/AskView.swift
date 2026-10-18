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
                OceanBackground()
                transcript
            }
            .contentShape(Rectangle())
            // Tapping open water folds the keyboard. Buttons, chips, and the
            // input bar sit above this gesture, so their taps still win.
            .onTapGesture { inputFocused = false }
            .navigationTitle("Ask the Ocean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
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

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if messages.isEmpty && searchPhase == nil { emptyState }
                    ForEach(messages) { message in
                        messageView(message).id(message.id)
                    }
                    if let searchPhase { searchBubble(searchPhase).id("searching") }
                }
                .padding()
                // Clear of the floating capture button.
                .padding(.bottom, 8)
            }
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
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .foregroundStyle(OceanTheme.abyss)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(OceanTheme.accent.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                // Found: the chips come first, because for a lookup they are
                // the answer and the paragraph is only a reading of them.
                if !message.referencedNodeIDs.isEmpty {
                    sourceChips(for: message)
                }

                Text(AnswerMarkdown.attributed(message.text))
                    .foregroundStyle(OceanTheme.foam)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if let note = provenanceNote(message) {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(OceanTheme.faint)
                        .padding(.leading, 4)
                }
                if let outward = message.outwardText, !outward.isEmpty {
                    outwardView(outward)
                }
            }
            .padding(.trailing, 30)
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

    /// Knowledge from beyond the user's notes. A warm whisper of a rim and
    /// label set its provenance apart from the grounded reflection above it:
    /// lit from the open sea, not their water.
    private func outwardView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Beyond your Ocean", systemImage: "sparkles")
                .font(.caption2.weight(.medium))
                .foregroundStyle(OceanTheme.glowWarm)
            Text(AnswerMarkdown.attributed(text))
                .foregroundStyle(OceanTheme.foam)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(OceanTheme.glowWarm.opacity(0.25), lineWidth: 0.6)
        )
    }

    private func sourceChips(for message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Found").font(.caption2).foregroundStyle(OceanTheme.faint)
            FlowLayout(spacing: 8) {
                ForEach(sourceNodes(message), id: \.id) { node in
                    Button { openedNode = node } label: {
                        Label(node.displayTitle, systemImage: node.kind.symbol)
                            .font(.caption2).lineLimit(1)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.white.opacity(0.08), in: Capsule())
                            .foregroundStyle(OceanTheme.foam)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    /// The finding, made visible — same capsule, two quiet beats.
    private func searchBubble(_ phase: SearchPhase) -> some View {
        HStack(spacing: 8) {
            switch phase {
            case .reading:
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(OceanTheme.mist).frame(width: 5, height: 5)
                        .opacity(0.4)
                        .scaleEffect(searchPhase == .reading ? 1 : 0.6)
                        .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2),
                                   value: searchPhase)
                }
                Text("Reading your Ocean…")
                    .font(.caption)
                    .foregroundStyle(OceanTheme.mist)

            case .found(let count):
                Image(systemName: "water.waves")
                    .font(.caption2)
                    .foregroundStyle(OceanTheme.mist)
                Text(foundLabel(count))
                    .font(.caption)
                    .foregroundStyle(OceanTheme.mist)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: phase)
    }

    private func foundLabel(_ count: Int) -> String {
        switch count {
        case 0:  String(localized: "Nothing drifts near this yet")
        case 1:  String(localized: "Found one fragment that drifts near this")
        default: String(localized: "Found \(count) fragments that drift near this")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask the Ocean")
                .font(.title3.weight(.semibold)).foregroundStyle(OceanTheme.foam)
            Text("Find a thought, or ask what a few of them mean together. Answers come from what you have captured.")
                .font(.subheadline).foregroundStyle(OceanTheme.mist)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(samplePrompts, id: \.self) { prompt in
                    Button { input = prompt } label: {
                        Label(prompt, systemImage: "sparkle")
                            .font(.caption).foregroundStyle(OceanTheme.accent)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.white.opacity(0.06), in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 30)
    }

    private var samplePrompts: [String] {
        [String(localized: "That idea I had about water"),
         String(localized: "What patterns keep resurfacing?"),
         String(localized: "What tension am I circling?")]
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask the Ocean", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .foregroundStyle(OceanTheme.foam)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .lineLimit(1...4)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? OceanTheme.accent : OceanTheme.faint)
            }
            .disabled(!canSend)
        }
        .padding(.leading)
        // Leave the floating capture button its corner.
        .padding(.trailing, FastCaptureLayout.buttonTrailing + FastCaptureLayout.buttonSize + 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
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

    private func composeText(_ response: OceanResponse) -> String {
        if let summary = response.patternSummary {
            return response.reflection + "\n\n" + summary
        }
        return response.reflection
    }

    private func sourceNodes(_ message: ChatMessage) -> [Node] {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        return message.referencedNodeIDs.compactMap { byID[$0] }
    }
}
