import Foundation
import Observation
import UIKit

/// The one capture gesture, shared by the floating button over the tabs and
/// the Fast Capture overlay's own button: tap to type, hold to whisper, slide
/// up to lock a long take, tap the locked button to stop.
///
/// Both buttons write the same touch state here; the overlay reads it and
/// drives the recorder. That is what lets a hold that began on the floating
/// button keep listening while the overlay rises under the finger.
@Observable
final class CaptureControl {
    enum Touch: Equatable {
        case up
        /// The finger has been down past the tap threshold: listening.
        case held(since: Date)
        /// Slid up (or started without a finger, from a widget): the take
        /// runs until Stop.
        case locked
    }

    /// How long a press must last before it is a hold, not a tap.
    static let holdThreshold: Duration = .milliseconds(250)
    /// How far up the finger slides to lock the take.
    static let lockDistance: CGFloat = 56

    var touch: Touch = .up

    /// Bumped by a short press when no take is live. The host opens the
    /// overlay typing-first; an open overlay focuses its field.
    private(set) var tapCount = 0
    /// Bumped by a tap on the locked button. The overlay catches the take.
    private(set) var stopCount = 0

    /// Mirrored by the overlay so every button breathes with the take.
    var isListening = false
    var level: Double = 0
    var overlayOpen = false
    /// The overlay is only its toast now: the bar comes back, and a tap or a
    /// hold on it starts the next capture in the same overlay.
    var toastShowing = false
    /// Reading down the Library folds the bar into its disc; heading back
    /// up, or reaching the top, unfolds it.
    var barFolded = false
    /// A thought is open in the Library: it is a page to read, so the bar
    /// (and the tab bar) step away until you go back.
    var readingThought = false

    /// VoiceOver, Switch Control and Calm Accessibility Mode make the button
    /// tap-to-start, tap-to-stop. The hold is an optimisation, never the only
    /// path.
    var tapToToggle = false

    func tap() { tapCount &+= 1 }
    func stop() { stopCount &+= 1 }

    @MainActor
    static var assistiveTechnologyRunning: Bool {
        UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
    }
}
