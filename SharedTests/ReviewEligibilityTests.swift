import XCTest
import Foundation

/// The rating ask waits until Oryne is part of someone's days: at least
/// seven days since first launch and at least three distinct active days.
final class ReviewEligibilityTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testFirstDayIsNeverEligible() {
        XCTAssertFalse(ReviewEligibility.isEligible(firstLaunch: start, activeDays: 1, now: start))
    }

    func testManyDaysButFewVisitsIsNotEligible() {
        XCTAssertFalse(ReviewEligibility.isEligible(firstLaunch: start, activeDays: 2, now: start + 30 * day))
    }

    func testManyVisitsInTheFirstWeekIsNotEligible() {
        XCTAssertFalse(ReviewEligibility.isEligible(firstLaunch: start, activeDays: 5, now: start + 6 * day))
    }

    func testSevenDaysAndThreeVisitsIsEligible() {
        XCTAssertTrue(ReviewEligibility.isEligible(firstLaunch: start, activeDays: 3, now: start + 7 * day))
    }

    func testMissingFirstLaunchIsNotEligible() {
        XCTAssertFalse(ReviewEligibility.isEligible(firstLaunch: nil, activeDays: 10, now: start))
    }

    func testActiveDayCountsOnlyNewDays() {
        let cal = Calendar(identifier: .gregorian)
        let morning = start
        let evening = start + 3600 * 8
        let tomorrow = start + day
        XCTAssertFalse(ReviewEligibility.isNewActiveDay(last: morning, now: evening, calendar: cal))
        XCTAssertTrue(ReviewEligibility.isNewActiveDay(last: morning, now: tomorrow, calendar: cal))
        XCTAssertTrue(ReviewEligibility.isNewActiveDay(last: nil, now: morning, calendar: cal))
    }
}
