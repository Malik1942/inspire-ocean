import Foundation

/// The words of one recognition pass, banked segment by segment.
///
/// On-device recognition resets its hypothesis after a silence gap: the
/// results that follow carry only the post-pause utterance, and a task's
/// final result can describe only its last segment. Trusting any single
/// result loses everything before the last pause, so every closed segment is
/// banked here, out of the recognizer's reach. Shared by the live take
/// (`LiveTranscriber`) and the recorded-file pass (`DriftTranscriber`) so the
/// two read a pause the same way. Pure, so `TranscriptSegmentsTests` holds it.
///
/// The live hypothesis is volatile by design: partials legitimately rewrite
/// it wholesale (Chinese partials rewrite earlier characters), so it is only
/// trusted once an explicit end-of-segment signal commits it.
struct TranscriptSegments {

    private struct Segment {
        var text: String
        /// Per-word confidences the recognizer scored this segment with.
        var confidences: [Float]
    }

    private var committed: [Segment] = []
    private var hypothesis = ""
    /// The last committed segment came from a segment-final result. The
    /// task's final usually re-delivers that same segment improved
    /// (punctuation, corrected words), so the final must replace the
    /// segment, not append a near-duplicate. Cleared the moment new words
    /// arrive: from then on the final describes the new segment.
    private var lastReplaceableByFinal = false

    /// Committed segments ⧺ the live hypothesis: the transcript as it stands.
    var text: String {
        var segments = committed.map(\.text)
        if !hypothesis.isEmpty { segments.append(hypothesis) }
        return Self.joined(segments)
    }

    /// Mean per-word confidence over every committed segment, 0...1; 0 when
    /// nothing scored was committed.
    var averageConfidence: Double {
        let all = committed.flatMap(\.confidences)
        guard !all.isEmpty else { return 0 }
        return all.map(Double.init).reduce(0, +) / Double(all.count)
    }

    /// A partial: the live hypothesis for the segment being spoken. Empty
    /// partials never erase words already heard.
    mutating func hypothesize(_ text: String) {
        guard !text.isEmpty else { return }
        hypothesis = text
        lastReplaceableByFinal = false
    }

    /// Segment-final: the recognizer endpointed on a silence. Bank the
    /// segment so the restarted-from-empty results that follow can't wipe it.
    mutating func commitSegment(_ text: String, confidences: [Float] = []) {
        let segment = text.isEmpty ? hypothesis : text
        guard !segment.isEmpty else { return }
        committed.append(Segment(text: segment, confidences: text.isEmpty ? [] : confidences))
        hypothesis = ""
        lastReplaceableByFinal = true
    }

    /// A task's non-empty final: it either re-delivers the last segment-final
    /// improved (replace it) or closes the segment the partials were still
    /// drafting (append it).
    mutating func commitFinal(_ text: String, confidences: [Float] = []) {
        let segment = Segment(text: text, confidences: confidences)
        if lastReplaceableByFinal, !committed.isEmpty {
            committed[committed.count - 1] = segment
        } else {
            committed.append(segment)
        }
        hypothesis = ""
        lastReplaceableByFinal = false
    }

    /// Banks the live hypothesis as-is, for task ends that deliver no final
    /// text (errors, empty finals).
    mutating func commitHypothesis() {
        guard !hypothesis.isEmpty else { return }
        committed.append(Segment(text: hypothesis, confidences: []))
        hypothesis = ""
        // A replacement task never heard this audio; its final must append.
        lastReplaceableByFinal = false
    }

    /// Drops the live hypothesis unbanked (wrong-language garbage below the
    /// confidence floor).
    mutating func dropHypothesis() {
        hypothesis = ""
    }

    // MARK: Joining

    /// Segments join with a single space, except across a CJK boundary:
    /// 中文 reads wrong with spaces injected between characters.
    static func joined(_ segments: [String]) -> String {
        segments.reduce(into: "") { joined, raw in
            let segment = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !segment.isEmpty else { return }
            if joined.isEmpty {
                joined = segment
            } else if isCJK(joined.last), isCJK(segment.first) {
                joined += segment
            } else {
                joined += " " + segment
            }
        }
    }

    /// CJK ideographs and full-width punctuation: the scripts written
    /// without inter-word spaces that this app ships (zh).
    private static func isCJK(_ character: Character?) -> Bool {
        guard let scalar = character?.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3000...0x303F,   // CJK symbols and punctuation (。、「」)
             0x3400...0x4DBF,   // CJK extension A
             0x4E00...0x9FFF,   // CJK unified ideographs
             0xF900...0xFAFF,   // CJK compatibility ideographs
             0xFF00...0xFF65:   // full-width forms (，！？)
            return true
        default:
            return false
        }
    }
}
