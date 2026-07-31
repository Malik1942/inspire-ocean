// Co-location eval for the interpret/grouping system (the "burger bug").
//
// The bug: thoughts that clearly belong together ("delicious hamburger",
// "yummy drink", "best burger in SF") get DIFFERENT free-text themes from the
// cloud understand() call ("taste", "food curiosity", ...). Currents group by
// EXACT theme-string equality (OceanLayout.swift), so different strings =
// different currents = fragmentation.
//
// This harness runs the real Anthropic Messages API twice over the same
// synthetic thought set, mirroring CloudOceanAIService.understand():
//   OLD  = the shipping prompt (each thought interpreted in isolation)   -> expect RED
//   NEW  = Fix C: the ocean's existing themes are passed in, with a
//          reuse-or-coin instruction and a bias toward broad reusable labels -> expect GREEN
// then scores co-location so you can see red -> green in one run, BEFORE any
// product code changes. The NEW prompt here is exactly what would then be
// adopted into CloudOceanAIService.
//
// Usage:  ANTHROPIC_API_KEY=sk-... ./run.sh          (see run.sh / README.md)
// Env:    OCEAN_CLOUD_MODEL (default claude-opus-4-8), OCEAN_CLOUD_BASE_URL

import Foundation

// MARK: - Eval set

struct Thought: Decodable {
    let id: String
    let group: String
    let lang: String
    let expectedTheme: String   // concept label, readout only — never string-matched
    let text: String
}
struct EvalSet: Decodable { let thoughts: [Thought] }

// MARK: - Config

let env = ProcessInfo.processInfo.environment
guard let apiKey = env["ANTHROPIC_API_KEY"], !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
    FileHandle.standardError.write(Data("""
    ERROR: no API key. Run via run.sh with a keyfile (recommended, once):
      mkdir -p ~/.config/oryne && pbpaste > ~/.config/oryne/anthropic.key
    (with your key on the clipboard from console.anthropic.com), or export
    ANTHROPIC_API_KEY yourself. Never commit the key anywhere.
    \n
    """.utf8))
    exit(2)
}
let model = env["OCEAN_CLOUD_MODEL"].flatMap { $0.isEmpty ? nil : $0 } ?? "claude-opus-4-8"
let baseURL = env["OCEAN_CLOUD_BASE_URL"].flatMap { URL(string: $0) } ?? URL(string: "https://api.anthropic.com")!

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let setURL = scriptDir.appendingPathComponent("eval-set.json")
guard let setData = try? Data(contentsOf: setURL),
      let evalSet = try? JSONDecoder().decode(EvalSet.self, from: setData) else {
    FileHandle.standardError.write(Data("ERROR: could not read \(setURL.path)\n".utf8))
    exit(2)
}
let thoughts = evalSet.thoughts

// MARK: - Prompts

// Verbatim from CloudOceanAIService.understand() at time of writing.
let OLD_SYSTEM = """
You interpret entries in a personal inspiration journal.
Reply with EXACTLY two lines and nothing else.
Line 1: a title of at most 6 words — capture the essence or feeling rather than restating the text; no quotation marks, no trailing punctuation.
Line 2: 1 to 3 conceptual themes, comma-separated, each one to three lowercase words. A theme names the underlying concept, intention, emotion, or domain — what the entry is really about, never words copied from it. Examples: creative direction, career uncertainty, recurring thoughts, social energy, emotional friction.
"""

// Mirrors ThemeVocabulary.filtered / isChinese: reuse candidates are limited
// to the entry's own language, so a zh entry can never reuse "food" verbatim —
// it must coin its own anchor. Script split (Han ≥ 1/3 of letters), since the
// app is zh-Hans + English and short theme strings defeat language detectors.
func isChinese(_ text: String) -> Bool {
    var letters = 0, han = 0
    for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
        letters += 1
        if scalar.properties.isIdeographic { han += 1 }
    }
    return han * 3 >= letters && han > 0
}

// Fix C. `existing` is the running list of themes already present in the
// ocean; only the entry's-language subset is offered for reuse.
func newSystem(existing: [String], entry: String) -> String {
    let reusable = existing.filter { isChinese($0) == isChinese(entry) }
    let vocab: String
    if reusable.isEmpty {
        vocab = "The journal has no themes yet in this entry's language — you are naming its first ones."
    } else {
        vocab = "The journal already uses these themes:\n" + reusable.map { "- \($0)" }.joined(separator: "\n")
    }
    return """
    You interpret entries in a personal inspiration journal.
    Reply with EXACTLY two lines and nothing else.
    Line 1: a title of at most 6 words — capture the essence or feeling rather than restating the text; no quotation marks, no trailing punctuation.
    Line 2: 1 to 3 conceptual themes, comma-separated, each one to three lowercase words. A theme names the underlying concept, intention, emotion, or domain.

    \(vocab)

    Consistency matters more than novelty. When an entry belongs with an existing theme, reuse that theme's exact wording rather than coining a near-synonym — a journal where "yummy drink" and "best burger" both sit under one "food" theme is far more useful than one that scatters them across "taste" and "food curiosity". Coin a NEW theme only when none of the existing ones genuinely fit, and keep new themes broad enough that future related entries can reuse them (prefer "food" over "food curiosity", "work" over "career uncertainty"). But a theme must still distinguish the entry from unrelated ones: never attach a catch-all that could fit most entries — "desire", "wanting", "thoughts", "feelings", "life". The entry's domain (food, work, nature) matters more than the stance it takes toward it. Write each theme in the language of the entry; for a mixed-language entry, its dominant language.
    """
}

