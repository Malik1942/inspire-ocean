import SwiftUI

/// The words of a live take, laid on the water: plain, unframed, newest at
/// the bottom, the oldest fading out above, in a six-line window that never
/// cuts the newest words. They appear as they are heard and leave in one
/// piece when the take ends. Nothing performs. They are the user's own, so
/// they are set in the serif they will wear on Tide, with room between the
/// lines; the overlay quiets the water behind them.
struct WhisperSubtitles: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let text: String
    var maxWords = 40
    /// A language without spaces (Chinese) is one long word: of the last
    /// `maxWords`, at most this many characters are kept.
    var maxCharacters = 240
    /// "Listening" while waiting for the first word; off when no live words
    /// are coming and while the words settle.
    var showsPlaceholder = true

    /// The window's height, in lines of the words at the current text size.
    private static let windowLines = 6
    /// The most of the screen the window takes, at the largest text sizes,
    /// where six lines would leave the page no room.
    private static let windowShare: CGFloat = 0.45

    private var tail: String {
        let words = text.split(whereSeparator: \.isWhitespace).suffix(maxWords).joined(separator: " ")
        return String(words.suffix(maxCharacters))
    }

    var body: some View {
        let window = OceanType.whisperWords.height(ofLines: Self.windowLines, at: typeSize)
        Group {
            if tail.isEmpty {
                if showsPlaceholder {
                    Text("Listening")
                        .oceanText(OceanType.statement)
                        .foregroundStyle(OceanTheme.mist)
                }
            } else {
                Text(tail)
                    .oceanText(OceanType.whisperWords)
                    .foregroundStyle(OceanTheme.foam)
                    .multilineTextAlignment(.leading)
                    // Its whole height, standing up out of the window: the
                    // window cuts the oldest words, never the newest.
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(OceanMotion.touch, value: tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One height for the whole take, the words at its foot, so a short
        // take sits under the mask's opaque part.
        .containerRelativeFrame(.vertical, alignment: .bottomLeading) { length, _ in
            min(window, length * Self.windowShare)
        }
        .clipped()
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.3), .init(color: .black, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .oceanShadow(OceanShadow.text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.isEmpty ? Text("Listening") : Text(text))
    }
}
