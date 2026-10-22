import Foundation
import Observation
import UIKit

/// The one capture gesture, shared by the bar's disc and the Fast Capture
/// overlay's own: tap to start a whisper and tap Stop to keep it, or hold
/// to whisper and lift to keep it. The bar's words open the keyboard.
///
/// Both discs write the same touch state here; the overlay reads it and
/// drives the recorder. That is what lets a hold that began on the bar's
/// disc keep listening while the overlay rises under the finger.
@Observable
final class CaptureControl {
    enum Touch: Equatable {
        case up
        /// The finger has been down past the tap threshold: listening.
        case held(since: Date)
        /// Started by a tap, a press that let go before a word, or without
        /// a finger (a widget): the take runs until Stop.
        case locked
    }

    /// How long a press must last before it is a hold, not a tap.
    static let holdThreshold: Duration = .milliseconds(250)

    var touch: Touch = .up

    /// A finger is down on a disc right now. A locked take has no finger:
    /// the overlay's own Stop runs it.
    var isHeld: Bool {
        if case .held = touch { return true }
        return false
    }

    /// Bumped by a tap on the bar's words. The host opens the overlay
    /// typing-first; an open overlay focuses its field.
    private(set) var tapCount = 0
    /// Bumped by a tap on a tapped take's Stop. The overlay catches it.
    private(set) var stopCount = 0

    /// Mirrored by the overlay so every button breathes with the take.
    var isListening = false
    var level: Double = 0
    var overlayOpen = false
    /// The overlay that holds the shared state above: its request's id.
    /// An overlay lets go the moment it finishes, so one still fading out
    /// never answers the bar; the next opens at once.
    var overlayID: UUID?
    /// How much of the page's bottom edge the open composer covers, card
    /// and gap; 0 when it is closed. The page keeps a bar this tall so the
    /// system's scroll edge effect runs behind the glass.
    var composerHeight: CGFloat = 0
    /// What the composer held when a tap in open water put it away. The
    /// bar shows its first line and its disc sends; tapping the bar brings
    /// it back to the field.
    var parked: ParkedCapture?
    /// The bar's send was tapped: the overlay releases the parked draft,
    /// opening for it if it isn't up, so the toast and Undo are the same.
    var releaseParked = false
    /// The overlay is only its toast now: the bar comes back, and a tap or a
    /// hold on it starts the next capture in the same overlay.
    var toastShowing = false
    /// The bar has a place on the tab on screen (Tide). The toast sits just
    /// above it there, and in its spot on a tab without one.
    var barOnTab = true

    /// VoiceOver, Switch Control and Calm Accessibility Mode turn the hold
    /// off: the disc only taps to start and stop. The hold is an
    /// optimisation, never the only path.
    var tapToToggle = false

    func tap() { tapCount &+= 1 }
    func stop() { stopCount &+= 1 }

    @MainActor
    static var assistiveTechnologyRunning: Bool {
        UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
    }
}

/// A draft put away unsent: the words, and the pictures or a take's audio
/// riding along with them. It lives as long as the app does.
struct ParkedCapture {
    var text: String
    var images: [CaptureImage] = []
    var heldDraft: CaptureDraft?

    /// The bar's line: the words' first line, or what rides along when
    /// nothing was typed.
    var line: String {
        if let first = text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) {
            return first
        }
        if heldDraft?.audioData != nil { return String(localized: "Whisper") }
        return images.count > 1 ? String(localized: "\(images.count) images") : String(localized: "Image")
    }
}
