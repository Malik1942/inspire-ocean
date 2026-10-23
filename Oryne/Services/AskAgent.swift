import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Ask as an agent (docs/plans/memory-layer/SPEC.md, phase 2): one session
/// with three tools over the person's own thoughts, so the model finds,
/// lists and reads before it answers instead of composing over whatever one
/// embedding search returned. `findThoughts` searches by meaning in either
/// language (through each thought's own words and its gist in the other
/// language); `listThoughts` filters by category, topic, recency or a name;
/// `readThought` returns one thought in full. Thoughts are named by short
/// references (t1, t2, …) the model cites back, which become the answer's
/// sources.
///
/// Independent of SwiftData and the UI on purpose: it works on `Thought`
/// snapshots, so `Scripts/ask-agent-eval` compiles it as it ships and runs
/// it against a fixed Ocean on the Mac's model. The bridge from `Node` and
/// to `OceanResponse` lives in `LocalOceanAIService`.
@available(iOS 26, macOS 26, *)
enum AskAgent {

    // MARK: Thoughts

    /// One thought as the tools see it: values only, so the agent can run
    /// off the main actor.
    struct Thought: Sendable {
        var id: UUID
        var title: String
        /// The person's own words: text, or a whisper's transcript, or a
        /// link's context.
        var body: String
        var gist: String?
        var summary: String?
        var createdAt: Date
        var category: ThoughtCategory?
        var kind: NodeKind
        var themes: [String]
        var themeKeys: [String]
        var entities: [String]
        /// Pictures attached, with or without words (a thought with words
        /// and a picture is a typed thought that carries a picture).
        var hasPictures = false

        var retrievalTexts: [String] {
            [[title, body, themes.joined(separator: " "), entities.joined(separator: " ")].joined(separator: " "), gist ?? ""]
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    /// One prior turn, oldest first.
    struct Turn: Sendable {
        var isUser: Bool
        var text: String
    }

    /// What the agent answered and what it stood on.
    struct Answer: Sendable {
        var text: String
        /// Thoughts the answer cited by reference, in citation order.
        var cited: [UUID]
        /// Thoughts the tools surfaced, first appearance first.
        var surfaced: [UUID]
        /// Thoughts read in full.
        var read: [UUID]
        var toolCalls: Int
        /// The model answered without a tool and was asked again with
        /// findThoughts results in the prompt.
        var forcedRetry = false
        /// The calls, in order, as the model made them.
        var calls: [String] = []
    }

    // MARK: Budget

    /// What one answer may spend of the context window. The on-device window
    /// is 4K tokens on iOS 26 and 8K on newer devices on iOS 27; the tight
    /// budget is the retry after the window overflowed.
    struct Budget: Sendable {
        var findLimit: Int
        var listLimit: Int
        var snippetLength: Int
        var readLength: Int
        var historyTurns: Int
        var historyLength: Int

        static let standard = Budget(findLimit: 8, listLimit: 12, snippetLength: 140, readLength: 1500, historyTurns: 4, historyLength: 200)
        static let roomy = Budget(findLimit: 12, listLimit: 16, snippetLength: 200, readLength: 3000, historyTurns: 6, historyLength: 300)
        static let tight = Budget(findLimit: 5, listLimit: 8, snippetLength: 80, readLength: 700, historyTurns: 0, historyLength: 0)

        /// The budget for this device's window, read when the API exists.
        static var forDevice: Budget {
            #if canImport(FoundationModels)
            if #available(iOS 26.4, macOS 26.4, *) {
                return SystemLanguageModel.default.contextSize >= 8192 ? .roomy : .standard
            }
            #endif
            return .standard
        }
    }

    // MARK: Ledger

    /// References handed out to thoughts as the tools surface them, and what
    /// the tools did, so the answer's sources are what the model actually
    /// stood on.
    actor Ledger {
        private var refs: [UUID: String] = [:]
        private var ids: [String: UUID] = [:]
        private(set) var surfaced: [UUID] = []
        private(set) var read: [UUID] = []
        private(set) var toolCalls = 0
        /// Each call as the model made it, for the eval and the console.
        private(set) var calls: [String] = []

        func record(_ call: String) {
            toolCalls += 1
            calls.append(call)
        }

        func reference(for id: UUID) -> String {
            if let ref = refs[id] { return ref }
            let ref = "t\(surfaced.count + 1)"
            refs[id] = ref
            ids[ref] = id
            surfaced.append(id)
            return ref
        }

        func id(for reference: String) -> UUID? {
            ids[reference.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)]
        }

