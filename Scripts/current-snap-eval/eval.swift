import Foundation
import FoundationModels

// A fixed Ocean: the screenshot seed's currents (Oryne/App/SeedScreenshot.swift)
// plus a few more, so near-miss thoughts have plausible wrong homes, and two
// Chinese currents for the per-language path.
let ocean: [(key: String, titles: [String])] = [
    ("light and color", ["Sunset gradient study", "Golden hour on the walk home", "Warm to cool, not a filter", "Desk at 6pm"]),
    ("interface design", ["A button that doesn't need a label"]),
    ("user experience", ["Apple Design Principles"]),
    ("reading", ["Are.na Editorial"]),
    ("product ideas", ["Half a sentence from the train"]),
    ("cooking", ["Weeknight noodles"]),
    ("sound & music", ["Four notes in the cafe"]),
    ("interior", ["Linen curtains, not blinds"]),
    ("collecting", ["Saved articles I never reread"]),
    ("family", ["Grandma's handwriting on the recipe card"]),
    ("travel", ["Night train to Lisbon"]),
    ("光与色彩", ["傍晚的天空", "窗边的光斑"]),
    ("烹饪", ["番茄炒蛋的火候"]),
]

// (entry, acceptable currents). Empty = must not join any current.
let cases: [(entry: String, accept: Set<String>)] = [
    // Clearly related: should join.
    ("The room feels slower when the light turns warm.", ["light and color"]),
    ("Late sun turns the brick wall orange for ten minutes.", ["light and color"]),
    ("Glass of water on the sill threw a tiny rainbow.", ["light and color"]),
    ("The settings screen buries the one toggle people want.", ["interface design", "user experience"]),
    ("Tried braising the short ribs in miso, far too salty.", ["cooking"]),
    ("That bassline in the café stuck with me all afternoon.", ["sound & music"]),
    ("An app where the whole screen is a single sentence.", ["product ideas"]),
    ("傍晚的光把整个房间染成了橘色。", ["光与色彩"]),
    ("红烧肉还是要小火慢炖。", ["烹饪"]),
    // Near misses: a shared word or mood, a different subject.
    ("Need to lighten my schedule this week.", []),
    ("The interior of the argument is where it falls apart.", []),
    ("Reading the room at work was hard today.", []),
    ("Collecting unpaid invoices from two clients again.", []),
    ("Color-coding my calendar made Mondays worse.", []),
    // Unrelated to every current.
    ("I keep thinking about quitting to freelance.", []),
    ("Ran 5k this morning, knees complained.", []),
    ("Thinking about why I care what strangers think.", []),
    ("想换工作，但又怕不稳定。", []),
]

@main
struct Eval {
    static func main() async {
        guard case .available = SystemLanguageModel.default.availability else {
            print("Apple Intelligence model unavailable on this Mac: \(SystemLanguageModel.default.availability)")
            exit(1)
        }
        let runs = Int(CommandLine.arguments.dropFirst().first ?? "") ?? 3
        let base = Date()
        let members = ocean.flatMap { current in
            current.titles.enumerated().map { i, title in
                CurrentSnap.Member(key: current.key, title: title, createdAt: base.addingTimeInterval(Double(-i) * 86_400))
            }
        }

        var joined = 0, missed = 0, wrongCurrent = 0, falseMerges = 0, noAnswer = 0
        var seconds: [Double] = []
        for (entry, accept) in cases {
            let candidates = CurrentSnap.candidates(from: members, forEntry: entry)
            var picks: [String] = []
            for _ in 0..<runs {
                let start = Date()
                let pick = await FoundationCurrentPicker.pick(entry: entry, candidates: candidates)
                seconds.append(Date().timeIntervalSince(start))
                let resolved = CurrentSnap.resolve(themes: [], pick: pick, candidates: candidates).first
                picks.append(pick ?? "(no answer)")
                if pick == nil { noAnswer += 1 }
                switch (accept.isEmpty, resolved) {
                case (true, nil): break
                case (true, _): falseMerges += 1
                case (false, nil): missed += 1
                case (false, let key?): if accept.contains(key) { joined += 1 } else { wrongCurrent += 1 }
                }
            }
            let expected = accept.isEmpty ? "none" : accept.sorted().joined(separator: " | ")
            print("\(entry)\n    expect \(expected)  →  \(picks.joined(separator: ", "))")
        }

        let positives = cases.filter { !$0.accept.isEmpty }.count * runs
        let negatives = cases.filter { $0.accept.isEmpty }.count * runs
        let meanSeconds = seconds.reduce(0, +) / Double(max(1, seconds.count))
        print("""

        runs per case: \(runs)
        related thoughts joined their current: \(joined)/\(positives)  (missed \(missed), wrong current \(wrongCurrent))
        false merges on near-miss/unrelated:   \(falseMerges)/\(negatives)
        no answer (error or refusal → no snap): \(noAnswer)
        mean pick latency: \(String(format: "%.2f", meanSeconds))s
        """)
    }
}
