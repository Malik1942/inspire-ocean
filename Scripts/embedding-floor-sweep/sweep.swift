// Reproduces EmbeddingService (Shared/Services/EmbeddingService.swift) exactly:
// averaged NLEmbedding word vectors, cosine similarity, keyword-overlap fallback.
// Reads the JSON that extract.py emits and prints, for each named anchor, the
// query's top score, the intended target's score and rank, and how many
// fragments clear the 0.70 dialogue floor. This is how the floor is re-derived
// when Apple revises the on-device NLEmbedding model.
//
// Usage: swift sweep.swift <nodes.json>

import Foundation
import NaturalLanguage

let floor = 0.70
let embedding = NLEmbedding.wordEmbedding(for: .english)

func vector(for text: String) -> [Double]? {
    let key = text.lowercased()
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
    return count > 0 ? sum.map { $0 / Double(count) } : nil
}

func cosine(_ a: [Double], _ b: [Double]) -> Double {
    let n = min(a.count, b.count)
    guard n > 0 else { return 0 }
    var dot = 0.0, na = 0.0, nb = 0.0
    for i in 0..<n { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
    guard na > 0, nb > 0 else { return 0 }
    return dot / (na.squareRoot() * nb.squareRoot())
}

func keywordOverlap(_ a: String, _ b: String) -> Double {
    func tokens(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 2 })
    }
    let sa = tokens(a), sb = tokens(b)
    guard !sa.isEmpty, !sb.isEmpty else { return 0 }
    return Double(sa.intersection(sb).count) / Double(sa.union(sb).count)
}

func similarity(_ a: String, _ b: String) -> Double {
    if let va = vector(for: a), let vb = vector(for: b) { return cosine(va, vb) }
    return keywordOverlap(a, b)
}

struct Node: Codable { let pk: Int; let title: String; let searchable: String }

// Named anchors: (label, query, optional target-title substring). The three
// documented corridor cases plus a nonsense probe that must land empty.
let anchors: [(label: String, query: String, target: String?)] = [
    ("R8 noise ceiling (must be empty)", "have I written about quantum accounting standards", nil),
    ("R2 paraphrase (target Blank page)", "why do I put off beginning work", "Blank page"),
    ("T6 boundary (target Attention Drain)", "notifications interrupt attention", "Attention Drain"),
]

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "nodes.json"
let nodes = try JSONDecoder().decode([Node].self, from: Data(contentsOf: URL(fileURLWithPath: path)))

print("Embedding floor sweep, floor \(floor), \(nodes.count) nodes\n")
for anchor in anchors {
    let scored = nodes
        .map { (title: $0.title, score: similarity(anchor.query, $0.searchable)) }
        .sorted { $0.score > $1.score }
    let cleared = scored.filter { $0.score >= floor }.count
    print("\(anchor.label)")
    print(String(format: "  query: \"%@\"", anchor.query))
    print(String(format: "  top: %.4f  %@", scored[0].score, scored[0].title))
    if let target = anchor.target,
       let idx = scored.firstIndex(where: { $0.title.contains(target) }) {
        let hit = scored[idx]
        print(String(format: "  target: %.4f  %@  (rank %d, %@)",
                     hit.score, hit.title, idx + 1, hit.score >= floor ? "retrieved" : "below floor"))
    }
    print("  cleared >= \(floor): \(cleared)\n")
}
