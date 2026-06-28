import Foundation
import SwiftData

extension ModelContext {
    /// Hard-deletes `node` and its branch subtree without the SwiftData
    /// use-after-delete crash.
    ///
    /// A direct `delete(node)` faults any SwiftUI view still rendering the node
    /// — or, when the node has branches, a cascade-deleted child — because the
    /// view re-evaluates and reads a property on the now-detached object:
    /// *"This backing data was detached from a context without resolving
    /// attribute faults: … \Node.themes."* A plain dismiss()-then-delete isn't
    /// enough: a Library row or an Ocean mote elsewhere still holds the child,
    /// and the cascade's relationship mutation forces it to re-read.
    ///
    /// So drop the subtree from every `!isArchived` query first by archiving it
    /// (the objects stay valid, so nothing faults), let SwiftUI settle, then
    /// detach it once no view renders it. The node is invisible for the brief
    /// window between, so the deferral is never seen.
    func deleteNodeSafely(_ node: Node) {
        func archive(_ n: Node) {
            n.isArchived = true
            (n.children ?? []).forEach(archive)
        }
        archive(node)
        try? save()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.delete(node)
            try? self.save()
        }
    }
}
