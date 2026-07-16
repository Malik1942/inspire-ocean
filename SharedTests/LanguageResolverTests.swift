import XCTest

/// Unit tests for `LanguageResolver`, exercised entirely through the
/// parameterized `resolve(preferredLanguages:supportedLocales:)` overload so
/// they don't depend on the live device's iOS Settings › Language or on
/// `SFSpeechRecognizer.supportedLocales()` (which varies by OS/simulator).
///
/// No `import Oryne`: the `SharedTests` target compiles the `Shared/` sources
/// directly (see project.yml), so `LanguageResolver` is part of this module.
final class LanguageResolverTests: XCTestCase {

    /// A representative slice of what `SFSpeechRecognizer.supportedLocales()`
    /// / `Speech.SpeechTranscriber.supportedLocales` report for English and
    /// Chinese in real life.
    private let supportedLocales: [Locale] = [
        Locale(identifier: "en-US"),
        Locale(identifier: "en-GB"),
        Locale(identifier: "en-AU"),
        Locale(identifier: "zh-CN"),
        Locale(identifier: "zh-TW"),
        Locale(identifier: "zh-HK"),
    ]

    // MARK: - Monolingual

    func test_monolingualEnglish_hasNoAlternate() {
        let result = LanguageResolver.resolve(
            preferredLanguages: ["en-US"],
            supportedLocales: supportedLocales
        )
        XCTAssertEqual(result.main.identifier, "en-US")
        XCTAssertNil(result.alternate)
    }

    func test_monolingualChinese_hasNoAlternate() {
        let result = LanguageResolver.resolve(
            preferredLanguages: ["zh-Hans-CN"],
            supportedLocales: supportedLocales
        )
        XCTAssertEqual(result.main.identifier, "zh-CN")
        XCTAssertNil(result.alternate)
    }

    /// A second preferred language that resolves to the *same* recognition
    /// language as main (e.g. en-US then en-GB) must not count as bilingual.
    func test_monolingualEnglish_withRegionalVariantSecondPreference_hasNoAlternate() {
        let result = LanguageResolver.resolve(
            preferredLanguages: ["en-US", "en-GB"],
            supportedLocales: supportedLocales
        )
        XCTAssertEqual(result.main.identifier, "en-US")
        XCTAssertNil(result.alternate)
    }

    // MARK: - Bilingual (both orderings)

    func test_bilingual_chineseMain_englishAlternate() {
        let result = LanguageResolver.resolve(
            preferredLanguages: ["zh-Hans-CN", "en-US"],
            supportedLocales: supportedLocales
        )
        XCTAssertEqual(result.main.identifier, "zh-CN")
        XCTAssertEqual(result.alternate?.identifier, "en-US")
    }

    func test_bilingual_englishMain_chineseAlternate() {
        let result = LanguageResolver.resolve(
            preferredLanguages: ["en-US", "zh-Hans-CN"],
            supportedLocales: supportedLocales
        )
        XCTAssertEqual(result.main.identifier, "en-US")
        XCTAssertEqual(result.alternate?.identifier, "zh-CN")
    }

    // MARK: - zh-Hans-US edge case (BRIEF decision 1)

    /// A device with system language Chinese but region United States reports
    /// preferred-language "zh-Hans-US". This must resolve to "zh-CN"
    /// recognition, not fail or silently fall back to English.
    func test_zhHansUS_resolvesToZhCN() {
        let result = LanguageResolver.resolve(
            preferredLanguages: ["zh-Hans-US"],
            supportedLocales: supportedLocales
        )
        XCTAssertEqual(result.main.identifier, "zh-CN")
        XCTAssertNil(result.alternate)
    }

    // MARK: - Unsupported-language fallback

    /// Neither preferred language is supported by recognition at all. `main`
    /// should still be a real (if unmapped) Locale — never crash, never
    /// silently substitute a different language — and `alternate` is nil.
    func test_unsupportedLanguages_fallBackToRawMainLocale_noAlternate() {
        let result = LanguageResolver.resolve(
            preferredLanguages: ["fr-FR", "de-DE"],
            supportedLocales: supportedLocales
        )
        XCTAssertEqual(result.main.identifier, "fr-FR")
        XCTAssertNil(result.alternate)
    }

    /// Main language is unsupported, but a later preferred language is a
    /// supported one: alternate should still be found even though main falls
    /// back to a raw passthrough.
    func test_unsupportedMain_supportedAlternateStillFound() {
        let result = LanguageResolver.resolve(
            preferredLanguages: ["fr-FR", "en-US"],
            supportedLocales: supportedLocales
        )
        XCTAssertEqual(result.main.identifier, "fr-FR")
        XCTAssertEqual(result.alternate?.identifier, "en-US")
    }

    // MARK: - Live smoke test

    /// Exercises the real `Locale.preferredLanguages` / OS-supported-locale
    /// path just enough to confirm it doesn't crash and always returns a
    /// non-empty main locale. Not a behavior assertion — the host's language
    /// settings vary per machine/CI runner.
    func test_liveResolve_returnsNonEmptyMain() async {
        let result = await LanguageResolver.resolve()
        XCTAssertFalse(result.main.identifier.isEmpty)
    }
}
