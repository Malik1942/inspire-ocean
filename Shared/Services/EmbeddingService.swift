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

    /// Rank candidates by similarity to a query. Returns ids in descending order.
    func rank<ID>(query: String, candidates: [(id: ID, text: String)], limit: Int) -> [ID] {
        let scored = candidates.map { (id: $0.id, score: similarity(query, $0.text)) }
        return scored
            .filter { $0.score > 0.0001 }
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