// MARK: - Theme parsing (mirrors SemanticThemes.tidyThemeList)

func tidyThemeList(_ raw: String) -> [String] {
    var seen = Set<String>()
    let trimSet = CharacterSet(charactersIn: "-–—•*\"'“”‘’.:;0123456789() ")
    let cleaned = raw
        .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "·" || $0.isNewline })
        .compactMap { piece -> String? in
            let s = piece.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: trimSet)
                .lowercased()
            guard !s.isEmpty, s.count <= 28,
                  s.split(separator: " ").count <= 3,
                  seen.insert(s).inserted
            else { return nil }
            return s
        }
    return Array(cleaned.prefix(3))
}

// MARK: - Anthropic Messages API (blocking, mirrors completeText)

enum CallError: Error { case api(String) }

func complete(system: String, user: String, maxTokens: Int) throws -> String {
    var request = URLRequest(url: baseURL.appendingPathComponent("/v1/messages"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    request.timeoutInterval = 30

    let body: [String: Any] = [
        "model": model,
        "max_tokens": maxTokens,
        "system": system,
        "messages": [["role": "user", "content": user]],
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    var result: Result<String, Error>!
    let sema = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { sema.signal() }
        if let error { result = .failure(error); return }
        guard let data, let http = response as? HTTPURLResponse else {
            result = .failure(CallError.api("no response")); return
        }
        guard http.statusCode == 200 else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String }
                ?? "HTTP \(http.statusCode)"
            result = .failure(CallError.api(msg)); return
        }
        let text = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
            .flatMap { $0["content"] as? [[String: Any]] }?
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined() ?? ""
        result = .success(text)
    }.resume()
    sema.wait()
    return try result.get()
}

func understand(_ text: String, system: String) throws -> [String] {
    let raw = try complete(system: system, user: "Entry:\n\(text)", maxTokens: 96)
    let lines = raw.split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    let themeLine = lines.dropFirst().first ?? ""
    return tidyThemeList(themeLine)
}

// MARK: - Run a pass

struct Outcome { let id: String; let group: String; let concept: String; let themes: [String] }

/// A failed call makes the whole run unscoreable: co-location measured over
/// empty theme lists reads as a confident "0% / 0 false merges" table that
/// looks like a result but measures nothing. So any error aborts the run
/// rather than degrading into misleading numbers.
func runPass(reuse: Bool) throws -> [Outcome] {
    var vocabulary: [String] = []           // ordered, de-duped
    var vocabSet = Set<String>()
    var outcomes: [Outcome] = []
    let label = reuse ? "NEW (Fix C)" : "OLD (shipping)"
    print("\n── \(label) ─────────────────────────────────────────")
    for t in thoughts {
        let system = reuse ? newSystem(existing: vocabulary, entry: t.text) : OLD_SYSTEM
        let themes = try understand(t.text, system: system)
        guard !themes.isEmpty else {
            throw CallError.api("\(t.id): the model returned no usable theme line — cannot score this run")
        }
        outcomes.append(Outcome(id: t.id, group: t.group, concept: t.expectedTheme, themes: themes))
        if reuse {
            for th in themes where vocabSet.insert(th).inserted { vocabulary.append(th) }
        }
        print("  \(t.id.padding(toLength: 12, withPad: " ", startingAt: 0)) [\(t.lang)] → \(themes)")
    }
    return outcomes
}

// MARK: - Scoring

func pairs<T>(_ a: [T]) -> [(T, T)] {
    var out: [(T, T)] = []
    for i in 0..<a.count { for j in (i+1)..<a.count { out.append((a[i], a[j])) } }
    return out
}
func share(_ x: Outcome, _ y: Outcome) -> Bool { !Set(x.themes).isDisjoint(with: Set(y.themes)) }

