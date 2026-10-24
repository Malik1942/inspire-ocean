import Foundation
import FoundationModels

// Reads every fixture thought (and the long entries) and checks the record
// against the fixture's category (and the ones an honest reader could also
// choose), the gist's language, the title's language (what
// TitleDistiller.speaksLike guards), and the themes' language as the model
// wrote them, so the number measures the prompt, not the guard; the line
// also shows what ThoughtReading.themesInEntryScript makes of a miss.
@main
struct Eval {
    static func main() async {
        guard case .available = SystemLanguageModel.default.availability else {
            print("Apple Intelligence model unavailable on this Mac: \(SystemLanguageModel.default.availability)")
            exit(1)
        }
        let runs = Int(CommandLine.arguments.dropFirst().first ?? "") ?? 1
        var categoryHits = 0, gistHits = 0, titleHits = 0, themeHits = 0, total = 0, noAnswer = 0
        var latencies: [TimeInterval] = []

        for item in EvalFixture.thoughts + EvalFixture.longEntries {
            let entry = item.entry
            let language = ThoughtReading.language(of: entry)
            for _ in 0..<runs {
                let started = Date()
                let reading = await FoundationThoughtReader.read(entry: entry)
                latencies.append(Date().timeIntervalSince(started))
                total += 1
                guard let reading else {
                    noAnswer += 1
                    print("✗ no answer   [\(language.rawValue)] \(entry)")
                    continue
                }
                let category = ThoughtReading.formalCategory(for: entry) ?? reading.category
                let categoryOK = item.accepts.contains(category)
                let gist = ThoughtReading.tidyGist(reading.gistInOtherLanguage, entryLanguage: language)
                let titleOK = ThoughtReading.mostlyChineseByWords(reading.title) == ThoughtReading.mostlyChineseByWords(entry)
                let entryChinese = ThoughtReading.mostlyChineseByWords(entry)
                let themesOK = !reading.themes.isEmpty && reading.themes.allSatisfy { ThoughtReading.mostlyChineseByWords($0) == entryChinese }
                let inScript = ThoughtReading.themesInEntryScript(reading.themes, english: reading.themesInEnglish, entry: entry)
                if categoryOK { categoryHits += 1 }
                if gist != nil { gistHits += 1 }
                if titleOK { titleHits += 1 }
                if themesOK { themeHits += 1 }
                let keys = ThoughtReading.keys(fromEnglish: reading.themesInEnglish, fallbackLabels: reading.themes)
                let shown = entry.count > 160 ? String(entry.prefix(160)) + "…" : entry
                print("\(categoryOK ? "✓" : "✗") \(category.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) [\(language.rawValue)] \(shown)")
                print("    title\(titleOK ? "" : " (wrong language)"): \(reading.title)   themes\(themesOK ? "" : " (wrong language; kept: \(inScript.joined(separator: ", ")))"): \(reading.themes.joined(separator: ", "))  keys: \(keys.joined(separator: ", "))")
                print("    gist\(gist == nil ? " (rejected: wrong language or empty)" : ""): \(reading.gistInOtherLanguage)")
            }
        }
        let mean = latencies.reduce(0, +) / Double(max(latencies.count, 1))
        print("")
        print("Category: \(categoryHits)/\(total)   Gist in the other language: \(gistHits)/\(total)   Title in its language: \(titleHits)/\(total)   Themes in its language: \(themeHits)/\(total)   No answer: \(noAnswer)   Mean latency: \(String(format: "%.2f", mean))s")
        EvalFixture.result("understanding", [("category", categoryHits), ("gist", gistHits), ("title_language", titleHits), ("theme_language", themeHits), ("no_answer", noAnswer), ("total", total)], latency: mean)
    }
}
