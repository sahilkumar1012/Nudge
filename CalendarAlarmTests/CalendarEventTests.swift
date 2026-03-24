import XCTest
import SwiftUI
@testable import CalendarAlarm

// =============================================================================
// CalendarEventTests — Tests for CalendarEvent model computed properties.
//
// Verifies: isHappeningNow, isUpcoming, timeUntilStart,
//           formattedTime, relativeTimeString, formattedDate, Equatable
// =============================================================================

final class CalendarEventTests: XCTestCase {

    // MARK: - Test Helpers

    /// Creates a CalendarEvent with sensible defaults. Override any parameter as needed.
    private func makeEvent(
        id: String = "test-event-1",
        title: String = "Test Meeting",
        start: Date = Date(),
        end: Date = Date().addingTimeInterval(3600),
        calendarName: String = "Work",
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String? = nil
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: end,
            calendarName: calendarName,
            calendarColor: .blue,
            location: location,
            notes: notes,
            isAllDay: isAllDay
        )
    }

    // MARK: - isHappeningNow

    func testIsHappeningNow_currentEvent() {
        let event = makeEvent(
            start: Date().addingTimeInterval(-1800),  // started 30 min ago
            end: Date().addingTimeInterval(1800)       // ends in 30 min
        )
        XCTAssertTrue(event.isHappeningNow)
    }

    func testIsHappeningNow_futureEvent() {
        let event = makeEvent(
            start: Date().addingTimeInterval(3600),
            end: Date().addingTimeInterval(7200)
        )
        XCTAssertFalse(event.isHappeningNow)
    }

    func testIsHappeningNow_pastEvent() {
        let event = makeEvent(
            start: Date().addingTimeInterval(-7200),
            end: Date().addingTimeInterval(-3600)
        )
        XCTAssertFalse(event.isHappeningNow)
    }

    // MARK: - isUpcoming

    func testIsUpcoming_futureEvent() {
        let event = makeEvent(
            start: Date().addingTimeInterval(3600),
            end: Date().addingTimeInterval(7200)
        )
        XCTAssertTrue(event.isUpcoming)
    }

    func testIsUpcoming_pastEvent() {
        let event = makeEvent(
            start: Date().addingTimeInterval(-7200),
            end: Date().addingTimeInterval(-3600)
        )
        XCTAssertFalse(event.isUpcoming)
    }

    func testIsUpcoming_currentlyHappening() {
        let event = makeEvent(
            start: Date().addingTimeInterval(-60),
            end: Date().addingTimeInterval(3600)
        )
        XCTAssertFalse(event.isUpcoming, "Event that already started should not be 'upcoming'")
    }

    // MARK: - timeUntilStart

    func testTimeUntilStart_futureEvent() {
        let event = makeEvent(
            start: Date().addingTimeInterval(3600),
            end: Date().addingTimeInterval(7200)
        )
        XCTAssertTrue(event.timeUntilStart > 0)
        XCTAssertEqual(event.timeUntilStart, 3600, accuracy: 5)
    }

    func testTimeUntilStart_pastEvent() {
        let event = makeEvent(
            start: Date().addingTimeInterval(-3600),
            end: Date().addingTimeInterval(-1800)
        )
        XCTAssertTrue(event.timeUntilStart < 0)
    }

    // MARK: - formattedTime

    func testFormattedTime_allDay() {
        let event = makeEvent(isAllDay: true)
        XCTAssertEqual(event.formattedTime, "All Day")
    }

    func testFormattedTime_regularEvent() {
        let event = makeEvent(
            start: Date(),
            end: Date().addingTimeInterval(3600),
            isAllDay: false
        )
        // Should contain a dash/en-dash separator and not be "All Day"
        XCTAssertNotEqual(event.formattedTime, "All Day")
        XCTAssertTrue(event.formattedTime.contains("–"), "Expected time range with en-dash, got: \(event.formattedTime)")
    }

    // MARK: - formattedDate

    func testFormattedDate_isNonEmpty() {
        let event = makeEvent()
        XCTAssertFalse(event.formattedDate.isEmpty)
    }

    // MARK: - relativeTimeString

    func testRelativeTimeString_now() {
        let event = makeEvent(
            start: Date().addingTimeInterval(-10),
            end: Date().addingTimeInterval(3600)
        )
        XCTAssertEqual(event.relativeTimeString, "Now")
    }

    func testRelativeTimeString_lessThanMinute() {
        let event = makeEvent(
            start: Date().addingTimeInterval(30),
            end: Date().addingTimeInterval(3630)
        )
        XCTAssertEqual(event.relativeTimeString, "In less than a minute")
    }

    func testRelativeTimeString_minutes() {
        let event = makeEvent(
            start: Date().addingTimeInterval(30 * 60),
            end: Date().addingTimeInterval(90 * 60)
        )
        XCTAssertEqual(event.relativeTimeString, "In 30 mins")
    }

    func testRelativeTimeString_singleMinute() {
        let event = makeEvent(
            start: Date().addingTimeInterval(90),
            end: Date().addingTimeInterval(3690)
        )
        XCTAssertEqual(event.relativeTimeString, "In 1 min")
    }

    func testRelativeTimeString_hours() {
        let event = makeEvent(
            start: Date().addingTimeInterval(2 * 3600),
            end: Date().addingTimeInterval(3 * 3600)
        )
        XCTAssertEqual(event.relativeTimeString, "In 2 hrs")
    }

    func testRelativeTimeString_singleHour() {
        let event = makeEvent(
            start: Date().addingTimeInterval(3600),
            end: Date().addingTimeInterval(7200)
        )
        XCTAssertEqual(event.relativeTimeString, "In 1 hr")
    }

    func testRelativeTimeString_days() {
        let event = makeEvent(
            start: Date().addingTimeInterval(2 * 86400),
            end: Date().addingTimeInterval(2 * 86400 + 3600)
        )
        XCTAssertEqual(event.relativeTimeString, "In 2 days")
    }

    func testRelativeTimeString_singleDay() {
        let event = makeEvent(
            start: Date().addingTimeInterval(86400),
            end: Date().addingTimeInterval(86400 + 3600)
        )
        XCTAssertEqual(event.relativeTimeString, "In 1 day")
    }

    // MARK: - Equatable

    func testEquatable_sameId() {
        let event1 = makeEvent(id: "same-id", title: "Meeting A")
        let event2 = makeEvent(id: "same-id", title: "Meeting A")
        XCTAssertEqual(event1, event2)
    }

    func testEquatable_differentId() {
        let event1 = makeEvent(id: "id-1")
        let event2 = makeEvent(id: "id-2")
        XCTAssertNotEqual(event1, event2)
    }
}
