import XCTest
import Foundation

/// Unit tests for `WhisperRules`: when a voice thought still needs the
/// recognizer, and when its title is only the Library's placeholder stamp.
///
/// No app-module import: the SharedTests target compiles Shared/ sources
/// directly into the test bundle.
final class WhisperRulesTests: XCTestCase {

    /// Stands in for `VoiceUnderstanding.whisperPlaceholders`, which reads
    /// the app bundle's localizations.
    private let placeholders: Set<String> = ["Whisper", "语音"]

    private func voice(title: String = "", transcription: String? = nil, titleEditedByUser: Bool = false) -> Node {
        let node = Node(kind: .voice, title: title, transcription: transcription)
        node.titleEditedByUser = titleEditedByUser
        return node
    }

    // MARK: - needsTranscription

    func test_voiceThoughtWithNoTranscript_needsTranscription() {
        XCTAssertTrue(WhisperRules.needsTranscription(voice(transcription: nil)))
    }

    func test_voiceThoughtWithAnEmptyTranscript_needsTranscription() {
        XCTAssertTrue(WhisperRules.needsTranscription(voice(transcription: "")))
    }

    func test_voiceThoughtWithWords_doesNotNeedTranscription() {
        XCTAssertFalse(WhisperRules.needsTranscription(voice(transcription: "a lighthouse cafe")))
    }

    func test_thoughtThatIsNotVoice_neverNeedsTranscription() {
        for kind in [NodeKind.text, .image, .link] {
            XCTAssertFalse(WhisperRules.needsTranscription(Node(kind: kind)), "\(kind)")
        }
    }

    // MARK: - The placeholder title

    func test_stampedVoiceThought_hasAPlaceholderTitle_inEveryLanguage() {
        for label in placeholders {
            XCTAssertTrue(WhisperRules.hasPlaceholderTitle(voice(title: label), placeholders: placeholders), label)
        }
    }

    func test_placeholderTitle_isRecognizedAroundWhitespace() {
        XCTAssertTrue(WhisperRules.hasPlaceholderTitle(voice(title: " 语音\n"), placeholders: placeholders))
    }

    /// A title the user typed is theirs, whatever it says.
    func test_titleTheUserTyped_isNeverAPlaceholder() {
        XCTAssertFalse(WhisperRules.hasPlaceholderTitle(
            voice(title: "Whisper", titleEditedByUser: true), placeholders: placeholders
        ))
    }

    /// Only a voice thought is stamped "Whisper"; a text thought so named
    /// was named so.
    func test_thoughtThatIsNotVoice_neverHasAPlaceholderTitle() {
        XCTAssertFalse(WhisperRules.hasPlaceholderTitle(Node(kind: .text, title: "Whisper"), placeholders: placeholders))
    }

    func test_titleThatOnlyContainsThePlaceholder_isAName() {
        XCTAssertFalse(WhisperRules.hasPlaceholderTitle(voice(title: "Whisper at dawn"), placeholders: placeholders))
    }

    func test_untitledVoiceThought_hasNoPlaceholderTitle() {
        XCTAssertFalse(WhisperRules.hasPlaceholderTitle(voice(), placeholders: placeholders))
    }

    // MARK: - The name

    func test_name_isTheTrimmedTitle() {
        XCTAssertEqual(WhisperRules.name(of: voice(title: "  Lighthouse café \n"), placeholders: placeholders), "Lighthouse café")
    }

    func test_name_ofAnUntitledThought_isNil() {
        XCTAssertNil(WhisperRules.name(of: voice(title: " \n"), placeholders: placeholders))
    }

    func test_name_ofAPlaceholderTitle_isNil() {
        XCTAssertNil(WhisperRules.name(of: voice(title: "Whisper"), placeholders: placeholders))
    }

    func test_name_ofAPlaceholderTheUserTyped_isTheirs() {
        XCTAssertEqual(
            WhisperRules.name(of: voice(title: "Whisper", titleEditedByUser: true), placeholders: placeholders),
            "Whisper"
        )
    }
}
