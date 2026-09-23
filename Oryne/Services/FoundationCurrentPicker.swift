import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Asks Apple's on-device model which existing current a new thought is
/// about. Guided generation constrains the answer to an exact candidate key
/// or `CurrentSnap.noneChoice`, so the exact-string grouping of currents can
/// never be missed by a near-synonym. Nil on any failure, including the
/// model's guardrail refusals, which means no snap: today's behavior.
///
/// Compiled verbatim by `Scripts/current-snap-eval`, so the eval measures
/// the shipping prompt and schema.
@available(iOS 26, macOS 26, *)
enum FoundationCurrentPicker {

    static func pick(entry: String, candidates: [CurrentCandidate]) async -> String? {
        #if canImport(FoundationModels)
        guard !candidates.isEmpty else { return nil }
        let choice = DynamicGenerationSchema(
            name: "Topic",
            anyOf: candidates.map(\.key) + [CurrentSnap.noneChoice]
        )
        let root = DynamicGenerationSchema(
            name: "Sorting",
            properties: [.init(name: "topic", schema: choice)]
        )
        do {
            let schema = try GenerationSchema(root: root, dependencies: [choice])
            let session = LanguageModelSession { CurrentSnap.instructions }
            let response = try await session.respond(
                to: CurrentSnap.prompt(entry: entry, candidates: candidates),
                schema: schema,
                options: GenerationOptions(samplingMode: .greedy)
            )
            return try response.content.value(String.self, forProperty: "topic")
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
