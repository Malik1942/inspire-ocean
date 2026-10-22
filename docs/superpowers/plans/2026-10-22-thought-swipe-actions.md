# Swipe to Delete or Archive a Thought Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Swipe left on a thought in the Currents page or a current's stream to reveal Archive and Delete (full swipe deletes), with an Undo toast, VoiceOver actions, and a long-press menu on Tide's "Drifted in" cards.

**Architecture:** `ThoughtRemoval` (Shared, unit-tested) hides or archives a thought and knows how to take that back; `ThoughtRemovals` (app, one per page) holds the pending removal behind an `UndoToast` and settles a delete through the existing `deleteNodeSafely`. `CurrentsPage` and `ClusterStreamView` become plain `List`s styled as tiles so the system `.swipeActions` apply.

**Tech Stack:** SwiftUI (iOS 18 floor, iOS 26 look), SwiftData, XCTest, XcodeGen.

Spec: `docs/superpowers/specs/2026-10-22-thought-swipe-actions-design.md`.

## Global Constraints

- No SwiftData model change (a model change forces a CloudKit schema redeploy).
- Do not edit anything under `Oryne/Features/FastCapture/` (PR #17 owns it); referencing its types is fine.
- iOS deployment target 18.0; Swift language mode 5.
- UI copy: English plus zh-Hans in `Oryne/Resources/Localizable.xcstrings` (value-as-key), no em or en dashes in UI copy.
- New copy: "Thought deleted" → 灵感已删除, "Thought archived" → 灵感已归档.
- Undo window: 10 s, the capture undo window.
- Layout: 20 pt gutter (`OceanSpacing.gutter`), 10 pt between tiles (`OceanSpacing.item`), tiles radius 20, unchanged.
- SharedTests compile `Shared/` directly: test files never `@testable import Oryne`.
- Build with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, run `xcodegen generate` after adding files, DerivedData outside `~/Documents`, git with `-c core.trustctime=false -c core.checkStat=minimal`.

Shell setup used by every command below:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DD=~/Library/Developer/Xcode/DerivedData/stoic-curie-swipe
SIM=F6E0B875-2AE9-43AE-B66B-C1940B6B5AD1   # throwaway "Oryne swipe test" sim, iPhone 17 Pro, iOS 26.5
G="git -c core.trustctime=false -c core.checkStat=minimal"
```

---

### Task 1: `ThoughtRemoval`, test first

**Files:**
- Create: `Shared/Services/ThoughtRemoval.swift`
- Test: `SharedTests/ThoughtRemovalTests.swift`

**Interfaces:**
- Produces: `struct ThoughtRemoval: Identifiable { enum Kind { case delete, archive }; let id: UUID; let kind: Kind; let node: Node; let hidden: [Node]; let previousUpdatedAt: Date; static func delete(_ node: Node) -> ThoughtRemoval; @discardableResult static func archive(_ node: Node) -> ThoughtRemoval; func undo() }`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import SwiftData

/// `ThoughtRemoval`: what a swiped delete or archive hides, and what its
/// Undo puts back, on an in-memory store.
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class ThoughtRemovalTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    private let stamp = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Node.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    /// A thought inserted the way BranchComposer inserts a branch.
    private func thought(_ title: String, parent: Node? = nil, archived: Bool = false) -> Node {
        let node = Node(title: title, isArchived: archived, parent: parent)
        node.updatedAt = stamp
        context.insert(node)
        return node
    }

    // MARK: - delete

    func test_delete_hidesTheThoughtAndItsBranches() throws {
        let root = thought("Root")
        let branch = thought("Branch", parent: root)
        let leaf = thought("Leaf", parent: branch)
        try context.save()

        let removal = ThoughtRemoval.delete(root)

        XCTAssertEqual(removal.kind, .delete)
        XCTAssertTrue(root.isArchived)
        XCTAssertTrue(branch.isArchived)
        XCTAssertTrue(leaf.isArchived)
        XCTAssertEqual(Set(removal.hidden.map(\.id)), [root.id, branch.id, leaf.id])
    }

    func test_undoDelete_bringsItBack_butABranchArchivedBeforeStaysArchived() throws {
        let root = thought("Root")
        let kept = thought("Kept", parent: root)
        let shelved = thought("Shelved", parent: root, archived: true)
        try context.save()

        let removal = ThoughtRemoval.delete(root)
        removal.undo()

        XCTAssertFalse(root.isArchived)
        XCTAssertFalse(kept.isArchived)
        XCTAssertTrue(shelved.isArchived)
    }

    func test_delete_leavesUpdatedAtAlone() throws {
        let root = thought("Root")
        try context.save()

        let removal = ThoughtRemoval.delete(root)
        XCTAssertEqual(root.updatedAt, stamp)
        removal.undo()
        XCTAssertEqual(root.updatedAt, stamp)
    }

    // MARK: - archive

    func test_archive_isTheLibrarysArchive_andUndoPutsItBack() throws {
        let root = thought("Root")
        let branch = thought("Branch", parent: root)
        try context.save()

        let removal = ThoughtRemoval.archive(root)

        XCTAssertEqual(removal.kind, .archive)
        XCTAssertTrue(root.isArchived)
        XCTAssertGreaterThan(root.updatedAt, stamp)
        XCTAssertFalse(branch.isArchived, "Archive takes the thought alone, as the Library does")

        removal.undo()

        XCTAssertFalse(root.isArchived)
        XCTAssertEqual(root.updatedAt, stamp)
    }

    // MARK: - undo after a sync

    func test_undo_skipsABranchDeletedMeanwhile() throws {
        let root = thought("Root")
        let branch = thought("Branch", parent: root)
        try context.save()
        let removal = ThoughtRemoval.delete(root)

        // Another device deleted the branch while the toast was up.
        context.delete(branch)
        try context.save()

        removal.undo()

        XCTAssertFalse(root.isArchived)
        XCTAssertNil(branch.modelContext)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project Oryne.xcodeproj -scheme Oryne -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath $DD -only-testing:SharedTests/ThoughtRemovalTests CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES 2>&1 | grep -E "error|Test Case|TEST" | tail -20`
Expected: build FAILS with `cannot find 'ThoughtRemoval' in scope`.

- [ ] **Step 3: Write the implementation**

`Shared/Services/ThoughtRemoval.swift`:

```swift
import Foundation
import SwiftData

/// One delete or archive of a thought that can still be taken back.
///
/// Delete hides the thought and its branches at once by archiving them, the
/// first step `deleteNodeSafely` takes anyway; the caller deletes them for
/// good only once the way back has closed. Archive is the Library's archive.
/// Undo puts back exactly what the removal changed, so a branch archived
/// before stays archived. `isArchived` is the only flag: no model change.
struct ThoughtRemoval: Identifiable {
    enum Kind { case delete, archive }

    let id = UUID()
    let kind: Kind
    let node: Node
    /// Every node this removal archived: the thought, and for a delete its
    /// branches that were not archived already.
    let hidden: [Node]
    /// The thought's `updatedAt` before an archive stamped it.
    let previousUpdatedAt: Date

    /// Hides `node` and its branches ahead of a delete. `updatedAt` stays:
    /// the thought either goes for good or comes back unchanged.
    static func delete(_ node: Node) -> ThoughtRemoval {
        var hidden: [Node] = []
        func hide(_ n: Node) {
            if !n.isArchived {
                n.isArchived = true
                hidden.append(n)
            }
            (n.children ?? []).forEach(hide)
        }
        hide(node)
        return ThoughtRemoval(kind: .delete, node: node, hidden: hidden, previousUpdatedAt: node.updatedAt)
    }

    /// Archives `node` alone, as the Library does; its branches stay where
    /// they are.
    @discardableResult
    static func archive(_ node: Node) -> ThoughtRemoval {
        let previous = node.updatedAt
        let hidden = node.isArchived ? [] : [node]
        node.isArchived = true
        node.updatedAt = .now
        return ThoughtRemoval(kind: .archive, node: node, hidden: hidden, previousUpdatedAt: previous)
    }

    /// Takes the removal back. A node deleted meanwhile (by a sync from
    /// another device) is detached, and touching it would fault: skipped.
    func undo() {
        for n in hidden where n.modelContext != nil {
            n.isArchived = false
        }
        if kind == .archive, node.modelContext != nil {
            node.updatedAt = previousUpdatedAt
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: the Step 2 command.
Expected: `Test Suite 'ThoughtRemovalTests' passed`, 5 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
$G add Shared/Services/ThoughtRemoval.swift SharedTests/ThoughtRemovalTests.swift docs/superpowers/specs/2026-10-22-thought-swipe-actions-design.md docs/superpowers/plans/2026-10-22-thought-swipe-actions.md
$G commit -m "Thought removal: a delete or archive that Undo can take back"
```

---

### Task 2: The toast, the page's removals, the tile list

**Files:**
- Create: `Oryne/DesignSystem/UndoToast.swift`
- Create: `Oryne/DesignSystem/TileList.swift`
- Create: `Oryne/Features/Ocean/ThoughtRemovals.swift`

**Interfaces:**
- Consumes: `ThoughtRemoval` (Task 1); `ModelContext.deleteNodeSafely(_:)` (`Oryne/Services/NodeDeletion.swift`); `OceanBarBackground` (`Oryne/Features/FastCapture/CaptureBar.swift`, read only).
- Produces: `struct UndoToast: View { let message: String; var onUndo: () -> Void }`; `extension View { func tileList() -> some View; func tileRow(top: CGFloat = OceanSpacing.item / 2, bottom: CGFloat = OceanSpacing.item / 2) -> some View }`; `@MainActor @Observable final class ThoughtRemovals { static let undoWindow: Duration; private(set) var pending: ThoughtRemoval?; func delete(_:); func archive(_:); func undo(); func settle() }`; `extension ThoughtRemoval { var message: String }`; `extension View { func thoughtSwipeActions(_ node: Node, removals: ThoughtRemovals) -> some View; func thoughtRemovalToast(_ removals: ThoughtRemovals) -> some View; func settlesThoughtRemovals(_ removals: ThoughtRemovals) -> some View }`.

- [ ] **Step 1: `UndoToast`**

```swift
import SwiftUI

/// The way back after a thought is deleted or archived: what happened, and
/// Undo. The capture toast's twin (`CaptureToast`): a capsule in the bar's
/// own material, floating over the page for the whole undo window.
struct UndoToast: View {
    /// Already localized: VoiceOver announces the same words.
    let message: String
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(OceanTheme.foam)
                .lineLimit(1)
            Button(action: onUndo) {
                Text("Undo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OceanTheme.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 22)
        .padding(.trailing, 12)
        .frame(height: 48)
        .background(OceanBarBackground())
        .accessibilityElement(children: .contain)
    }
}
```

- [ ] **Step 2: `tileList()` and `tileRow()`**

```swift
import SwiftUI

/// Tiles in a `List`, so the system's swipe actions work on them, laid out
/// as they are in a scroll view: no row backgrounds, no separators, the
/// water showing through. Rows set their own spacing.
extension View {
    func tileList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
    }

    /// One row of a tile list: the page gutter at the sides, `top` and
    /// `bottom` toward its neighbors. Two tiles sit an item gap apart.
    func tileRow(top: CGFloat = OceanSpacing.item / 2, bottom: CGFloat = OceanSpacing.item / 2) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: OceanSpacing.gutter, bottom: bottom, trailing: OceanSpacing.gutter))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
```

- [ ] **Step 3: `ThoughtRemovals` and its view modifiers**

```swift
import SwiftUI
import SwiftData

/// A page's way back from a swiped delete or archive: the one removal its
/// Undo toast offers. A new removal settles the one before it; the window
/// running out, the page closing and the app going to the background settle
/// the last. Settling a delete is the existing `deleteNodeSafely`; if the app
/// is killed first, the thought is left archived, not lost.
@MainActor
@Observable
final class ThoughtRemovals {
    /// As long as a capture can be taken back (`CaptureSession.undoWindow`).
    static let undoWindow: Duration = .seconds(10)

    private(set) var pending: ThoughtRemoval?
    @ObservationIgnored private var window: Task<Void, Never>?

    func delete(_ node: Node) {
        begin(.delete(node))
    }

    func archive(_ node: Node) {
        begin(.archive(node))
    }

    /// The thought is back where it was.
    func undo() {
        guard let removal = pending else { return }
        close()
        removal.undo()
        try? removal.node.modelContext?.save()
    }

    /// The way back closes: a delete goes for good, an archive stays.
    func settle() {
        guard let removal = pending else { return }
        close()
        if removal.kind == .delete, let context = removal.node.modelContext {
            context.deleteNodeSafely(removal.node)
        }
    }

    private func begin(_ removal: ThoughtRemoval) {
        settle()
        try? removal.node.modelContext?.save()
        pending = removal
        AccessibilityNotification.Announcement(removal.message).post()
        window = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.settle()
        }
    }

    private func close() {
        window?.cancel()
        window = nil
        pending = nil
    }
}

extension ThoughtRemoval {
    /// What the toast says, and what VoiceOver hears.
    var message: String {
        switch kind {
        case .delete: String(localized: "Thought deleted")
        case .archive: String(localized: "Thought archived")
        }
    }
}

extension View {
    /// A thought's row in a list: swipe left for Archive and Delete, swipe
    /// all the way to delete, as in Notes. VoiceOver gets the same two as
    /// actions on the row.
    func thoughtSwipeActions(_ node: Node, removals: ThoughtRemovals) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { removals.delete(node) } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { removals.archive(node) } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }
        .accessibilityActions {
            Button("Delete") { removals.delete(node) }
            Button("Archive") { removals.archive(node) }
        }
    }

    /// The page's Undo toast, floating at the bottom of the page.
    func thoughtRemovalToast(_ removals: ThoughtRemovals) -> some View {
        overlay(alignment: .bottom) {
            ZStack {
                if let removal = removals.pending {
                    UndoToast(message: removal.message) { removals.undo() }
                        .id(removal.id)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
            .padding(.bottom, 12)
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: removals.pending?.id)
        }
    }

    /// Settles the page's removals when the page closes or the app goes to
    /// the background. On the page's `NavigationStack`, so opening a thought
    /// from the page does not count as closing it.
    func settlesThoughtRemovals(_ removals: ThoughtRemovals) -> some View {
        modifier(SettleThoughtRemovals(removals: removals))
    }
}

private struct SettleThoughtRemovals: ViewModifier {
    let removals: ThoughtRemovals
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onDisappear { removals.settle() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { removals.settle() }
            }
    }
}
```

- [ ] **Step 4: Build**

Run: `xcodegen generate && xcodebuild build -project Oryne.xcodeproj -scheme Oryne -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath $DD CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES 2>&1 | grep -E "error:|BUILD" | tail -10`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
$G add Oryne/DesignSystem/UndoToast.swift Oryne/DesignSystem/TileList.swift Oryne/Features/Ocean/ThoughtRemovals.swift
$G commit -m "Undo toast and swipe actions for a thought's row"
```

---

### Task 3: The Currents page as a tile list

**Files:**
- Modify: `Oryne/Features/Ocean/CurrentsPage.swift` (the `CurrentsPage` struct, lines 38-154)

**Interfaces:**
- Consumes: `tileList()`, `tileRow(top:bottom:)`, `ThoughtRemovals`, `thoughtSwipeActions`, `thoughtRemovalToast`, `settlesThoughtRemovals` (Task 2).

- [ ] **Step 1: Replace the struct body**

Keep `CurrentGroup`, `StreamSelection`, `groups`, `query` and `visible` as they are. New state, constants, body and `current`:

```swift
    @State private var search = ""
    @State private var stream: StreamSelection?
    /// Thoughts opened from this page. A path, not `NavigationLink`s: a
    /// link in a `List` draws a chevron the tiles don't wear.
    @State private var path: [Node] = []
    /// The way back from a swiped delete or archive.
    @State private var removals = ThoughtRemovals()

    /// Newest thoughts previewed under each current's name.
    private static let previewCount = 2
    /// From one current's last tile to the next current's name.
    private static let currentGap: CGFloat = OceanSpacing.section - 8

    var body: some View {
        let entries = visible
        NavigationStack(path: $path) {
            ZStack {
                OceanBackground(animated: false)
                List {
                    if entries.isEmpty {
                        Text("Nothing drifts near this yet")
                            .font(.subheadline)
                            .foregroundStyle(OceanTheme.mist)
                            .frame(maxWidth: .infinity)
                            .tileRow(top: OceanSpacing.block)
                    }
                    ForEach(entries, id: \.group.id) { entry in
                        current(entry.group, rows: entry.rows, forced: entry.forced,
                                isFirst: entry.group.id == entries.first?.group.id)
                    }
                }
                .tileList()
                .contentMargins(.bottom, OceanSpacing.section, for: .scrollContent)
                .thoughtRemovalToast(removals)
            }
            // The page as one container, for UI tests and pointing tools.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("currents.page")
            // No custom bar background: it would swap in its own appearance
            // and drop the New York large title Library wears.
            .navigationTitle("Currents")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $search, prompt: "Search currents and thoughts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .navigationDestination(for: Node.self) { node in
                NodeDetailContent(node: node)
            }
            .sheet(item: $stream) { selection in
                ClusterStreamView(theme: selection.theme)
            }
            // A summary or a question opens in Ask: step out of the way so
            // the answer is what you see.
            .onChange(of: appState.selectedTab) { _, tab in
                if tab == .ask { dismiss() }
            }
        }
        .settlesThoughtRemovals(removals)
    }

    // MARK: Current

    /// One current, as rows: its name and a › open the whole current
    /// (Summarize and Add a thought at the top, every thought below); its
    /// two newest thoughts sit under the name as a preview, each a way into
    /// that thought, and each swipes away. Searching, every match is listed.
    @ViewBuilder
    private func current(_ group: CurrentGroup, rows: [Node], forced: Bool, isFirst: Bool) -> some View {
        let shown = forced ? rows : Array(rows.prefix(Self.previewCount))
        Button { stream = StreamSelection(theme: group.key) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.label)
                    .font(OceanType.sectionLabel)
                    .foregroundStyle(group.isAdrift ? OceanTheme.mist : OceanTheme.foam)
                    .lineLimit(1)
                    .padding(.leading, 2)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OceanTheme.mist)
            }
            .frame(minHeight: OceanControlSize.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens every thought in this current.")
        .opacity(group.isAdrift ? 0.75 : 1)
        .tileRow(top: isFirst ? 8 : Self.currentGap - OceanSpacing.item / 2)

        ForEach(shown) { node in
            Button { path.append(node) } label: { NodeRow(node: node, showsCurrent: false) }
                .buttonStyle(.plain)
                .opacity(group.isAdrift ? 0.75 : 1)
                .thoughtSwipeActions(node, removals: removals)
                .tileRow()
        }
    }
