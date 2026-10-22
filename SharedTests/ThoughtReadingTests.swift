import XCTest
import Foundation

/// The deterministic half of the understanding record: language split,
/// slugs, keys, and the cleaning of what the model returns.
final class ThoughtReadingTests: XCTestCase {

    // MARK: Language

    func test_english() {
        XCTAssertEqual(ThoughtReading.language(of: "An app where the whole screen is a single sentence."), .en)
    }

    func test_chinese() {
        XCTAssertEqual(ThoughtReading.language(of: "傍晚的光把整个房间染成了橘色。"), .zh)
    }

    func test_chineseWithOneProductName_isChinese() {
        XCTAssertEqual(ThoughtReading.language(of: "想把 Tide 的浮现改成按海流轮换。"), .zh)
    }

    func test_halfAndHalf_isMixed() {
        XCTAssertEqual(ThoughtReading.language(of: "Oryne 的 Ask 不够聪明 and cannot translate anything yet"), .mixed)
    }

    func test_noLetters_isEnglish() {
        XCTAssertEqual(ThoughtReading.language(of: "2026-10-22 !!"), .en)
    }

    // MARK: Slugs and keys

    func test_slug_lowercasesAndHyphenates() {
        XCTAssertEqual(ThoughtReading.slug("Light and Color"), "light-and-color")
    }

    func test_slug_readsAmpersandAsAnd() {
        XCTAssertEqual(ThoughtReading.slug("light & color"), "light-and-color")
    }

    func test_slug_dropsPunctuationAndCollapsesBreaks() {
        XCTAssertEqual(ThoughtReading.slug("  career,  uncertainty!  "), "career-uncertainty")
    }

    func test_slug_keepsNonLatinLabels() {
        XCTAssertEqual(ThoughtReading.slug("光与色彩"), "光与色彩")
    }

    func test_keys_preferEnglishRendering_dedupe_andCap() {
        let keys = ThoughtReading.keys(
            fromEnglish: ["Light and color", "light & color", "warmth", "evening", "extra"],
            fallbackLabels: ["光与色彩"]
        )
        XCTAssertEqual(keys, ["light-and-color", "warmth", "evening"])
    }

    func test_keys_fallBackToLabels() {
        XCTAssertEqual(ThoughtReading.keys(fromEnglish: [], fallbackLabels: ["Product Ideas"]), ["product-ideas"])
    }

    // MARK: Gist

    func test_gist_keptOnlyInTheOtherLanguage() {
        XCTAssertEqual(ThoughtReading.tidyGist("一个整屏只有一句话的应用。", entryLanguage: .en), "一个整屏只有一句话的应用。")
        XCTAssertNil(ThoughtReading.tidyGist("An app with one sentence per screen.", entryLanguage: .en))
        XCTAssertEqual(ThoughtReading.tidyGist("An app with one sentence per screen.", entryLanguage: .zh), "An app with one sentence per screen.")
        XCTAssertEqual(ThoughtReading.tidyGist("An app with one sentence per screen.", entryLanguage: .mixed), "An app with one sentence per screen.")
        XCTAssertNil(ThoughtReading.tidyGist("  \n", entryLanguage: .en))
        XCTAssertNil(ThoughtReading.tidyGist(nil, entryLanguage: .en))
    }

    func test_gist_takesFirstLineAndCapsLength() {
        let long = String(repeating: "很", count: 200) + "\nsecond line"
        let gist = ThoughtReading.tidyGist(long, entryLanguage: .en)
        XCTAssertEqual(gist?.count, ThoughtReading.maxGistLength)
    }

    // MARK: Entities

    func test_entities_trimDedupeAndCap() {
        let entities = ThoughtReading.tidyEntities(["“Mara”", "mara", " Lisbon, ", "", "Are.na", "Oryne", "Tide"])
        XCTAssertEqual(entities, ["Mara", "Lisbon", "Are.na", "Oryne"])
    }
}

extension ThoughtReadingTests {
    func test_formalCategory_quoteQuestionLink() {
        XCTAssertEqual(ThoughtReading.formalCategory(for: "“我们塑造工具，工具反过来塑造我们。”"), .quote)
        XCTAssertEqual(ThoughtReading.formalCategory(for: "\"We shape our tools.\" Culkin"), .quote)
        XCTAssertEqual(ThoughtReading.formalCategory(for: "为什么我这么在意陌生人怎么看我的作品？"), .question)
        XCTAssertEqual(ThoughtReading.formalCategory(for: "Why do I care?"), .question)
        XCTAssertEqual(ThoughtReading.formalCategory(for: "https://www.are.na/editorial a feed worth coming back to"), .link)
        XCTAssertNil(ThoughtReading.formalCategory(for: "The bakery on 5th opens at 7."))
        XCTAssertNil(ThoughtReading.formalCategory(for: ""))
    }

    func test_entities_dropCommonNounsAndPronouns_keepNames() {
        XCTAssertEqual(ThoughtReading.tidyEntities(["self", "work", "strangers", "dentist"]), [])
        XCTAssertEqual(ThoughtReading.tidyEntities(["iPhone SE", "are.na", "John Culkin", "我们", "牙医"]), ["iPhone SE", "are.na", "John Culkin", "牙医"])
    }

    func test_prompt_namesTheLanguages() {
        let en = ThoughtReading.prompt(entry: "Call the dentist before Friday.")
        XCTAssertTrue(en.contains("written in English"))
        XCTAssertTrue(en.contains("Write title and themes in English"))
        XCTAssertTrue(en.contains("gistInOtherLanguage in Chinese"))
        let zh = ThoughtReading.prompt(entry: "周五之前给牙医打电话。")
        XCTAssertTrue(zh.contains("written in Chinese"))
        XCTAssertTrue(zh.contains("gistInOtherLanguage in English"))
    }
}

extension ThoughtReadingTests {
    func test_gist_keepsProductNamesInLatinInsideAChineseGist() {
        let gist = "iPhone SE的undo toast覆盖了tab bar，导致Library无法被触发。"
        XCTAssertEqual(ThoughtReading.tidyGist(gist, entryLanguage: .en), gist)
        XCTAssertNil(ThoughtReading.tidyGist(gist, entryLanguage: .zh))
    }
}
