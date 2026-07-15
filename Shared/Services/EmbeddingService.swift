import Foundation
import NaturalLanguage

/// A sentence-level vector for a piece of text, or nil when the backing
/// model has no signal (assets not present, model unavailable for the
/// detected language, empty input). This is the seam behind
/// `EmbeddingService` — see its type doc for why there are two
/// implementations and how they're composed.
protocol EmbeddingBackend {
    func vector(for text: String) -> [Double]?
}

/// On-device semantic similarity, backed by one of two candidate embedding
/// models behind a stable seam other code depends on (`vector(for:)`,
/// `similarity(_:_:)`, `rank(...)`). This gives Ocean genuine (offline)
/// semantic search and related-node sensing without a cloud round-trip,
/// while leaving a clean seam for a cloud embedding model later (see
/// `OceanAIService`).
///
/// ## Candidate A — `NLContextualEmbedding` (primary)
/// Apple's contextual (subword, transformer-style) embedding, chosen as the
/// default because within one language it is meaningfully better than
/// averaged word vectors. **Empirically verified caveat**, relevant to
/// `docs/plans/bilingual-voice/BRIEF.md` decision 11, which frames this as
/// "multilingual, one space for zh+en kinship": that framing does not hold
/// on-device. Probing `NLContextualEmbedding.contextualEmbeddings(forValues:)`
/// shows Apple groups languages by script family, not into one universal
/// space — `NLContextualEmbedding(language: .english)` resolves to a
/// Latin-script European model (cs/da/de/en/es/fi/fr/hr/hu/id/it/nb/nl/pl/
/// pt/ro/sk/sv/tr/vi), while `NLContextualEmbedding(language: .simplifiedChinese)`
/// resolves to a *different* CJK model (ja/ko/zh-Hans/zh-Hant). Feeding a
/// Chinese string through the English model doesn't throw (its detected
/// `NLLanguage` comes back `.und`), but the resulting vector is meaningless
/// against the Chinese model's space: a measured cross-model cosine on a
/// genuinely related zh/en pair landed at ~0.02 (noise floor), versus
/// ~0.65–0.92 for real same-model pairs. So this backend only improves
/// *same-language* similarity; it does not make a Chinese node and an
/// English node directly comparable by cosine. Cross-language kinship still
/// has to lean on `SemanticThemes.relatedness`'s theme-overlap term, and
/// even that needs the concept vocabulary to have non-English prototypes to
/// mean anything for Chinese text (see `SemanticThemes.concepts`) — a real
/// gap this task did not close, flagged as an open question.
///
/// ## Candidate B — `NLEmbedding` (dual, per-language, fallback)
/// The averaged-word-vector approach that used to ship hardcoded to
/// `.english` (the bilingual-voice bug), generalized here into
/// detect-then-route: `NLLanguageRecognizer` identifies the dominant
/// language and the matching `NLEmbedding.wordEmbedding` is used, falling
/// back to English when no word model exists for the detected language.
/// Kept as the automatic fallback (not merely a document footnote): it
/// needs no separate asset download beyond what `NLEmbedding` already
/// provides, so it stays available even before the contextual model's
/// assets have downloaded, keeping semantic search working offline on
/// first run — consistent with the "never block or degrade silently on a
/// pending download" spirit of decision 12.
///
/// See `Scripts/embedding-floor-sweep/sweep.swift` for measured
/// `relatednessFloor` candidates for both backends; it does not change
/// `SemanticThemes.relatednessFloor` itself.
final class EmbeddingService {
    static let shared = EmbeddingService()

    private let primary: EmbeddingBackend
    private let fallback: EmbeddingBackend
    private var cache: [String: [Double]] = [:]
    private let lock = NSLock()

    init(primary: EmbeddingBackend = ContextualEmbeddingBackend(), fallback: EmbeddingBackend = DualLanguageEmbeddingBackend()) {
        self.primary = primary
        self.fallback = fallback
    }

    /// Sentence-level vector for a piece of text, tried against the primary
    /// backend first and the fallback second. Returns nil if neither has a
    /// vector (both models unavailable, or no recognizable token).
    func vector(for text: String) -> [Double]? {
        let key = text.lowercased()
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached.isEmpty ? nil : cached
        }
        lock.unlock()

        let result = primary.vector(for: text) ?? fallback.vector(for: text) ?? []
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
    /// This value was derived against the old English-only `NLEmbedding`
    /// backend; it has not yet been re-swept against the contextual backend
    /// added in this pass (only `relatednessFloor` candidates were, per the
    /// bilingual-voice A4 task) — re-derive before trusting it across a
    /// backend switch.
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

    /// Jaccard overlap of meaningful tokens, used only when embeddings have
    /// no vector for either side.
    static func keywordOverlap(_ a: String, _ b: String) -> Double {
        let sa = meaningfulTokens(in: a)
        let sb = meaningfulTokens(in: b)
        guard !sa.isEmpty, !sb.isEmpty else { return 0 }
        let inter = sa.intersection(sb).count
        let union = sa.union(sb).count
        return union == 0 ? 0 : Double(inter) / Double(union)
    }

