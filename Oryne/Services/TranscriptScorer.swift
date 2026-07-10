import Foundation

/// A single locale's attempt at transcribing one recorded drift, plus the raw
/// signals needed to judge it. Produced by `DriftTranscriber` from an
/// `SFSpeechRecognitionResult`; consumed by `TranscriptScorer`.
struct TranscriptCandidate {
    /// The recognition locale this attempt used.
    let locale: Locale
    /// The best transcription's formatted string (may be empty).
    let transcript: String
    /// Mean per-segment confidence over `bestTranscription.segments`, 0...1.
    /// 0 when there are no segments.
    let averageConfidence: Double
    /// Length of the source audio in seconds (the honest denominator for
    /// "output relative to duration"), 0 when it could not be measured.
    let audioDuration: TimeInterval
}

/// Picks the better of two competing transcripts for the same audio, and
/// decides when a main-language transcript looks bad enough to be worth a
/// second pass in the alternate language.
///
/// Pure and self-contained on purpose: the automatic file dual-pass
/// (`DriftTranscriber.transcribe(url:)`, BRIEF decision 7) and the manual
/// "Re-transcribe" escape hatch (BRIEF decision 8) both route their judgement
/// through here, so there is exactly one definition of "which transcript won".
///
/// The failure signal is the recorded-file adaptation of the live bake-off
/// scoring (BRIEF decision 5): output length vs. audio duration, average
/// segment confidence, and how much of the transcript is actually written in
/// the script the locale expects. See `docs/plans/bilingual-voice/BRIEF.md`.
enum TranscriptScorer {

    // MARK: - Tunables

    /// Below this fraction of the expected character yield for the locale's
    /// language, the output is "sparse" relative to how long the person spoke.
    static let sparseDensityFloor = 0.15
    /// Mean segment confidence below this reads as the recognizer guessing.
    static let lowConfidenceFloor = 0.35
    /// Clips shorter than this carry too little signal to call sparse — a
    /// two-word note legitimately produces very few characters.
    static let minDurationForSparseCheck: TimeInterval = 1.5
    /// Score gap under which the two candidates are treated as a tie, handing
    /// the decision to the asymmetric zh tie-break (BRIEF decision 5).
    static let tieEpsilon = 0.08

    // Component weights for the blended 0...1 quality score. Script coverage
    // and confidence lead; raw density is the weakest signal (the wrong model
    // can be both dense and confident — hence the zh tie-break, not density,
    // is the ultimate arbiter).
    private static let confidenceWeight = 0.35
    private static let scriptWeight = 0.40
    private static let densityWeight = 0.25

    // MARK: - Public API

    /// Loud failure signals on the main-language transcript that justify
    /// spending a second recognition pass on the alternate locale
    /// (BRIEF decision 7). Any one of: empty output, sparse output relative to
    /// audio duration, or low average confidence.
    static func hasLoudFailureSignals(_ candidate: TranscriptCandidate) -> Bool {
        if candidate.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if candidate.averageConfidence > 0, candidate.averageConfidence < lowConfidenceFloor {
            return true
        }
        if candidate.audioDuration >= minDurationForSparseCheck,
           densityRatio(candidate) < sparseDensityFloor {
            return true
        }
        return false
    }

    /// Blended 0...1 quality score. Higher is better.
    static func score(_ candidate: TranscriptCandidate) -> Double {
        let density = min(1.0, densityRatio(candidate))
        let confidence = max(0.0, min(1.0, candidate.averageConfidence))
        let coverage = scriptCoverage(of: candidate.transcript, for: candidate.locale)
        return confidence * confidenceWeight
            + coverage * scriptWeight
            + density * densityWeight
    }

    /// The winner between two candidates for the same audio. Higher score wins;
    /// within `tieEpsilon` the decision is asymmetric — Chinese wins the tie
    /// (BRIEF decision 5: the zh model survives embedded English, whereas the
    /// en model produces confident garbage on Chinese, so an ambiguous pair is
    /// trusted to zh).
    static func pickWinner(_ a: TranscriptCandidate, _ b: TranscriptCandidate) -> TranscriptCandidate {
        let sa = score(a)
        let sb = score(b)
        if abs(sa - sb) < tieEpsilon {
            let aIsChinese = isChinese(a.locale)
            let bIsChinese = isChinese(b.locale)
            if aIsChinese != bIsChinese {
                return aIsChinese ? a : b
            }
        }
        return sa >= sb ? a : b
    }

    // MARK: - Components

    /// Characters produced per second of audio, divided by a reference rate for
    /// the locale's language, so both a terse Chinese transcript and a wordy
    /// English one land on a comparable 0...~1 scale.
    private static func densityRatio(_ candidate: TranscriptCandidate) -> Double {
        guard candidate.audioDuration > 0 else { return 1.0 }
        let chars = Double(candidate.transcript.trimmingCharacters(in: .whitespacesAndNewlines).count)
        let perSecond = chars / candidate.audioDuration
        return perSecond / expectedCharsPerSecond(for: candidate.locale)
    }

    /// Fraction of the transcript's letters written in the script the locale
    /// expects (Han for Chinese, Latin otherwise). Detects a transcript that is
    /// nominally in one language but rendered in the wrong script.
    static func scriptCoverage(of text: String, for locale: Locale) -> Double {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return 0 }
        let expectsHan = isChinese(locale)
        let matching = letters.filter { expectsHan ? isHan($0) : isLatin($0) }.count
        return Double(matching) / Double(letters.count)
    }

    // MARK: - Language / script helpers

    static func isChinese(_ locale: Locale) -> Bool {
        locale.language.languageCode?.identifier == "zh"
    }

    /// Rough spoken-character rate: Chinese packs meaning into far fewer
    /// characters per second than alphabetic English (which counts every
    /// letter and space).
    private static func expectedCharsPerSecond(for locale: Locale) -> Double {
        isChinese(locale) ? 3.5 : 12.0
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF,   // CJK Unified Ideographs
             0x3400...0x4DBF,   // Extension A
             0xF900...0xFAFF,   // Compatibility Ideographs
             0x20000...0x2A6DF: // Extension B
            return true
        default:
            return false
        }
    }

    private static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0041...0x005A,   // A-Z
             0x0061...0x007A,   // a-z
             0x00C0...0x024F:   // Latin-1 Supplement + Extended-A/B
            return true
        default:
            return false
        }
    }
}
