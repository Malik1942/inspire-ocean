import Foundation
import StoreKit
import SwiftUI

/// The single, once-ever App Store review ask, armed only when value has just
/// landed: the 5th verified capture (capture becoming a habit), or a couple of
/// seconds after a resurfaced thought is opened (the core promise paying off).
///
/// Fire-and-forget by design: the system, not the app, decides whether the sheet
/// actually appears and caps how often, so nothing here gates UI on it and the ask
/// is never on launch, on a timer, or blocking. Both triggers converge on one
/// `hasRequested` flag, so whichever comes first wins and the other never fires.
@MainActor
@Observable
final class ReviewPrompt {
    static let shared = ReviewPrompt()

    /// Capture becoming a habit: the 5th verified save arms the ask.
    private let captureThreshold = 5

    /// Watched by the root view, which owns the environment review action and does
    /// the actual firing. A value-has-landed moment flips this true.
    private(set) var pendingRequest = false

    private let store: UserDefaults

    private enum Keys {
        static let captureCount = "review.captureCount"
        static let hasRequested = "review.hasRequested"
    }

    private init(store: UserDefaults = FastCapturePreferences.defaults) {
        self.store = store
    }

    /// True once the ask has been made, regardless of whether the system showed the
    /// sheet. Read to short-circuit both triggers.
    var hasRequested: Bool { store.bool(forKey: Keys.hasRequested) }

    /// Trigger A: one verified capture, called from the single save path. Counts up
    /// and arms the ask on the fifth.
    func recordCapture() {
        guard !hasRequested else { return }
        let count = store.integer(forKey: Keys.captureCount) + 1
        store.set(count, forKey: Keys.captureCount)
        if count >= captureThreshold { pendingRequest = true }
    }

    /// Trigger B: a resurfaced thought has been on screen long enough to land.
    func recordResurfacedOpen() {
        guard !hasRequested else { return }
        pendingRequest = true
    }

    /// The one gate. Fires at most once, ever; safe to call repeatedly. `hasRequested`
    /// is set before the request, so a suppressed sheet still counts as asked.
    func fulfill(using requestReview: RequestReviewAction) {
        pendingRequest = false
        guard !hasRequested else { return }
        store.set(true, forKey: Keys.hasRequested)
        requestReview()
    }
}
