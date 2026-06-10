import SwiftUI
import SwiftData

/// Ocean Dialogue (§11): converse with your inspiration memory. Responses
/// include a reflection, source nodes, pattern summaries, and suggested
/// branches — and are grounded in the user's saved fragments.
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

    @State private var conversation: Conversation?
    @State private var mode: DialogueMode = .synthesis
    @State private var input: String = ""
    @State private var searchPhase: SearchPhase?

    @State private var openedNode: Node?
    @State private var branchTarget: Node?
    @State private var branchPrefill: SuggestedBranch?

    private var messages: [ChatMessage] { conversation?.orderedMessages ?? [] }

    var body: some View {
        NavigationStack {
            ZStack {
                OceanBackground()
                VStack(spacing: 0) {
                    modePicker
                    transcript
                }
            }
            .navigationTitle("Ask the Ocean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { inputBar }
            .sheet(item: $openedNode) { ExpandedNodeView(node: $0) }
            .sheet(item: $branchTarget) { target in
                BranchComposer(
                    parent: target,
                    prefill: branchPrefill?.title ?? "",
                    prefillType: branchPrefill?.type ?? .concept
                )
            }
            .onAppear(perform: consumePendingPrompt)
            .onChange(of: appState.pendingAskPrompt) { _, _ in consumePendingPrompt() }
        }
    }

    // MARK: Mode

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(DialogueMode.allCases) { m in
                Text(m.label).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal).padding(.vertical, 8)
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
                Text(message.text)
                    .foregroundStyle(OceanTheme.foam)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if !message.referencedNodeIDs.isEmpty {
                    sourceChips(for: message)
                }
                if !message.suggestedBranches.isEmpty {
                    suggestedBranches(for: message)
                }
            }
            .padding(.trailing, 30)
        }
    }

    private func sourceChips(for message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Drawn from").font(.caption2).foregroundStyle(OceanTheme.faint)
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

    private func suggestedBranches(for message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Grow a branch").font(.caption2).foregroundStyle(OceanTheme.faint)
            ForEach(parsedBranches(message)) { branch in
                Button {
                    branchPrefill = branch
                    branchTarget = sourceNodes(message).first ?? nodes.first
                } label: {
                    HStack {
                        Image(systemName: branch.type.symbol)
                        Text(branch.title).font(.caption).lineLimit(2)
                        Spacer()
                        Image(systemName: "plus.circle.fill").foregroundStyle(OceanTheme.accent)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(OceanTheme.foam)
                }.buttonStyle(.plain)
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
        case 0:  "Nothing drifts near this yet"
        case 1:  "Found one fragment that drifts near this"
        default: "Found \(count) fragments that drift near this"
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask the Ocean")
                .font(.title3.weight(.semibold)).foregroundStyle(OceanTheme.foam)
            Text("Search a fragment, sense a pattern, or grow an idea. Responses come from what you've captured.")
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
        ["What patterns keep resurfacing?", "What connects my recent thoughts?", "Help me grow my newest idea"]
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(mode.placeholder, text: $input, axis: .vertical)
                .textFieldStyle(.plain)
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
        .padding(.horizontal).padding(.vertical, 8)
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
        let convo = ensureConversation()

        // Prior turns (before this one), for follow-up continuity.
        let history = messages.suffix(4).map {
            DialogueTurn(isUser: $0.role == .user, text: $0.text)
        }

        let userMessage = ChatMessage(role: .user, text: query, mode: mode)
        userMessage.conversation = convo
        context.insert(userMessage)
        convo.updatedAt = .now
        try? context.save()

        input = ""
        withAnimation { searchPhase = .reading }
        let currentMode = mode
        let snapshot = nodes

        Task {
            let started = ContinuousClock.now
            let response = await ai.respond(
                to: query, history: history, mode: currentMode, nodes: snapshot
            )

            // Let "Reading your Ocean…" breathe even when retrieval is instant,
            // then name the find for a beat before the reply lands.
            let elapsed = started.duration(to: .now)
            if elapsed < .milliseconds(500) {
                try? await Task.sleep(for: .milliseconds(500) - elapsed)
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
                    suggestedBranches: response.suggestedBranches.map { "\($0.type.rawValue)|\($0.title)" },
                    mode: currentMode
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

    // MARK: Decode helpers

    private func sourceNodes(_ message: ChatMessage) -> [Node] {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        return message.referencedNodeIDs.compactMap { byID[$0] }
    }

    private func parsedBranches(_ message: ChatMessage) -> [SuggestedBranch] {
        message.suggestedBranches.compactMap { raw in
            let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let type = BranchType(rawValue: parts[0]) else { return nil }
            return SuggestedBranch(title: parts[1], type: type)
        }
    }
}
