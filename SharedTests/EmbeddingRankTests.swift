import XCTest
import Foundation

/// Retrieval across languages: a thought is reachable through its own words
/// and through its gist in the other language, and scores by the better of
/// the two. A fake backend stands in for Apple's models, which live in
/// per-script spaces and compare across them at noise.
final class EmbeddingRankTests: XCTestCase {

    /// English and Chinese texts live on different axes, like Apple's
    /// script-grouped models; same-language texts about one subject share
    /// an axis.
    private struct ScriptSplitBackend: EmbeddingBackend {
        func vector(for text: String) -> [Double]? {
            let isChinese = text.unicodeScalars.contains { $0.properties.isIdeographic }
            let aboutLight = text.contains("light") || text.contains("光")
            let aboutFood = text.contains("noodle") || text.contains("面")
            // [en-light, en-food, zh-light, zh-food]
            var v = [0.0, 0.0, 0.0, 0.0]
            if aboutLight { v[isChinese ? 2 : 0] = 1 }
            if aboutFood { v[isChinese ? 3 : 1] = 1 }
            return v == [0, 0, 0, 0] ? nil : v
        }
    }

    private var service: EmbeddingService!

    override func setUp() {
        service = EmbeddingService(primary: ScriptSplitBackend(), fallback: ScriptSplitBackend(), disk: nil)
    }

    func test_chineseQuestion_reachesEnglishThought_throughItsGist() {
        let candidates: [(id: String, texts: [String])] = [
            ("light", ["warm light on the brick wall", "傍晚的光把墙染成橘色"]),
            ("food", ["weeknight noodles", "工作日晚上的面"]),
        ]
        XCTAssertEqual(service.rank(query: "光", candidates: candidates, limit: 2, floor: 0.5), ["light"])
    }

    func test_withoutAGist_theChineseQuestionFindsNothing() {
        let candidates: [(id: String, texts: [String])] = [
            ("light", ["warm light on the brick wall"]),
        ]
        XCTAssertEqual(service.rank(query: "光", candidates: candidates, limit: 2, floor: 0.5), [])
    }

    func test_singleTextRank_stillWorks() {
        let candidates: [(id: String, text: String)] = [
            ("light", "warm light on the brick wall"),
            ("food", "weeknight noodles"),
        ]
        XCTAssertEqual(service.rank(query: "light", candidates: candidates, limit: 1, floor: 0.5), ["light"])
    }

    func test_diskCache_roundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("embedding-cache-test-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = EmbeddingDiskCache(url: url)
        cache.store([0.25, 0.5], forKey: "a:" + EmbeddingDiskCache.digest("hello"))
        cache.flush()
        let reopened = EmbeddingDiskCache(url: url)
        XCTAssertEqual(reopened.vector(forKey: "a:" + EmbeddingDiskCache.digest("hello")), [0.25, 0.5])
        XCTAssertNil(reopened.vector(forKey: "b:" + EmbeddingDiskCache.digest("hello")))
    }
}
