import Foundation

/// How long a title reads, for stepping a thought's name down a size rather
/// than squeezing it (`OceanType.thoughtTitle(for:)`, 34/28/24 pt at 40 and
/// 80). A character counts by the room it takes: an East Asian wide or
/// fullwidth character, or an emoji, stands about as wide as two Latin
/// letters, so a Chinese title steps down at half the characters an English
/// one does. Pure, so `TitleLengthTests` holds it.
enum TitleLength {
    /// The title's length in Latin-letter widths: each Character counts 2
    /// when its first scalar is East Asian Wide or Fullwidth (or an emoji
    /// shown as one), otherwise 1. A letter and its combining marks are one
    /// Character, so they count once.
    static func weighted(_ text: String) -> Int {
        text.reduce(0) { length, character in length + (isWide(character) ? 2 : 1) }
    }

    private static func isWide(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        if scalar.properties.isEmojiPresentation { return true }
        return wideRanges.contains { $0.contains(scalar.value) }
    }

    /// The Unicode East Asian Wide and Fullwidth blocks a title is likely to
    /// hold: Hangul Jamo, CJK radicals through symbols and punctuation, kana
    /// and CJK compatibility, the CJK ideographs and their extension A, Yi,
    /// Hangul syllables, compatibility ideographs and forms, fullwidth forms
    /// and signs, and the supplementary ideographic planes. Halfwidth kana
    /// (U+FF61 and on) stay narrow.
    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F,
        0x2E80...0x303E,
        0x3041...0x33FF,
        0x3400...0x4DBF,
        0x4E00...0x9FFF,
        0xA000...0xA4CF,
        0xAC00...0xD7A3,
        0xF900...0xFAFF,
        0xFE30...0xFE4F,
        0xFF00...0xFF60,
        0xFFE0...0xFFE6,
        0x20000...0x2FFFD,
        0x30000...0x3FFFD
    ]
}