        func markRead(_ id: UUID) {
            if !read.contains(id) { read.append(id) }
        }

        func countCall() { toolCalls += 1 }
    }

    // MARK: The Ocean the tools look into

    /// The thoughts, the ledger and the budget one answer works with.
    final class Ocean: Sendable {
        let thoughts: [Thought]
        let byID: [UUID: Thought]
        let budget: Budget
        let ledger = Ledger()

        /// Whether the question names a time ("recent", "last week", 最近):
        /// a `withinDays` the model invents for a timeless question is
        /// dropped (measured 2026-10-22: "What pictures have I saved?"
        /// became the last 7 days and lost a picture from 9 days ago).
        let namesTime: Bool

        init(thoughts: [Thought], budget: Budget, query: String = "") {
            self.thoughts = thoughts
            self.byID = Dictionary(thoughts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.budget = budget
            self.namesTime = AskAgent.namesTime(query)
        }

        /// Three nets, widest last, merged in that order: embedding similarity
        /// in the question's language (through each thought's own words and
        /// its gist), then the question's content words found in a thought
        /// (a name, a product, 水 inside 潮水), then every thought of a kind
        /// the question names ("bugs", "想法"), since the model often reaches
        /// for findThoughts where listThoughts was meant.
        func find(_ query: String) async -> String {
            await ledger.record("find \"\(query)\"")
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return "Give findThoughts something to look for." }

            var hits: [Thought] = []
            var seen = Set<UUID>()
            func take(_ candidates: [Thought]) {
                for thought in candidates where hits.count < budget.findLimit && seen.insert(thought.id).inserted {
                    hits.append(thought)
                }
            }

            // A kind the question names comes first: "what bugs did I note"
            // is about the bugs, whatever else the words match. So does a
            // form: "what pictures did I save" (measured 2026-10-22: the
            // model searched the word and found a postcard by meaning).
            if let category = AskAgent.categoryNamed(in: q) {
                take(thoughts.filter { $0.category == category }.sorted { $0.createdAt > $1.createdAt })
            }
            if let form = AskAgent.formNamed(in: q) {
                take(thoughts.filter { AskAgent.matches(form: form, $0) }.sorted { $0.createdAt > $1.createdAt })
            }
            // A named kind or form that found anything is the whole answer:
            // word and similarity hits would only pad a list with thoughts
            // that are not what was asked for (measured 2026-10-22: "what
            // pictures" came back with eight thoughts, five without one).
            if !hits.isEmpty {
                return await lines(for: hits, heading: "\(hits.count) thoughts match \"\(q)\":")
            }

            // Then the question's own words found in a thought: an exact
            // "bakery" or 水 outranks any similarity score.
            let words = AskAgent.contentWords(in: q).filter { AskAgent.categoryWords[$0] == nil }
            if !words.isEmpty {
                let scored = thoughts.compactMap { thought -> (Thought, Int)? in
                    let haystack = thought.retrievalTexts.joined(separator: " ").lowercased()
                    let count = words.filter { haystack.contains($0) }.count
                    return count > 0 ? (thought, count) : nil
                }
                take(scored
                    .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.createdAt > $1.0.createdAt }
                    .map(\.0))
            }

            // Then by meaning, on word vectors: the contextual model scores a
            // short question against everything at 0.65 to 0.88, related or
            // not, while word vectors separate (measured 2026-10-22: "bakery"
            // 0.75 against at most 0.42; "quantum physics" nothing above
            // 0.29). Kept are the scores above the floor and within a margin
            // of the best, so one strong match does not drag noise along.
            let scored = AskAgent.finder.rankScored(
                query: q,
                candidates: thoughts.map { (id: $0.id, texts: $0.retrievalTexts) },
                limit: budget.findLimit,
                floor: AskAgent.findFloor
            )
            if let top = scored.first?.score {
                take(scored.filter { $0.score >= top - AskAgent.findMargin }.compactMap { byID[$0.id] })
            }

            guard !hits.isEmpty else { return "No thoughts match \"\(q)\"." }
            return await lines(for: hits, heading: "\(hits.count) thoughts match \"\(q)\":")
        }

