import Foundation
import SwiftData

/// Seeds a small, evocative Ocean on first launch so the field feels alive and
/// rediscovery/dialogue can be demonstrated immediately.
enum SeedData {

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let descriptor = FetchDescriptor<Node>()
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        guard existing == 0 else { return }

        let now = Date()
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

        let drifts: [(String, NodeKind, Double)] = [
            ("The ocean remembers every river that ever fed it. What if memory worked the same way — nothing lost, only carried.", .text, 0.5),
            ("Bioluminescence: light made by living things in the dark. A metaphor for ideas that only glow when you stop looking for them.", .text, 1.2),
            ("Voice note — I keep coming back to the feeling of tide. Things leaving and returning without me forcing them.", .voice, 2.0),
            ("Screenshot of that interface where the cards breathe slightly. Calm motion. Felt alive without being busy.", .image, 3.1),
            ("Why do my best ideas arrive in the shower, never at the desk? Something about not gripping them too hard.", .text, 4.4),
            ("A reading list keeps growing but I never finish. Maybe the point isn't finishing — it's drifting through.", .text, 6.0),
            ("Half a song lyric: 'we are the weather, not the forecast'. Don't know where it goes yet.", .text, 8.5),
            ("Color study — deep teal fading to violet at the horizon. Want a whole app to feel like dusk underwater.", .image, 11.0),
            ("What would a tool feel like if it never asked me to organize anything?", .text, 14.0),
            ("Note to self: capture before consciousness. The thought before you judge the thought.", .text, 18.0)
        ]

        for (textBody, kind, daysAgo) in drifts {
            let node: Node
            switch kind {
            case .voice:
                node = NodeComposer.make(kind: .voice, transcription: textBody)
            case .image:
                node = NodeComposer.make(kind: .image, text: textBody)
            default:
                node = NodeComposer.make(kind: .text, text: textBody)
            }
            node.createdAt = ago(daysAgo)
            node.updatedAt = ago(daysAgo)
            context.insert(node)
        }

        try? context.save()
    }
}
