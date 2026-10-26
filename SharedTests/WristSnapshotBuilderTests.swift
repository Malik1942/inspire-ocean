import XCTest
import Foundation

final class WristSnapshotBuilderTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func source(
        _ offset: TimeInterval = 0, title: String? = nil, summary: String? = nil,
        words: String? = nil, isVoice: Bool = true, hasAudio: Bool = false
    ) -> WristSnapshotBuilder.Source {
        WristSnapshotBuilder.Source(
            id: UUID(), title: title, summary: summary, words: words,
            isVoice: isVoice, hasAudio: hasAudio, createdAt: now.addingTimeInterval(offset)
        )
    }

    /// Every source is a live wrist take; `gone` were imported and deleted since.
    private func build(_ sources: [WristSnapshotBuilder.Source], gone: Set<UUID> = [],
                       today: WristSnapshotBuilder.Source? = nil) -> WristSnapshot {
        let ids = Set(sources.map(\.id))
        return WristSnapshotBuilder.build(ledgerIDs: ids.union(gone), liveIDs: ids, recent: sources, today: today, now: now)
    }

    func test_recent_isTheNewestTwentyNewestFirst() {
        let sources = (0..<25).map { source(TimeInterval($0)) }
        let snapshot = build(sources.shuffled())
        XCTAssertEqual(snapshot.recent.count, WristSnapshotBuilder.recentLimit)
        XCTAssertEqual(snapshot.recent.first?.id, sources[24].id)
        XCTAssertEqual(snapshot.recent.last?.id, sources[5].id)
    }

    func test_recent_leavesOutThoughtsTheWatchDidntCatch() {
        let wrist = source(), phone = source(1)
        let snapshot = WristSnapshotBuilder.build(
            ledgerIDs: [wrist.id], liveIDs: [wrist.id, phone.id], recent: [wrist, phone], today: nil, now: now
        )
        XCTAssertEqual(snapshot.recent.map(\.id), [wrist.id])
    }

    func test_deletedIDs_areImportedTakesNoLongerInTheStore() {
        let gone = UUID()
        XCTAssertEqual(build([source()], gone: [gone]).deletedIDs, [gone])
        XCTAssertEqual(build([source()]).deletedIDs, [])
    }

    func test_summary_isTheReadingAndIsMarked() {
        let thought = WristSnapshotBuilder.thought(from: source(
            summary: "  A room that tells you to stay. ", words: String(repeating: "word ", count: 80)
        ))
        XCTAssertEqual(thought.reading, "A room that tells you to stay.")
        XCTAssertTrue(thought.readingIsSummary)
        XCTAssertFalse(thought.continues)
    }

    func test_shortWords_areTheWholeReading() {
        let thought = WristSnapshotBuilder.thought(from: source(words: "Lighthouse café at closing time"))
        XCTAssertEqual(thought.reading, "Lighthouse café at closing time")
        XCTAssertFalse(thought.readingIsSummary)
        XCTAssertFalse(thought.continues)
    }

    func test_longWords_areCutAtAWordBoundary() throws {
        let thought = WristSnapshotBuilder.thought(from: source(words: String(repeating: "lighthouse ", count: 40)))
        let reading = try XCTUnwrap(thought.reading)
        XCTAssertTrue(thought.continues)
        XCTAssertLessThanOrEqual(reading.count, WristSnapshotBuilder.readingLimit)
        XCTAssertTrue(reading.hasSuffix("lighthouse"), "never cut mid-word")
    }

    func test_chineseWords_areCutAtTheLimit() {
        let thought = WristSnapshotBuilder.thought(from: source(words: String(repeating: "灯塔咖啡馆", count: 60)))
        XCTAssertEqual(thought.reading?.count, WristSnapshotBuilder.readingLimit)
        XCTAssertTrue(thought.continues)
    }

    func test_noWords_meansNoReading() {
        let thought = WristSnapshotBuilder.thought(from: source(words: "   "))
        XCTAssertNil(thought.reading)
        XCTAssertFalse(thought.hasTranscript)
    }

    func test_hasTranscript_onlyForAVoiceThoughtWithWords() {
        XCTAssertTrue(WristSnapshotBuilder.thought(from: source(words: "words")).hasTranscript)
        XCTAssertFalse(WristSnapshotBuilder.thought(from: source(words: "words", isVoice: false)).hasTranscript)
    }

    func test_titleAndAudio_passThrough() {
        let thought = WristSnapshotBuilder.thought(from: source(title: "Lighthouse café", hasAudio: true))
        XCTAssertEqual(thought.title, "Lighthouse café")
        XCTAssertTrue(thought.hasAudio)
        XCTAssertTrue(thought.isVoice)
    }

    func test_today_carriesTheDayItWasPicked() {
        let pick = source(-40 * 86_400, isVoice: false)
        let with = build([], today: pick)
        XCTAssertEqual(with.today?.id, pick.id)
        XCTAssertEqual(with.todayDay, now)
        let without = build([])
        XCTAssertNil(without.today)
        XCTAssertNil(without.todayDay)
    }
}