        func list(category: ThoughtCategory?, kind: NodeKind? = nil, topic: String?, withinDays: Int?, mentioning: String?) async -> String {
            await ledger.record("list category=\(category?.rawValue ?? "-") form=\(kind?.rawValue ?? "-") topic=\(topic ?? "-") days=\(withinDays.map(String.init) ?? "-") mentioning=\(mentioning ?? "-")")
            // The model often puts the kind or the form in the topic or the
            // name ("pictures", "bugs"); read it out rather than match the word.
            var category = category, kind = kind, topic = topic, mentioning = mentioning
            if let word = topic, category == nil, let named = AskAgent.categoryNamed(in: word) { category = named; topic = nil }
            if let word = topic, kind == nil, let named = AskAgent.formNamed(in: word) { kind = named; topic = nil }
            if let word = mentioning, category == nil, let named = AskAgent.categoryNamed(in: word) { category = named; mentioning = nil }
            if let word = mentioning, kind == nil, let named = AskAgent.formNamed(in: word) { kind = named; mentioning = nil }
            let topicNeedle = topic?.lowercased().trimmingCharacters(in: .whitespaces)
            let topicKey = topic.map(ThoughtReading.slug)
            let nameNeedle = mentioning?.lowercased().trimmingCharacters(in: .whitespaces)
            let withinDays = namesTime ? withinDays : nil
            let since = withinDays.map { Date.now.addingTimeInterval(-Double(max($0, 1)) * 86_400) }

            // A guessed kind next to a named form ("list category=memory
            // form=image", measured 2026-10-22) finds nothing; the form is
            // what the person named, so it stands alone when the pair fails.
            func select(category: ThoughtCategory?) -> [Thought] { thoughts.filter { thought in
                if let category, thought.category != category { return false }
                if let kind, !AskAgent.matches(form: kind, thought) { return false }
                if let since, thought.createdAt < since { return false }
                if let topicNeedle, !topicNeedle.isEmpty {
                    let inThemes = thought.themes.contains { $0.lowercased().contains(topicNeedle) }
                        || thought.themeKeys.contains { key in topicKey.map { key.contains($0) } ?? false }
                    let inWords = (thought.title + " " + thought.body + " " + (thought.gist ?? "")).lowercased().contains(topicNeedle)
                    if !inThemes && !inWords { return false }
                }
                if let nameNeedle, !nameNeedle.isEmpty {
                    let inEntities = thought.entities.contains { $0.lowercased().contains(nameNeedle) }
                    let inWords = (thought.title + " " + thought.body).lowercased().contains(nameNeedle)
                    if !inEntities && !inWords { return false }
                }
                return true
            }.sorted { $0.createdAt > $1.createdAt } }
            var matched = select(category: category)
            if matched.isEmpty, kind != nil, category != nil {
                matched = select(category: nil)
                if !matched.isEmpty { category = nil }
            }

            var filters: [String] = []
            if let category { filters.append("kind \(category.rawValue)") }
            if let kind { filters.append(kind == .image ? "pictures" : kind == .voice ? "whispers" : kind == .link ? "links" : "typed thoughts") }
            if let topic, !topic.isEmpty { filters.append("topic \"\(topic)\"") }
            if let withinDays { filters.append("last \(withinDays) days") }
            if let mentioning, !mentioning.isEmpty { filters.append("mentioning \"\(mentioning)\"") }
            let scope = filters.isEmpty ? "all thoughts" : filters.joined(separator: ", ")

            guard !matched.isEmpty else { return "No thoughts for \(scope)." }
            let shown = Array(matched.prefix(budget.listLimit))
            let heading = shown.count == matched.count
                ? "\(matched.count) thoughts for \(scope), newest first:"
                : "\(matched.count) thoughts for \(scope); the newest \(shown.count):"
            return await lines(for: shown, heading: heading)
        }

