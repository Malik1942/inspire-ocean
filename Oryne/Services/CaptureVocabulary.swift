import Foundation
import SwiftData

/// The user's own words, handed to the recognizer as contextual strings: the
/// English terms that turn up inside Chinese speech, product names, people.
/// Drawn from titles, themes and text of the user's thoughts, most frequent
/// first, capped so the recognizer treats it as a hint, not a dictionary.
enum CaptureVocabulary {
    static let limit = 80

    static func build(context: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<Node>(predicate: #Predicate { !$0.isArchived && !$0.isExample })
        guard let nodes = try? context.fetch(descriptor) else { return [] }
        return build(from: nodes.map { [$0.title, $0.text, $0.themes.joined(separator: " ")].joined(separator: " ") })
    }

    static func build(from texts: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for text in texts {
            for token in text.split(whereSeparator: { !$0.isLetter && $0 != "-" }) {
                let word = String(token)
                // Latin-script words of some length: the ones a Chinese
                // recognizer would otherwise spell by ear.
                guard word.count >= 3, word.unicodeScalars.allSatisfy({ $0.isASCII }) else { continue }
                let lower = word.lowercased()
                guard !stopwords.contains(lower) else { continue }
                counts[word, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(limit)
            .map(\.key)
    }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "that", "this", "with", "from", "have", "not", "are", "was", "but",
        "you", "your", "about", "into", "when", "what", "how", "why", "all", "one", "out", "can",
        "just", "like", "more", "than", "then", "them", "they", "there", "here", "some", "any",
        "will", "would", "should", "could", "does", "did", "has", "had", "its", "our", "who"
    ]
}
