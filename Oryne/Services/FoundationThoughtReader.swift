import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One guided-generation call that reads a thought into its understanding
/// record: title, themes in the entry's language and in English, one of
/// the eight categories, a gist in the other language, and the proper
/// names it mentions. Guided generation means the category can only be
/// one of the eight and the lists stay bounded; the deterministic cleaning
/// lives in `ThoughtReading`. Nil on any failure, including guardrail
/// refusals, and the caller falls back to the older free-text calls.
///
/// Compiled verbatim by `Scripts/understanding-eval`, so the eval measures
/// the shipping prompt and schema.
@available(iOS 26, macOS 26, *)
enum FoundationThoughtReader {

    /// The model's record, before cleaning.
    struct Result: Sendable {
        var title: String
        var themes: [String]
        var themesInEnglish: [String]
        var category: ThoughtCategory
        var gistInOtherLanguage: String
        var entities: [String]
    }

    #if canImport(FoundationModels)
    @Generable
    enum Category: String {
        case idea, task, bug, note, quote, question, link, memory
    }

    @Generable
    struct Reading {
        @Guide(description: "At most 6 words, in the entry's own language, the essence or feeling, no quotation marks")
        var title: String
        @Guide(description: "1 to 3 conceptual themes in the entry's own language, lowercase, one to three words each", .maximumCount(3))
        var themes: [String]
        @Guide(description: "The same themes in English, same order", .maximumCount(3))
        var themesInEnglish: [String]
        @Guide(description: "What kind of entry this is")
        var category: Category
        @Guide(description: "One sentence on what the entry is about, in the language the prompt names for it")
        var gistInOtherLanguage: String
        @Guide(description: "Names one could look up: people, places, products, companies, projects. Never pronouns or common nouns. Empty when there are none", .maximumCount(4))
        var entities: [String]
    }
    #endif

    static func read(entry: String) async -> Result? {
        #if canImport(FoundationModels)
        do {
            let session = LanguageModelSession { ThoughtReading.instructions }
            let response = try await session.respond(
                to: ThoughtReading.prompt(entry: entry),
                generating: Reading.self,
                options: GenerationOptions(samplingMode: .greedy)
            )
            let reading = response.content
            return Result(
                title: reading.title,
                themes: reading.themes,
                themesInEnglish: reading.themesInEnglish,
                category: ThoughtCategory(rawValue: reading.category.rawValue) ?? .note,
                gistInOtherLanguage: reading.gistInOtherLanguage,
                entities: reading.entities
            )
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
