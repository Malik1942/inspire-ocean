import Foundation
import FoundationModels

// A fixed bilingual Ocean with understanding records, as phase 1 writes them.
func thought(_ key: String, _ title: String, _ body: String, gist: String?, _ category: ThoughtCategory, daysAgo: Int, themes: [String], entities: [String] = []) -> (key: String, thought: AskAgent.Thought) {
    (key, AskAgent.Thought(
        id: UUID(), title: title, body: body, gist: gist, summary: nil,
        createdAt: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
        category: category, kind: .text, themes: themes,
        themeKeys: themes.map(ThoughtReading.slug), entities: entities
    ))
}

let ocean: [(key: String, thought: AskAgent.Thought)] = [
    thought("water", "One line a day", "An app where the whole screen is a single sentence, like a tide that brings one line a day.", gist: "一个整屏只显示一句话的应用，像潮水一样每天带来一行。", .idea, daysAgo: 12, themes: ["product ideas", "digital minimalism"]),
    thought("bug-undo", "Undo toast hides the tab bar", "The Undo toast covers the tab bar on iPhone SE, so Library cannot be tapped.", gist: "iPhone SE 上撤销提示挡住了标签栏，点不到库。", .bug, daysAgo: 3, themes: ["product", "interface"], entities: ["iPhone SE"]),
    thought("bug-ask", "Ask 不会翻译", "Oryne 的 Ask 还不够聪明，连翻译都做不到。", gist: "Oryne's Ask is not smart enough to translate.", .bug, daysAgo: 1, themes: ["智能", "翻译"], entities: ["Oryne"]),
    thought("task-dentist", "Dentist before Friday", "Call the dentist before Friday and ask Mara about the Lisbon tickets.", gist: "周五前给牙医打电话，顺便问玛拉里斯本的票。", .task, daysAgo: 2, themes: ["health", "planning"], entities: ["Mara", "Lisbon"]),
    thought("task-invoice", "寄发票", "周五之前把 Oryne 的发票寄给会计。", gist: "Send the Oryne invoice to the accountant before Friday.", .task, daysAgo: 4, themes: ["财务", "事务"], entities: ["Oryne"]),
    thought("note-bakery", "Bakery on 5th", "The bakery on 5th opens at 7; croissants are gone by 8.", gist: "第五街的面包店七点开门，八点可颂就卖完了。", .note, daysAgo: 20, themes: ["food", "neighborhood"]),
    thought("quote-tools", "Tools shape us", "\"We shape our tools and thereafter our tools shape us.\" John Culkin", gist: "我们塑造工具，工具反过来塑造我们。", .quote, daysAgo: 40, themes: ["technology", "philosophy"], entities: ["John Culkin"]),
    thought("question-strangers", "Why strangers' opinions", "Why do I care so much what strangers think of my work?", gist: "为什么我这么在意陌生人怎么看我的作品？", .question, daysAgo: 8, themes: ["self-worth", "social comparison"]),
    thought("memory-train", "Night train to Lisbon", "Night train to Lisbon with Mara, we talked until the windows went grey.", gist: "和玛拉坐夜车去里斯本，聊到窗户泛灰。", .memory, daysAgo: 60, themes: ["travel", "friendship"], entities: ["Mara", "Lisbon"]),
    thought("memory-kitchen", "外婆的厨房", "小时候外婆家的厨房总有八角的味道。", gist: "My grandmother's kitchen always smelled of star anise when I was small.", .memory, daysAgo: 90, themes: ["家", "回忆"]),
    thought("idea-tide", "Tide 按海流轮换", "想把 Tide 的 resurfacing 改成按海流轮换。", gist: "Change Tide's resurfacing to rotate through the currents.", .idea, daysAgo: 5, themes: ["产品", "浮现"], entities: ["Tide"]),
    thought("note-light", "傍晚的光", "傍晚的光把整个房间染成了橘色。", gist: "The evening light turned the whole room orange.", .note, daysAgo: 15, themes: ["光与色彩"]),
]
let byKey = Dictionary(uniqueKeysWithValues: ocean.map { ($0.key, $0.thought.id) })
let keyByID = Dictionary(uniqueKeysWithValues: ocean.map { ($0.thought.id, $0.key) })

// (question, keys an honest answer must cite, keys it must not cite)
let cases: [(question: String, must: Set<String>, mustNot: Set<String>)] = [
    ("What bugs have I noted?", ["bug-undo", "bug-ask"], ["task-dentist", "water"]),
    ("我记过哪些 bug？", ["bug-undo", "bug-ask"], ["task-dentist"]),
    ("那个关于水的想法", ["water"], ["bug-undo"]),
    ("What tasks are still open?", ["task-dentist", "task-invoice"], ["bug-undo"]),
    ("What did I say about Mara?", ["task-dentist", "memory-train"], ["bug-ask"]),
    ("Translate my thought about the bakery into Chinese.", ["note-bakery"], []),
    ("把我关于工具的那句引用翻译成中文", ["quote-tools"], []),
    ("总结一下我最近的想法类灵感", ["idea-tide", "water"], ["task-invoice"]),
    ("Did I write anything about quantum physics?", [], ["water", "bug-undo"]),
]

@main
struct Eval {
    static func main() async {
        guard case .available = SystemLanguageModel.default.availability else {
            print("Apple Intelligence model unavailable on this Mac: \(SystemLanguageModel.default.availability)")
            exit(1)
        }
        let thoughts = ocean.map(\.thought)
        var citedOK = 0, languageOK = 0, answered = 0
        var latencies: [TimeInterval] = []

        for item in cases {
            let started = Date()
            let answer = await AskAgent.answer(query: item.question, history: [], thoughts: thoughts)
            latencies.append(Date().timeIntervalSince(started))
            guard let answer else {
                print("✗ no answer   \(item.question)")
                continue
            }
            answered += 1
            let cited = Set(answer.cited.compactMap { keyByID[$0] })
            let surfaced = Set(answer.surfaced.compactMap { keyByID[$0] })
            let stood = cited.isEmpty ? surfaced : cited
            let mustOK = item.must.isSubset(of: stood) && item.mustNot.isDisjoint(with: cited)
            let answerChinese = ThoughtReading.mostlyChineseByWords(answer.text)
            let expectChinese: Bool
            if let request = AskAgent.translationRequest(in: item.question), let target = request.target {
                expectChinese = target == .zh
            } else {
                expectChinese = ThoughtReading.mostlyChineseByWords(item.question)
            }
            let langOK = expectChinese == answerChinese
            if mustOK { citedOK += 1 }
            if langOK { languageOK += 1 }
            print("\(mustOK ? "✓" : "✗") sources \(langOK ? "✓" : "✗") language   \(item.question)")
            print("    tools: \(answer.toolCalls)  cited: \(answer.cited.compactMap { keyByID[$0] })  read: \(answer.read.compactMap { keyByID[$0] })  surfaced: \(answer.surfaced.count)")
            print("    answer: \(answer.text.replacingOccurrences(of: "\n", with: " / "))")
        }
        let mean = latencies.reduce(0, +) / Double(max(latencies.count, 1))
        print("")
        print("Answered: \(answered)/\(cases.count)   Sources right: \(citedOK)/\(cases.count)   Language right: \(languageOK)/\(cases.count)   Mean latency: \(String(format: "%.1f", mean))s")
    }
}
