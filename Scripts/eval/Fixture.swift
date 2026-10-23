import Foundation

/// One Ocean for every eval (docs/plans/memory-layer/SPEC.md): twenty-six
/// thoughts over three months in English, Chinese and a mix, with the
/// understanding record phase 1 writes, grouped into currents by their
/// first theme. The understanding eval reads the bodies and checks the
/// categories; the snap eval offers the currents; the Ask eval answers over
/// the thoughts; the memory eval reads the recent ones. Change it here and
/// every eval moves together.
struct FixtureThought {
    let key: String
    let title: String
    let body: String
    let gist: String?
    let category: ThoughtCategory
    /// Categories an honest reader could also choose; the eval accepts them.
    let alsoAccept: Set<ThoughtCategory>
    let daysAgo: Int
    /// First theme names the current; labels in the thought's own language.
    let themes: [String]
    let themesEnglish: [String]
    let entities: [String]
    /// A picture attached (with words, it is still a typed thought).
    let hasPictures: Bool
    /// What the device read off the picture (`PictureReading.context`), for
    /// a thought whose picture is its substance; nil when the words are.
    let pictureContext: String?

    init(_ key: String, _ title: String, _ body: String, gist: String?, _ category: ThoughtCategory,
         also: Set<ThoughtCategory> = [], daysAgo: Int, themes: [String], english: [String]? = nil, entities: [String] = [],
         pictures: Bool = false, picture: String? = nil) {
        self.key = key; self.title = title; self.body = body; self.gist = gist; self.category = category
        self.alsoAccept = also; self.daysAgo = daysAgo; self.themes = themes
        self.themesEnglish = english ?? themes; self.entities = entities
        self.hasPictures = pictures || picture != nil; self.pictureContext = picture
    }

