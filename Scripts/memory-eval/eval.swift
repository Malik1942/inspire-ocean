import Foundation
import FoundationModels

// The last 45 days of the fixture, as Consolidation lines them up, with one
// record already kept; then a summary for three of the fixture's currents.
let recent = EvalFixture.thoughts.filter { $0.daysAgo <= 45 }.sorted { $0.daysAgo < $1.daysAgo }
let lines: [FoundationMemoryExtractor.Line] = recent.enumerated().map { index, t in
    var parts = [t.createdAt.formatted(.relative(presentation: .named)), t.category.rawValue]
    if !t.entities.isEmpty { parts.append("mentions " + t.entities.joined(separator: ", ")) }
    return .init(reference: "t\(index + 1)", text: "\(parts.joined(separator: " · ")) · “\(t.title)”: \(String(t.entry.prefix(110)))", category: t.category.rawValue, entities: t.entities)
}
let byRef = Dictionary(uniqueKeysWithValues: recent.enumerated().map { ("t\($0.offset + 1)", $0.element) })
let existing = ["You keep noticing the light at the end of the day."]

/// Words that claim repetition; a record may use them only on three or
/// more grounded thoughts.
let frequencyWords = ["frequently", "often", "always", "every", "regularly", "usually", "keep ", "经常", "总是", "每天", "常常", "一直"]
func overstates(_ text: String, grounded: Int) -> Bool {
    let lowered = text.lowercased()
    return grounded < 3 && frequencyWords.contains { lowered.contains($0) }
}
func firstPerson(_ text: String) -> Bool {
    text.range(of: #"(^|[^A-Za-z])(I|I'm|I’m|my|me)([^A-Za-z]|$)"#, options: .regularExpression) != nil
        || text.hasPrefix("我") || text.contains("我的") || text.contains("我在")
}
func definesName(_ text: String, name: String) -> Bool {
    let lowered = text.lowercased()
    return [" is a ", " is the ", " refers to ", " means ", "是一种", "指的是", "是指", "意味着"].contains { lowered.contains($0) }
        && lowered.hasPrefix("“\(name.lowercased())”") || lowered.hasPrefix(name.lowercased())
}

@main
struct Eval {
    static func main() async {
        guard case .available = SystemLanguageModel.default.availability else {
            print("Apple Intelligence model unavailable on this Mac: \(SystemLanguageModel.default.availability)")
            exit(1)
        }
        let started = Date()
        var kept = 0, overstated = 0, invented = 0, proposed = 0
        if let proposals = await FoundationMemoryExtractor.extract(lines: lines, existing: existing) {
            proposed = proposals.count
            let fresh = MemoryRules.fresh(proposals.map(\.text), against: existing)
            for proposal in proposals {
                let isFresh = fresh.contains(proposal.text)
                let cited = proposal.evidence.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                let groundedIdx = MemoryRules.groundedEvidence(for: proposal.text, evidence: cited.map { byRef[$0].map { $0.title + " " + $0.entry + " " + $0.entities.joined(separator: " ") } ?? "" })
                let grounded = groundedIdx.map { cited[$0] }
                if grounded.count < cited.count { invented += 1 }
                let isKept = isFresh && grounded.count >= 2
                let worded = MemoryRules.softened(proposal.text, grounded: grounded.count)
                let over = isKept && overstates(worded, grounded: grounded.count)
                if isKept { kept += 1 }
                if over { overstated += 1 }
                print("\(isKept ? (over ? "△" : "✓") : "✗") \(proposal.kind.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(worded)\(worded != proposal.text ? "  (softened from: \(proposal.text))" : "")")
                print("    cited: \(cited.joined(separator: ", "))  grounded: \(grounded.joined(separator: ", "))\(isFresh ? "" : "  (repeats a kept record)")\(over ? "  (claims repetition on fewer than three thoughts)" : "")")
            }
        } else {
            print("no answer from the extractor")
        }

        // Current summaries.
        var summaryMissing = 0, summaryFirstPerson = 0, summaryDefines = 0, summaryEcho = 0
        for key in ["light-and-color", "product", "family"] {
            guard let current = EvalFixture.currents.first(where: { $0.key == key }) else { continue }
            let members = EvalFixture.thoughts.filter { $0.currentKey == key }.sorted { $0.daysAgo < $1.daysAgo }
            let chinese = members.filter { ThoughtReading.dominantScriptIsChinese($0.entry) }.count * 2 > members.count
            let memberLines = members.prefix(10).map { "- “\($0.title)”: \(String($0.entry.prefix(120)))" }
            let name = CurrentKey_humanized(current.label)
            let summary = await FoundationMemoryExtractor.summarizeCurrent(name: name, lines: memberLines, inChinese: chinese)
            guard let summary else { summaryMissing += 1; print("✗ summary missing for \(name)"); continue }
            let fp = firstPerson(summary), dn = definesName(summary, name: name)
            let echo = MemoryRules.summaryProblem(summary, memberTexts: memberLines)?.contains("repeats") ?? false
            if fp { summaryFirstPerson += 1 }
            if dn { summaryDefines += 1 }
            if echo { summaryEcho += 1 }
            print("\(fp || dn || echo ? "✗" : "✓") summary \(name): \(summary)\(fp ? "  (first person)" : "")\(dn ? "  (defines the name)" : "")\(echo ? "  (echoes a thought)" : "")")
        }
        let elapsed = Date().timeIntervalSince(started)
        print("")
        print("Proposed: \(proposed)   Kept: \(kept)   Overstated: \(overstated)   Invented evidence: \(invented)   Summaries first person: \(summaryFirstPerson)  define name: \(summaryDefines)  missing: \(summaryMissing)   Elapsed: \(String(format: "%.1f", elapsed))s")
        EvalFixture.result("memory", [("proposed", proposed), ("kept", kept), ("overstated", overstated), ("invented_evidence", invented), ("ungrounded_kept", 0),
                                      ("summary_first_person", summaryFirstPerson), ("summary_defines_name", summaryDefines), ("summary_echo", summaryEcho), ("summary_missing", summaryMissing)], latency: elapsed)
    }
}

/// "light and color" → "Light and Color", as the app's CurrentKey does.
func CurrentKey_humanized(_ key: String) -> String {
    let small: Set<String> = ["and", "of", "the", "in", "on", "at", "to", "a", "an"]
    let words = key.split(whereSeparator: { $0 == "-" || $0 == " " }).map(String.init)
    return words.enumerated().map { i, w in
        if w == "&" { return "&" }
        if i > 0, small.contains(w.lowercased()) { return w.lowercased() }
        return w.prefix(1).uppercased() + w.dropFirst()
    }.joined(separator: " ")
}
