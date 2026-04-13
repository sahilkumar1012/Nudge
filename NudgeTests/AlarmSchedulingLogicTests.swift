import XCTest
import SwiftUI
@testable import Nudge

// =============================================================================
// AlarmSchedulingLogicTests — Tests for the pure scheduling logic extracted
// from NotificationManager.
//
// Verifies: buildGroupTitle, filterEligibleEvents, computeTriggerDates,
//           groupByTriggerMinute — all with zero system dependencies.
// =============================================================================

final class AlarmSchedulingLogicTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeEvent(
        id: String = UUID().uuidString,
        title: String = "Test Meeting",
        start: Date = Date().addingTimeInterval(3600),
        end: Date = Date().addingTimeInterval(7200),
        isAllDay: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: end,
            calendarName: "Work",
            calendarColor: .blue,
            location: nil,
            notes: nil,
            isAllDay: isAllDay
        )
    }

    // =========================================================================
    // MARK: - buildGroupTitle
    // =========================================================================

    func testBuildGroupTitle_empty() {
        let title = AlarmSchedulingLogic.buildGroupTitle(events: [])
        XCTAssertEqual(title, "")
    }

    func testBuildGroupTitle_singleEvent() {
        let events = [makeEvent(title: "Team Standup")]
        let title = AlarmSchedulingLogic.buildGroupTitle(events: events)
        XCTAssertEqual(title, "Team Standup")
    }

    func testBuildGroupTitle_twoEvents() {
        let events = [
            makeEvent(title: "Team Standup"),
            makeEvent(title: "Design Review")
        ]
        let title = AlarmSchedulingLogic.buildGroupTitle(events: events)
        XCTAssertEqual(title, "Team Standup & Design Review")
    }

    func testBuildGroupTitle_threeEvents() {
        let events = [
            makeEvent(title: "Team Standup"),
            makeEvent(title: "Design Review"),
            makeEvent(title: "Sprint Planning")
        ]
        let title = AlarmSchedulingLogic.buildGroupTitle(events: events)
        XCTAssertEqual(title, "Team Standup & Design Review + 1 more")
    }

    func testBuildGroupTitle_fiveEvents() {
        let events = (1...5).map { makeEvent(title: "Event \($0)") }
        let title = AlarmSchedulingLogic.buildGroupTitle(events: events)
        XCTAssertEqual(title, "Event 1 & Event 2 + 3 more")
    }

    // =========================================================================
    // MARK: - filterEligibleEvents
    // =========================================================================

    func testFilter_removesMutedEvents() {
        let e1 = makeEvent(id: "e1")
        let e2 = makeEvent(id: "e2")
        let e3 = makeEvent(id: "e3")
        let mutedIDs: Set<String> = ["e2"]

        let result = AlarmSchedulingLogic.filterEligibleEvents(
            [e1, e2, e3],
            mutedIDs: mutedIDs,
            includeAllDayEvents: true,
            maxDate: Date().addingTimeInterval(86400 * 7)
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.contains(where: { $0.id == "e2" }))
    }

    func testFilter_removesAllDayWhenDisabled() {
        let regular = makeEvent(id: "regular", isAllDay: false)
        let allDay = makeEvent(id: "allDay", isAllDay: true)

        let result = AlarmSchedulingLogic.filterEligibleEvents(
            [regular, allDay],
            mutedIDs: [],
            includeAllDayEvents: false,
            maxDate: Date().addingTimeInterval(86400 * 7)
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "regular")
    }

    func testFilter_includesAllDayWhenEnabled() {
        let regular = makeEvent(id: "regular", isAllDay: false)
        let allDay = makeEvent(id: "allDay", isAllDay: true)

        let result = AlarmSchedulingLogic.filterEligibleEvents(
            [regular, allDay],
            mutedIDs: [],
            includeAllDayEvents: true,
            maxDate: Date().addingTimeInterval(86400 * 7)
        )

        XCTAssertEqual(result.count, 2)
    }

    func testFilter_removesBeyondMaxDate() {
        let soon = makeEvent(id: "soon", start: Date().addingTimeInterval(3600))
        let far = makeEvent(id: "far", start: Date().addingTimeInterval(86400 * 30))

        let result = AlarmSchedulingLogic.filterEligibleEvents(
            [soon, far],
            mutedIDs: [],
            includeAllDayEvents: true,
            maxDate: Date().addingTimeInterval(86400 * 7)
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "soon")
    }

    func testFilter_combinedFilters() {
        let goodEvent = makeEvent(id: "good", title: "Good", start: Date().addingTimeInterval(3600), isAllDay: false)
        let mutedEvent = makeEvent(id: "muted", title: "Muted", start: Date().addingTimeInterval(3600))
        let allDayEvent = makeEvent(id: "allday", title: "AllDay", start: Date().addingTimeInterval(3600), isAllDay: true)
        let farEvent = makeEvent(id: "far", title: "Far", start: Date().addingTimeInterval(86400 * 30))

        let result = AlarmSchedulingLogic.filterEligibleEvents(
            [goodEvent, mutedEvent, allDayEvent, farEvent],
            mutedIDs: ["muted"],
            includeAllDayEvents: false,
            maxDate: Date().addingTimeInterval(86400 * 7)
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "good")
    }

    // =========================================================================
    // MARK: - computeTriggerDates
    // =========================================================================

    func testComputeTriggerDates_noLeadTime() {
        let eventStart = Date().addingTimeInterval(3600) // 1 hour from now
        let event = makeEvent(start: eventStart)

        let result = AlarmSchedulingLogic.computeTriggerDates(
            for: [event], leadTimeMinutes: 0
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first!.triggerDate, eventStart, "With 0 lead time, trigger should equal event start")
    }

    func testComputeTriggerDates_withLeadTime() {
        let eventStart = Date().addingTimeInterval(3600) // 1 hour from now
        let event = makeEvent(start: eventStart)

        let result = AlarmSchedulingLogic.computeTriggerDates(
            for: [event], leadTimeMinutes: 15
        )

        XCTAssertEqual(result.count, 1)
        let expectedTrigger = eventStart.addingTimeInterval(-15 * 60)
        XCTAssertEqual(result.first!.triggerDate.timeIntervalSince1970,
                       expectedTrigger.timeIntervalSince1970, accuracy: 1)
    }

    func testComputeTriggerDates_skipsPastTriggers() {
        let pastEvent = makeEvent(start: Date().addingTimeInterval(-60)) // already started
        let futureEvent = makeEvent(start: Date().addingTimeInterval(3600))

        let result = AlarmSchedulingLogic.computeTriggerDates(
            for: [pastEvent, futureEvent], leadTimeMinutes: 0
        )

        XCTAssertEqual(result.count, 1, "Past event should be filtered out")
    }

    func testComputeTriggerDates_allDayAt8AM() {
        // Create an all-day event for tomorrow
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let tomorrowStart = Calendar.current.startOfDay(for: tomorrow)
        let event = makeEvent(start: tomorrowStart, isAllDay: true)

        let result = AlarmSchedulingLogic.computeTriggerDates(
            for: [event], leadTimeMinutes: 0
        )

        XCTAssertEqual(result.count, 1)
        let triggerComponents = Calendar.current.dateComponents([.hour, .minute], from: result.first!.triggerDate)
        XCTAssertEqual(triggerComponents.hour, 8, "All-day events should trigger at 8 AM")
        XCTAssertEqual(triggerComponents.minute, 0)
    }

    func testComputeTriggerDates_allDayWithLeadTime() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let tomorrowStart = Calendar.current.startOfDay(for: tomorrow)
        let event = makeEvent(start: tomorrowStart, isAllDay: true)

        let result = AlarmSchedulingLogic.computeTriggerDates(
            for: [event], leadTimeMinutes: 30
        )

        XCTAssertEqual(result.count, 1)
        let triggerComponents = Calendar.current.dateComponents([.hour, .minute], from: result.first!.triggerDate)
        XCTAssertEqual(triggerComponents.hour, 7, "Should be 8 AM minus 30 min = 7:30 AM")
        XCTAssertEqual(triggerComponents.minute, 30)
    }

    // =========================================================================
    // MARK: - groupByTriggerMinute
    // =========================================================================

    func testGroupByTriggerMinute_sameMinute() {
        let baseTime = Date().addingTimeInterval(3600)
        let e1 = makeEvent(id: "e1", title: "Event 1", start: baseTime)
        let e2 = makeEvent(id: "e2", title: "Event 2", start: baseTime.addingTimeInterval(10)) // same minute

        let triggers = [
            AlarmSchedulingLogic.EventWithTrigger(event: e1, triggerDate: baseTime),
            AlarmSchedulingLogic.EventWithTrigger(event: e2, triggerDate: baseTime.addingTimeInterval(10))
        ]

        let groups = AlarmSchedulingLogic.groupByTriggerMinute(triggers)

        XCTAssertEqual(groups.count, 1, "Events in the same minute should be grouped together")
        XCTAssertEqual(groups.first!.events.count, 2)
    }

    func testGroupByTriggerMinute_differentMinutes() {
        let time1 = Date().addingTimeInterval(3600)
        let time2 = time1.addingTimeInterval(120) // 2 minutes later
        let e1 = makeEvent(id: "e1", start: time1)
        let e2 = makeEvent(id: "e2", start: time2)

        let triggers = [
            AlarmSchedulingLogic.EventWithTrigger(event: e1, triggerDate: time1),
            AlarmSchedulingLogic.EventWithTrigger(event: e2, triggerDate: time2)
        ]

        let groups = AlarmSchedulingLogic.groupByTriggerMinute(triggers)

        XCTAssertEqual(groups.count, 2, "Events in different minutes should be separate groups")
    }

    func testGroupByTriggerMinute_sortedByTime() {
        let time1 = Date().addingTimeInterval(7200) // 2 hours
        let time2 = Date().addingTimeInterval(3600) // 1 hour (earlier)
        let e1 = makeEvent(id: "e1", start: time1)
        let e2 = makeEvent(id: "e2", start: time2)

        let triggers = [
            AlarmSchedulingLogic.EventWithTrigger(event: e1, triggerDate: time1),
            AlarmSchedulingLogic.EventWithTrigger(event: e2, triggerDate: time2)
        ]

        let groups = AlarmSchedulingLogic.groupByTriggerMinute(triggers)

        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups[0].triggerDate < groups[1].triggerDate,
                       "Groups should be sorted by trigger time")
    }

    func testGroupByTriggerMinute_respectsMaxAlarms() {
        // Create 70 events at different times — should be capped at 64
        let triggers = (0..<70).map { i -> AlarmSchedulingLogic.EventWithTrigger in
            let time = Date().addingTimeInterval(Double(i * 120 + 3600))
            let event = makeEvent(id: "e\(i)", start: time)
            return AlarmSchedulingLogic.EventWithTrigger(event: event, triggerDate: time)
        }

        let groups = AlarmSchedulingLogic.groupByTriggerMinute(triggers, maxAlarms: 64)

        XCTAssertEqual(groups.count, 64, "Should cap at 64 alarms")
    }

    func testGroupByTriggerMinute_emptyInput() {
        let groups = AlarmSchedulingLogic.groupByTriggerMinute([])
        XCTAssertTrue(groups.isEmpty)
    }

    // =========================================================================
    // MARK: - Integration: filter → compute → group
    // =========================================================================

    func testFullSchedulingPipeline() {
        let now = Date()
        let events = [
            makeEvent(id: "e1", title: "Standup", start: now.addingTimeInterval(3600)),
            makeEvent(id: "e2", title: "Review", start: now.addingTimeInterval(3600 + 20)), // same minute
            makeEvent(id: "e3", title: "Lunch", start: now.addingTimeInterval(7200)),
            makeEvent(id: "muted", title: "Skip This", start: now.addingTimeInterval(3600)),
        ]

        // Step 1: Filter
        let filtered = AlarmSchedulingLogic.filterEligibleEvents(
            events, mutedIDs: ["muted"],
            includeAllDayEvents: false,
            maxDate: now.addingTimeInterval(86400 * 7)
        )
        XCTAssertEqual(filtered.count, 3)

        // Step 2: Compute triggers
        let triggers = AlarmSchedulingLogic.computeTriggerDates(
            for: filtered, leadTimeMinutes: 5, now: now
        )
        XCTAssertEqual(triggers.count, 3)

        // Step 3: Group
        let groups = AlarmSchedulingLogic.groupByTriggerMinute(triggers)
        // e1 and e2 should be grouped (same trigger minute), e3 separate
        XCTAssertEqual(groups.count, 2, "Two groups: standup+review at same time, lunch later")

        // Verify the grouped title
        let firstGroup = groups.first!
        XCTAssertEqual(firstGroup.events.count, 2)
        let title = AlarmSchedulingLogic.buildGroupTitle(events: firstGroup.events)
        XCTAssertTrue(title.contains("&"), "Two events should produce a combined title")
    }
}
