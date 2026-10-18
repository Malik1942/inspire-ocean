import Foundation
import SwiftData

extension CurrentSnap {
    /// The currents a new thought may join, read from the Ocean's nodes.
    /// `excluding` is the thought being themed: it is already saved with
    /// provisional themes and must not offer itself as a current. Archived
    /// and example thoughts aren't part of the living Ocean.
    static func candidates(in nodes: [Node], excluding: UUID?, forEntry entry: String) -> [CurrentCandidate] {
        let members = nodes.compactMap { node -> Member? in
            guard node.id != excluding, !node.isArchived, !node.isExample,
                  let key = node.currentKey
            else { return nil }
            return Member(key: key, title: node.displayTitle, createdAt: node.createdAt)
        }
        return candidates(from: members, forEntry: entry)
    }

    /// Same, read from the store: the Ocean's non-archived thoughts.
    static func candidates(in context: ModelContext, excluding: UUID?, forEntry entry: String) -> [CurrentCandidate] {
        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { !$0.isArchived })
        guard let nodes = try? context.fetch(descriptor) else { return [] }
        return candidates(in: nodes, excluding: excluding, forEntry: entry)
    }
}
