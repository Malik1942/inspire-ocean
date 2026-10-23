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
        /// A thought whose understanding record predates the current reader:
        /// category, language, gist, entities and keys filled in; its title
        /// and themes kept (docs/plans/memory-layer/SPEC.md, decision 6).
        case enrich
    }

    /// What the pass does for one thought, or nil to leave it alone.
    /// `migrating` is true until this install's one-time re-theme has run.
    ///
    /// Examples are curated: seeded with final titles and themes, and
    /// re-localized wholesale on language change. Understanding must never
    /// retitle or re-theme them, and they carry no user-edit flags, so they
    /// are skipped here rather than protected per field.
    ///
    /// `understandingVersion` is the thought's `Node.understandingVersion`;
    /// enrichment needs a model (`modelAvailable`), because the concept
    /// fallback cannot fill the record and would only be rerun on every open.
    static func work(
        isExample: Bool,
        hasTitle: Bool,
        createdAt: Date,
        migrating: Bool,
        understandingVersion: Int = ThoughtReading.version,
        modelAvailable: Bool = false
    ) -> Work? {
        guard !isExample else { return nil }
        if !hasTitle { return .understand }
        if migrating && createdAt < semanticLayerLanded { return .retheme }
        if modelAvailable && understandingVersion < ThoughtReading.version { return .enrich }
        return nil
    }

    /// How many thoughts one Library open enriches, newest first. The rest
    /// wait for the next open (and, in phase 4, the charging-time pass), so
    /// a large Ocean never pins the model for minutes at once.
    static let enrichmentPerOpen = 50

    /// How many thoughts' pictures one Library open reads (Vision, a second
    /// or two per picture), newest first; the rest wait for the next open.
    static let picturesPerOpen = 20
}
