import XCTest
@testable import Nudge

// =============================================================================
// DateExtensionsTests — Tests for Date+Extensions.swift
//
// Verifies: startOfDay, endOfDay, isToday, isTomorrow,
//           shortTimeString, relativeDayString
// =============================================================================

final class DateExtensionsTests: XCTestCase {

    // MARK: - startOfDay

    func testStartOfDay_returnsMidnight() {
        // Create a date at 3:45:30 PM today
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 15
        components.minute = 45
        components.second = 30
        let date = calendar.date(from: components)!

        let start = date.startOfDay

        let startComponents = calendar.dateComponents([.hour, .minute, .second], from: start)
        XCTAssertEqual(startComponents.hour, 0)
        XCTAssertEqual(startComponents.minute, 0)
        XCTAssertEqual(startComponents.second, 0)
    }

    func testStartOfDay_sameCalendarDay() {
        let date = Date()
        let start = date.startOfDay

        XCTAssertTrue(Calendar.current.isDate(date, inSameDayAs: start))
    }

    // MARK: - endOfDay

    func testEndOfDay_isNextDayMidnight() {
        let calendar = Calendar.current
        let today = Date()
        let endOfDay = today.endOfDay

        // endOfDay should be the start of the next day
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!
        XCTAssertEqual(endOfDay, tomorrow)
    }

    func testEndOfDay_isAfterStartOfDay() {
        let date = Date()
        XCTAssertTrue(date.endOfDay > date.startOfDay)
    }

    // MARK: - isToday

    func testIsToday_nowIsTrue() {
        XCTAssertTrue(Date().isToday)
    }

    func testIsToday_yesterdayIsFalse() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertFalse(yesterday.isToday)
    }

    func testIsToday_tomorrowIsFalse() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertFalse(tomorrow.isToday)
    }

    // MARK: - isTomorrow

    func testIsTomorrow_tomorrowIsTrue() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertTrue(tomorrow.isTomorrow)
    }

    func testIsTomorrow_todayIsFalse() {
        XCTAssertFalse(Date().isTomorrow)
    }

    // MARK: - shortTimeString

    func testShortTimeString_isNonEmpty() {
        let timeString = Date().shortTimeString
        XCTAssertFalse(timeString.isEmpty)
    }

    // MARK: - relativeDayString

    func testRelativeDayString_today() {
        XCTAssertEqual(Date().relativeDayString, "Today")
    }

    func testRelativeDayString_tomorrow() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertEqual(tomorrow.relativeDayString, "Tomorrow")
    }

    func testRelativeDayString_otherDay() {
        // 3 days from now should NOT be "Today" or "Tomorrow"
        let futureDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let result = futureDate.relativeDayString
        XCTAssertNotEqual(result, "Today")
        XCTAssertNotEqual(result, "Tomorrow")
        XCTAssertFalse(result.isEmpty)
    }

    func testRelativeDayString_otherDay_containsDayName() {
        // Should contain a day name like "Monday", "Tuesday", etc.
        let futureDate = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        let result = futureDate.relativeDayString
        let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let containsDayName = dayNames.contains { result.contains($0) }
        XCTAssertTrue(containsDayName, "Expected '\(result)' to contain a day name")
    }
}
