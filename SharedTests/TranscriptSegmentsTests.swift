import XCTest
import Foundation

/// Unit tests for `TranscriptSegments`: a pause in a whisper keeps the words
/// already heard, whether the pass is live or over a recorded file.
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class TranscriptSegmentsTests: XCTestCase {

    // MARK: - Pauses

    /// The reported bug: a file of several paragraphs came back as its last
    /// sentence, because the final result describes only the last segment.
    func test_finalAfterSeveralPauses_keepsEverySegment() {
        var words = TranscriptSegments()
        words.hypothesize("I went for a run")
        words.commitSegment("I went for a run this morning.")
        words.hypothesize("The algorithm")
        words.commitSegment("The algorithm should listen.")
        words.hypothesize("Slow and annoyed")
        words.commitFinal("Slow and annoyed because of the setup.")
        XCTAssertEqual(
            words.text,
            "I went for a run this morning. The algorithm should listen. Slow and annoyed because of the setup."
        )
    }

    func test_finalRedeliveringTheLastSegment_replacesIt() {
        var words = TranscriptSegments()
        words.commitSegment("first part")
        words.commitSegment("second part")
        words.commitFinal("Second part.")
        XCTAssertEqual(words.text, "first part Second part.")
    }

    func test_partialAfterPause_doesNotEraseCommittedWords() {
        var words = TranscriptSegments()
        words.commitSegment("before the pause")
        words.hypothesize("after")
        XCTAssertEqual(words.text, "before the pause after")
    }

    func test_newWordsAfterSegment_makeTheFinalAppend() {
        var words = TranscriptSegments()
        words.commitSegment("before the pause")
        words.hypothesize("after the")
        words.commitFinal("After the pause.")
        XCTAssertEqual(words.text, "before the pause After the pause.")
    }

    // MARK: - Endings without a final

    func test_emptyPartial_neverErasesTheHypothesis() {
        var words = TranscriptSegments()
        words.hypothesize("still heard")
        words.hypothesize("")
        XCTAssertEqual(words.text, "still heard")
    }

    func test_commitHypothesis_banksWordsOfADeadTask() {
        var words = TranscriptSegments()
        words.commitSegment("one")
        words.hypothesize("two")
        words.commitHypothesis()
        words.commitFinal("three")
        XCTAssertEqual(words.text, "one two three")
    }

    func test_emptySegmentFinal_banksTheHypothesis() {
        var words = TranscriptSegments()
        words.hypothesize("faint words")
        words.commitSegment("")
        XCTAssertEqual(words.text, "faint words")
    }

    func test_dropHypothesis_keepsCommittedWordsOnly() {
        var words = TranscriptSegments()
        words.commitSegment("kept")
        words.hypothesize("garbage")
        words.dropHypothesis()
        XCTAssertEqual(words.text, "kept")
    }

    // MARK: - Joining and confidence

    func test_chineseSegments_joinWithoutSpaces() {
        var words = TranscriptSegments()
        words.commitSegment("我今天去跑步。")
        words.commitSegment("训练计划应该适应人。")
        XCTAssertEqual(words.text, "我今天去跑步。训练计划应该适应人。")
    }

    func test_mixedScripts_joinWithASpace() {
        var words = TranscriptSegments()
        words.commitSegment("我想到")
        words.commitSegment("an algorithm")
        XCTAssertEqual(words.text, "我想到 an algorithm")
    }

    func test_averageConfidence_spansEveryCommittedSegment() {
        var words = TranscriptSegments()
        words.commitSegment("a b", confidences: [0.2, 0.4])
        words.hypothesize("c")
        words.commitFinal("c d", confidences: [0.6, 0.8])
        XCTAssertEqual(words.averageConfidence, 0.5, accuracy: 0.0001)
    }

    func test_averageConfidence_isZeroWhenNothingWasScored() {
        var words = TranscriptSegments()
        words.hypothesize("unscored")
        words.commitHypothesis()
        XCTAssertEqual(words.averageConfidence, 0)
    }
}
