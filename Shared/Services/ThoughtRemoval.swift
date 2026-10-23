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

    /// Whether this is a delete still waiting to happen for `node`: the
    /// thought itself or a branch it hid. A delete only archives until the
    /// way back closes, so a list of archived thoughts leaves these out.
    func deletes(_ node: Node) -> Bool {
        kind == .delete && (node.id == self.node.id || hidden.contains { $0.id == node.id })
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
