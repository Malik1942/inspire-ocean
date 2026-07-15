import Foundation
import Speech

/// Resolves which locale(s) speech recognition should use, fresh on every call.
///
/// `Locale.current` and `Locale.preferredLanguages[0]` are not recognition-ready
/// on their own: a device set to Chinese reports a preferred-language tag like
/// `"zh-Hans-US"` (script + the device *region*, which is US, not a Chinese
/// region). Speech recognition only understands locales from its own supported
/// set (e.g. `"zh-CN"`), so every preferred-language entry has to be *mapped*
/// to the closest supported recognition locale rather than wrapped directly in
/// `Locale(identifier:)`.
///
/// See `docs/plans/bilingual-voice/BRIEF.md`, locked decisions 1, 2, and 4.
enum LanguageResolver {

    // MARK: - Public API

    /// Resolves against live system state: `Locale.preferredLanguages` and
    /// whichever supported-locale source applies to the running OS (BRIEF
    /// decision 4 — `Speech.SpeechTranscriber` on iOS 26+, `SFSpeechRecognizer`
    /// on iOS 18–25).
    ///
    /// Call this fresh at the start of every capture — never cache the result
    /// at app launch or store it in a property. BRIEF decision 1 requires the
    /// *current* system language, and a user can change iOS Settings ›
    /// Language between captures without relaunching the app.
    static func resolve() async -> (main: Locale, alternate: Locale?) {
        resolve(preferredLanguages: Locale.preferredLanguages, supportedLocales: Array(await liveSupportedLocales()))
    }

    /// Core resolution logic, parameterized for testing.
    ///
    /// - Parameters:
    ///   - preferredLanguages: Mirrors `Locale.preferredLanguages` — BCP-47
    ///     identifiers, most preferred first.
    ///   - supportedLocales: Mirrors whatever the active speech-recognition
    ///     API reports as supported.
    /// - Returns: `main`, the best recognition locale for the first preferred
    ///   language (BRIEF decision 1). `alternate`, the best recognition locale
    ///   for the first *later* preferred language whose resolved language
    ///   differs from `main`'s (BRIEF decision 2) — `nil` for monolingual
    ///   users, so they pay zero extra recognition cost.
    static func resolve(preferredLanguages: [String], supportedLocales: [Locale]) -> (main: Locale, alternate: Locale?) {
        guard let mainIdentifier = preferredLanguages.first else {
            // iOS always reports at least one preferred language; this guard
            // only exists so the API stays total instead of force-unwrapping.
            return (Locale(identifier: "en-US"), nil)
        }

        // If nothing in the supported set maps to the main preferred language,
        // hand back the raw (unmapped) locale rather than silently swapping in
        // a substitute language. An honestly-unsupported locale lets the
        // existing `speechAvailability == .unavailable` degrade path (BRIEF
        // invariants — capture never blocks on recognition) do its job,
        // instead of this resolver masking the mismatch.
        let main = bestRecognitionLocale(for: mainIdentifier, in: supportedLocales)
            ?? Locale(identifier: mainIdentifier)
        let mainLanguageCode = main.language.languageCode?.identifier

        for identifier in preferredLanguages.dropFirst() {
            guard let candidate = bestRecognitionLocale(for: identifier, in: supportedLocales) else { continue }
            if candidate.language.languageCode?.identifier != mainLanguageCode {
                return (main, candidate)
            }
        }
        return (main, nil)
    }

    // MARK: - Supported-locale source (BRIEF decision 4)

    private static func liveSupportedLocales() async -> Set<Locale> {
        if #available(iOS 26, *) {
            return Set(await Speech.SpeechTranscriber.supportedLocales)
        }
        return SFSpeechRecognizer.supportedLocales()
    }

    // MARK: - Mapping a preferred-language tag to a supported recognition locale

    /// Curated tie-breaks for when more than one supported locale shares a
    /// language (and, where relevant, script). Keyed by `"<language>-<script>"`
    /// when script disambiguation matters (Chinese Hans vs. Hant), otherwise by
    /// the bare `"<language>"` code.
    private static let regionPriority: [String: [String]] = [
        "zh-Hans": ["CN", "SG"],
        "zh-Hant": ["TW", "HK"],
        "zh": ["CN", "TW", "HK", "SG"],
        "en": ["US", "GB", "AU", "CA", "IN"],
    ]

    private static func bestRecognitionLocale(for preferredIdentifier: String, in supportedLocales: [Locale]) -> Locale? {
        guard !supportedLocales.isEmpty else { return nil }

        let preferred = Locale.Language(identifier: preferredIdentifier)
        // `maximalIdentifier` fills in the script implied by likely-subtag
        // rules even for a bare code like "zh" (-> "zh-Hans-CN"), which is
        // what lets a scriptless or region-mismatched preference still match
        // by script below.
        let maximal = Locale.Language(identifier: preferred.maximalIdentifier)
        guard let languageCode = (preferred.languageCode ?? maximal.languageCode)?.identifier else { return nil }

        let sameLanguage = supportedLocales.filter { $0.language.languageCode?.identifier == languageCode }
        guard !sameLanguage.isEmpty else { return nil }

        // 1. Exact region match honors an explicit, already-valid request
        //    (e.g. preferred "en-GB" when "en-GB" is itself supported).
        if let region = preferred.region?.identifier,
           let exact = sameLanguage.first(where: { $0.region?.identifier == region }) {
            return exact
        }

        // 2. Script match. This is what makes "zh-Hans-US" resolve to
        //    "zh-CN" instead of failing: region "US" doesn't exist among
        //    supported Chinese locales, but script "Hans" does.
        if let script = preferred.script?.identifier ?? maximal.script?.identifier {
            let scriptMatches = sameLanguage.filter { candidate in
                let candidateMaximal = Locale.Language(identifier: candidate.language.maximalIdentifier)
                return candidateMaximal.script?.identifier == script
            }
            if let best = pickByPriority(scriptMatches, key: "\(languageCode)-\(script)") {
                return best
            }
        }

        // 3. No usable script signal (or nothing matched it): fall back
        //    across every supported locale that shares the language.
        return pickByPriority(sameLanguage, key: languageCode)
    }

    private static func pickByPriority(_ candidates: [Locale], key: String) -> Locale? {
        guard !candidates.isEmpty else { return nil }
        if let priorities = regionPriority[key] {
            for region in priorities {
                if let match = candidates.first(where: { $0.region?.identifier == region }) {
                    return match
                }
            }
        }
        // Deterministic fallback so the result doesn't depend on whatever
        // order the supported-locale source happens to enumerate in.
        return candidates.sorted { $0.identifier < $1.identifier }.first
    }
}
