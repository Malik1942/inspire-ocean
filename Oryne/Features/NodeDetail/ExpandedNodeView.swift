import SwiftUI
import Translation
import SwiftData

/// Expanded Node View (§9): a lightweight contextual layer around a single
/// fragment — "zooming into the atmosphere around an idea."
struct ExpandedNodeView: View {
    let node: Node
    /// Branches and neighbours opened from this thought, crossfaded in place.
    @State private var opened: [Node] = []

    var body: some View {
        NavigationStack {
            OceanFadeStack(path: $opened) {
                NodeDetailContent(node: node, isSheetRoot: true)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }
}

struct NodeDetailContent: View {
    let node: Node
    /// True only when this is the root of a presented sheet (so it shows its
    /// own leading "Close"). When pushed onto a navigation stack the system
    /// supplies a back button, so the leading slot is left to it.
    var isSheetRoot: Bool = false

    @Environment(\.modelContext) private var context
    @Environment(\.oceanAI) private var ai
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openThought) private var openThought
    @Environment(\.popThought) private var popThought
    @Environment(\.dynamicTypeSize) private var typeSize

    @Query(filter: #Predicate<Node> { !$0.isArchived }) private var allNodes: [Node]

    @State private var showBranchComposer = false
    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false
    @State private var showMovePicker = false
    @State private var editFocusesBody = false
    @State private var relatedIDs: [UUID] = []
    @State private var showImageViewer = false
    @State private var viewerIndex = 0
    @State private var retranscribing = false
    @State private var transcriptOpen = false
    /// A theme tapped on this page: its current opens in a sheet.
    @State private var themeStream: StreamSelection?
    @State private var showTranslation = false
    @State private var showReplaceConfirm = false
    @State private var pendingRetranscribe: (data: Data, locale: Locale)?
    @State private var retranscribeFailed = false

    private let transcriber = DriftTranscriber()

    private var related: [Node] {
        let byID = Dictionary(uniqueKeysWithValues: allNodes.map { ($0.id, $0) })
        return relatedIDs.compactMap { byID[$0] }
    }

    private var children: [Node] {
        (node.children ?? []).filter { !$0.isArchived }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        // Undo can take back the thought this page shows (the capture toast
        // floats over a pushed page), and a sync can delete it elsewhere.
        // Reading any \Node attribute on the detached object faults (see
        // NodeRow), so render nothing and leave.
        if node.modelContext == nil {
            Color.clear.onAppear { dismiss() }
        } else {
            page
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                subject
                if !node.themes.isEmpty { themesSection.padding(.top, OceanSpacing.section) }
                if !children.isEmpty { branchesSection.padding(.top, OceanSpacing.section) }
                relatedSection.padding(.top, nearbyTop)
                actions.padding(.top, actionsTop)
            }
            .oceanReadableColumn()
            .padding(.horizontal, OceanSpacing.gutter)
            .padding(.top, OceanSpacing.gap)
            .padding(.bottom, OceanSpacing.section)
        }
        // You reached for this thought: the cool light, the ring's color.
        .background(PageBackground(light: .cool))
        // A thought is a page to read: pushed, it hides the tab bar (the
        // capture bar steps away with it); the back gesture returns.
        .toolbar(isSheetRoot ? .automatic : .hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        // A sheet root has no close of its own: the grabber and the pull
        // down are the way out. A pushed view has the system back button.
        .toolbar {
            // Back to the thought beneath, where the system's back would be,
            // after a crossfade instead of a slide.
            if let popThought {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: popThought) { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Back")
                }
            }
            // One group in the system's own glass: move, share, delete.
            // Share is absent when there is nothing of the user's to hand
            // out (an example, or an empty whisper).
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showMovePicker = true
                } label: {
                    Image(systemName: "folder")
                }
                .accessibilityLabel("Move to a current")
                if ThoughtShareContent.make(from: node) != nil {
                    ThoughtShareMenu(node: node)
                }
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete")
            }
        }
        // The system alert: centered within reach of the thumb, Cancel always
        // there. Every destructive confirm in the app takes this one form.
        .alert(
            "Delete this thought?",
            isPresented: $showDeleteConfirm
        ) {
            Button("Delete", role: .destructive) { deleteNode() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This drifts out of the Ocean for good.")
        }
        .sheet(isPresented: $showBranchComposer) {
            BranchComposer(parent: node)
        }
        .sheet(isPresented: $showEditSheet) {
            NodeEditSheet(node: node, focusBodyOnAppear: editFocusesBody)
        }
        .sheet(isPresented: $showMovePicker) {
            MoveToCurrentSheet(node: node)
        }
        // Words the user has touched are never overwritten by a re-transcribe
        // without asking (mirrors NodeEditSheet's transcript-edit guard).
        .alert(
            "Replace transcript?",
            isPresented: $showReplaceConfirm
        ) {
            Button("Replace", role: .destructive) {
                if let pending = pendingRetranscribe {
                    Task { await runRetranscribe(pending.data, locale: pending.locale) }
                }
                pendingRetranscribe = nil
            }
            Button("Cancel", role: .cancel) { pendingRetranscribe = nil }
        } message: {
            Text("Your edited words will be replaced by a fresh transcription.")
        }
        .alert("Couldn't transcribe", isPresented: $retranscribeFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Speech recognition couldn't produce words for this recording.")
        }
        // A summary or a question opens in Ask: a thought shown as a sheet
        // steps out of the way so the answer is what you see.
        .onChange(of: appState.selectedTab) { _, tab in
            if isSheetRoot, tab == .ask { dismiss() }
        }
        .fullScreenCover(isPresented: $showImageViewer) {
            ImageViewer(datas: node.imageDatas, index: $viewerIndex)
        }
        .task(id: node.id) {
            relatedIDs = ai.relatedNodeIDs(to: node, among: allNodes, limit: 4)
            // Safety net for links that never got a first pass — legacy nodes and
            // share-extension captures (the extension doesn't enrich) — or whose
            // pass a quit cut off (left in progress). A prior failure waits for
            // the card's explicit retry, so opening detail doesn't re-hammer it.
            switch node.linkEnrichmentState {
            case .notStarted, .fetchingMeta, .fetchingContent, .summarizing:
                if node.linkURL != nil {
                    LinkEnrichmentService.shared.enrich(nodeID: node.id, context: context, ai: ai)
                }
            case .enriched, .failed:
                break
            }
        }
    }

