import Foundation
import FoundationModels

// (entry, acceptable categories). Two categories where an honest reader
// could go either way.
let cases: [(entry: String, accept: Set<ThoughtCategory>)] = [
    // English
    ("An app where the whole screen is a single sentence.", [.idea]),
    ("Call the dentist before Friday.", [.task]),
    ("The Undo toast covers the tab bar on iPhone SE, so Library can't be tapped.", [.bug]),
    ("The bakery on 5th opens at 7; croissants are gone by 8.", [.note]),
    ("\"We shape our tools and thereafter our tools shape us.\" John Culkin", [.quote]),
    ("Why do I care so much what strangers think of my work?", [.question]),
    ("https://www.are.na/editorial a feed worth coming back to", [.link]),
    ("Grandma's handwriting on the recipe card; the kitchen smelled of star anise.", [.memory]),
    ("Night train to Lisbon with Mara, we talked until the windows went grey.", [.memory]),
    // Chinese
    ("做一个整屏只显示一句话的 App。", [.idea]),
    ("周五之前给牙医打电话。", [.task]),
    ("撤销提示挡住了标签栏，点不到“库”。", [.bug]),
    ("五街那家面包店七点开门，八点可颂就卖完了。", [.note]),
    ("“我们塑造工具，工具反过来塑造我们。”", [.quote]),
    ("为什么我这么在意陌生人怎么看我的作品？", [.question]),
    ("小时候外婆家的厨房总有八角的味道。", [.memory]),
    ("傍晚的光把整个房间染成了橘色。", [.note, .memory]),
    // Mixed
    ("Oryne 的 Ask 还不够聪明，连翻译都做不到。", [.bug, .note]),
    ("想把 Tide 的 resurfacing 改成按海流轮换。", [.idea, .task]),
]

@main
struct Eval {
    static func main() async {
        guard case .available = SystemLanguageModel.default.availability else {
            print("Apple Intelligence model unavailable on this Mac: \(SystemLanguageModel.default.availability)")
            exit(1)
        }
        let runs = Int(CommandLine.arguments.dropFirst().first ?? "") ?? 1

        var categoryHits = 0, categoryTotal = 0
        var gistHits = 0, gistTotal = 0
        var noAnswer = 0
        var latencies: [TimeInterval] = []

        for item in cases {
            let language = ThoughtReading.language(of: item.entry)
            for _ in 0..<runs {
                let started = Date()
                let reading = await FoundationThoughtReader.read(entry: item.entry)
                latencies.append(Date().timeIntervalSince(started))
                categoryTotal += 1
                gistTotal += 1
                guard let reading else {
                    noAnswer += 1
                    print("✗ no answer   [\(language.rawValue)] \(item.entry)")
                    continue
                }
                // As the app resolves it: form first, then the model.
                let category = ThoughtReading.formalCategory(for: item.entry) ?? reading.category
                let categoryOK = item.accept.contains(category)
                let gist = ThoughtReading.tidyGist(reading.gistInOtherLanguage, entryLanguage: language)
                let gistOK = gist != nil
                if categoryOK { categoryHits += 1 }
                if gistOK { gistHits += 1 }
                let keys = ThoughtReading.keys(fromEnglish: reading.themesInEnglish, fallbackLabels: reading.themes)
                let entities = ThoughtReading.tidyEntities(reading.entities)
                print("\(categoryOK ? "✓" : "✗") \(category.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) [\(language.rawValue)] \(item.entry)")
                print("    title: \(reading.title)")
                print("    themes: \(reading.themes.joined(separator: ", "))  keys: \(keys.joined(separator: ", "))")
                print("    gist\(gistOK ? "" : " (rejected: wrong language or empty)"): \(reading.gistInOtherLanguage)")
                if !entities.isEmpty { print("    entities: \(entities.joined(separator: ", "))") }
            }
        }

        let mean = latencies.reduce(0, +) / Double(max(latencies.count, 1))
        print("")
        print("Category: \(categoryHits)/\(categoryTotal)   Gist in the other language: \(gistHits)/\(gistTotal)   No answer: \(noAnswer)   Mean latency: \(String(format: "%.2f", mean))s")
    }
}
