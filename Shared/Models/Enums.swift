import Foundation

/// The kind of inspiration fragment a `Node` holds.
enum NodeKind: String, CaseIterable, Codable, Identifiable {
    case text
    case voice
    case image
    case link

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: return String(localized: "Thought")
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