        func read(_ reference: String) async -> String {
            await ledger.record("read \(reference)")
            guard let id = await ledger.id(for: reference), let thought = byID[id] else {
                return "No thought has the reference \(reference). Call findThoughts or listThoughts first and use a reference it returned."
            }
            await ledger.markRead(id)
            var out = "[\(reference.lowercased())] \"\(thought.title)\" · \(Self.when(thought.createdAt)) · \(Self.kindLabel(thought))"
            if !thought.themes.isEmpty { out += " · themes: " + thought.themes.joined(separator: ", ") }
            if !thought.entities.isEmpty { out += " · mentions: " + thought.entities.joined(separator: ", ") }
            out += "\n"
            let words = thought.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if words.count > budget.readLength, let summary = thought.summary, !summary.isEmpty {
                out += "Summary of a long whisper: \(summary)\nOpening words: \(String(words.prefix(budget.readLength / 2)))"
            } else if words.isEmpty {
                out += "No words of their own" + (thought.gist.map { "; gist: \($0)" } ?? ".")
            } else {
                out += "Their words: \(String(words.prefix(budget.readLength)))"
                if words.count > budget.readLength { out += " …" }
            }
            if let gist = thought.gist, !gist.isEmpty { out += "\nGist in the other language: \(gist)" }
            return out
        }

        /// A faithful translation of one thought's words, by a session of its
        /// own: the agent's session, busy with tools and rules, tends to echo
        /// the original instead. Measured 2026-10-22 on the bakery note.
        func translate(_ reference: String, into language: ThoughtLanguage) async -> String {
            await ledger.record("translate \(reference) into \(language.rawValue)")
            guard let id = await ledger.id(for: reference), let thought = byID[id] else {
                return "No thought has the reference \(reference). Call findThoughts or listThoughts first and use a reference it returned."
            }
            await ledger.markRead(id)
            let words = thought.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = String((words.isEmpty ? thought.title : words).prefix(budget.readLength))
            let target = language == .zh ? "Chinese" : "English"
            if let translated = await AskAgent.translate(source, into: language) {
                return "[\(reference.lowercased())] \"\(thought.title)\" translated into \(target):\n\(translated)"
            }
            return "[\(reference.lowercased())] could not be translated; their words: \(source)"
        }

        private func lines(for hits: [Thought], heading: String) async -> String {
            var out = [heading]
            for thought in hits {
                let ref = await ledger.reference(for: thought.id)
                out.append("[\(ref)] \(Self.when(thought.createdAt)) · \(Self.kindLabel(thought)) · \"\(thought.title)\": \(Self.snippet(thought, length: budget.snippetLength))")
            }
            return out.joined(separator: "\n")
        }

        static func when(_ date: Date) -> String {
            date.formatted(.relative(presentation: .named))
        }

        static func kindLabel(_ thought: Thought) -> String {
            thought.category?.rawValue ?? thought.kind.rawValue
        }

