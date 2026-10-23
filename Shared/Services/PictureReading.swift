import Foundation

/// The deterministic half of reading a thought's pictures into words
/// (docs/plans/memory-layer/SPEC.md, pictures): the version stamp, the
/// cleaning of what the device read, and the one passage the understanding
/// and retrieval layers take. The device half is `PictureReader` (Vision on
/// iOS 26: text recognition and scene classification); the two are kept
/// apart so this file compiles everywhere `Node` does and the eval scripts
/// can build a picture's passage without an image.
enum PictureReading {

    /// Bump when the reader or this passage changes in a way that makes
    /// earlier readings worth redoing: pictures below this version are read
    /// again on a later Library open. Version 2 is reserved for the model's
    /// own look at the picture (iOS 27), which replaces labels with a line
    /// of its own.
    static let version = 1

    static let maxTextLength = 400
    static let maxLabels = 5
    /// A recognized line shorter than this is noise: a stray glyph, a
    /// bullet, an icon read as a letter.
    static let minLineLength = 2

    // MARK: Cleaning

    /// The recognized lines as one passage: trimmed, noise dropped,
    /// deduplicated, in reading order, capped. Nil when nothing survives.
    static func tidyText(_ lines: [String]) -> String? {
        var seen = Set<String>()
        var kept: [String] = []
        var length = 0
        for raw in lines {
            let line = raw
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard line.count >= minLineLength,
                  line.contains(where: { $0.isLetter || $0.isNumber }),
                  seen.insert(line.lowercased()).inserted else { continue }
            if length + line.count + 1 > maxTextLength { break }
            kept.append(line)
            length += line.count + 1
        }
        return kept.isEmpty ? nil : kept.joined(separator: " ")
    }

    /// Labels the classifier gives that say nothing about a picture a
    /// person would recognise it by.
    /// Measured 2026-10-22: a waterfall photo also reads "land", "liquid",
    /// "water body" and "waterways"; a sunset "celestial body".
    static let genericLabels: Set<String> = [
        "structure", "material", "object", "thing", "pattern", "texture", "art", "design",
        "indoor", "outdoor", "closeup", "close_up", "adult", "people", "person", "scenery",
        "land", "liquid", "water_body", "waterways", "celestial_body", "celestial_body_other",
        "conveyance", "machine", "consumer_electronics", "recreation"
    ]

    /// Classifier identifiers as labels: lowercased, underscores to spaces,
    /// the generic ones and duplicates dropped, capped. Order is the
    /// classifier's, most confident first.
    static func tidyLabels(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for identifier in identifiers {
            let lowered = identifier.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lowered.isEmpty, !genericLabels.contains(lowered) else { continue }
            let label = lowered.replacingOccurrences(of: "_", with: " ")
            guard seen.insert(label).inserted else { continue }
            out.append(label)
            if out.count == maxLabels { break }
        }
        return out
    }

    // MARK: The passage

    /// What the device read, as a passage the reader prompt and the
    /// embeddings take with the thought's own words: what the picture shows,
    /// then the words in it. English framing, so the small model reads it as
    /// a description of a picture and not as the writer's words; the words
    /// themselves stay in their own language. Empty when nothing was read.
    static func context(text: String?, labels: [String]) -> String {
        var parts: [String] = []
        if !labels.isEmpty {
            parts.append("Picture of \(naturalList(labels)).")
        }
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            parts.append("Text in the picture: \(text)")
        }
        return parts.joined(separator: " ")
    }

    /// "a", "a and b", "a, b and c".
    static func naturalList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}