    /// The entry as the reader and the agent see it: the words, then what
    /// the picture holds (`Node.meaningText` joins them the same way).
    var entry: String {
        [body, pictureContext ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var createdAt: Date { Date().addingTimeInterval(-Double(daysAgo) * 86_400) }
    var currentKey: String { ThoughtReading.slug(themesEnglish.first ?? themes.first ?? "") }
    var themeKeys: [String] { ThoughtReading.keys(fromEnglish: themesEnglish, fallbackLabels: themes) }
    var accepts: Set<ThoughtCategory> { alsoAccept.union([category]) }
}

enum EvalFixture {
    static let thoughts: [FixtureThought] = [
        // Light and color: the creative concern that keeps returning.
        FixtureThought("light-sunset", "Sunset gradient study", "The orange does not really exist; it is the blue leaving.", gist: "橘色其实并不存在，是蓝色在离开。", .note, also: [.idea], daysAgo: 2, themes: ["light and color", "visual study"]),
        FixtureThought("light-golden", "Golden hour on the walk home", "Streetlights coming on while the sky is still blue.", gist: "路灯亮起时天空还是蓝的。", .note, also: [.memory], daysAgo: 6, themes: ["light and color"]),
        FixtureThought("light-filter", "Warm to cool, not a filter", "Stop adding an orange overlay. The sunset is already a temperature shift.", gist: "别再加橙色叠层了，日落本身就是色温的变化。", .idea, also: [.note], daysAgo: 3, themes: ["light and color", "creative direction"]),
        FixtureThought("light-desk", "Desk at 6pm", "The desk turns amber for ten minutes and then it is gone.", gist: "书桌会变成琥珀色十分钟，然后就没了。", .note, also: [.memory], daysAgo: 9, themes: ["light and color", "interior"], pictures: true),
        FixtureThought("light-dunes", "Sunset over the dunes", "Sunset over the dunes, the colour I want for the Tide tiles.", gist: "沙丘上的日落，我想要的 Tide 卡片颜色。", .idea, also: [.note], daysAgo: 1, themes: ["light and color", "product"], entities: ["Tide"], pictures: true),
        FixtureThought("light-zh", "傍晚的光", "傍晚的光把整个房间染成了橘色。", gist: "The evening light turned the whole room orange.", .note, also: [.memory], daysAgo: 15, themes: ["光与色彩"], english: ["light and color"]),
        // Product work on Oryne.
        FixtureThought("oryne-bug-undo", "Undo toast hides the tab bar", "The Undo toast covers the tab bar on iPhone SE, so Library cannot be tapped.", gist: "iPhone SE 上撤销提示挡住了标签栏，点不到库。", .bug, daysAgo: 3, themes: ["interface design", "product"], entities: ["iPhone SE"]),
        FixtureThought("oryne-bug-ask", "Ask 不会翻译", "Oryne 的 Ask 还不够聪明，连翻译都做不到。", gist: "Oryne's Ask is not smart enough to translate.", .bug, also: [.note], daysAgo: 1, themes: ["产品", "智能"], english: ["product", "intelligence"], entities: ["Oryne"]),
        FixtureThought("oryne-idea-tide", "Tide 按海流轮换", "想把 Tide 的 resurfacing 改成按海流轮换。", gist: "Change Tide's resurfacing to rotate through the currents.", .idea, also: [.task], daysAgo: 5, themes: ["产品", "浮现"], english: ["product", "resurfacing"], entities: ["Tide"]),
        FixtureThought("oryne-task-invoice", "寄发票", "周五之前把 Oryne 的发票寄给会计。", gist: "Send the Oryne invoice to the accountant before Friday.", .task, daysAgo: 4, themes: ["事务", "财务"], english: ["errands", "finance"], entities: ["Oryne"]),
        FixtureThought("oryne-button", "A button that doesn't need a label", "If the shape says what it does, the word is noise.", gist: "如果形状已经说明了用途，文字就是噪音。", .idea, also: [.note], daysAgo: 12, themes: ["interface design"]),
        // Ideas.
        FixtureThought("water", "One line a day", "An app where the whole screen is a single sentence, like a tide that brings one line a day.", gist: "一个整屏只显示一句话的应用，像潮水一样每天带来一行。", .idea, daysAgo: 12, themes: ["product ideas", "digital minimalism"]),
        FixtureThought("idea-screen", "整屏一句话", "做一个整屏只显示一句话的 App。", gist: "An app that shows a single sentence on the whole screen.", .idea, daysAgo: 20, themes: ["产品想法"], english: ["product ideas"]),
        // Mara and Lisbon.
        FixtureThought("task-dentist", "Dentist before Friday", "Call the dentist before Friday and ask Mara about the Lisbon tickets.", gist: "周五前给牙医打电话，顺便问玛拉里斯本的票。", .task, daysAgo: 2, themes: ["errands", "travel"], entities: ["Mara", "Lisbon"]),
        FixtureThought("memory-train", "Night train to Lisbon", "Night train to Lisbon with Mara, we talked until the windows went grey.", gist: "和玛拉坐夜车去里斯本，聊到窗户泛灰。", .memory, daysAgo: 60, themes: ["travel", "friendship"], entities: ["Mara", "Lisbon"]),
        FixtureThought("memory-postcard", "Mara's postcard", "Mara's postcard from Porto, the one with the tiles.", gist: "玛拉从波尔图寄来的明信片，有瓷砖的那张。", .memory, also: [.note], daysAgo: 21, themes: ["friendship", "travel"], entities: ["Mara", "Porto"]),
        // Cooking.
        FixtureThought("cook-noodles", "Weeknight noodles", "Soy, black vinegar, a little sugar, chili crisp. Ten minutes.", gist: "酱油、黑醋、一点糖、辣椒脆。十分钟。", .note, daysAgo: 14, themes: ["cooking"]),
        FixtureThought("cook-zh", "红烧肉的火候", "红烧肉还是要小火慢炖。", gist: "Braised pork still wants a low flame and a slow simmer.", .note, daysAgo: 18, themes: ["烹饪"], english: ["cooking"]),
        FixtureThought("note-bakery", "Bakery on 5th", "The bakery on 5th opens at 7; croissants are gone by 8.", gist: "第五街的面包店七点开门，八点可颂就卖完了。", .note, daysAgo: 20, themes: ["neighborhood", "food"]),
        // Family and memory.
        FixtureThought("memory-kitchen", "外婆的厨房", "小时候外婆家的厨房总有八角的味道。", gist: "My grandmother's kitchen always smelled of star anise when I was small.", .memory, daysAgo: 90, themes: ["家", "回忆"], english: ["family", "memory"]),
        FixtureThought("memory-recipe", "Grandma's handwriting", "Grandma's handwriting on the recipe card; the kitchen smelled of star anise.", gist: "奶奶在食谱卡上的手写字，厨房里有八角的味道。", .memory, daysAgo: 40, themes: ["family"]),
        // Quotes, questions, links, sound, collecting, interior.
        FixtureThought("quote-tools", "Tools shape us", "\"We shape our tools and thereafter our tools shape us.\" John Culkin", gist: "我们塑造工具，工具反过来塑造我们。", .quote, daysAgo: 40, themes: ["technology", "philosophy"], entities: ["John Culkin"]),
        FixtureThought("quote-zh", "工具与我们", "“我们塑造工具，工具反过来塑造我们。”", gist: "We shape our tools, and our tools shape us in turn.", .quote, daysAgo: 45, themes: ["工具", "哲学"], english: ["tools", "philosophy"]),
        FixtureThought("question-strangers", "Why strangers' opinions", "Why do I care so much what strangers think of my work?", gist: "为什么我这么在意陌生人怎么看我的作品？", .question, daysAgo: 8, themes: ["self-worth", "social comparison"]),
        FixtureThought("link-arena", "Are.na Editorial", "https://www.are.na/editorial a feed worth coming back to", gist: "are.na 值得反复访问的订阅。", .link, daysAgo: 30, themes: ["collecting", "reading"], entities: ["Are.na"]),
        FixtureThought("sound-cafe", "Four notes in the cafe", "That bassline in the café stuck with me all afternoon.", gist: "咖啡馆里那段贝斯线一下午都在我脑子里。", .note, also: [.memory], daysAgo: 25, themes: ["sound & music"]),
        FixtureThought("sound-rain", "Rain keeping time", "The rain on the skylight kept time with the kettle.", gist: "天窗上的雨和水壶一起打着拍子。", .note, also: [.memory], daysAgo: 33, themes: ["sound & music"]),
        FixtureThought("interior-linen", "Linen curtains, not blinds", "The light through linen is the whole point of the room.", gist: "透过亚麻的光才是这个房间的全部意义。", .note, also: [.idea], daysAgo: 16, themes: ["interior", "light and color"]),
        // Pictures without words: what the device read off them is all there is.
        FixtureThought("pic-receipt", "Blue Bottle receipt", "", gist: "一张 Blue Bottle 的咖啡收据，两杯卡布奇诺。", .note, also: [.memory], daysAgo: 2, themes: ["coffee", "errands"], entities: ["Blue Bottle"],
                       picture: PictureReading.context(text: "Blue Bottle Coffee  Cappuccino x2  9.50  Thank you", labels: ["document", "text"])),
        FixtureThought("pic-beach", "Beach at dusk", "", gist: "黄昏时的海滩，有海和天空。", .note, also: [.memory], daysAgo: 7, themes: ["sea", "travel"],
                       picture: PictureReading.context(text: nil, labels: ["beach", "sea", "sunset", "sky"])),
    ]

    static func thought(_ key: String) -> FixtureThought {
        guard let t = thoughts.first(where: { $0.key == key }) else { fatalError("no fixture thought \(key)") }
        return t
    }

    /// Currents as the app keeps them: key, the label the thought's language
    /// reads, members newest first.
    struct Current {
        let key: String
        let label: String
        let titles: [String]
    }

    static var currents: [Current] {
        var byKey: [String: (label: String, members: [FixtureThought])] = [:]
        for t in thoughts {
            let key = t.currentKey
            var entry = byKey[key] ?? (label: t.themes.first ?? key, members: [])
            entry.members.append(t)
            byKey[key] = entry
        }
        return byKey.map { key, entry in
            Current(key: key, label: entry.label, titles: entry.members.sorted { $0.daysAgo < $1.daysAgo }.map(\.title))
        }.sorted { $0.key < $1.key }
    }

    /// The line a RESULT must take so `Scripts/eval/run.sh` can read it:
    /// `RESULT <eval> k=v k=v …`, one per run, last line.
    static func result(_ eval: String, _ metrics: [(String, Int)], latency: Double) {
        let fields = metrics.map { "\($0.0)=\($0.1)" } + [String(format: "latency=%.2f", latency)]
        print("RESULT \(eval) " + fields.joined(separator: " "))
    }
}
