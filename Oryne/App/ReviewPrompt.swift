import Foundation
import StoreKit
import SwiftUI

/// The single, once-ever App Store review ask, armed only when value has just
/// landed: the 5th verified capture (capture becoming a habit), or a couple of
/// seconds after a real resurfaced thought is opened (the core promise paying
/// off). Never in the first sessions: a trigger arms the ask only once
/// `ReviewEligibility` holds (seven days since first launch, three active
/// days). Where it may appear is the root view's call: Tide or the Library,
/// nothing on screen, after two still seconds; never over Ask.
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
        static let firstLaunch = "review.firstLaunch"
        static let activeDays = "review.activeDays"
        static let lastActiveDay = "review.lastActiveDay"
    }

    /// Called whenever the app becomes active: stamps first launch and
    /// counts distinct days of use.
    func noteActive(now: Date = .now) {
        if store.object(forKey: Keys.firstLaunch) == nil {
            store.set(now, forKey: Keys.firstLaunch)
        }
        let last = store.object(forKey: Keys.lastActiveDay) as? Date
        if ReviewEligibility.isNewActiveDay(last: last, now: now) {
            store.set(store.integer(forKey: Keys.activeDays) + 1, forKey: Keys.activeDays)
            store.set(now, forKey: Keys.lastActiveDay)
        }
    }

    private var isEligible: Bool {
        ReviewEligibility.isEligible(
            firstLaunch: store.object(forKey: Keys.firstLaunch) as? Date,
            activeDays: store.integer(forKey: Keys.activeDays),
            now: .now
        )
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
        if count >= captureThreshold, isEligible { pendingRequest = true }
    }

    /// Trigger B: a resurfaced thought has been on screen long enough to land.
    func recordResurfacedOpen() {
        guard !hasRequested, isEligible else { return }
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
