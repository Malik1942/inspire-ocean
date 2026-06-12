import SwiftUI

/// Calm Accessibility Mode: the same Ocean, stilled.
///
/// The default experience keeps its drift and whisper-light labels. With this
/// mode on (Settings → Calm Accessibility), the water holds still, the words
/// that carry information brighten, and every touch target widens — the
/// metaphor survives, the strain doesn't. The system Reduce Motion setting
/// stills the water too, independently of this switch.
enum CalmAccessibility {
    /// App-Group-backed so every surface (and a future widget pass) agrees.
    static let key = "ocean.calmAccessibilityMode"
}

extension EnvironmentValues {
    /// True when Calm Accessibility Mode is on. Injected once at the root;
    /// views read it rather than the preference store so previews and tests
    /// can set it directly.
    @Entry var calmAccessibility: Bool = false
}
