import Foundation
import FoundationModels

// The fixture's currents, every one offered whatever the entry's language,
// and entries that should join one, or none.
// `may`: a join the fixture does not require but would not call wrong,
// such as unpaid client invoices beside "send the invoice to the accountant".
let cases: [(entry: String, accept: Set<String>, may: Set<String>)] = [
    // Clearly related: should join.
    ("The room feels slower when the light turns warm.", ["light-and-color"], []),
    ("Late sun turns the brick wall orange for ten minutes.", ["light-and-color"], []),
    ("Glass of water on the sill threw a tiny rainbow.", ["light-and-color"], []),
    ("The settings screen buries the one toggle people want.", ["interface-design", "product"], []),
    ("Tried braising the short ribs in miso, far too salty.", ["cooking"], []),
    ("That bassline in the café stuck with me all afternoon.", ["sound-and-music"], []),
    ("An app where the whole screen is a single sentence.", ["product-ideas", "product"], []),
    // A one-thought current is offered only on a shared word (here "linen").
    ("Thinking about linen for the reading corner.", ["interior"], []),
    ("傍晚的光把整个房间染成了橘色。", ["light-and-color"], []),
    ("红烧肉还是要小火慢炖。", ["cooking"], []),
    ("外婆写在食谱卡上的字。", ["family"], []),
    // Near misses: a shared word or mood, a different subject.
    ("Need to lighten my schedule this week.", [], []),
    ("The interior of the argument is where it falls apart.", [], []),
    ("Reading the room at work was hard today.", [], []),
    // The errands current holds "send the Oryne invoice to the accountant":
    // joining it is defensible, staying out is too.
    ("Collecting unpaid invoices from two clients again.", [], ["errands"]),
    ("Color-coding my calendar made Mondays worse.", [], []),
    // Unrelated to every current.
    ("I keep thinking about quitting to freelance.", [], []),
    ("Ran 5k this morning, knees complained.", [], []),
    ("Thinking about why I care what strangers think.", ["self-worth"], []),
    ("想换工作，但又怕不稳定。", [], []),
]

@main
struct Eval {
    static func main() async {
        guard case .available = SystemLanguageModel.default.availability else {
            print("Apple Intelligence model unavailable on this Mac: \(SystemLanguageModel.default.availability)")
            exit(1)
        }
        let runs = Int(CommandLine.arguments.dropFirst().first ?? "") ?? 1
        let base = Date()
        let members = EvalFixture.currents.flatMap { current in
            current.titles.enumerated().map { i, title in
                CurrentSnap.Member(key: current.key, title: title, createdAt: base.addingTimeInterval(Double(-i) * 86_400), label: current.label)
            }
        }
        var related = 0, joined = 0, missed = 0, wrong = 0, falseMerges = 0, unrelated = 0, noAnswer = 0
        var seconds: [TimeInterval] = []

        for item in cases {
            let candidates = CurrentSnap.candidates(from: members, forEntry: item.entry)
            var picks: [String] = []
            for _ in 0..<runs {
                let start = Date()
                let pick = await FoundationCurrentPicker.pick(entry: item.entry, candidates: candidates)
                seconds.append(Date().timeIntervalSince(start))
                let key = CurrentSnap.joinKey(pick: pick, candidates: candidates, entry: item.entry)
                picks.append(key ?? (pick == nil ? "(no answer)" : "none"))
                if pick == nil { noAnswer += 1 }
                if item.accept.isEmpty {
                    unrelated += 1
                    if let key, !item.may.contains(key) { falseMerges += 1 }
                } else {
                    related += 1
                    if let key, item.accept.contains(key) { joined += 1 }
                    else if key != nil { wrong += 1 }
                    else { missed += 1 }
                }
            }
            print(item.entry)
            print("    expect \(item.accept.isEmpty ? (item.may.isEmpty ? "none" : "none or " + item.may.sorted().joined(separator: " | ")) : item.accept.sorted().joined(separator: " | "))  →  \(picks.joined(separator: ", "))")
        }
        let mean = seconds.reduce(0, +) / Double(max(seconds.count, 1))
        print("")
        print("runs per case: \(runs)")
        print("related thoughts joined their current: \(joined)/\(related)  (missed \(missed), wrong current \(wrong))")
        print("false merges on near-miss/unrelated:   \(falseMerges)/\(unrelated)")
        print("no answer (error or refusal → no snap): \(noAnswer)")
        print("mean pick latency: \(String(format: "%.2f", mean))s")
        EvalFixture.result("snap", [("joined", joined), ("related", related), ("missed", missed + wrong), ("false_merges", falseMerges), ("no_answer", noAnswer)], latency: mean)
    }
}