    /// Removes the fragment and leaves this view (pops if pushed, dismisses the
    /// sheet if presented). `deleteNodeSafely` archives the subtree out of every
    /// query before detaching it, so neither this view nor a Library row / Ocean
    /// mote faults on a deleted node (see its doc); dismissing alongside is then
    /// purely cosmetic.
    private func deleteNode() {
        context.deleteNodeSafely(node)
        dismiss()
    }

    // MARK: Re-transcribe (BRIEF decision 8)

    /// Everything about the words' language lives behind the language itself:
    /// switch to the other pass when one was kept, re-transcribe in a chosen
    /// language while the recording exists, translate on demand. A user with
    /// one language sees one item. Language names are endonyms, not chrome.
    /// It wears the quiet Link, a way on beside the label that is never
    /// louder than it.
    @ViewBuilder
    private func transcriptMenu(_ data: Data?) -> some View {
        let transcription = node.transcription ?? ""
        Menu {
            if let alt = node.alternateTranscription, !alt.isEmpty,
               let altName = Self.languageName(node.alternateTranscriptLocale) {
                Button {
                    switchToAlternate()
                } label: {
                    Label(String(localized: "Switch to \(altName)"), systemImage: "arrow.2.squarepath")
                }
            }
            if let data, !data.isEmpty {
                Section("Re-transcribe in") {
                    Button {
                        requestRetranscribe(data, locale: Locale(identifier: "zh-CN"))
                    } label: {
                        Text(verbatim: "中文")
                    }
                    Button {
                        requestRetranscribe(data, locale: Locale(identifier: "en-US"))
                    } label: {
                        Text(verbatim: "English")
                    }
                }
            }
            if !transcription.isEmpty {
                Button {
                    showTranslation = true
                } label: {
                    Label("Translate", systemImage: "translate")
                }
            }
        } label: {
            HStack(spacing: OceanSpacing.snug) {
                if retranscribing {
                    ProgressView().controlSize(.mini)
                } else if let name = Self.languageName(node.transcriptLocale) {
                    Text(verbatim: name)
                } else {
                    Image(systemName: "character.bubble")
                }
                Image(systemName: "chevron.down").font(OceanType.glyphSmall)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.oceanLink(.quiet))
        .disabled(retranscribing)
        .accessibilityLabel("Transcript language")
        .translationPresentation(isPresented: $showTranslation, text: transcription)
    }

    private func requestRetranscribe(_ data: Data, locale: Locale) {
        // Only guard when there are user-touched words to lose.
        if node.transcriptEditedByUser, let existing = node.transcription, !existing.isEmpty {
            pendingRetranscribe = (data, locale)
            showReplaceConfirm = true
        } else {
            Task { await runRetranscribe(data, locale: locale) }
        }
    }

    private func runRetranscribe(_ data: Data, locale: Locale) async {
        retranscribing = true
        defer { retranscribing = false }
        // The recognizer wants a file URL; the model's bytes are written out
        // briefly and reclaimed. Audio in the node is never touched.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("retranscribe-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? data.write(to: url)) != nil,
              let transcript = await transcriber.transcribe(url: url, locale: locale),
              !transcript.isEmpty else {
            retranscribeFailed = true
            return
        }
        node.transcription = transcript
        node.transcriptLocale = locale.identifier
        node.alternateTranscription = nil
        node.alternateTranscriptLocale = nil
        node.summary = nil
        // A fresh machine transcription is no longer a user-edited one.
        node.transcriptEditedByUser = false
        if transcript.count >= CaptureSession.summaryThreshold {
            node.summary = await ai.summarizeTranscript(transcript)
        }
    }

    /// The other language's pass becomes the transcript; the previous one
    /// waits behind the same button, so the swap is never a loss.
    private func switchToAlternate() {
        guard let alt = node.alternateTranscription else { return }
        let previous = node.transcription
        let previousLocale = node.transcriptLocale
        node.transcription = alt
        node.transcriptLocale = node.alternateTranscriptLocale
        node.alternateTranscription = previous
        node.alternateTranscriptLocale = previousLocale
        node.transcriptEditedByUser = false
        node.summary = nil
        node.updatedAt = .now
        Task {
            if alt.count >= CaptureSession.summaryThreshold {
                node.summary = await ai.summarizeTranscript(alt)
            }
        }
    }

    /// Endonyms for the two languages the app speaks; anything else by the
    /// system's name for it.
    static func languageName(_ localeID: String?) -> String? {
        guard let localeID else { return nil }
        if localeID.hasPrefix("zh") { return "中文" }
        if localeID.hasPrefix("en") { return "English" }
        return Locale.current.localizedString(forIdentifier: localeID)
    }

    // MARK: The thought

    /// The thought itself, in one order for every kind: what it shows (its
    /// picture, or its link when there is no picture), what it is and when,
    /// its title, its words, then the device's reading and the transcript.
    /// Text on the water; only the picture and the link are framed. The
    /// title steps down by its length (34, 28, 24 pt) as it does on Tide's
    /// stage, so a long name wraps at a size that still reads as one.
    private var subject: some View {
        VStack(alignment: .leading, spacing: 0) {
            if node.hasImages || node.linkURL != nil {
                media.padding(.bottom, OceanSpacing.block)
            }
            NodeMeta(node: node, detail: metaDetail)
            Text(node.displayTitle)
                .oceanText(OceanType.thoughtTitle(for: node.displayTitle))
                .foregroundStyle(OceanTheme.coolInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, OceanSpacing.gap)
                .contentShape(Rectangle())
                // Tapping the words is how corrections are found: the same
                // sheet as the toolbar pencil.
                .onTapGesture { edit(focusingBody: false) }
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("thought.title")
                // The words are the way to edit; no separate pencil.
                .accessibilityHint("Tap to edit this thought.")
                .accessibilityAction(named: Text("Edit")) { edit(focusingBody: false) }
            if showsWords {
                Text(node.text)
                    .oceanText(OceanType.thoughtBody)
                    .foregroundStyle(OceanTheme.coolWords)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, OceanSpacing.item)
                    .contentShape(Rectangle())
                    .onTapGesture { edit(focusingBody: true) }
            }
            if node.hasImages, node.linkURL != nil {
                // A picture leads; the link it came with follows the words.
                LinkCard(node: node)
                    .padding(.top, OceanSpacing.block)
            }
            readingBlock
            transcriptBlock
        }
    }

