import Foundation
import FoundationModels

// The fixture as the agent sees it, and questions with the thoughts an
// honest answer must stand on, and must not.
let thoughts: [AskAgent.Thought] = EvalFixture.thoughts.map { t in
    AskAgent.Thought(
        id: UUID(), title: t.title, body: t.entry, gist: t.gist, summary: nil,
        createdAt: t.createdAt, category: t.category, kind: .text,
        themes: t.themes, themeKeys: t.themeKeys, entities: t.entities, hasPictures: t.hasPictures
    )
}
let keyByID = Dictionary(uniqueKeysWithValues: zip(thoughts.map(\.id), EvalFixture.thoughts.map(\.key)))

let cases: [(question: String, must: Set<String>, mustNot: Set<String>)] = [
    ("What bugs have I noted?", ["oryne-bug-undo", "oryne-bug-ask"], ["task-dentist", "water"]),
    ("我记过哪些 bug？", ["oryne-bug-undo", "oryne-bug-ask"], ["task-dentist"]),
    ("那个关于水的想法", ["water"], ["oryne-bug-undo"]),
    ("What tasks are still open?", ["task-dentist", "oryne-task-invoice"], ["oryne-bug-undo"]),
    ("What did I say about Mara?", ["task-dentist", "memory-train"], ["oryne-bug-ask"]),
    ("Translate my thought about the bakery into Chinese.", ["note-bakery"], []),
    ("把我关于工具的那句引用翻译成中文", ["quote-tools"], []),
    ("总结一下我最近的想法类灵感", ["oryne-idea-tide", "water"], ["oryne-task-invoice"]),
    ("Did I write anything about quantum physics?", [], ["water", "oryne-bug-undo"]),
    ("What pictures have I saved?", ["light-desk", "light-dunes", "pic-receipt", "pic-beach"], ["task-dentist", "quote-tools"]),
    ("Where did I buy coffee?", ["pic-receipt"], ["task-dentist", "note-bakery"]),
    ("我拍过海边的照片吗？", ["pic-beach"], ["oryne-bug-undo"]),
]

@main
struct Eval {
    static func main() async {
        guard case .available = SystemLanguageModel.default.availability else {
            print("Apple Intelligence model unavailable on this Mac: \(SystemLanguageModel.default.availability)")
            exit(1)
        }
        var answered = 0, sourcesOK = 0, languageOK = 0, translateEcho = 0, forcedRetries = 0
        var latencies: [TimeInterval] = []

        for item in cases {
            let started = Date()
            let answer = await AskAgent.answer(query: item.question, history: [], thoughts: thoughts)
            latencies.append(Date().timeIntervalSince(started))
            guard let answer else {
                print("✗ no answer   \(item.question)   [\(AskAgent.lastFailure ?? "no reason recorded")]")
                continue
            }
            answered += 1
            if answer.forcedRetry { forcedRetries += 1 }
            let cited = Set(answer.cited.compactMap { keyByID[$0] })
            let surfaced = Set(answer.surfaced.compactMap { keyByID[$0] })
            let stood = cited.isEmpty ? surfaced : cited
            let mustOK = item.must.isSubset(of: stood) && item.mustNot.isDisjoint(with: cited)
            let request = AskAgent.translationRequest(in: item.question)
            let answerChinese = ThoughtReading.mostlyChineseByWords(answer.text)
            let expectChinese = request?.target.map { $0 == .zh } ?? ThoughtReading.mostlyChineseByWords(item.question)
            let langOK = expectChinese == answerChinese
            // A translation that returns the original words is an echo.
            var echo = false
            if request != nil, let key = item.must.first, let source = EvalFixture.thoughts.first(where: { $0.key == key }) {
                echo = MemoryRules_normalized(answer.text).contains(MemoryRules_normalized(source.body).prefix(30))
            }
            if mustOK { sourcesOK += 1 }
            if langOK { languageOK += 1 }
            if echo { translateEcho += 1 }
            print("\(mustOK ? "✓" : "✗") sources \(langOK ? "✓" : "✗") language\(echo ? " ✗ echo" : "")\(answer.forcedRetry ? "  (forced retry)" : "")   \(item.question)")
            print("    tools: \(answer.calls.joined(separator: " ; "))  cited: \(answer.cited.compactMap { keyByID[$0] })  read: \(answer.read.compactMap { keyByID[$0] })  surfaced: \(answer.surfaced.count)")
            print("    answer: \(answer.text.replacingOccurrences(of: "\n", with: " / "))")
        }
        let mean = latencies.reduce(0, +) / Double(max(latencies.count, 1))
        print("")
        print("Answered: \(answered)/\(cases.count)   Sources right: \(sourcesOK)/\(cases.count)   Language right: \(languageOK)/\(cases.count)   Translation echoes: \(translateEcho)   Forced retries: \(forcedRetries)   Mean latency: \(String(format: "%.1f", mean))s")
        EvalFixture.result("ask", [("answered", answered), ("sources", sourcesOK), ("language", languageOK), ("translate_echo", translateEcho), ("no_tool", forcedRetries), ("total", cases.count)], latency: mean)
    }
}

/// Letters and digits only, lowercased, for the echo check.
func MemoryRules_normalized(_ text: String) -> String {
    String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
}
