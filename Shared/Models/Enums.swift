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
        case .text: return "Thought"
        case .voice: return "Whisper"
        case .image: return "Image"
        case .link: return "Link"
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
        case .question: return "Question"
        case .concept: return "Concept"
        case .research: return "Research"
        case .project: return "Project"
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
        case .question: return "What question does this open up?"
        case .concept: return "What concept could grow from this?"
        case .research: return "What would you want to research?"
        case .project: return "What could this become?"
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
        case .search: return "Search"
        case .synthesis: return "Synthesis"
        case .expansion: return "Expansion"
        case .research: return "Research"
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
        case .search: return "Find a fragment in the Ocean…"
        case .synthesis: return "What patterns are forming?"
        case .expansion: return "Help me grow an idea…"
        case .research: return "What should I explore next?"
        }
    }

    /// One whispered line naming the cognitive lens — shown under the mode
    /// picker so each mode reads as a different way of looking, not a tone.
    var lens: String {
        switch self {
        case .search: return "Find what you've captured"
        case .synthesis: return "See the thread running through"
        case .expansion: return "Grow it somewhere unexpected"
        case .research: return "Look beyond your Ocean"
        }
    }

    /// The working beat shown while the Ocean is read — each lens works
    /// differently, so each waits differently.
    var searching: String {
        switch self {
        case .search: return "Searching your Ocean…"
        case .synthesis: return "Reading across your currents…"
        case .expansion: return "Drifting out from your thought…"
        case .research: return "Reading your Ocean, then looking beyond…"
        }
    }
}

enum MessageRole: String, Codable {
    case user
    case ocean
}
