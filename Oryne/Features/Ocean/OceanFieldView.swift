import SwiftUI
import SwiftData
import AVFoundation
import WidgetKit

/// Tide: where the Ocean meets you. What rose today, what just drifted
/// in, which currents are moving (docs/plans/phone-refocus/SPEC.md,
/// decision 5). The Ocean is the whole water; this is its surface, and the
/// Library is the depth.
///
/// Today's thought stands on a stage (design/identity-2.1.md, Round 4): in
/// the Reading light from the top of the screen, or, when it has a picture,
/// on the picture itself, whose color carries down into the water. Below
/// it the column: the newest thoughts on the depth ladder, sinking by age,
/// with no dates. Then the currents. The page names itself only in the tab
/// bar; its first line is the thought that came back.
struct OceanFieldView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.oceanAI) private var ai
    @Environment(\.calmAccessibility) private var calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.isBigScreen) private var isBigScreen
    @Environment(CaptureControl.self) private var control
    @Query(filter: #Predicate<Node> { !$0.isArchived }, sort: \Node.createdAt, order: .reverse)
    private var nodes: [Node]

    @State private var sheet: OceanSheet?
    @State private var showSettings = false
    /// "Nearby" is open under the resurfacing thought.
    @State private var nearbyOpen = false
    @State private var nearby: [Node] = []
    /// Bumped by "Let it rest" so today's pick recomputes.
    @State private var restTick = 0
    /// The Resurfacing widget was reloaded since Tide first appeared.
    @State private var widgetReloaded = false
    /// The lamp's extra warmth while a new thought rises; 0 at rest.
    @State private var lampLift: Double = 0
    /// The lamp dims while a thought sinks.
    @State private var lampDim: Double = 1
    /// "Let it rest": today's thought is going under.
    @State private var lettingGo = false
    /// The thought being let go stays on screen until it has gone under;
    /// resting it re-picks today's thought at once.
    @State private var goingUnder: Node?
    /// A thought a line's menu asked to delete, waiting on the alert.
    @State private var pendingDelete: Node?
    /// The status bar and the navigation bar's height: a picture stage
    /// reaches up under both to the screen's top edge.
    @State private var topInset: CGFloat = 0
    /// The page's height under the bars, as it stands without the keyboard:
    /// a short page (landscape) gets a shorter picture stage.
    @State private var pageHeight: CGFloat = 0
    /// The page's width, beside its height: a big screen turned wider than
    /// tall splits Tide in two.
    @State private var pageWidth: CGFloat = 0
    /// The screen folds down the page (iPhone Duo).
    @State private var folds = false
    /// The half a thought or a current opens on while the page is split:
    /// the other one from where it was tapped.
    @State private var sheetSide: BigScreen.Side = .trailing
    /// What stands under today's picture, its words and its actions, read
    /// off their layout: split, the picture reaches down to meet them.
    @State private var stageWords: CGFloat = 0
    @State private var stageActions: CGFloat = 0

    private var stilled: Bool { calm || reduceMotion }

    private static let newestLimit = 5
    private static let currentLimit = 4
    /// Where Nearby enters the depth ladder: two levels down, so a
    /// neighbour never outranks today's thought.
    private static let nearbyLevel = 2
    /// How far today's thought sinks as it is let go: the motion's own
    /// travel, so it keeps its distance whatever the spacing tokens become.
    private static let restSink: CGFloat = 4 // art-directed: the let-go sink

    private enum OceanSheet: Identifiable {
        case thought(Node)
        case stream(theme: String)

        var id: String {
            switch self {
            case .thought(let node): return node.id.uuidString
            case .stream(let theme): return "stream·\(theme)"
            }
        }
    }

    // MARK: Derived

    private var resurfacing: Node? {
        _ = restTick
        return Resurfacing.pick(from: nodes)
    }

    /// The newest thoughts, the resurfacing one aside. A brand-new Ocean
    /// shows the starter examples so the surface is never bare.
    private var newest: [Node] {
        let own = nodes.filter { !$0.isExample && $0.id != resurfacing?.id }
        let pool = own.isEmpty ? nodes.filter { $0.isExample } : own
        return Array(pool.prefix(Self.newestLimit))
    }

    private var currents: [CurrentGroup] {
        CurrentGroup.build(from: nodes).filter { !$0.isAdrift }
    }

    // MARK: Body

    var body: some View {
        let shown = goingUnder ?? resurfacing
        let onPicture = shown.map(hasStagePicture) ?? false
        let split = splits && shown != nil
        NavigationStack {
            ZStack {
                OceanBackground()
                // A picture is its own light; the Reading light falls on a
                // thought without one, and on the empty page.
                if !onPicture {
                    StageLight(lift: lampLift, dim: lampDim)
                        .transition(.opacity)
                }
                if nodes.isEmpty {
                    emptyState
                } else if let shown, split {
                    // Split, the page is two halves, even, each its own
                    // scroll: today's thought the leading one's hero, top to
                    // foot, and the depth with the capture bar the trailing
                    // one's.
                    HStack(spacing: 0) {
                        ScrollView {
                            stage(shown, beside: true)
                                .padding(.horizontal, OceanSpacing.gutter)
                                .padding(.top, onPicture ? 0 : OceanSpacing.gap)
                                .padding(.bottom, heroFoot)
                        }
                        .frame(width: pageWidth / 2)
                        ScrollView {
                            // The column starts where a title would, under
                            // the gear.
                            depth(below: nil)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(.horizontal, OceanSpacing.gutter)
                                .padding(.top, OceanSpacing.gap)
                                .padding(.bottom, FastCaptureLayout.contentClearance)
                        }
                        .modifier(CaptureComposerEdge())
                        .frame(width: pageWidth / 2)
                    }
                } else {
                    ScrollView {
                        // Sections a page's section apart, measured between
                        // what you see; each text block in the reading column.
                        VStack(alignment: .leading, spacing: 0) {
                            if let shown { stage(shown, beside: false) }
                            depth(below: shown)
                        }
                        .padding(.horizontal, OceanSpacing.gutter)
                        // A picture starts at the screen's top edge; a title
                        // starts just under the bar's gear.
                        .padding(.top, onPicture ? 0 : OceanSpacing.gap)
                        .padding(.bottom, FastCaptureLayout.contentClearance)
                    }
                    .modifier(CaptureComposerEdge())
                }
                // Split, the shore stands only under the capture bar's half:
                // the hero runs to the screen's foot.
                ShoreGradient()
                    .frame(width: split ? pageWidth / 2 : nil)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
            // Read past the keyboard's inset, so the keys never shorten the
            // stage; only a short page does.
            .background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
                    .onGeometryChange(for: Bool.self) { BigScreen.folds(in: $0) } action: { folds = $0 }
                    .ignoresSafeArea(.keyboard)
            }
            // The capture bar and its composer keep to the trailing half once
            // the page splits.
            .onChange(of: split, initial: true) { _, split in control.tideSplits = split }
            // No large title: the tab bar already says Tide, and the page's
            // first line is today's thought. The title stays for the system
            // (VoiceOver, the app switcher); the gear stays in the bar's glass.
            .navigationTitle(OceanTab.homeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Ocean settings")
                }
            }
            .onAppear(perform: consumePendingFocus)
            .onChange(of: appState.pendingFocusNodeID) { _, _ in consumePendingFocus() }
            .onChange(of: resurfacing?.id) { _, _ in
                nearbyOpen = false
                nearby = []
            }
            // The Resurfacing widget shows this same pick: reload it when the
            // pick changes, and once when Tide first appears, for a change made
            // while the app was closed (a sync, a reseed). `initial` runs again
            // on every return to this tab; those reload nothing.
            .onChange(of: resurfacing?.id, initial: true) { old, new in
                guard old != new || !widgetReloaded else { return }
                widgetReloaded = true
                WidgetCenter.shared.reloadTimelines(ofKind: Resurfacing.widgetKind)
            }
            // On a split iPhone Duo it stands beside the page instead (the
            // pane below); a sheet everywhere else.
            .sheet(item: Binding(get: { besidePane ? nil : sheet },
                                 set: { if !besidePane || $0 != nil { sheet = $0 } })) { item in
                sheetPage(item)
            }
            .sheet(isPresented: $showSettings) { OceanSettingsView() }
            // The system alert, as on a thought's page and in the Library.
            .alert(
                "Delete this thought?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let node = pendingDelete { context.deleteNodeSafely(node) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("This drifts out of the Ocean for good.")
            }
            .onChange(of: sheet?.id) { _, _ in updateOceanSheetPresence() }
            .onChange(of: showSettings) { _, _ in updateOceanSheetPresence() }
        }
        // On a split iPhone Duo what was opened stands in the other half: a
        // second screen, not a sheet over both. The half it was opened from
        // stays as it was.
        .overlay(alignment: sheetSide == .leading ? .leading : .trailing) {
            Group {
                if besidePane, let opened = sheet {
                    sheetPage(opened)
                        .id(opened.id)
                        .environment(\.closePane) { sheet = nil }
                        .environment(\.paneSide, sheetSide)
                        .frame(width: pageWidth / 2)
                        .transition(.opacity)
                }
            }
            .animation(OceanMotion.standard, value: besidePane ? sheet?.id : nil)
        }
        // The capture bar steps aside only for a half opened over its own.
        .onChange(of: besidePane && sheet != nil && sheetSide == .trailing, initial: true) { _, open in
            control.paneOpen = open
        }
    }

    /// A thought or a current, as a sheet or as the half beside the page.
    @ViewBuilder
    private func sheetPage(_ item: OceanSheet) -> some View {
        switch item {
        case .thought(let node): ExpandedNodeView(node: node)
        case .stream(let theme): ClusterStreamView(theme: theme)
        }
    }

    // MARK: Layout

    /// Tide splits in two, today's thought beside the depth, on a big screen
    /// turned wider than tall (`BigScreen.splits`): the inner display of
    /// iPhone Duo, an iPad on its side.
    private var splits: Bool {
        isBigScreen && BigScreen.splits(CGSize(width: pageWidth, height: pageHeight))
    }

    /// A split page on iPhone Duo: what is opened stands in the other half
    /// instead of a sheet. Read live, so a sheet's binding asks it as it is
    /// now, not as it was when the page last drew.
    private var besidePane: Bool {
        splits && (goingUnder ?? resurfacing) != nil && folds
    }

    /// Under the hero's actions, split: their row stands level with the
    /// capture bar across the page, centered on it.
    private var heroFoot: CGFloat {
        let row = max(0, stageActions - OceanSpacing.inset)
        return FastCaptureLayout.restClearance(control.tabBarEdge)
            + max(0, (FastCaptureLayout.barHeight - row) / 2)
    }

    /// Today's thought on its stage. One thought goes under, then the next
    /// comes up: never both on screen at once.
    private func stage(_ node: Node, beside: Bool) -> some View {
        resurfacingSection(node, beside: beside)
            .opacity(lettingGo ? 0 : 1)
            .offset(y: stilled || !lettingGo ? 0 : Self.restSink)
    }

    /// The depth: the newest thoughts, then the currents, under today's
    /// thought, or beside it when there is none above (`shown` nil).
    private func depth(below shown: Node?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            newestSection
                .oceanReadableColumn()
                .padding(.top, shown == nil ? 0 : newestTop)
            if !currents.isEmpty {
                currentsSection
                    .oceanReadableColumn()
                    .padding(.top, currentsTop)
            }
        }
    }

    // MARK: Resurfacing

    private func resurfacingSection(_ node: Node, beside: Bool) -> some View {
        let picture = stagePicture(node)
        let words = node.ownWords
        // At accessibility sizes the head no longer fits on the picture: it
        // stands right below it, on the bleed's held scrim, and the stage
        // keeps its height.
        let headBelow = picture != nil && typeSize.isAccessibilitySize
        // The head stands on the picture at its foot, and the caption's own
        // bottom inset parts the title from what follows.
        let captioned = picture != nil && !headBelow
        return VStack(alignment: .leading, spacing: 0) {
            Button { open(node) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    if let picture {
                        ResurfacingPicture(image: picture.image, data: picture.data, id: node.id,
                                           height: beside ? heroHeight(picture.height) : stageHeight(picture.height),
                                           topInset: topInset, holdsScrim: headBelow, dissolvesTrailing: beside) {
                            if !headBelow { stageHead(node, onPicture: true) }
                        }
                    } else {
                        stageHead(node, onPicture: false)
                            .oceanReadableColumn()
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        if headBelow {
                            stageHead(node, onPicture: true)
                                .oceanReadableColumn()
                                .padding(.top, OceanSpacing.gap)
                        }
                        if let words {
                            Text(words)
                                .oceanText(OceanType.thoughtBody)
                                .foregroundStyle(picture == nil ? OceanTheme.stageWords : OceanTheme.foam)
                                .oceanLineLimit(picture == nil ? 4 : 3, accessibility: picture == nil ? 6 : 4)
                                .multilineTextAlignment(.leading)
                                .oceanReadableColumn()
                                .padding(.top, captioned ? 0 : OceanSpacing.item)
                                .accessibilityIdentifier("tide.stage.words")
                        }
                        if let domain = node.linkDomain {
                            linkSource(node, domain: domain, showsAbout: words == nil, onPicture: picture != nil)
                                .oceanReadableColumn()
                                .padding(.top, words == nil && captioned ? 0 : OceanSpacing.item)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stageWords = $0 }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the thought.")

            // Wraps onto a second line at accessibility sizes rather than
            // running off the page.
            FlowLayout(spacing: OceanSpacing.gap) {
                Button(nearbyOpen ? "Nearby" : "Nearby") { toggleNearby(node) }
                    .buttonStyle(.oceanSecondary(selected: nearbyOpen))
                if !Resurfacing.Rest.restedToday || goingUnder != nil {
                    Button("Let it rest") { rest(node) }
                        .buttonStyle(.oceanSecondary)
                }
                if node.kind == .voice, let data = node.audioData {
                    PlayWhisperButton(data: data)
                }
            }
            .oceanReadableColumn()
            .padding(.top, OceanSpacing.inset)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stageActions = $0 }

            if nearbyOpen {
                Group {
                    if nearby.isEmpty {
                        Text("Nothing drifts nearby yet.")
                            .oceanText(OceanType.secondary)
                            .foregroundStyle(OceanTheme.mist)
                            .padding(.vertical, OceanSpacing.gap)
                    } else {
                        DepthList(nodes: nearby, startLevel: Self.nearbyLevel, open: { open($0) })
                    }
                }
                .oceanReadableColumn()
                .padding(.top, OceanSpacing.gap)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// The label and the title, the same on a picture and in the light. A
    /// title steps down by its weighted length (TitleLength: 34, 28, 24 pt
    /// at 40 and 80, a Chinese character counting 2) rather than squeezing
    /// to fit.
    private func stageHead(_ node: Node, onPicture: Bool) -> some View {
        let title = node.displayTitle
        let role = OceanType.thoughtTitle(for: title)
        return VStack(alignment: .leading, spacing: OceanSpacing.gap) {
            Text("Resurfacing")
                .oceanText(OceanType.stageLabel)
                .foregroundStyle(OceanTheme.warm)
                .padding(.leading, OceanSpacing.hairline)
            Text(title)
                .oceanText(role)
                // White in the warm light; plain white on a picture, where
                // no warm light falls.
                .foregroundStyle(onPicture ? OceanTheme.onPhoto : OceanTheme.stageInk)
                .oceanLineLimit(onPicture ? 3 : 4, accessibility: nil)
                .multilineTextAlignment(.leading)
                .accessibilityIdentifier("tide.stage.title")
        }
    }

    /// Where a link points, and what the page says about itself: the site's
    /// words, so the system's face, never the serif (only when the thought
    /// has no words of the user's). On a picture the domain takes the
    /// reading ink, which holds on the bleed where mist would not.
    private func linkSource(_ node: Node, domain: String, showsAbout: Bool, onPicture: Bool) -> some View {
        VStack(alignment: .leading, spacing: OceanSpacing.snug) {
            HStack(spacing: OceanSpacing.snug) {
                Image(systemName: "link")
                Text(domain)
            }
            .oceanText(OceanType.meta)
            .foregroundStyle(onPicture ? OceanTheme.text : OceanTheme.mist)
            if showsAbout, let about = node.linkSummary ?? node.linkDescription, !about.isEmpty {
                Text(about)
                    .oceanText(OceanType.secondary)
                    .foregroundStyle(OceanTheme.text)
                    .oceanLineLimit(2, accessibility: 3)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    /// The picture a thought stands on: its own first picture, or a link's
    /// image, which is wider than it is tall and gets a shorter stage.
    private func stagePicture(_ node: Node) -> (image: UIImage, data: Data, height: CGFloat)? {
        if let data = node.imageDatas.first, let image = UIImage(data: data) {
            return (image, data, OceanSize.stage)
        }
        if let data = node.linkImageData, let image = UIImage(data: data) {
            return (image, data, OceanSize.stageLink)
        }
        return nil
    }

    /// Whether a thought stands on a picture, without loading the pictures
    /// attached to it.
    private func hasStagePicture(_ node: Node) -> Bool {
        node.hasImages || node.linkImageData != nil
    }

    /// The stage's height from the screen's top edge: the picture's own, or
    /// less on a short page (landscape, a small window), so the caption's
    /// foot clears the capture bar while the page rests. A phone in
    /// portrait always has the room.
    private func stageHeight(_ full: CGFloat) -> CGFloat {
        guard pageHeight > 0 else { return full }
        let clear = topInset + pageHeight - FastCaptureLayout.contentClearance
        return min(full, max(clear, full / 2)) // art-directed: a short page keeps half the stage at least
    }

    /// Split, the stage is its half's hero: the picture reaches down until
    /// its words and actions end at the half's foot (`heroFoot`), however
    /// tall the page. A page too short for that keeps half the stage, as
    /// `stageHeight` does.
    private func heroHeight(_ full: CGFloat) -> CGFloat {
        guard pageHeight > 0 else { return full }
        let reach = topInset + pageHeight - stageWords - stageActions - heroFoot
        return max(reach, full / 2) // art-directed: a short page keeps half the stage at least
    }

    // MARK: Drifted in

    /// "Drifted in" stands a section below the stage, measured between what
    /// you see: below the actions, or, with Nearby open, below its last
    /// line's words, whose 44 pt row (or the empty line's padding) leaves
    /// some of the 40 under them already.
    private var newestTop: CGFloat {
        guard nearbyOpen else { return OceanSpacing.section }
        guard !nearby.isEmpty else { return OceanSpacing.section - OceanSpacing.gap }
        let deepest = DepthList.role(atLevel: Self.nearbyLevel + nearby.count - 1)
        return OceanSpacing.section - deepest.rowSlack(at: typeSize)
    }

    /// The column: the newest thoughts on the depth ladder. A new one enters
    /// just under the surface and every older one steps a level deeper. The
    /// lines sit right under the label: each 44 pt row's own slack is the gap.
    private var newestSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            OceanSectionLabel("Drifted in")
            DepthList(nodes: newest, open: { open($0, on: .leading) }, archive: archive, delete: { pendingDelete = $0 })
                .animation(stilled ? OceanMotion.quick : OceanMotion.standard, value: newest.map(\.id))
                .accessibilityIdentifier("tide.column")
        }
    }

    // MARK: Currents

    /// Currents stands a section below the column, measured between what
    /// you see: the last line's 44 pt row and the label's row (it carries a
    /// 44 pt Link) each leave their slack, which comes off the 40.
    private var currentsTop: CGFloat {
        let lines = newest.count
        let lastLine = lines == 0 ? 0 : DepthList.role(atLevel: lines - 1).rowSlack(at: typeSize)
        return OceanSpacing.section - lastLine - OceanType.sectionLabel.rowSlack(at: typeSize, floor: OceanSpacing.tight)
    }

    /// The moving currents as tiles, two to a row and one at accessibility
    /// sizes, right under the label's row, whose slack is the gap.
    private var currentsSection: some View {
        let shown = Array(currents.prefix(Self.currentLimit))
        let perRow = typeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: shown.count, by: perRow).map { Array(shown[$0..<min($0 + perRow, shown.count)]) }
        return VStack(alignment: .leading, spacing: 0) {
            OceanSectionLabel("Currents") {
                // Every current is in the Library, under Currents.
                Button {
                    appState.showAllCurrents()
                } label: {
                    // A quiet accessory to the section label, never louder
                    // than it: a Link in the label's mist.
                    HStack(spacing: OceanSpacing.snug) {
                        Text("All currents")
                        Image(systemName: "chevron.right").font(OceanType.glyphSmall)
                    }
                }
                .buttonStyle(.oceanLink(.quiet))
            }
            Grid(alignment: .topLeading, horizontalSpacing: OceanSpacing.item, verticalSpacing: OceanSpacing.item) {
                ForEach(rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(rows[row]) { group in
                            Button {
                                sheetSide = .leading
                                sheet = .stream(theme: group.key)
                            } label: {
                                VStack(alignment: .leading, spacing: OceanSpacing.snug) {
                                    Text(group.label)
                                        .oceanText(OceanType.cardTitle)
                                        .foregroundStyle(OceanTheme.foam)
                                        .oceanLineLimit(1)
                                    Text(group.newest?.displayTitle ?? "")
                                        .oceanText(OceanType.depth3)
                                        .foregroundStyle(OceanTheme.text)
                                        .oceanLineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(OceanSpacing.inset)
                                // Tiles in a row share a height: the tallest
                                // one's, never a fixed one the words outgrow.
                                .frame(maxHeight: .infinity, alignment: .topLeading)
                                .background(OceanSurface(shape: RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)))
                            }
                            .buttonStyle(.plain)
                        }
                        // A short row keeps both columns, so a lone tile
                        // stays a tile wide rather than the row's width.
                        if rows[row].count < perRow {
                            Color.clear.gridCellUnsizedAxes(.vertical)
                        }
                    }
                }
            }
        }
    }

    // MARK: Empty state

    /// An empty stage with the light already on, standing at the stage's own
    /// place, top-leading under the bar, where the first thought will come
    /// back: the ring, then the line and its note.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            OceanRing(size: OceanSize.ringHero)
            Text("The Ocean is still")
                .oceanText(OceanType.statement)
                .foregroundStyle(OceanTheme.foam)
                .padding(.top, OceanSpacing.inset)
            Text("Capture a thought and watch it drift in.")
                .oceanText(OceanType.secondary)
                .foregroundStyle(OceanTheme.mist)
                .padding(.top, OceanSpacing.gap)
        }
        .oceanReadableColumn()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, OceanSpacing.gutter)
        .padding(.top, OceanSpacing.gap)
    }

    // MARK: Interaction

    /// The Library's archive: out of Tide and every current, kept in the
    /// Library under Show archived.
    private func archive(_ node: Node) {
        ThoughtRemoval.archive(node)
        try? context.save()
    }

    private func toggleNearby(_ node: Node) {
        if !nearbyOpen {
            let ids = ai.relatedNodeIDs(to: node, among: nodes, limit: 3)
            let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
            nearby = ids.compactMap { byID[$0] }
        }
        withAnimation(OceanMotion.standard) { nearbyOpen.toggle() }
    }

    /// Today's thought goes under; the next one surfaces. It counts as met,
    /// so it rests. Three steps, one at a time: the thought fades and sinks
    /// 4 pt while the lamp lowers a little; only once it is gone is the rest
    /// written, so the page never reloads mid-motion, and the next thought
    /// takes its place unseen while the page eases to its height; then it
    /// rises from those 4 pt on a long ease-out as the lamp warms a touch.
    /// Calm and Reduce Motion: a plain fade.
    private func rest(_ node: Node) {
        guard goingUnder == nil else { return }
        goingUnder = node
        let stilled = self.stilled
        Task { @MainActor in
            withAnimation(stilled ? OceanMotion.quick : .easeInOut(duration: 0.45)) { // art-directed: the lamp
                nearbyOpen = false
                lettingGo = true
                if !stilled { lampDim = 0.6 }
            }
            try? await Task.sleep(for: .milliseconds(stilled ? 180 : 450))
            Resurfacing.markMet(node, context: context)
            Resurfacing.Rest.rest(node.id)
            withAnimation(OceanMotion.standard) {
                goingUnder = nil
                restTick += 1
            }
            try? await Task.sleep(for: .milliseconds(stilled ? 0 : 320))
            withAnimation(stilled ? OceanMotion.quick : OceanMotion.gentle) {
                lettingGo = false
                lampDim = 1
                if !stilled { lampLift = 0.04 }
            }
            guard !stilled else { return }
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(.easeInOut(duration: 1.4)) { lampLift = 0 } // art-directed: the lamp
        }
    }

    /// Opens a thought; meeting today's resurfaced fragment rests it, so the
    /// rhythm moves on to another memory tomorrow. On a split iPhone Duo it
    /// opens on `side`: the half across from the one it was tapped in (the
    /// stage and Nearby lead, the depth beside them trails).
    private func open(_ node: Node, on side: BigScreen.Side = .trailing) {
        sheetSide = side
        if node.id == resurfacing?.id {
            Resurfacing.markMet(node, context: context)
            // Seeded examples are a tour, not the promise paying off.
            if !ReviewPrompt.shared.hasRequested, !node.isExample {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    ReviewPrompt.shared.recordResurfacedOpen()
                }
            }
        }
        sheet = .thought(node)
    }

    private func updateOceanSheetPresence() {
        appState.isPresentingOceanSheet = sheet != nil || showSettings
    }

    /// A deep link (the Resurfacing widget) queued a node: open it.
    private func consumePendingFocus() {
        guard let id = appState.pendingFocusNodeID else { return }
        appState.pendingFocusNodeID = nil
        guard let node = nodes.first(where: { $0.id == id }) else { return }
        open(node)
    }
}

/// Plays the resurfacing whisper from its action row; the label is the
/// duration, the glyph the state.
private struct PlayWhisperButton: View {
    let data: Data

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let playing = AudioPlayback.shared.isPlaying(data)
            Button {
                AudioPlayback.shared.toggle(data: data)
            } label: {
                Label(AudioDurations.format(AudioDurations.seconds(for: data, id: nil) ?? 0),
                      systemImage: playing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.oceanSecondary)
            .accessibilityLabel(playing ? Text("Pause whisper") : Text("Play whisper"))
        }
    }
}

/// Recording lengths, read once per thought and cached.
enum AudioDurations {
    private static var cache: [UUID: TimeInterval] = [:]

    static func seconds(for data: Data, id: UUID?) -> TimeInterval? {
        if let id, let cached = cache[id] { return cached }
        guard let player = try? AVAudioPlayer(data: data) else { return nil }
        let seconds = player.duration
        if let id { cache[id] = seconds }
        return seconds
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
