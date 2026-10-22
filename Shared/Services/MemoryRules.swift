import Foundation
import NaturalLanguage

/// The deterministic rules around memory records: when two say the same
/// thing, when one has lost its ground, what the person deleted and must
/// not come back, and how much of it Ask may read.
enum MemoryRules {

    static let maxRecords = 24
    static let maxTextLength = 160
    /// What Ask reads: a handful of lines, well under the small model's window.
    static let preambleRecords = 8
    static let preambleCharacters = 900

    // MARK: Sameness

    /// Lowercased content words, so "You keep returning to light." and "you
    /// keep returning to the light" are one observation.
    static func contentTokens(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = lowered
        var tokens = Set<String>()
        tokenizer.enumerateTokens(in: lowered.startIndex..<lowered.endIndex) { range, _ in
            let token = String(lowered[range])
            let isCJK = token.unicodeScalars.contains { $0.properties.isIdeographic }
            guard token.count > (isCJK ? 0 : 2), token.rangeOfCharacter(from: .letters) != nil,
                  !ThemeDetector.grammaticalWords.contains(token), !groundingStopwords.contains(token)
            else { return true }
            tokens.insert(token)
            return true
        }
        return tokens
    }

    /// Two records are the same observation when their content words mostly
    /// overlap (at least three in five, word forms allowed: notice and
    /// noticing count as one) or read identically once normalized. Measured
    /// 2026-10-22: "You frequently notice the light at the end of the day"
    /// came back for a kept "You keep noticing the light at the end of the
    /// day", and exact words alone let it through.
    static func isSame(_ a: String, _ b: String) -> Bool {
        if normalized(a) == normalized(b) { return true }
        let ta = contentTokens(a), tb = contentTokens(b)
        guard !ta.isEmpty, !tb.isEmpty else { return false }
        let shared = ta.filter { word in tb.contains { related(word, $0) } }.count
        let union = ta.count + tb.count - shared
        return union > 0 && Double(shared) / Double(union) >= 0.6
    }

    /// The same word, or one a form of the other (a shared stem of four
    /// letters or more).
    static func related(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let shorter = a.count <= b.count ? a : b
        let longer = a.count <= b.count ? b : a
        return shorter.count >= 4 && longer.hasPrefix(shorter.prefix(max(4, shorter.count - 2)))
    }

    static func normalized(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Candidates that are new against the records already kept and against
    /// each other, trimmed and capped in length.
    static func fresh(_ candidates: [String], against existing: [String]) -> [String] {
        var kept: [String] = []
        for raw in candidates {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= maxTextLength else { continue }
            guard !existing.contains(where: { isSame($0, text) }),
                  !kept.contains(where: { isSame($0, text) }) else { continue }
            kept.append(text)
        }
        return kept
    }

    // MARK: Ground

    /// Words that say nothing about the subject of an observation.
    private static let groundingStopwords: Set<String> = [
        "you", "your", "yours", "yourself", "keep", "like", "often", "frequently", "mention",
        "mentions", "mentioned", "working", "about", "with", "and", "the", "are", "have",
        "你", "你的", "一直", "经常", "常常", "提到", "喜欢", "正在", "关于"
    ]

    /// Which of the evidence texts actually touch the observation: they
    /// share a content word with it (a name, a thing, a place). Measured
    /// 2026-10-22: the model cited a run for a curtain preference and an
    /// unrelated bug for an app project; this is the gate that catches it.
    static func groundedEvidence(for text: String, evidence: [String]) -> [Int] {
        let subject = contentTokens(text).subtracting(groundingStopwords)
        guard !subject.isEmpty else { return [] }
        return evidence.indices.filter { index in
            let tokens = contentTokens(evidence[index])
            return subject.contains { word in tokens.contains { related(word, $0) } }
        }
    }

    struct Standing: Equatable {
        let id: UUID
        let evidence: [UUID]
        let userEdited: Bool
        let createdAt: Date
    }

    /// Records to remove: those whose every evidence thought is gone (a
    /// record with no evidence listed keeps standing), never one the user
    /// edited; then the oldest beyond the cap.
    static func toPrune(_ records: [Standing], liveThoughtIDs: Set<UUID>) -> [UUID] {
        var gone: [UUID] = []
        for record in records where !record.userEdited {
            if !record.evidence.isEmpty, record.evidence.allSatisfy({ !liveThoughtIDs.contains($0) }) {
                gone.append(record.id)
            }
        }
        let standing = records.filter { !gone.contains($0.id) }
        if standing.count > maxRecords {
            let excess = standing
                .filter { !$0.userEdited }
                .sorted { $0.createdAt < $1.createdAt }
                .prefix(standing.count - maxRecords)
            gone.append(contentsOf: excess.map(\.id))
        }
        return gone
    }

    // MARK: What the person sent away

    static let dismissedKey = "memory.dismissed"

    static func isDismissed(_ text: String, defaults: UserDefaults = .standard) -> Bool {
        let dismissed = defaults.stringArray(forKey: dismissedKey) ?? []
        return dismissed.contains { isSame($0, text) }
    }

    static func dismiss(_ text: String, defaults: UserDefaults = .standard) {
        var dismissed = defaults.stringArray(forKey: dismissedKey) ?? []
        dismissed.append(text)
        if dismissed.count > 200 { dismissed.removeFirst(dismissed.count - 200) }
        defaults.set(dismissed, forKey: dismissedKey)
    }

    // MARK: What Ask reads

    /// The preamble for Ask: the newest records, one per line, within the
    /// budget; nil when there is nothing to say.
    static func preamble(_ records: [(kind: MemoryKind, text: String)]) -> String? {
        var lines: [String] = []
        var used = 0
        for record in records.prefix(preambleRecords) {
            let line = "- (\(record.kind.rawValue)) \(record.text)"
            guard used + line.count <= preambleCharacters else { break }
            lines.append(line)
            used += line.count
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
