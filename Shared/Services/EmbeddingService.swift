import Foundation
import NaturalLanguage

/// On-device semantic similarity using Apple's `NLEmbedding` word vectors.
///
/// This gives Ocean genuine (offline) semantic search and related-node sensing
/// without a cloud round-trip, while leaving a clean seam for a cloud embedding
/// model later (see `OceanAIService`).
final class EmbeddingService {
    static let shared = EmbeddingService()

    private let embedding = NLEmbedding.wordEmbedding(for: .english)
    private var cache: [String: [Double]] = [:]
    private let lock = NSLock()

    /// Average word-vector for a piece of text. Returns nil if no token is known.
    func vector(for text: String) -> [Double]? {
        let key = text.lowercased()
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached.isEmpty ? nil : cached
        }
        lock.unlock()

        guard let embedding else { return nil }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = key
        var sum: [Double] = []
        var count = 0

        tokenizer.enumerateTokens(in: key.startIndex..<key.endIndex) { range, _ in
            let token = String(key[range])
            guard token.count > 1, let vec = embedding.vector(for: token) else { return true }
            if sum.isEmpty {
                sum = vec
            } else {
                for i in 0..<min(sum.count, vec.count) { sum[i] += vec[i] }
            }
            count += 1
            return true
        }

        let result = count > 0 ? sum.map { $0 / Double(count) } : []
        lock.lock()
        cache[key] = result
        lock.unlock()
        return result.isEmpty ? nil : result
    }

    /// Cosine similarity in [-1, 1]; returns a keyword-overlap fallback when
    /// embeddings are unavailable so the feature degrades gracefully.
    func similarity(_ a: String, _ b: String) -> Double {
        if let va = vector(for: a), let vb = vector(for: b) {
            return EmbeddingService.cosine(va, vb)
        }
        return EmbeddingService.keywordOverlap(a, b)
    }

    /// Similarity below which a fragment is not relevant enough to enter an
    /// Ocean Dialogue answer. A grounded reply built from noise is worse than
    /// an honest "nothing matches", so retrieval drops everything under this
    /// floor and lets the empty state fire. Chosen from the on-device
    /// `NLEmbedding` score distribution: nonsense queries top out around 0.67,
    /// real paraphrase matches land near 0.74, so 0.70 sits in the gap.
    /// Sibling of `SemanticThemes.relatednessFloor` (a different, lower bar for
    /// ambient related-node sensing).
    ///
    /// The corridor is narrow (about 0.03 above the noise ceiling, 0.04 below
    /// the paraphrase target) and depends on Apple's NLEmbedding distribution,
    /// so it can drift when Apple revises the model. Re-derive it with
    /// `Scripts/embedding-floor-sweep/` rather than guessing a new number.
    static let dialogueRetrievalFloor = 0.70

    /// Rank candidates by similarity to a query. Returns ids in descending
    /// order. `floor` drops candidates that score below it, so a caller can
    /// require genuine relevance rather than padding the result to `limit`.
    func rank<ID>(query: String, candidates: [(id: ID, text: String)], limit: Int, floor: Double = 0) -> [ID] {
        let cutoff = Swift.max(floor, 0.0001)
        let scored = candidates.map { (id: $0.id, score: similarity(query, $0.text)) }
        return scored
            .filter { $0.score >= cutoff }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.id }
    }

    // MARK: - Math

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<n {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    static func keywordOverlap(_ a: String, _ b: String) -> Double {
        let sa = Set(a.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count > 2 })
        let sb = Set(b.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count > 2 })
        guard !sa.isEmpty, !sb.isEmpty else { return 0 }
        let inter = sa.intersection(sb).count
        let union = sa.union(sb).count
        return union == 0 ? 0 : Double(inter) / Double(union)
    }
}
