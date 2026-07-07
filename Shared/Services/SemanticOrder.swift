import Foundation

/// Orders fragments into one continuous "Related" ribbon for the Library, so
/// semantically adjacent thoughts sit next to each other without folders or
/// extra chrome. Adjacency in the ribbon means adjacency in meaning.
enum SemanticOrder {

    /// A Sendable snapshot of the fields the ordering needs. SwiftData `@Model`
    /// objects are not Sendable, and faulting their attributes off their
    /// context's thread is unsafe, so callers snapshot on the main actor and
    /// hand these value types to `arrange`, which then runs anywhere.
    struct Item: Sendable {
        let id: UUID
        let text: String
        let createdAt: Date
        let updatedAt: Date
    }

    /// Greedy nearest-neighbor chaining: start from the newest node, then
    /// repeatedly append the not-yet-placed node most similar to the last one
    /// placed. Neighbors in the result read as neighbors in meaning.
    ///
    /// Known limitation, accepted at this scale: greedy chains drift. A~B,
    /// B~C, C~D can place A and D on one ribbon even though A and D are
    /// unrelated; the ribbon reads as a gradient, and gradual drift is fine.
    /// What is not acceptable is an abrupt seam inside one screenful (a jump
    /// where consecutive cards share nothing). Mitigations, in order: (a)
    /// precompute each node's vector once and chain on cosine, (b) when the
    /// best remaining similarity to the chain tail falls below
    /// `SemanticThemes.relatednessFloor`, restart the chain from the most
    /// recent unplaced node instead of appending a weak link. The restart
    /// point is where a new visual paragraph begins, which reads better than a
    /// forced weak join.
    ///
    /// Pure and Sendable-safe: call it off the main actor. Returns the ordered
    /// node ids; the caller re-maps them to nodes on the main actor.
    static func arrange(_ items: [Item]) -> [UUID] {
        guard items.count > 1 else { return items.map(\.id) }

        // Memoized by a fingerprint over (id, updatedAt) so a set change or any
        // in-place content edit (backfill, user edit) invalidates the order,
        // while a plain Recent-to-Related toggle returns the cached ribbon.
        let key = Set(items.map { Fingerprint(id: $0.id, updatedAt: $0.updatedAt) })
        lock.lock()
        if let cached = memo, cached.key == key {
            lock.unlock()
            return cached.order
        }
        lock.unlock()

        // Precompute each node's vector once (nil for empty-content nodes, which
        // then fall back to per-pair string similarity below).
        var vectors: [UUID: [Double]] = [:]
        vectors.reserveCapacity(items.count)
        for item in items {
            if let vector = EmbeddingService.shared.vector(for: item.text) {
                vectors[item.id] = vector
            }
        }

        func score(_ a: Item, _ b: Item) -> Double {
            if let va = vectors[a.id], let vb = vectors[b.id] {
                return EmbeddingService.cosine(va, vb)
            }
            // Empty-content nodes have no vector; the string fallback returns a
            // low score, which lands them at paragraph breaks (below the floor).
            return EmbeddingService.shared.similarity(a.text, b.text)
        }

        // Newest first: the chain starts from the newest node, and every restart
        // resumes from the most recent unplaced node.
        var remaining = items.sorted { $0.createdAt > $1.createdAt }
        var order: [UUID] = []
        order.reserveCapacity(items.count)

        var tail = remaining.removeFirst()
        order.append(tail.id)

        while !remaining.isEmpty {
            var bestIndex = 0
            var bestScore = -Double.infinity
            for (index, candidate) in remaining.enumerated() {
                let s = score(tail, candidate)
                if s > bestScore {
                    bestScore = s
                    bestIndex = index
                }
            }
            if bestScore >= SemanticThemes.relatednessFloor {
                tail = remaining.remove(at: bestIndex)
            } else {
                // New visual paragraph: resume from the most recent unplaced
                // node rather than forcing a weak join.
                tail = remaining.removeFirst()
            }
            order.append(tail.id)
        }

        lock.lock()
        memo = (key: key, order: order)
        lock.unlock()
        return order
    }

    // MARK: - Memo

    private struct Fingerprint: Hashable {
        let id: UUID
        let updatedAt: Date
    }

    private static let lock = NSLock()
    private static var memo: (key: Set<Fingerprint>, order: [UUID])?
}