func report(_ label: String, _ outcomes: [Outcome]) {
    print("\n══ \(label): co-location ══")
    // 1) WITHIN-GROUP (same group = same concept AND same language): must co-locate.
    let groups = Dictionary(grouping: outcomes, by: { $0.group })
    var withinTotal = 0, withinShared = 0
    for (g, members) in groups.sorted(by: { $0.key < $1.key }) where members.count > 1 {
        let ps = pairs(members)
        let s = ps.filter { share($0.0, $0.1) }.count
        withinTotal += ps.count; withinShared += s
        // all members share one common theme?
        let common = members.dropFirst().reduce(Set(members.first!.themes)) { $0.intersection(Set($1.themes)) }
        let unified = !common.isEmpty
        print("  \(g.padding(toLength: 12, withPad: " ", startingAt: 0)) pairs \(s)/\(ps.count) share  " +
              (unified ? "✓ unified on \(common.sorted())" : "✗ NOT unified"))
    }
    let withinRate = withinTotal == 0 ? 0 : Double(withinShared) / Double(withinTotal)
    print(String(format: "  → within-group co-location: %d/%d = %.0f%%  (want 100%%)", withinShared, withinTotal, withinRate * 100))

    // 2) DIFFERENT-CONCEPT pairs: must NOT co-locate (false merge = bug).
    let diffConcept = pairs(outcomes).filter { $0.0.concept != $0.1.concept }
    let falseMerges = diffConcept.filter { share($0.0, $0.1) }
    print(String(format: "  → false merges across concepts: %d/%d  (want 0)", falseMerges.count, diffConcept.count))
    for (x, y) in falseMerges { print("      ⚠︎ \(x.id) & \(y.id) both have \(Set(x.themes).intersection(Set(y.themes)).sorted())") }

    // 3) Theme-language correctness: a zh entry must wear zh themes and an en
    //    entry en themes — a Chinese thought with an English "food" chip is a
    //    localization break even when the grouping is right. Checked per
    //    thought against the eval set's lang tag (mixed entries are tagged by
    //    their dominant language).
    let byID = Dictionary(uniqueKeysWithValues: thoughts.map { ($0.id, $0.lang) })
    var langChecked = 0, langCorrect = 0
    for o in outcomes {
        guard let lang = byID[o.id], !o.themes.isEmpty else { continue }
        langChecked += 1
        let wrong = o.themes.filter { isChinese($0) != (lang == "zh") }
        if wrong.isEmpty { langCorrect += 1 }
        else { print("      ⚠︎ \(o.id) [\(lang)] wears wrong-language theme(s) \(wrong)") }
    }
    print("  → theme-language correctness: \(langCorrect)/\(langChecked)  (want all)")

    // 4) Same-concept, different language (food-en vs food-zh): with the
    //    language filter these stay separate currents by design; sharing here
    //    would mean the filter leaked.
    let crossLang = pairs(outcomes).filter { $0.0.concept == $0.1.concept && $0.0.group != $0.1.group }
    if !crossLang.isEmpty {
        let merged = crossLang.filter { share($0.0, $0.1) }.count
        print("  · cross-language same concept sharing a theme: \(merged)/\(crossLang.count) (expect 0 under the language filter)")
    }
}

// MARK: - Main

print("model: \(model)   thoughts: \(thoughts.count)")

// Preflight: one cheap call, so a rejected key or unreachable endpoint fails
// here with an actionable message instead of 18 identical errors followed by
// a scoring table that measures nothing.
do {
    _ = try complete(system: "Reply with the single word: ok", user: "ping", maxTokens: 8)
    print("preflight: API reachable, key accepted ✓")
} catch {
    let detail = "\(error)"
    FileHandle.standardError.write(Data("""

    PREFLIGHT FAILED — no eval was run, and no scores are reported.
      \(detail)

    """.utf8))
    if detail.contains("x-api-key") || detail.contains("authentication") || detail.contains("401") {
        FileHandle.standardError.write(Data("""
        The key in ANTHROPIC_API_KEY was sent but rejected. Check that:
          • it is a real key, not the literal placeholder "sk-ant-..."
          • it has no stray quotes, spaces, or a trailing newline
          • it is current (not revoked/rotated) and has credit available
        Inspect it safely without printing it:
          echo "len=${#ANTHROPIC_API_KEY} prefix=${ANTHROPIC_API_KEY:0:7}"
        A real key looks like: len=108 prefix=sk-ant-

        """.utf8))
    }
    exit(1)
}

let old: [Outcome], new: [Outcome]
do {
    old = try runPass(reuse: false)
    new = try runPass(reuse: true)
} catch {
    FileHandle.standardError.write(Data("""

    RUN ABORTED — \(error)
    No scores are reported: co-location computed over failed calls would look
    like a result (0%, 0 false merges) while measuring nothing. Re-run once the
    cause above is fixed.

    """.utf8))
    exit(1)
}
report("OLD (shipping prompt)", old)
report("NEW (Fix C: reuse-or-coin)", new)
print("\nDone. RED = OLD within-group well below 100% / fragmented; GREEN = NEW at/near 100% with 0 false merges,")
print("full theme-language correctness (zh thoughts wear zh themes, mixed follow their dominant language),")
print("and the food-zh group unifying on its own zh anchor (bilingual proof).")
