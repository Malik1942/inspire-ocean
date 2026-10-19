import Foundation

/// Which thoughts the Library's understanding backfill touches on open, and how.
///
/// The pass names untitled thoughts (branches, share-sheet captures), and
/// once per install it re-themed every thought for the semantic understanding
/// layer. That one-time pass ran on the first Library open, so it also
/// re-themed thoughts that were understood at capture, each in isolation, and
/// renamed the user's currents (observed 2026-10-19: "light and color",
/// "product ideas" and "cooking" became "thought", "quick", "melody" and
/// "creative direction"). Only a thought captured before the layer existed
/// carries keyword-era themes, so only such a thought is re-themed.
enum UnderstandingBackfill {

    /// When the semantic understanding layer replaced the keyword extractor
    /// (b3607e5, 2026-06-10 21:58:54 -0700). Every build since, and so every
    /// App Store build, themes a thought by meaning when it is captured.
    static let semanticLayerLanded = Date(timeIntervalSince1970: 1_781_153_934)

    enum Work: Equatable {
        /// An untitled thought: its title and themes, as at capture.
        case understand
        /// A keyword-era thought: new themes, its title kept.
        case retheme
    }

    /// What the pass does for one thought, or nil to leave it alone.
    /// `migrating` is true until this install's one-time re-theme has run.
    ///
    /// Examples are curated: seeded with final titles and themes, and
    /// re-localized wholesale on language change. Understanding must never
    /// retitle or re-theme them, and they carry no user-edit flags, so they
    /// are skipped here rather than protected per field.
    static func work(isExample: Bool, hasTitle: Bool, createdAt: Date, migrating: Bool) -> Work? {
        guard !isExample else { return nil }
        if !hasTitle { return .understand }
        return migrating && createdAt < semanticLayerLanded ? .retheme : nil
    }
}
