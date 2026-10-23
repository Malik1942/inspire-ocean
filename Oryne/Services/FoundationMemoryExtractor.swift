import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One guided-generation call that reads the person's recent thoughts and
/// proposes durable observations about them (docs/plans/memory-layer/
/// SPEC.md, layer 3). Guided generation bounds the kind to five and the
/// count to a few; `MemoryRules` decides what is new. Nil on any failure.
///
/// Compiled verbatim by `Scripts/memory-eval`, so the eval measures the
/// shipping prompt and schema.
@available(iOS 26, macOS 26, *)
enum FoundationMemoryExtractor {

    /// One thought as the extractor reads it, with what the record already
    /// knows about it so the hints can be counted.
    struct Line: Sendable {
        var reference: String
        var text: String
        var category: String? = nil
        var entities: [String] = []
    }

    struct Proposal: Sendable {
        var kind: MemoryKind
        var text: String
        var evidence: [String]
    }

    #if canImport(FoundationModels)
    @Generable
    enum Kind: String {
        case concern, project, person, preference, habit
    }

    @Generable
    struct Item {
        @Guide(description: "concern: something they keep coming back to or worry about; project: something they are making or working toward; person: someone who keeps appearing, by name; preference: a taste or a way they like things; habit: something they do regularly")
        var kind: Kind
        @Guide(description: "One plain sentence addressed to them as you, in the language most of the thoughts are in, naming what the thoughts show. Nothing the thoughts do not say.")
        var text: String
        @Guide(description: "References of the thoughts this rests on, such as t3; at least two", .maximumCount(5))
        var evidence: [String]
    }

    @Generable
    struct Extraction {
        @Guide(description: "At most four observations that several thoughts support; none when the thoughts show no pattern", .maximumCount(4))
        var records: [Item]
    }
    #endif

    static let instructions = """
    You read recent entries from one person's inspiration journal and write down what they \
    show about the person that will still be true in a month: a concern they keep returning \
    to, a project under way, a person who keeps appearing, a preference, a habit. An \
    observation is only what two or more different entries about the same subject show; \
    list exactly those entries as its evidence, and never an entry about something else. \
    One subject per observation: never combine a person with a product or two projects. \
    Say "often", "every", "always" or "frequently" only when the entries themselves show \
    repetition; a single entry shows none. State each in one plain sentence addressed to \
    the person as "you", in the language most of the entries are in. Do not repeat \
    observations already kept, do not infer feelings the entries do not state. When the \
    entries show no pattern, return none.
    """

    /// Counted, not inferred: the names that appear in more than one entry
    /// and how many entries each kind has. A small model finds a pattern it
    /// is pointed at and misses one it has to count for itself (measured
    /// 2026-10-22: it proposed two single-entry observations and missed a
    /// person named in three entries).
    static func hints(for lines: [Line]) -> [String] {
        var byName: [String: Int] = [:]
        for line in lines { for name in Set(line.entities) { byName[name, default: 0] += 1 } }
        let repeated = byName.filter { $0.value >= 2 }.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        var out: [String] = []
        if !repeated.isEmpty {
            out.append("Names in more than one entry: " + repeated.map { "\($0.key) (\($0.value))" }.joined(separator: ", "))
        }
        var byKind: [String: Int] = [:]
        for line in lines { if let kind = line.category { byKind[kind, default: 0] += 1 } }
        if !byKind.isEmpty {
            out.append("Entries by kind: " + byKind.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        }
        return out
    }

    static func prompt(lines: [Line], existing: [String]) -> String {
        var prompt = ""
        if !existing.isEmpty {
            prompt += "Already kept (do not repeat):\n" + existing.map { "- " + $0 }.joined(separator: "\n") + "\n\n"
        }
        let hints = hints(for: lines)
        if !hints.isEmpty {
            prompt += hints.joined(separator: "\n") + "\n\n"
        }
        prompt += "Recent entries:\n" + lines.map { "[\($0.reference)] \($0.text)" }.joined(separator: "\n")
        return prompt
    }

    static func extract(lines: [Line], existing: [String]) async -> [Proposal]? {
        #if canImport(FoundationModels)
        guard !lines.isEmpty else { return [] }
        do {
            let session = LanguageModelSession { instructions }
            let response = try await session.respond(
                to: prompt(lines: lines, existing: existing),
                generating: Extraction.self,
                options: GenerationOptions(samplingMode: .greedy)
            )
            return response.content.records.map {
                Proposal(kind: MemoryKind(rawValue: $0.kind.rawValue) ?? .concern, text: $0.text, evidence: $0.evidence)
            }
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// One sentence on what runs through a current's thoughts, for its row.
    /// Checked by `MemoryRules.summaryProblem` and asked for once more with
    /// the problem named; a second miss is no summary (measured
    /// 2026-10-22: a preamble ending in a colon, a thought quoted verbatim).
    static func summarizeCurrent(name: String, lines: [String], inChinese: Bool) async -> String? {
        #if canImport(FoundationModels)
        guard lines.count >= 2 else { return nil }
        do {
            let session = LanguageModelSession {
                """
                You describe what runs through a small set of a person's thoughts in one calm \
                sentence, in \(inChinese ? "Chinese" : "English"), addressed to them as "you" \
                (never "I"). In your own words, never quoting a thought. Only what these \
                thoughts say: do not define or explain the current's name, give no advice, \
                no exclamation marks, no list, no introduction.
                """
            }
            let prompt = "The current is called “\(name)”. Its thoughts:\n" + lines.joined(separator: "\n")
            var text = try await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines)
            if let problem = MemoryRules.summaryProblem(text, memberTexts: lines) {
                text = try await session.respond(to: "That \(problem). Write the one sentence itself, in your own words, addressed to them as you.")
                    .content.trimmingCharacters(in: .whitespacesAndNewlines)
                if MemoryRules.summaryProblem(text, memberTexts: lines) != nil { return nil }
            }
            return text.isEmpty ? nil : AnswerLength.capped(text, sentences: 1)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