```

Update the struct's doc comment: "a tile opens its thought, and swiping it left archives or deletes it."

- [ ] **Step 2: Build** (Task 2 Step 4 command). Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Look at it** on `$SIM` (Task 6 has the launch steps): the page matches the old spacing (title, 8 pt to the first name, 10 pt between tiles, 32 pt between currents), no chevrons on tiles, no row highlight, tapping a tile opens the thought, tapping a name opens the stream.

- [ ] **Step 4: Commit**

```bash
$G add Oryne/Features/Ocean/CurrentsPage.swift
$G commit -m "Currents page: swipe a thought left to archive or delete it"
```

---

### Task 4: A current's stream as a tile list

**Files:**
- Modify: `Oryne/Features/Ocean/ClusterStreamView.swift` (state and `body`, lines 11-84)

**Interfaces:**
- Consumes: Task 2's `tileList()`, `tileRow(top:bottom:)`, `ThoughtRemovals`, `thoughtSwipeActions`, `thoughtRemovalToast`, `settlesThoughtRemovals`.

- [ ] **Step 1: State and body**

Add next to `showCapture`:

```swift
    /// Thoughts opened from this stream. A path, not `NavigationLink`s: a
    /// link in a `List` draws a chevron the tiles don't wear.
    @State private var path: [Node] = []
    /// The way back from a swiped delete or archive.
    @State private var removals = ThoughtRemovals()
