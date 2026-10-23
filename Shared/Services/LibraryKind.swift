import Foundation

/// The Library's one filter: every thought, or one kind of them. It asks
/// what a thought holds rather than how it was made, so a link pasted into
/// a typed thought (a `.text` node carrying a URL) counts as a link, and a
/// thought with a picture as an image. A thought can hold two kinds at
/// once (a whisper with a photo); Text is what holds neither.
enum LibraryKind: String, CaseIterable, Identifiable, Sendable {
    case all
    case text
    case voice
    case image
    case link

    var id: String { rawValue }

    /// The filter's name, in the plural where the kind has one.
    var label: String {
        switch self {
        case .all: return String(localized: "All")
        case .text: return NodeKind.text.label
        case .voice: return String(localized: "Whispers")
        case .image: return String(localized: "Images")
        case .link: return String(localized: "Links")
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return NodeKind.text.symbol
        case .voice: return NodeKind.voice.symbol
        case .image: return NodeKind.image.symbol
        case .link: return NodeKind.link.symbol
        }
    }

    /// Whether the filter keeps this thought. The image relationship is
    /// only walked when the answer depends on it.
    func admits(_ node: Node) -> Bool {
        switch self {
        case .all: return true
        case .voice: return node.kind == .voice
        case .link: return node.kind == .link || node.linkURL != nil
        case .image: return node.kind == .image || node.hasImages
        case .text: return node.kind == .text && node.linkURL == nil && !node.hasImages
        }
    }
}
