// Two independent sweeps live in this file:
//
// 1. Dialogue-floor sweep (below): reproduces EmbeddingService (Shared/Services/
//    EmbeddingService.swift) exactly as it stood pre bilingual-voice — averaged
//    English-only NLEmbedding word vectors, cosine similarity, keyword-overlap
//    fallback. Reads the JSON that extract.py emits and prints, for each named
//    anchor, the query's top score, the intended target's score and rank, and
//    how many fragments clear the 0.70 dialogue floor. Needs a device-store-
//    derived nodes.json (skipped with a message if none is given).
//
// 2. Bilingual candidate sweep (BilingualRelatednessSweep, below): runs BOTH
//    EmbeddingService backend candidates added in bilingual-voice A4
//    (NLContextualEmbedding and dual per-language NLEmbedding) over a small
//    hand-built zh/en/mixed fixture set, to recommend candidate
//    SemanticThemes.relatednessFloor values per candidate. Self-contained, no
//    nodes.json needed — see Scripts/embedding-floor-sweep/README.md.
//
// Usage: swift sweep.swift               (bilingual sweep only)
//        swift sweep.swift <nodes.json>  (both sweeps)

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

// The dialogue-floor sweep above needs a real device store (via extract.py);
// the bilingual candidate sweep below is fully self-contained (a small
// hand-built fixture set), so it always runs. Only run the dialogue-floor
// sweep when a store-derived nodes.json was actually supplied.
let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "nodes.json"
if FileManager.default.fileExists(atPath: path) {
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
} else {
    print("(skipping dialogue-floor sweep: no nodes.json at \"\(path)\" — pass a store-derived path via run.sh to include it)\n")
}

BilingualRelatednessSweep.run()

// ============================================================================
// Bilingual candidate sweep (bilingual-voice A4)
// ============================================================================
//
// Reproduces the embedding-similarity term of SemanticThemes.relatedness
// (Shared/Services/SemanticThemes.swift) — the 0.60-weighted cosine-similarity
// component, not the full theme-overlap + mood blend — under BOTH
// EmbeddingService backend candidates:
//
//   - contextual: NLContextualEmbedding, mean-pooled subword token vectors
//   - dual:       per-language NLEmbedding word vectors, routed by detected
//                 language (mirrors DualLanguageEmbeddingBackend)
//
// against a small hand-built zh / en / mixed fixture set, so a candidate
// `relatednessFloor` can be read off for each backend. This does NOT change
// SemanticThemes.relatednessFloor (currently 0.45, tuned against the old
// English-only NLEmbedding) — Malik picks the final value.
//
// Only the embedding-similarity term is measured, deliberately: this same
// sweep's fixture set doubles as the evidence for a separate, larger finding
// documented in EmbeddingService.swift and SemanticThemes.swift — neither
// candidate backend gives Chinese and English a shared vector space, so
// theme-overlap (SemanticThemes.concepts, English-only prototypes) cannot
// contribute real cross-lingual signal for a zh thought today. Blending in a
// known-broken term would produce a misleading single floor number; keeping
// them separate keeps this sweep honest about what it's actually measuring.
enum BilingualRelatednessSweep {

    // MARK: Candidate A — contextual (NLContextualEmbedding)

    private static var contextualModels: [NLLanguage: NLContextualEmbedding?] = [:]

    private static func contextualModel(for language: NLLanguage) -> NLContextualEmbedding? {
        if let cached = contextualModels[language] { return cached }
        let model = NLContextualEmbedding(language: language)
        contextualModels[language] = model
        return model
    }

    /// Mirrors `ContextualEmbeddingBackend.vector(for:)` in EmbeddingService.swift.
    static func contextualVector(for text: String) -> [Double]? {
        let key = text.lowercased()
        guard !key.isEmpty, let language = detectLanguage(key) else { return nil }
        guard let model = contextualModel(for: language), model.hasAvailableAssets else { return nil }
        guard let result = try? model.embeddingResult(for: key, language: language) else { return nil }

        var sum: [Double] = []
        var count = 0
        result.enumerateTokenVectors(in: key.startIndex..<key.endIndex) { vec, _ in
            if sum.isEmpty { sum = vec } else { for i in 0..<min(sum.count, vec.count) { sum[i] += vec[i] } }
            count += 1
            return true
        }
        return count > 0 ? sum.map { $0 / Double(count) } : nil
    }

    // MARK: Candidate B — dual per-language (NLEmbedding)

    private static var dualEmbeddings: [NLLanguage: NLEmbedding?] = [:]

    private static func dualEmbedding(for language: NLLanguage) -> NLEmbedding? {
        if let cached = dualEmbeddings[language] { return cached }
        let embedding = NLEmbedding.wordEmbedding(for: language)
        dualEmbeddings[language] = embedding
        return embedding
    }

    /// Mirrors `DualLanguageEmbeddingBackend.vector(for:)` in EmbeddingService.swift.
    static func dualVector(for text: String) -> [Double]? {
        let key = text.lowercased()
        guard !key.isEmpty else { return nil }
        let embedding = detectLanguage(key).flatMap(dualEmbedding(for:)) ?? dualEmbedding(for: .english)
        guard let embedding else { return nil }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = key
        var sum: [Double] = []
        var count = 0
        tokenizer.enumerateTokens(in: key.startIndex..<key.endIndex) { range, _ in
            let token = String(key[range])
            guard token.count > 1, let vec = embedding.vector(for: token) else { return true }
            if sum.isEmpty { sum = vec } else { for i in 0..<min(sum.count, vec.count) { sum[i] += vec[i] } }
            count += 1
            return true
        }
        return count > 0 ? sum.map { $0 / Double(count) } : nil
    }

