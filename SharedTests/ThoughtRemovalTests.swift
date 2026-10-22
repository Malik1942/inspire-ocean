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

    /// Before any test runs (2023-11-14), so an archive's stamp is later.
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

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
