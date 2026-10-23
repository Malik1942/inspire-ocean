import Foundation

/// The kind of inspiration fragment a `Node` holds.
enum NodeKind: String, CaseIterable, Codable, Identifiable {
    case text
    case voice
    case image
    case link

    var id: String { rawValue }

    /// The kind by name. A typed thought is "Text": "Thought" is the app's
    /// word for every kind, so it can't also name one of them.
    var label: String {
        switch self {
        case .text: return String(localized: "kind.text", defaultValue: "Text")
        case .voice: return String(localized: "Whisper")
        case .image: return String(localized: "Image")
        case .link: return String(localized: "Link")
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .voice: return "waveform"
        case .image: return "photo"
        case .link: return "link"
        }
    }
}

/// Branching grows new ideas from existing fragments rather than editing them.
enum BranchType: String, CaseIterable, Codable, Identifiable {
    case question
    case concept
    case research
    case project

    var id: String { rawValue }

    var label: String {
        switch self {
        case .question: return String(localized: "Question")
        case .concept: return String(localized: "Concept")
        case .research: return String(localized: "Research")
        case .project: return String(localized: "Project")
        }
    }

    var symbol: String {
        switch self {
        case .question: return "questionmark.bubble"
        case .concept: return "lightbulb"
        case .research: return "magnifyingglass"
        case .project: return "hammer"
        }
    }

    var prompt: String {
        switch self {
        case .question: return String(localized: "What question does this open up?")
        case .concept: return String(localized: "What concept could grow from this?")
        case .research: return String(localized: "What would you want to research?")
        case .project: return String(localized: "What could this become?")
        }
    }
}

/// Conversational modes for Ocean Dialogue.
enum DialogueMode: String, CaseIterable, Identifiable {
    case search
    case synthesis
    case expansion
    case research

    var id: String { rawValue }

    var label: String {
        switch self {
        case .search: return String(localized: "Search")
        case .synthesis: return String(localized: "Synthesis")
        case .expansion: return String(localized: "Expansion")
        case .research: return String(localized: "Research")
        }
    }

    var symbol: String {
        switch self {
        case .search: return "sparkle.magnifyingglass"
        case .synthesis: return "circle.hexagongrid"
        case .expansion: return "arrow.up.left.and.arrow.down.right"
        case .research: return "books.vertical"
        }
    }

    var placeholder: String {
        switch self {
        case .search: return String(localized: "Find a fragment in the Ocean…")
        case .synthesis: return String(localized: "What patterns are forming?")
        case .expansion: return String(localized: "Help me grow an idea…")
        case .research: return String(localized: "What should I explore next?")
        }
    }

    /// One whispered line naming the cognitive lens — shown under the mode
    /// picker so each mode reads as a different way of looking, not a tone.
    var lens: String {
        switch self {
        case .search: return String(localized: "Find what you've captured")
        case .synthesis: return String(localized: "See the thread running through")
        case .expansion: return String(localized: "Grow it somewhere unexpected")
        case .research: return String(localized: "Look beyond your Ocean")
        }
    }

    /// The working beat shown while the Ocean is read — each lens works
    /// differently, so each waits differently.
    var searching: String {
        switch self {
        case .search: return String(localized: "Searching your Ocean…")
        case .synthesis: return String(localized: "Reading across your currents…")
        case .expansion: return String(localized: "Drifting out from your thought…")
        case .research: return String(localized: "Reading your Ocean, then looking beyond…")
        }
    }
}

enum MessageRole: String, Codable {
    case user
    case ocean
}

/// What kind of thought this is, as read by the understanding step. Fixed,
/// so Ask can list and filter by it and the model can only choose, never
/// invent (docs/plans/memory-layer/SPEC.md, layer 1).
enum ThoughtCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case idea
    case task
    case bug
    case note
    case quote
    case question
    case link
    case memory

    var id: String { rawValue }

    var label: String {
        switch self {
        case .idea: return String(localized: "category.idea", defaultValue: "Idea")
        case .task: return String(localized: "category.task", defaultValue: "Task")
        case .bug: return String(localized: "category.bug", defaultValue: "Bug")
        case .note: return String(localized: "category.note", defaultValue: "Note")
        case .quote: return String(localized: "category.quote", defaultValue: "Quote")
        case .question: return String(localized: "category.question", defaultValue: "Question")
        case .link: return String(localized: "category.link", defaultValue: "Link")
        case .memory: return String(localized: "category.memory", defaultValue: "Memory")
        }
    }

    var symbol: String {
        switch self {
        case .idea: return "lightbulb"
        case .task: return "checkmark.circle"
        case .bug: return "ant"
        case .note: return "note.text"
        case .quote: return "quote.opening"
        case .question: return "questionmark.circle"
        case .link: return "link"
        case .memory: return "clock.arrow.circlepath"
        }
    }
}

/// The language a thought is written in, by the share of Han among its
/// letters (`ThoughtReading.language(of:)`). Retrieval and the gist in the
/// other language hang off this.
enum ThoughtLanguage: String, Codable, Sendable {
    case zh
    case en
    case mixed
}

/// Where a task or bug stands. Only the user sets it; the system reads it.
enum ThoughtStatus: String, Codable, Sendable {
    case open
    case done
}

/// Which pass produced a thought's understanding record.
enum UnderstandingSource: String, Codable, Sendable {
    /// The on-device (or cloud) language model read the thought.
    case model
    /// The concept-space fallback: embeddings and heuristics, no model.
    case concepts
}

extension NodeKind {
    /// What a captured thought is, from what it holds: a recording makes a
    /// whisper and words a thought; with neither, its pictures name it, then
    /// its link. The kind follows what happened, never a choice.
    static func captured(voice: Bool, words: String, images: Int, link: Bool) -> NodeKind {
        if voice { return .voice }
        if !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .text }
        if images > 0 { return .image }
        if link { return .link }
        return .text
    }
}
