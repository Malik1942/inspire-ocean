import Foundation

/// When the once-ever App Store rating ask may happen at all: never in the
/// first sessions. Oryne has to be part of someone's days first, at least
/// seven days since first launch and at least three distinct days of use.
/// Pure, so the rule is tested apart from StoreKit and the UI.
enum ReviewEligibility {
    static let minimumDaysSinceFirstLaunch = 7
    static let minimumActiveDays = 3

    static func isEligible(firstLaunch: Date?, activeDays: Int, now: Date) -> Bool {
        guard let firstLaunch else { return false }
        let days = now.timeIntervalSince(firstLaunch) / 86_400
        return days >= Double(minimumDaysSinceFirstLaunch) && activeDays >= minimumActiveDays
    }

    /// True when `now` falls on a different calendar day from the last
    /// recorded active day.
    static func isNewActiveDay(last: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let last else { return true }
        return !calendar.isDate(last, inSameDayAs: now)
    }
}