    private static func detectLanguage(_ text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }

    // MARK: Fixture set

    /// Small hand-built zh / en / mixed pairs, bucketed by language pairing
    /// so a corridor can be read off per bucket rather than one number that
    /// conflates same-language and cross-lingual behavior (they turn out to
    /// behave very differently — see `run()`'s output). `related` pairs
    /// restate the same underlying thought (paraphrase, translation, or
    /// code-switch); `unrelated` pairs are genuinely different thoughts,
    /// including two nonsense probes (the noise ceiling each candidate's
    /// floor must clear).
    private struct Pair {
        enum Bucket: String { case en, zh, cross }
        let label: String
        let bucket: Bucket
        let a: String
        let b: String
        let related: Bool
    }

    private static let fixtures: [Pair] = [
        // en <-> en
        Pair(label: "en/en career anxiety (paraphrase)", bucket: .en,
             a: "I feel anxious about my career and whether I made the right choice",
             b: "Worried I picked the wrong job, I can't stop second-guessing it",
             related: true),
        Pair(label: "en/en recurring thought (paraphrase)", bucket: .en,
             a: "The tide keeps returning my ideas about the ocean at dusk",
             b: "Watching the waves come back again at sunset, the same thought returns",
             related: true),
        Pair(label: "en/en unrelated topics", bucket: .en,
             a: "I feel anxious about my career and whether I made the right choice",
             b: "The tide keeps returning my ideas about the ocean at dusk",
             related: false),
        Pair(label: "en nonsense probe", bucket: .en,
             a: "I feel anxious about my career and whether I made the right choice",
             b: "have I written about quantum accounting standards",
             related: false),

        // zh <-> zh
        Pair(label: "zh/zh career anxiety (paraphrase)", bucket: .zh,
             a: "我对职业选择感到很焦虑，一直在怀疑自己",
             b: "总是担心自己选错了工作，心里很不安",
             related: true),
        Pair(label: "zh/zh recurring thought (paraphrase)", bucket: .zh,
             a: "海浪一次次涌来，让我又想起那件事",
             b: "潮水反复退去又涌来，那个念头也一直回来",
             related: true),
        Pair(label: "zh/zh unrelated topics", bucket: .zh,
             a: "我对职业选择感到很焦虑，一直在怀疑自己",
             b: "海浪一次次涌来，让我又想起那件事",
             related: false),
        Pair(label: "zh nonsense probe", bucket: .zh,
             a: "我对职业选择感到很焦虑，一直在怀疑自己",
             b: "量子会计准则的历史发展趋势",
             related: false),

        // zh <-> en and mixed (the actual kinship question decision 11 cares about)
        Pair(label: "zh->en career anxiety (translation)", bucket: .cross,
             a: "我对职业选择感到很焦虑，一直在怀疑自己",
             b: "I feel anxious about my career and whether I made the right choice",
             related: true),
        Pair(label: "zh->en unrelated cross-language", bucket: .cross,
             a: "我对职业选择感到很焦虑，一直在怀疑自己",
             b: "The tide keeps returning my ideas about the ocean at dusk",
             related: false),
        Pair(label: "mixed->en code-switch (paraphrase)", bucket: .cross,
             a: "今天开会的时候 I felt so stuck, 不知道该怎么表达自己的想法",
             b: "I was stuck in the meeting today and couldn't find the words",
             related: true),
    ]

    // MARK: Reporting

    static func run() {
        for (label, vectorFn) in [("contextual (NLContextualEmbedding)", contextualVector), ("dual (per-language NLEmbedding)", dualVector)] as [(String, (String) -> [Double]?)] {
            print("=== Bilingual relatedness candidate: \(label) ===\n")

            var scored: [(pair: Pair, score: Double)] = []
            for pair in fixtures {
                let score: Double
                if let va = vectorFn(pair.a), let vb = vectorFn(pair.b) {
                    score = max(0, cosine(va, vb))
                } else {
                    score = 0 // no vector on one side: this candidate has no signal for the pair
                }
                scored.append((pair, score))
                let paddedLabel = pair.label.padding(toLength: 42, withPad: " ", startingAt: 0)
                let tag = pair.related ? "related  " : "unrelated"
                print(String(format: "  %@ %@  %.4f", paddedLabel, tag, score))
            }
            print("")

            for bucket in [Pair.Bucket.en, .zh, .cross] {
                let inBucket = scored.filter { $0.pair.bucket == bucket }
                guard !inBucket.isEmpty else { continue }
                let related = inBucket.filter { $0.pair.related }.map(\.score)
                let unrelated = inBucket.filter { !$0.pair.related }.map(\.score)
                guard let minRelated = related.min(), let maxUnrelated = unrelated.max() else { continue }
                print(String(format: "  [%@] min(related)=%.4f  max(unrelated)=%.4f", bucket.rawValue, minRelated, maxUnrelated))
                if minRelated < 0.05 && maxUnrelated < 0.05 {
                    // Both sides pinned near zero (seen on the `cross` bucket for
                    // both candidates): the model has no signal at all for this
                    // pairing, not a genuine corridor — a "floor" fit to this would
                    // treat everything as related. Report it as no-signal, not a
                    // recommendation.
                    print("  [\(bucket.rawValue)] NO SIGNAL: both related and unrelated scores are near zero — not a usable corridor")
                } else if minRelated > maxUnrelated {
                    let candidateFloor = (minRelated + maxUnrelated) / 2
                    print(String(format: "  [%@] clean corridor: candidate relatednessFloor ~= %.4f", bucket.rawValue, candidateFloor))
                } else {
                    print("  [\(bucket.rawValue)] NO clean corridor: related and unrelated scores overlap")
                }
            }
            print("")
        }
    }
}