        static func snippet(_ thought: Thought, length: Int) -> String {
            let source = thought.body.isEmpty ? (thought.gist ?? (thought.hasPictures || thought.kind == .image ? "(a picture, no words)" : "")) : thought.body
            let oneLine = source.split(whereSeparator: \.isNewline).joined(separator: " ")
            return oneLine.count > length ? String(oneLine.prefix(length)) + "…" : oneLine
        }
    }

    // MARK: Tools

    #if canImport(FoundationModels)
    struct FindThoughts: Tool {
        let name = "findThoughts"
        let description = "Find the person's thoughts about something, by meaning, in Chinese or English. Use this first for any question about what they captured, thought, noted or wondered."

        @Generable
        struct Arguments {
            @Guide(description: "What to look for, as a short phrase in the question's language")
            var query: String
        }

        let ocean: Ocean
        func call(arguments: Arguments) async throws -> String { await ocean.find(arguments.query) }
    }

    struct ListThoughts: Tool {
        let name = "listThoughts"
        let description = "List thoughts by kind (idea, task, bug, note, quote, question, link, memory), by form (pictures, whispers, links, typed), by topic, by how recent, or by a name they mention. Use this for questions like what bugs did I note, my tasks, what pictures did I save, ideas from last week, everything about a person."

        @Generable
        enum Form: String {
            case pictures, whispers, links, typed
        }

        @Generable
        struct Arguments {
            @Guide(description: "The kind of thought, or omit for any kind")
            var category: FoundationThoughtReader.Category?
            @Guide(description: "The form: pictures, whispers (voice), links, or typed words; omit for any")
            var form: Form?
            @Guide(description: "A topic word or theme to match, or omit")
            var topic: String?
            @Guide(description: "Only thoughts from the last this many days, or omit for all time")
            var withinDays: Int?
            @Guide(description: "A person, place or product the thought mentions, or omit")
            var mentioning: String?
        }

        let ocean: Ocean
        func call(arguments: Arguments) async throws -> String {
            let kind: NodeKind? = switch arguments.form {
            case .pictures?: .image
            case .whispers?: .voice
            case .links?: .link
            case .typed?: .text
            case nil: nil
            }
            return await ocean.list(
                category: arguments.category.flatMap { ThoughtCategory(rawValue: $0.rawValue) },
                kind: kind,
                topic: arguments.topic,
                withinDays: arguments.withinDays,
                mentioning: arguments.mentioning
            )
        }
    }

    struct TranslateThought: Tool {
        let name = "translateThought"
        let description = "Translate one thought's words into Chinese or English by its reference, such as t2. Use it whenever they ask for a translation, then answer with the translation it returns."

        @Generable
        enum Language: String {
            case chinese, english
        }

        @Generable
        struct Arguments {
            @Guide(description: "The reference from an earlier result, such as t2")
            var reference: String
            @Guide(description: "The language to translate into")
            var into: Language
        }

        let ocean: Ocean
        func call(arguments: Arguments) async throws -> String {
            await ocean.translate(arguments.reference, into: arguments.into == .chinese ? .zh : .en)
        }
    }

    struct ReadThought: Tool {
        let name = "readThought"
        let description = "Read one thought in full by its reference, such as t2. Use it before translating, summarizing or quoting a thought, or when a snippet is not enough to answer."

        @Generable
        struct Arguments {
            @Guide(description: "The reference from an earlier result, such as t2")
            var reference: String
        }

        let ocean: Ocean
        func call(arguments: Arguments) async throws -> String { await ocean.read(arguments.reference) }
    }
    #endif

    // MARK: Translation session

    /// A faithful translation by a session of its own, with nothing else in
    /// its context. Nil when the model declines or returns nothing.
    static func translate(_ text: String, into language: ThoughtLanguage) async -> String? {
        #if canImport(FoundationModels)
        let target = language == .zh ? "Chinese" : "English"
        do {
            let session = LanguageModelSession {
                """
                You translate short personal notes faithfully into \(target). Keep the first \
                person, keep names and product names as they are, add nothing, leave nothing \
                out. Reply with the translation only: no preamble, no quotation marks.
                """
            }
            let response = try await session.respond(to: text)
            let translated = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return translated.isEmpty ? nil : translated
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: Prompt

    static let instructions = """
    You are the quiet, reflective voice of a personal inspiration space called the Ocean. \
    You answer questions about the thoughts this person captured, using tools: findThoughts \
    finds by meaning in either language; listThoughts lists by kind, topic, recency or a \
    name; readThought reads one thought in full by its reference, such as t2; translateThought \
    translates one thought's words into Chinese or English. Always call a \
    tool before answering, and answer only from what the tools return, never from memory or \
    general knowledge. When the tools return nothing relevant, say plainly that nothing in \
    their Ocean matches yet. Mention every thought you draw on by its reference in square \
    brackets, like [t2]. To translate, summarize or quote a thought, read it first and stay \
    faithful to its words. Speak to the person as "you", never "the user". Answer in the \
    language the question is written in. Plain prose of two to five sentences, unless they \
    ask for a list, then a short list. No exclamation marks.
    """

    /// The question, its language named, and the rules the small model
    /// weighs most when they come last: call a tool first, answer in the
    /// question's language, in its own words, citing references.
    /// The instructions, with what Oryne knows about the person appended
    /// when there is anything: background for reading their question, never
    /// a source, never something to recite.
    static func instructions(aboutPerson: String?) -> String {
        guard let aboutPerson, !aboutPerson.isEmpty else { return instructions }
        return instructions + """
         What you know about this person from their own thoughts, as background only (it may be \
        out of date, it is not a source, and you do not repeat it unless asked):
        \(aboutPerson)
        """
    }

    static func prompt(query: String, history: [Turn], budget: Budget) -> String {
        let turns = history.suffix(budget.historyTurns).map {
            ($0.isUser ? "They said: " : "You said: ") + $0.text.prefix(budget.historyLength)
        }
        let language = ThoughtReading.mostlyChineseByWords(query) ? "Chinese" : "English"
        var prompt = "Their question: \(query)"
        if !turns.isEmpty {
            prompt += "\n\nEarlier in this conversation (context only; answer the current question):\n" + turns.joined(separator: "\n")
        }
        prompt += """


        First call findThoughts or listThoughts; never answer before you have results. For a \
        kind of thought (bugs, tasks, ideas, notes, quotes, questions, links, memories) call \
        listThoughts with that kind. Write the whole answer in \(language), even when the \
        thoughts are in another language, in your own words rather than the tool lines, naming \
        each thought by its title and citing it like [t2]. If they ask for a translation, call \
        translateThought and answer with the translation it returns and nothing else.
        """
        return prompt
    }

    /// Word vectors for the find tool, both as primary and fallback so every
    /// score lives in one space (see `find`). Shares the disk cache, keyed
    /// by backend.
    static let finder = EmbeddingService(
        primary: DualLanguageEmbeddingBackend(),
        fallback: DualLanguageEmbeddingBackend()
    )

    /// Word-vector similarity below which a thought is not a find, and how
    /// far below the best match a find may still be. Measured 2026-10-22 on
    /// `Scripts/ask-agent-eval`'s Ocean: related tops at 0.75 to 0.81,
    /// unrelated at most 0.42 for a concrete word; a Chinese question
    /// against a Chinese gist tops near 0.59, its wrong neighbour 0.47.
    static let findFloor = 0.55
    static let findMargin = 0.06

    /// Why the agent last stood down, for the eval harness; DEBUG builds
    /// also print it.
    nonisolated(unsafe) static var lastFailure: String?

    static func log(_ message: @autoclosure () -> String) {
        let text = message()
        lastFailure = text
        #if DEBUG
        print("🜁 AskAgent: \(text)")
        #endif
    }

    // MARK: Translation requests

    struct TranslationRequest: Equatable {
        /// What to find: the question's content words minus the words that
        /// ask for the translation.
        var needle: String
        /// The language asked for; nil means the other one.
        var target: ThoughtLanguage?
    }

    private static let translationWords: Set<String> = [
        "translate", "translation", "translated", "into", "chinese", "english", "mandarin",
        "翻译", "译成", "翻成", "译为", "中文", "英文", "英语", "汉语", "成"
    ]

    /// Whether the question asks for a translation, and of what into what.
    static func translationRequest(in query: String) -> TranslationRequest? {
        let lowered = query.lowercased()
        let asks = ["translate", "翻译", "译成", "翻成", "译为"].contains { lowered.contains($0) }
        guard asks else { return nil }
        var target: ThoughtLanguage?
        if ["chinese", "mandarin", "中文", "汉语"].contains(where: lowered.contains) { target = .zh }
        else if ["english", "英文", "英语"].contains(where: lowered.contains) { target = .en }
        let words = contentWords(in: query).filter { !translationWords.contains($0) }
        let needle = words.isEmpty ? query : words.joined(separator: " ")
        return TranslationRequest(needle: needle, target: target)
    }

    // MARK: Words and kinds in a question

    /// Question filler in both languages, on top of the grammatical words
    /// `SemanticThemes` already drops: what remains is what to look for.
    static let filler: Set<String> = [
        "idea", "ideas", "thought", "thoughts", "note", "noted", "notes", "wrote", "write", "written",
        "said", "say", "anything", "something", "about", "did", "have", "has", "mention", "mentioned",
        "my", "me", "that", "the", "one", "ever", "any", "what", "which", "where", "when", "tell",
        "那个", "这个", "关于", "什么", "哪些", "哪个", "我的", "一下", "最近", "有没有", "是否", "记过",
        "写过", "说过", "提过", "想法", "灵感", "笔记", "东西", "那条", "这条", "那句", "这句", "我"
    ]

    /// The words worth searching for in a question.
    static func contentWords(in query: String) -> [String] {
        SemanticThemes.contentWords(in: query).filter { !filler.contains($0) }
    }

    /// Words that name a kind of thought, in either language.
    static let categoryWords: [String: ThoughtCategory] = [
        "bug": .bug, "bugs": .bug, "defect": .bug, "defects": .bug,
        "task": .task, "tasks": .task, "todo": .task, "todos": .task, "任务": .task, "待办": .task,
        "idea": .idea, "ideas": .idea, "想法": .idea, "点子": .idea, "创意": .idea,
        "note": .note, "notes": .note, "笔记": .note,
        "quote": .quote, "quotes": .quote, "引用": .quote, "名言": .quote, "引言": .quote,
        "question": .question, "questions": .question, "问题": .question, "疑问": .question,
        "link": .link, "links": .link, "链接": .link, "网页": .link,
        "memory": .memory, "memories": .memory, "回忆": .memory, "记忆": .memory
    ]

    /// Words that name a form of thought, in either language.
    static let formWords: [String: NodeKind] = [
        "picture": .image, "pictures": .image, "photo": .image, "photos": .image, "image": .image, "images": .image,
        "screenshot": .image, "screenshots": .image, "图片": .image, "照片": .image, "截图": .image, "图": .image,
        "whisper": .voice, "whispers": .voice, "recording": .voice, "recordings": .voice, "voice": .voice, "语音": .voice, "录音": .voice,
        "link": .link, "links": .link, "url": .link, "urls": .link, "网页": .link, "链接": .link
    ]

    /// The form a question names, if any ("what pictures did I save").
    static func formNamed(in query: String) -> NodeKind? {
        for word in SemanticThemes.contentWords(in: query) {
            if let kind = formWords[word] { return kind }
        }
        return nil
    }

    /// Time words, in both languages, that make a "last N days" filter the
    /// person's own.
    static let timeWords: [String] = [
        "recent", "recently", "lately", "latest", "today", "yesterday", "week", "weeks", "month", "months",
        "day", "days", "year", "ago", "since", "last", "past", "this morning", "tonight",
        "最近", "近期", "今天", "昨天", "前天", "本周", "这周", "上周", "这个月", "上个月", "今年", "去年", "几天", "以来", "之内", "最新"
    ]

    static func namesTime(_ query: String) -> Bool {
        let lowered = query.lowercased()
        return timeWords.contains { lowered.contains($0) }
    }

    /// Pictures ride on any kind of thought; the other forms are the kind.
    static func matches(form: NodeKind, _ thought: Thought) -> Bool {
        form == .image ? (thought.hasPictures || thought.kind == .image) : thought.kind == form
    }

    /// The kind a question names, if any ("what bugs did I note", "我记过哪些 bug").
    static func categoryNamed(in query: String) -> ThoughtCategory? {
        for word in SemanticThemes.contentWords(in: query) {
            if let category = categoryWords[word] { return category }
        }
        return nil
    }

    // MARK: Run

    /// Answers with the on-device model and its tools. Nil when the model
    /// failed outright. A context overflow goes straight to the tight
    /// budget; any other generation error (measured 2026-10-22: an opaque
    /// GenerationError with several underlying errors, once in about
    /// fourteen questions) gets one fresh session on the same budget first,
    /// since the next attempt usually succeeds.
    static func answer(query: String, history: [Turn], thoughts: [Thought], aboutPerson: String? = nil) async -> Answer? {
        lastFailure = nil
        #if canImport(FoundationModels)
        // A translation is an intent the question states outright, and the
        // small model, having read the thought, tends to echo it instead of
        // calling translateThought (measured 2026-10-22). So it is routed by
        // hand: find the thought, translate it in its own session, answer
        // with the translation.
        if let request = translationRequest(in: query) {
            let ocean = Ocean(thoughts: thoughts, budget: Budget.forDevice)
            _ = await ocean.find(request.needle)
            if let id = await ocean.ledger.surfaced.first, let thought = ocean.byID[id] {
                let reference = await ocean.ledger.reference(for: id)
                let target = request.target
                    ?? (ThoughtReading.mostlyChineseByWords(thought.body.isEmpty ? thought.title : thought.body) ? .en : .zh)
                let result = await ocean.translate(reference, into: target)
                let translated = result.split(separator: "\n", maxSplits: 1).count == 2
                    ? String(result.split(separator: "\n", maxSplits: 1)[1])
                    : result
                return Answer(
                    text: translated.trimmingCharacters(in: .whitespacesAndNewlines),
                    cited: [id],
                    surfaced: await ocean.ledger.surfaced,
                    read: [id],
                    toolCalls: await ocean.ledger.toolCalls,
                    calls: await ocean.ledger.calls
                )
            }
        }

        let attempts: [(budget: Budget, retryOnError: Bool)] = [(Budget.forDevice, true), (Budget.forDevice, false), (Budget.tight, false)]
        var index = 0
        while index < attempts.count {
            let (budget, retryOnError) = attempts[index]
            index += 1
            let ocean = Ocean(thoughts: thoughts, budget: budget, query: query)
            do {
                let session = LanguageModelSession(
                    tools: [FindThoughts(ocean: ocean), ListThoughts(ocean: ocean), ReadThought(ocean: ocean), TranslateThought(ocean: ocean)]
                ) { Self.instructions(aboutPerson: aboutPerson) }
                var response = try await session.respond(to: prompt(query: query, history: history, budget: budget))
                var forced = false
                // The model answered from nowhere, or looked in the wrong
                // place for a form or a kind the question names outright
                // (measured 2026-10-22: "what pictures" listed memories of
                // the last week). Run the right call for it and ask again
                // with the results in hand, so the answer is grounded or
                // honestly empty.
                let namedForm = AskAgent.formNamed(in: query)
                let namedKind = AskAgent.categoryNamed(in: query)
                let lookedWrong = await ocean.ledger.surfaced.isEmpty && (namedForm != nil || namedKind != nil)
                if await ocean.ledger.toolCalls == 0 || lookedWrong {
                    forced = true
                    log("retrying with results in the prompt (\(lookedWrong ? "named form or kind found nothing" : "no tool was called"))")
                    let results: String
                    if let namedForm {
                        results = await ocean.list(category: nil, kind: namedForm, topic: nil, withinDays: nil, mentioning: nil)
                    } else if let namedKind {
                        results = await ocean.list(category: namedKind, topic: nil, withinDays: nil, mentioning: nil)
                    } else {
                        results = await ocean.find(query)
                    }
                    response = try await session.respond(to: """
                        Results for their question:
                        \(results)

                        Answer their question from these results only, citing each thought you use like [t2]; \
                        if none fits, say that nothing in their Ocean matches yet. \
                        Write in \(ThoughtReading.mostlyChineseByWords(query) ? "Chinese" : "English").
                        """)
                }
                var answer = await compose(response.content, ocean: ocean, question: query)
                answer?.forcedRetry = forced
                return answer
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = error {
                    log("context overflowed on \(budget.findLimit)-result budget; retrying tight")
                    index = attempts.count - 1   // straight to the tight budget
                    continue
                }
                let underlying = ((error as NSError).userInfo[NSMultipleUnderlyingErrorsKey] as? [Error])?
                    .map { String(describing: $0) }.joined(separator: " | ") ?? ""
                log("generation error: \(error) \(underlying)")
                if retryOnError { continue }
                return nil
            } catch {
                log("error: \(error)")
                if retryOnError { continue }
                return nil
            }
        }
        return nil
        #else
        return nil
        #endif
    }

    /// The cited references resolved to thoughts, the markers removed from
    /// the prose, and the answer dropped when no tool was ever called.
    static func compose(_ raw: String, ocean: Ocean, question: String) async -> Answer? {
        let calls = await ocean.ledger.toolCalls
        guard calls > 0 else {
            log("no tool was called; answer dropped: \(raw.prefix(120))")
            return nil
        }
        var cited: [UUID] = []
        for match in AskReferences.references(in: raw) {
            if let id = await ocean.ledger.id(for: match), !cited.contains(id) { cited.append(id) }
        }
        var titles: [String: String] = [:]
        for id in await ocean.ledger.surfaced {
            if let thought = ocean.byID[id] { titles[await ocean.ledger.reference(for: id)] = thought.title }
        }
        var text = AnswerLength.capped(AskReferences.resolve(raw, titles: titles), sentences: 8)
        // The rule the small model drops most often is the language. When
        // the answer came back in the other one, a session of its own
        // translates it; the thoughts quoted inside follow.
        let wantsChinese = ThoughtReading.mostlyChineseByWords(question)
        if ThoughtReading.mostlyChineseByWords(text) != wantsChinese,
           let translated = await translate(text, into: wantsChinese ? .zh : .en) {
            text = translated
        }
        return Answer(
            text: text,
            cited: cited,
            surfaced: await ocean.ledger.surfaced,
            read: await ocean.ledger.read,
            toolCalls: calls,
            calls: await ocean.ledger.calls
        )
    }
}
