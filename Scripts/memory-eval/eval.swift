import Foundation
import FoundationModels

// Three weeks of one person's thoughts: two threads that should become
// records (light and color as a creative concern; Mara and the Lisbon trip),
// a product under way (Oryne), a preference, and noise that should not.
let thoughts: [String] = [
    "2 days ago · idea · “One line a day”: An app where the whole screen is a single sentence, like a tide that brings one line a day.",
    "3 days ago · bug · “Undo toast hides the tab bar”: The Undo toast covers the tab bar on iPhone SE, so Library cannot be tapped.",
    "3 days ago · note · “Warm to cool, not a filter”: Stop adding an orange overlay. The sunset is already a temperature shift.",
    "4 days ago · memory · mentions Mara, Lisbon · “Night train to Lisbon”: Night train to Lisbon with Mara, we talked until the windows went grey.",
    "5 days ago · task · mentions Mara, Lisbon · “Dentist before Friday”: Call the dentist before Friday and ask Mara about the Lisbon tickets.",
    "6 days ago · note · “Golden hour on the walk home”: Streetlights coming on while the sky is still blue.",
    "1 week ago · idea · mentions Oryne · “Ask 不会翻译”: Oryne 的 Ask 还不够聪明，连翻译都做不到。",
    "1 week ago · idea · mentions Tide · “Tide 按海流轮换”: 想把 Tide 的 resurfacing 改成按海流轮换。",
    "1 week ago · note · “Desk at 6pm”: The desk turns amber for ten minutes and then it is gone.",
    "2 weeks ago · note · “Weeknight noodles”: Soy, black vinegar, a little sugar, chili crisp. Ten minutes.",
    "2 weeks ago · quote · mentions John Culkin · “Tools shape us”: We shape our tools and thereafter our tools shape us.",
    "2 weeks ago · task · mentions Oryne · “寄发票”: 周五之前把 Oryne 的发票寄给会计。",
    "2 weeks ago · note · “Linen curtains, not blinds”: The light through linen is the whole point of the room.",
    "3 weeks ago · memory · mentions Mara · “Mara's postcard”: Mara's postcard from Porto, the one with the tiles.",
    "3 weeks ago · question · “Why strangers' opinions”: Why do I care so much what strangers think of my work?",
    "3 weeks ago · note · “Ran 5k”: Ran 5k this morning, knees complained.",
]

@main
struct Eval {
    static func main() async {
        guard case .available = SystemLanguageModel.default.availability else {
            print("Apple Intelligence model unavailable on this Mac: \(SystemLanguageModel.default.availability)")
            exit(1)
        }
        let lines = thoughts.enumerated().map { FoundationMemoryExtractor.Line(reference: "t\($0.offset + 1)", text: $0.element) }
        let started = Date()
        guard let proposals = await FoundationMemoryExtractor.extract(lines: lines, existing: ["You keep noticing the light at the end of the day."]) else {
            print("no answer"); exit(1)
        }
        let elapsed = Date().timeIntervalSince(started)
        let fresh = MemoryRules.fresh(proposals.map(\.text), against: ["You keep noticing the light at the end of the day."])
        let byRef = Dictionary(uniqueKeysWithValues: lines.map { ($0.reference, $0.text) })
        var keptCount = 0
        for proposal in proposals {
            let isFresh = fresh.contains(proposal.text)
            let cited = proposal.evidence.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            let grounded = MemoryRules.groundedEvidence(for: proposal.text, evidence: cited.map { byRef[$0] ?? "" }).map { cited[$0] }
            let kept = isFresh && grounded.count >= 2
            if kept { keptCount += 1 }
            print("\(kept ? "✓" : "✗") \(proposal.kind.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(proposal.text)")
            print("    cited: \(cited.joined(separator: ", "))  grounded: \(grounded.joined(separator: ", "))\(isFresh ? "" : "  (repeats a kept record)")")
        }
        print("")
        print("Proposed: \(proposals.count)   Kept (fresh, two grounded thoughts): \(keptCount)   Latency: \(String(format: "%.1f", elapsed))s")
    }
}