    /// The picture at the page's full width, in its own shape up to a limit
    /// (portrait 3:4, panorama 1.9:1) so a tall photo never fills the
    /// screen. Several pictures make a strip. The viewer shows each whole.
    @ViewBuilder
    private var media: some View {
        let datas = node.imageDatas
        if datas.count == 1, let ui = UIImage(data: datas[0]) {
            picture(ui)
        } else if datas.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OceanSpacing.gap) {
                    ForEach(Array(datas.enumerated()), id: \.offset) { index, data in
                        if let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable().scaledToFill()
                                .frame(width: 176, height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: OceanRadius.media, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: OceanRadius.media, style: .continuous))
                                .onTapGesture { viewerIndex = index; showImageViewer = true }
                        }
                    }
                }
            }
            .scrollClipDisabled()
        } else if node.linkURL != nil {
            LinkCard(node: node)
        }
    }

    private func picture(_ ui: UIImage) -> some View {
        let aspect = ui.size.height > 0 ? ui.size.width / ui.size.height : 1
        let shape = RoundedRectangle(cornerRadius: OceanRadius.media, style: .continuous)
        return Color.clear
            .aspectRatio(min(max(aspect, 0.75), 1.9), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { Image(uiImage: ui).resizable().scaledToFill() }
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture { viewerIndex = 0; showImageViewer = true }
            .accessibilityElement()
            .accessibilityLabel(Text(NodeKind.image.label))
            .accessibilityAddTraits(.isButton)
    }

    /// The meta line's lead on a thought's own page: the kind by name, a
    /// whisper's length, a branch's kind.
    private var metaDetail: String {
        var parts = [node.kind.label]
        if let category = node.category { parts.append(category.label) }
        if node.kind == .voice, let data = node.audioData,
           let seconds = AudioDurations.seconds(for: data, id: node.id) {
            parts.append(AudioDurations.format(seconds))
        }
        if let branchType = node.branchType { parts.append(branchType.label) }
        return parts.joined(separator: " · ")
    }

    /// The user's own words, unless they already are the title or are only
    /// the link's address, which belongs to the link card, not to the serif.
    private var showsWords: Bool {
        let words = node.text.trimmed
        return !words.isEmpty && words != node.displayTitle.trimmed && words != node.linkURLString?.trimmed
    }

    private func edit(focusingBody: Bool) {
        editFocusesBody = focusingBody
        showEditSheet = true
    }

    /// What the device read, said to be a reading (§3): the summary of a
    /// long whisper or of the page a link points to, under one label in one
    /// place. A page's own description, when there is no summary, says so.
    private enum Reading {
        case summary(String)
        case page(String)
    }

    private var reading: Reading? {
        if node.transcription?.isEmpty == false, let summary = node.summary, !summary.isEmpty {
            return .summary(summary)
        }
        guard node.linkURL != nil else { return nil }
        if let summary = node.linkSummary, !summary.isEmpty { return .summary(summary) }
        if let description = node.linkDescription, !description.isEmpty { return .page(description) }
        return nil
    }

    @ViewBuilder
    private var readingBlock: some View {
        if let reading {
            VStack(alignment: .leading, spacing: OceanSpacing.afterLabel) {
                switch reading {
                case .summary(let text):
                    OceanSectionLabel("Summary", systemImage: "sparkles")
                    readingText(text)
                case .page(let text):
                    OceanSectionLabel("From the page", systemImage: "doc.text")
                    readingText(text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, OceanSpacing.block)
        }
    }

    private func readingText(_ text: String) -> some View {
        Text(text)
            .oceanText(OceanType.body)
            .foregroundStyle(OceanTheme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A whisper's words with its controls on the label's line: listen, and
    /// the language menu. Under a summary they fold to three lines; without
    /// one they are the thought's words, in full. They sit `afterLabel`
    /// under Listen's capsule; once the recording has expired the language
    /// menu, a Link with no surface, holds the row alone, and its 44 pt row
    /// is the gap.
    @ViewBuilder
    private var transcriptBlock: some View {
        if let transcription = node.transcription, !transcription.isEmpty {
            VStack(alignment: .leading, spacing: (node.audioData?.isEmpty == false) ? OceanSpacing.afterLabel : 0) {
                OceanSectionLabel("Transcript", systemImage: "waveform") {
                    HStack(spacing: OceanSpacing.gap) {
                        if let data = node.audioData, !data.isEmpty {
                            ListenChip(data: data)
                        }
                        transcriptMenu(node.audioData)
                    }
                }
                if node.summary?.isEmpty == false {
                    // Under a summary the words fold to three lines that fade
                    // out, with a plain button to read the rest. Three at
                    // every text size: it is the fold, not a preview.
                    VStack(alignment: .leading, spacing: OceanSpacing.inset) {
                        Text(transcription)
                            .oceanText(OceanType.thoughtBody)
                            .foregroundStyle(OceanTheme.coolWords)
                            .lineLimit(transcriptOpen ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .mask {
                                LinearGradient(
                                    stops: [.init(color: .black, location: 0),
                                            .init(color: .black, location: transcriptOpen ? 1 : 0.55),
                                            .init(color: .black.opacity(transcriptOpen ? 1 : 0.15), location: 1)], // art-directed: a mask, not a color
                                    startPoint: .top, endPoint: .bottom
                                )
                            }
                        Button {
                            withAnimation(OceanMotion.standard) { transcriptOpen.toggle() }
                        } label: {
                            Label(transcriptOpen ? "Show less" : "Read full transcript",
                                  systemImage: transcriptOpen ? "chevron.up" : "chevron.down")
                        }
                        .buttonStyle(.oceanSecondary)
                        .accessibilityHint(transcriptOpen ? Text("Collapses the transcript.") : Text("Shows the whole transcript."))
                    }
                } else {
                    Text(transcription)
                        .oceanText(OceanType.thoughtBody)
                        .foregroundStyle(OceanTheme.coolWords)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { edit(focusingBody: true) }
                }
            }
            .padding(.top, OceanSpacing.block)
        } else if node.kind == .voice {
            VStack(alignment: .leading, spacing: OceanSpacing.afterLabel) {
                // Honest about state: "transcribing" only while a pass
                // can plausibly still be running; after that the words
                // are simply missing and the recovery is one tap away.
                OceanSectionLabel(node.createdAt.timeIntervalSinceNow > -120
                                  ? LocalizedStringKey("Transcribing…")
                                  : LocalizedStringKey("No words yet"),
                                  systemImage: "waveform") {
                    HStack(spacing: OceanSpacing.gap) {
                        if let data = node.audioData, !data.isEmpty {
                            ListenChip(data: data)
                            transcriptMenu(data)
                        }
                    }
                }
                if node.createdAt.timeIntervalSinceNow <= -120 {
                    Text("Tap to type the words or re-transcribe.")
                        .oceanText(OceanType.secondary)
                        .foregroundStyle(OceanTheme.mist)
                        .contentShape(Rectangle())
                        .onTapGesture { edit(focusingBody: true) }
                }
            }
            .padding(.top, OceanSpacing.block)
        }
    }

    // MARK: Sections

    /// Each theme is a way in: tap it to see every thought that carries it.
    private var themesSection: some View {
        VStack(alignment: .leading, spacing: OceanSpacing.afterLabel) {
            OceanSectionLabel("Themes")
            FlowLayout(spacing: OceanSpacing.gap) {
                ForEach(node.themes, id: \.self) { theme in
                    Button { themeStream = StreamSelection(theme: ThoughtReading.slug(theme)) } label: {
                        Text(CurrentKey.humanized(theme))
                    }
                    .buttonStyle(.oceanSecondary)
                    .accessibilityHint("Shows every thought with this theme.")
                }
            }
        }
        .sheet(item: $themeStream) { selection in
            ClusterStreamView(theme: selection.theme)
        }
    }

    private var branchesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            OceanSectionLabel("Branches")
            VStack(alignment: .leading, spacing: OceanSpacing.item) {
                ForEach(children) { child in
                    Button { openThought(child) } label: {
                        NodeRow(node: child)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, OceanSpacing.afterLabel)
        }
    }

    /// Where Nearby enters the depth ladder: two levels down, so a
    /// neighbour never outranks this thought's own words.
    private static let nearbyLevel = 2

    /// The neighbours Nearby shows: three lines, so the deepest still
    /// reads. Summarize reads every neighbour found, the fourth too.
    private var nearbyLines: [Node] { Array(related.prefix(3)) }

    /// Sections stand `section` apart, measured between what you see. With
    /// lines, Nearby's label shares Summarize's 44 pt row and both sit on
    /// its foot, so what the row leaves above Summarize's words comes off
    /// the 40 (never less than the Link's own floor); without them the
    /// label is the first thing you see.
    private var nearbyTop: CGFloat {
        guard !related.isEmpty else { return OceanSpacing.section }
        let aboveWords = OceanControlSize.height - OceanSpacing.tight - OceanType.control.lineHeight(at: typeSize)
        return OceanSpacing.section - max(OceanSpacing.tight, aboveWords)
    }

    /// The actions stand `section` below the deepest line's words: its 44
    /// pt row leaves some of that space under them already.
    private var actionsTop: CGFloat {
        guard !related.isEmpty else { return OceanSpacing.section }
        let deepest = DepthList.role(atLevel: Self.nearbyLevel + nearbyLines.count - 1)
        return OceanSpacing.section - deepest.rowSlack(at: typeSize)
    }

    /// With lines, the ladder sits right under the label's row: each line's
    /// own 44 pt row is the gap. The empty line sits `afterLabel` below.
    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: related.isEmpty ? OceanSpacing.afterLabel : 0) {
            OceanSectionLabel("Nearby") {
                // Read this thought and its neighbours together, in Ask.
                if !related.isEmpty {
                    Button {
                        appState.summarize([node.id] + related.map(\.id), title: node.displayTitle)
                        dismiss()
                    } label: {
                        // The Link's 44 pt rises above its words instead of
                        // hanging below them, so they sit on the row's foot,
                        // right over the first line, and Nearby, on their
                        // baseline, comes down with them.
                        Label("Summarize", systemImage: "text.line.first.and.arrowtriangle.forward")
                            .frame(minHeight: OceanControlSize.height - 2 * OceanSpacing.tight, alignment: .bottom)
                    }
                    .buttonStyle(.oceanLink(.quiet))
                }
            }
            if related.isEmpty {
                Text("Nothing drifts nearby yet.")
                    .oceanText(OceanType.secondary)
                    .foregroundStyle(OceanTheme.mist)
            } else {
                DepthList(nodes: nearbyLines, startLevel: Self.nearbyLevel, open: { openThought($0) })
            }
        }
    }

    /// Two quiet actions. Nothing on a thought's page is the main action;
    /// the thought is. Primary is kept for Release, Keep and Ask's send.
    /// Side by side while both fit their words; one above the other when
    /// they do not, at the larger text sizes.
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: OceanSpacing.gap) { actionButtons }
            VStack(spacing: OceanSpacing.gap) { actionButtons }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button { showBranchComposer = true } label: {
            Label("Grow a branch", systemImage: "arrow.triangle.branch")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.oceanSecondary)

        Button {
            appState.ask(String(localized: "About “\(node.displayTitle)”: "))
            dismiss()
        } label: {
            Label("Ask Ocean", systemImage: "quote.bubble")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.oceanSecondary)
    }
}

/// Full-screen, paged viewer for a node's images, opened by tapping one in the
/// detail view. Paging only shows when there's more than one.
private struct ImageViewer: View {
    let datas: [Data]
    @Binding var index: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(datas.enumerated()), id: \.offset) { i, data in
                    if let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable().scaledToFit()
                            .tag(i)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: datas.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.oceanIcon)
            .padding(OceanSpacing.inset)
            .accessibilityLabel("Close")
        }
    }
}