```

Replace `NavigationStack { ScrollView { ... } ... }` through `.toolbar { ... } }` with:

```swift
        NavigationStack(path: $path) {
            List {
                header
                    .tileRow(top: 4, bottom: OceanSpacing.block - OceanSpacing.item / 2)
                ForEach(members) { node in
                    Button { path.append(node) } label: { NodeRow(node: node, showsCurrent: false) }
                        .buttonStyle(.plain)
                        .thoughtSwipeActions(node, removals: removals)
                        .tileRow()
                }
            }
            .tileList()
            .contentMargins(.bottom, OceanSpacing.section, for: .scrollContent)
            .thoughtRemovalToast(removals)
            .background(OceanBackground())
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Node.self) { node in
                NodeDetailContent(node: node)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
        .settlesThoughtRemovals(removals)
```

The `.presentationDetents`, `.presentationBackground`, `.onChange(of: appState.selectedTab)` and the capture `.sheet` stay after it. Update the type's doc comment: "Each tile opens the familiar thought page; swiping it left archives or deletes it."

- [ ] **Step 2: Build** (Task 2 Step 4 command). Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Look at it**: header spacing (4 pt top, 24 pt to the first tile), Summarize and Add a thought each tap on their own, the medium detent still grows to large on scroll.

- [ ] **Step 4: Commit**

```bash
$G add Oryne/Features/Ocean/ClusterStreamView.swift
$G commit -m "A current's stream: swipe a thought left to archive or delete it"
```

---

### Task 5: Cards: "Drifted in" menu, VoiceOver actions, copy

**Files:**
- Modify: `Oryne/Features/Ocean/OceanFieldView.swift` (`newestSection`, state, alert)
- Modify: `Oryne/Features/Library/LibraryView.swift` (`cell(_:)`)
- Modify: `Oryne/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ThoughtRemoval.archive(_:)` (Task 1), `ModelContext.deleteNodeSafely(_:)`.

- [ ] **Step 1: "Drifted in" (`OceanFieldView`)**

State, next to `goingUnder`:

```swift
    /// A thought a card's menu asked to delete, waiting on the alert.
    @State private var pendingDelete: Node?
```

`newestSection`'s cell:

```swift
                Button { open(node) } label: { GlanceCard(node: node) }
                    .buttonStyle(.plain)
                    // The Library's long-press menu: a card half the page
                    // wide has no room for a swipe.
                    .contextMenu {
                        Button { archive(node) } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        Button(role: .destructive) { pendingDelete = node } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .accessibilityActions {
                        Button("Delete") { pendingDelete = node }
                        Button("Archive") { archive(node) }
                    }
```

After `.sheet(isPresented: $showSettings)`:

```swift
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
```

In `// MARK: Interaction`:

```swift
    /// The Library's archive: out of Tide and every current, kept in the
    /// Library under Show archived.
    private func archive(_ node: Node) {
        ThoughtRemoval.archive(node)
        try? context.save()
    }
```

- [ ] **Step 2: Library card actions (`LibraryView.cell`)**, after `.contextMenu { ... }`:

```swift
        // VoiceOver: the menu's removals as actions on the card.
        .accessibilityActions {
            Button("Delete") { pendingDelete = node }
            Button((node.isArchived ? "Restore" : "Archive") as LocalizedStringKey) { archive(node) }
        }
```

- [ ] **Step 3: Copy.** Add to `Localizable.xcstrings`, in key order, in the file's own formatting:

```json
    "Thought archived" : {
      "localizations" : {
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "灵感已归档"
          }
        }
      }
    },
    "Thought deleted" : {
      "localizations" : {
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "灵感已删除"
          }
        }
      }
    },
```

Check: `python3 -c "import json;d=json.load(open('Oryne/Resources/Localizable.xcstrings'));print(d['strings']['Thought deleted'],d['strings']['Thought archived'])"`.

- [ ] **Step 4: Build** (Task 2 Step 4 command). Expected: `** BUILD SUCCEEDED **`; then `xcrun xcstringstool sync Oryne/Resources/Localizable.xcstrings --stringsdata $DD/Build/Intermediates.noindex/Oryne.build/Debug-iphonesimulator/Oryne.build/Objects-normal/arm64/*.stringsdata` leaves both keys without `extractionState: stale` (revert any unrelated churn it makes).

- [ ] **Step 5: Commit**

```bash
$G add Oryne/Features/Ocean/OceanFieldView.swift Oryne/Features/Library/LibraryView.swift Oryne/Resources/Localizable.xcstrings
$G commit -m "Drifted in: Archive and Delete on long press; VoiceOver actions on cards"
```

---

### Task 6: Verify on the simulator, hand over, finish

- [ ] **Step 1: Full SharedTests**: `xcodebuild test ... -only-testing:SharedTests` (Task 1 command without the class). Expected: all pass.
- [ ] **Step 2: Launch** the Debug build on `$SIM` with a seeded ocean: write `fastCapture.onboardingCompleted` into the App Group plist before first launch, then `SIMCTL_CHILD_OCEAN_SIM_COUNT=60 xcrun simctl launch $SIM com.inspireocean.app -AppleLanguages '(en)'`.
- [ ] **Step 3: Real swipes** with the iOS Simulator control tool on Tide › All currents:
  - partial swipe on a tile: Archive and Delete discs show (screenshot with `simctl io`);
  - tap Delete: the tile goes, "Thought deleted" toast with Undo; tap Undo: the tile is back;
  - full swipe: the tile goes; after 10 s the toast leaves; the row is gone from `ZNODE` (sqlite, app terminated);
  - Archive: toast "Thought archived"; Undo brings it back; archive again and check `ZISARCHIVED = 1`;
  - the same in a current's stream.
- [ ] **Step 4: VoiceOver tree**: inject a DYLD accessibility dump into the running app (scratchpad only) and check each tile is one element with exactly `Delete, Archive`, the page container carries `currents.page`, and "Drifted in" and Library cards have their actions.
- [ ] **Step 5: zh-Hans** launch (`-AppleLanguages '(zh-Hans)'`): swipe labels 删除/归档, toast 灵感已删除 with 撤销.
- [ ] **Step 6: Hand-over note** for the `am/apple-intelligence-oryne-248869` session in the shared notes folder: where its CurrentsPage and ClusterStreamView additions go when it merges main.
- [ ] **Step 7: Commit** any fixes from the pass.