    /// Word-boundary tokens for `keywordOverlap`. Uses `NLTokenizer` rather
    /// than splitting on non-letter characters: Chinese has no whitespace
    /// between words, and every Han character is `isLetter`, so the old
    /// `split(whereSeparator: { !$0.isLetter })` treated an entire Chinese
    /// sentence as one indivisible "word" — two Chinese fragments sharing
    /// real content words would silently never overlap. The minimum-length
    /// filter is CJK-aware for the same reason `SemanticThemes.contentWords`
    /// is: most Chinese content words are two characters, so the
    /// English three-character-plus bar would drop nearly all of them.
    private static func meaningfulTokens(in text: String) -> Set<String> {
        let lowered = text.lowercased()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = lowered
        var tokens = Set<String>()
        tokenizer.enumerateTokens(in: lowered.startIndex..<lowered.endIndex) { range, _ in
            let token = String(lowered[range])
            let isCJK = token.unicodeScalars.contains { $0.properties.isIdeographic }
            let minLength = isCJK ? 1 : 2
            guard token.count > minLength, token.rangeOfCharacter(from: .letters) != nil else { return true }
            tokens.insert(token)
            return true
        }
        return tokens
    }
}

// MARK: - Backend A: contextual (multilingual, script-grouped)

/// Wraps `NLContextualEmbedding`, one model instance per detected-language
/// script family (cached, since Apple resolves several `NLLanguage` values
/// to the same shared model — see `EmbeddingService`'s doc for the measured
/// language groupings). Produces a sentence vector by mean-pooling the
/// model's per-token vectors, matching the pooling `NLContextualEmbeddingResult`
/// itself recommends (it returns subword-level vectors, not one
/// whole-string vector).
final class ContextualEmbeddingBackend: EmbeddingBackend {
    private let lock = NSLock()
    private var modelsByLanguage: [NLLanguage: NLContextualEmbedding?] = [:]

    func vector(for text: String) -> [Double]? {
        let key = text.lowercased()
        guard !key.isEmpty else { return nil }
        guard let language = ContextualEmbeddingBackend.detectLanguage(key) else { return nil }
        guard let model = model(for: language), model.hasAvailableAssets else { return nil }
        guard let result = try? model.embeddingResult(for: key, language: language) else { return nil }

        var sum: [Double] = []
        var count = 0
        result.enumerateTokenVectors(in: key.startIndex..<key.endIndex) { vec, _ in
            if sum.isEmpty {
                sum = vec
            } else {
                for i in 0..<min(sum.count, vec.count) { sum[i] += vec[i] }
            }
            count += 1
            return true
        }
        guard count > 0 else { return nil }
        return sum.map { $0 / Double(count) }
    }

    /// One `NLContextualEmbedding` instance per language, memoized. Apple
    /// resolves several languages to the same underlying model (e.g. `.japanese`,
    /// `.korean`, `.simplifiedChinese`, and `.traditionalChinese` all resolve
    /// to one CJK model), so this cache is keyed by the requested language,
    /// not the model identity — a few redundant instances for the same model
    /// is a fine tradeoff for a straightforward cache.
    private func model(for language: NLLanguage) -> NLContextualEmbedding? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = modelsByLanguage[language] { return cached }
        let model = NLContextualEmbedding(language: language)
        modelsByLanguage[language] = model
        return model
    }

    private static func detectLanguage(_ text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }
}

// MARK: - Backend B: dual per-language word vectors (fallback)

/// Averaged `NLEmbedding` word vectors, routed by detected language instead
/// of hardcoded to `.english` (the bilingual-voice bug this replaces). Kept
/// as the always-available fallback — see `EmbeddingService`'s doc comment
/// for why.
final class DualLanguageEmbeddingBackend: EmbeddingBackend {
    private let lock = NSLock()
    private var embeddingsByLanguage: [NLLanguage: NLEmbedding?] = [:]

    func vector(for text: String) -> [Double]? {
        let key = text.lowercased()
        guard !key.isEmpty else { return nil }
        guard let embedding = resolvedEmbedding(for: key) else { return nil }

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

    /// Detected language's word-embedding model, falling back to English
    /// when detection fails or that language has no `NLEmbedding` model —
    /// the same always-on default the pre-bilingual code hardcoded, now
    /// reached only when routing doesn't have anything better.
    private func resolvedEmbedding(for text: String) -> NLEmbedding? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let detected = recognizer.dominantLanguage, let embedding = embedding(for: detected) {
            return embedding
        }
        return embedding(for: .english)
    }

    private func embedding(for language: NLLanguage) -> NLEmbedding? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = embeddingsByLanguage[language] { return cached }
        let embedding = NLEmbedding.wordEmbedding(for: language)
        embeddingsByLanguage[language] = embedding
        return embedding
    }
}
