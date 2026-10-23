import XCTest
import Foundation

/// Unit tests for `LinkSensing`: which links the composer senses, which one
/// a release attaches, and when the link leaves the words.
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class LinkSensingTests: XCTestCase {

    // MARK: Finding

    func testFindsAFullURL() {
        XCTAssertEqual(
            LinkSensing.links(in: "https://www.nytimes.com/2026/10/20/arts/story.html").map(\.urlString),
            ["https://www.nytimes.com/2026/10/20/arts/story.html"]
        )
    }

    func testABareDomainGetsHTTPS() {
        XCTAssertEqual(
            LinkSensing.links(in: "check this nytimes.com/2026/10/20/story later").map(\.urlString),
            ["https://nytimes.com/2026/10/20/story"]
        )
        XCTAssertEqual(
            LinkSensing.links(in: "www.are.na/block/12345").map(\.urlString),
            ["https://www.are.na/block/12345"]
        )
    }

    func testATypedHTTPStaysHTTP() {
        XCTAssertEqual(
            LinkSensing.links(in: "old site http://example.com/page").map(\.urlString),
            ["http://example.com/page"]
        )
    }

    func testEmailsAreNotLinks() {
        XCTAssertTrue(LinkSensing.links(in: "email me at me@example.com").isEmpty)
    }

    func testFileNamesAndAbbreviationsAreNotLinks() {
        XCTAssertTrue(LinkSensing.links(in: "sunset.jpg looks nice, 3.5x brighter, e.g. this").isEmpty)
    }

    func testTheHostDropsWWW() {
        XCTAssertEqual(LinkSensing.links(in: "www.are.na/block/12345").first?.host, "are.na")
    }

    // MARK: Choosing

    func testTheFirstLinkIsChosen() {
        XCTAssertEqual(
            LinkSensing.chosen(in: "two links: https://a.com and https://b.org/page")?.urlString,
            "https://a.com"
        )
    }

    func testADismissedLinkGivesWayToTheNext() {
        XCTAssertEqual(
            LinkSensing.chosen(
                in: "two links: https://a.com and https://b.org/page",
                dismissed: ["https://a.com"]
            )?.urlString,
            "https://b.org/page"
        )
    }

    func testNothingIsChosenWhenEveryLinkIsDismissed() {
        XCTAssertNil(LinkSensing.chosen(in: "only https://a.com", dismissed: ["https://a.com"]))
    }

    // MARK: Lifting

    func testALinkAtTheEndLeavesTheWords() {
        XCTAssertEqual(
            LinkSensing.words("Love this palette https://are.na/b/42", lifting: "https://are.na/b/42"),
            "Love this palette"
        )
    }

    func testATrailingLinkTakesItsSentenceEnd() {
        XCTAssertEqual(LinkSensing.words("see https://a.com.", lifting: "https://a.com"), "see")
        XCTAssertEqual(
            LinkSensing.words("看这个 https://www.bilibili.com/video/BV1xx 。", lifting: "https://www.bilibili.com/video/BV1xx"),
            "看这个"
        )
    }

    func testATrailingLinkTakesWhatJoinedIt() {
        XCTAssertEqual(LinkSensing.words("Great read - https://a.com", lifting: "https://a.com"), "Great read")
        XCTAssertEqual(
            LinkSensing.words("Love this: https://are.na/b/42", lifting: "https://are.na/b/42"),
            "Love this"
        )
        XCTAssertEqual(
            LinkSensing.words("看这个：https://www.bilibili.com/video/BV1xx", lifting: "https://www.bilibili.com/video/BV1xx"),
            "看这个"
        )
    }

    func testAQuestionBeforeATrailingLinkKeepsItsMark() {
        XCTAssertEqual(LinkSensing.words("Is this real? https://a.com", lifting: "https://a.com"), "Is this real?")
    }

    func testALinkAtTheStartLeavesTheWords() {
        XCTAssertEqual(LinkSensing.words("https://a.com, great read", lifting: "https://a.com"), "great read")
        XCTAssertEqual(LinkSensing.words("https://a.com\nGreat read", lifting: "https://a.com"), "Great read")
    }

    func testALinkMidSentenceStays() {
        let words = "read https://x.com/someone/status/123 before friday"
        XCTAssertEqual(LinkSensing.links(in: words).map(\.urlString), ["https://x.com/someone/status/123"])
        XCTAssertEqual(LinkSensing.words(words, lifting: "https://x.com/someone/status/123"), words)
    }

    func testAChineseLinkMidSentenceStays() {
        let words = "小红书链接 xhslink.com/a/AbC123，复制后打开"
        XCTAssertEqual(LinkSensing.links(in: words).map(\.urlString), ["https://xhslink.com/a/AbC123"])
        XCTAssertEqual(LinkSensing.words(words, lifting: "https://xhslink.com/a/AbC123"), words)
    }

    func testOnlyALinkLeavesNoWords() {
        XCTAssertEqual(LinkSensing.words("  https://are.na/b/42 \n", lifting: "https://are.na/b/42"), "")
    }

    func testABareDomainIsLiftedByItsHTTPSForm() {
        XCTAssertEqual(
            LinkSensing.words("check nytimes.com/2026/10/20/story", lifting: "https://nytimes.com/2026/10/20/story"),
            "check"
        )
    }

    func testOnlyTheChosenOfTwoLinksIsLifted() {
        XCTAssertEqual(LinkSensing.words("https://a.com https://b.com", lifting: "https://a.com"), "https://b.com")
    }

    func testAFinalQuestionMarkIsNotTheLinks() {
        XCTAssertEqual(LinkSensing.links(in: "Is this real https://a.com?").map(\.urlString), ["https://a.com"])
        XCTAssertEqual(LinkSensing.words("Is this real https://a.com?", lifting: "https://a.com"), "Is this real")
        XCTAssertEqual(
            LinkSensing.links(in: "see https://a.com/search?q=1").map(\.urlString),
            ["https://a.com/search?q=1"]
        )
    }

    func testALinkWithOnlyItsSentenceEndLeavesNoWords() {
        XCTAssertEqual(LinkSensing.words("https://a.com.", lifting: "https://a.com"), "")
        XCTAssertEqual(LinkSensing.words("https://a.com !", lifting: "https://a.com"), "")
        XCTAssertEqual(
            LinkSensing.words("https://www.bilibili.com/video/BV1xx。", lifting: "https://www.bilibili.com/video/BV1xx"),
            ""
        )
    }

    func testALeadingLinkTakesItsSentenceEnd() {
        XCTAssertEqual(LinkSensing.words("https://a.com. Great read", lifting: "https://a.com"), "Great read")
        XCTAssertEqual(LinkSensing.words("https://a.com。看这个", lifting: "https://a.com"), "看这个")
    }

    func testEverySentenceEndAndJointLeavesWithATrailingLink() {
        for end in ["!", "?", "…", "，", "；", "！", "？"] {
            XCTAssertEqual(LinkSensing.words("see https://a.com\(end)", lifting: "https://a.com"), "see", end)
        }
        for joint in ["–", "—", "|", "·", ";", "，", "；"] {
            XCTAssertEqual(LinkSensing.words("Great read \(joint) https://a.com", lifting: "https://a.com"), "Great read", joint)
        }
    }

    func testProseTypedAgainstALinkEndsIt() {
        XCTAssertEqual(LinkSensing.links(in: "https://a.com这个不错").map(\.urlString), ["https://a.com"])
        XCTAssertEqual(LinkSensing.links(in: "看这个https://a.com/x复制").map(\.urlString), ["https://a.com/x"])
        XCTAssertEqual(LinkSensing.links(in: "https://a.com—great").map(\.urlString), ["https://a.com"])
        XCTAssertEqual(LinkSensing.links(in: "see https://a.com/“quoted”").map(\.urlString), ["https://a.com/"])
        XCTAssertTrue(LinkSensing.links(in: "https://这个").isEmpty)
    }

    func testChineseRightAfterALeadingLinkIsTheWords() {
        XCTAssertEqual(LinkSensing.words("https://a.com这个不错", lifting: "https://a.com"), "这个不错")
        XCTAssertEqual(LinkSensing.words("https://a.com、看看", lifting: "https://a.com"), "看看")
        XCTAssertEqual(LinkSensing.words("看这个 https://a.com、", lifting: "https://a.com"), "看这个")
        let words = "看这个https://a.com/x复制"
        XCTAssertEqual(LinkSensing.words(words, lifting: "https://a.com/x"), words)
    }

    func testALeadingLinkNeedsSomethingToSetItApart() {
        XCTAssertEqual(LinkSensing.links(in: "stripe.com’s new docs are great").map(\.urlString), ["https://stripe.com"])
        XCTAssertEqual(
            LinkSensing.words("stripe.com’s new docs are great", lifting: "https://stripe.com"),
            "stripe.com’s new docs are great"
        )
        XCTAssertEqual(LinkSensing.words("https://a.com -5 degrees", lifting: "https://a.com"), "-5 degrees")
        XCTAssertEqual(LinkSensing.words("https://a.com :) nice", lifting: "https://a.com"), ":) nice")
        XCTAssertEqual(LinkSensing.words("https://a.com - great", lifting: "https://a.com"), "great")
        XCTAssertEqual(LinkSensing.words("https://a.com! Amazing", lifting: "https://a.com"), "Amazing")
    }

    func testEveryFinalQuestionMarkIsTheSentences() {
        XCTAssertEqual(LinkSensing.links(in: "really https://a.com??").map(\.urlString), ["https://a.com"])
    }

    func testASCIIMarksAroundALink() {
        XCTAssertEqual(LinkSensing.words("see https://a.com,", lifting: "https://a.com"), "see")
        XCTAssertEqual(LinkSensing.words("see https://a.com;", lifting: "https://a.com"), "see")
        XCTAssertEqual(LinkSensing.words("Great read, https://a.com", lifting: "https://a.com"), "Great read")
        XCTAssertEqual(LinkSensing.words("Wow! https://a.com", lifting: "https://a.com"), "Wow!")
    }

    func testEmojiTypedAgainstALinkEndIt() {
        XCTAssertEqual(LinkSensing.links(in: "这个https://a.com👍").map(\.urlString), ["https://a.com"])
        XCTAssertEqual(LinkSensing.links(in: "https://a.com🔥").map(\.urlString), ["https://a.com"])
        XCTAssertEqual(LinkSensing.links(in: "nice https://a.com/x👍").map(\.urlString), ["https://a.com/x"])
        XCTAssertEqual(LinkSensing.links(in: "call 1234 or see https://a.com/2#3").map(\.urlString), ["https://a.com/2#3"])
    }

    func testCJKLettersOpeningAPathSegmentAreTheLinks() {
        let wiki = URL(string: "https://zh.wikipedia.org/wiki/海洋")!.absoluteString
        XCTAssertEqual(LinkSensing.links(in: "https://zh.wikipedia.org/wiki/海洋").map(\.urlString), [wiki])
        XCTAssertEqual(LinkSensing.links(in: "zh.wikipedia.org/wiki/海洋").map(\.urlString), [wiki])
        XCTAssertEqual(LinkSensing.links(in: "https://zh.wikipedia.org/wiki/海洋，很美").map(\.urlString), [wiki])
        XCTAssertEqual(
            LinkSensing.links(in: "https://baike.baidu.com/item/海洋/1101").map(\.urlString),
            [URL(string: "https://baike.baidu.com/item/海洋/1101")!.absoluteString]
        )
    }

    func testACutRightAfterADotLeavesTheDotBehind() {
        XCTAssertEqual(LinkSensing.links(in: "https://a.com.这个").map(\.urlString), ["https://a.com"])
    }

    func testWithoutALinkTheWordsAreOnlyTrimmed() {
        XCTAssertEqual(LinkSensing.words("  hello  ", lifting: nil), "hello")
        XCTAssertEqual(LinkSensing.words("hello", lifting: "https://a.com"), "hello")
    }
}
