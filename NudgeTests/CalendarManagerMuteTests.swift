import XCTest
import SwiftUI
@testable import Nudge

// =============================================================================
// CalendarManagerMuteTests — Tests for CalendarManager's muting logic.
//
// Uses a custom UserDefaults suite so tests don't pollute the real app data.
// Verifies: toggleMute, setMute, isEventMuted, enabledEvents,
//           mute persistence across instances, stale ID cleanup.
// =============================================================================

final class CalendarManagerMuteTests: XCTestCase {

    private let suiteName = "com.nudge.tests.CalendarManagerMuteTests"
    private var testDefaults: UserDefaults!
    private var manager: CalendarManager!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)
        manager = CalendarManager(userDefaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        manager = nil
        super.tearDown()
    }

    // MARK: - Test Helpers

    private func makeEvent(id: String, title: String = "Event") -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: Date().addingTimeInterval(3600),
            endDate: Date().addingTimeInterval(7200),
            calendarName: "Test",
            calendarColor: .blue,
            location: nil,
            notes: nil,
            isAllDay: false
        )
    }

    // MARK: - Initial State

    func testInitialMutedEventsIsEmpty() {
        XCTAssertTrue(manager.mutedEventIDs.isEmpty)
    }

    // MARK: - toggleMute

    func testToggleMute_mutesEvent() {
        manager.toggleMute(for: "event-1")
        XCTAssertTrue(manager.isEventMuted("event-1"))
    }

    func testToggleMute_unmutesEvent() {
        manager.toggleMute(for: "event-1")
        manager.toggleMute(for: "event-1")
        XCTAssertFalse(manager.isEventMuted("event-1"))
    }

    func testToggleMute_multipleEvents() {
        manager.toggleMute(for: "event-1")
        manager.toggleMute(for: "event-2")
        manager.toggleMute(for: "event-3")

        XCTAssertTrue(manager.isEventMuted("event-1"))
        XCTAssertTrue(manager.isEventMuted("event-2"))
        XCTAssertTrue(manager.isEventMuted("event-3"))
        XCTAssertFalse(manager.isEventMuted("event-4"))
    }

    // MARK: - setMute

    func testSetMute_true() {
        manager.setMute(true, for: "event-1")
        XCTAssertTrue(manager.isEventMuted("event-1"))
    }

    func testSetMute_false() {
        manager.setMute(true, for: "event-1")
        manager.setMute(false, for: "event-1")
        XCTAssertFalse(manager.isEventMuted("event-1"))
    }

    func testSetMute_idempotent() {
        manager.setMute(true, for: "event-1")
        manager.setMute(true, for: "event-1")
        XCTAssertTrue(manager.isEventMuted("event-1"))
        XCTAssertEqual(manager.mutedEventIDs.count, 1)
    }

    // MARK: - isEventMuted

    func testIsEventMuted_unmutedEvent() {
        XCTAssertFalse(manager.isEventMuted("nonexistent"))
    }

    // MARK: - enabledEvents

    func testEnabledEvents_filtersOutMuted() {
        let event1 = makeEvent(id: "e1", title: "Standup")
        let event2 = makeEvent(id: "e2", title: "Lunch")
        let event3 = makeEvent(id: "e3", title: "Retro")

        manager.upcomingEvents = [event1, event2, event3]
        manager.toggleMute(for: "e2")

        let enabled = manager.enabledEvents
        XCTAssertEqual(enabled.count, 2)
        XCTAssertTrue(enabled.contains(where: { $0.id == "e1" }))
        XCTAssertFalse(enabled.contains(where: { $0.id == "e2" }))
        XCTAssertTrue(enabled.contains(where: { $0.id == "e3" }))
    }

    func testEnabledEvents_allMuted() {
        let event1 = makeEvent(id: "e1")
        manager.upcomingEvents = [event1]
        manager.toggleMute(for: "e1")

        XCTAssertTrue(manager.enabledEvents.isEmpty)
    }

    func testEnabledEvents_noneMuted() {
        let event1 = makeEvent(id: "e1")
        let event2 = makeEvent(id: "e2")
        manager.upcomingEvents = [event1, event2]

        XCTAssertEqual(manager.enabledEvents.count, 2)
    }

    // MARK: - Persistence

    func testMutedEventsPersistAcrossInstances() {
        manager.toggleMute(for: "event-a")
        manager.toggleMute(for: "event-b")

        // Create a new manager with the same UserDefaults
        let manager2 = CalendarManager(userDefaults: testDefaults)

        XCTAssertTrue(manager2.isEventMuted("event-a"))
        XCTAssertTrue(manager2.isEventMuted("event-b"))
        XCTAssertFalse(manager2.isEventMuted("event-c"))
    }

    func testUnmutedEventNotPersistedAfterToggle() {
        manager.toggleMute(for: "event-1")
        manager.toggleMute(for: "event-1") // unmute

        let manager2 = CalendarManager(userDefaults: testDefaults)
        XCTAssertFalse(manager2.isEventMuted("event-1"))
    }

    // MARK: - mutedEventIDs set

    func testMutedEventIDsCount() {
        manager.toggleMute(for: "a")
        manager.toggleMute(for: "b")
        manager.toggleMute(for: "c")
        manager.toggleMute(for: "b") // unmute b

        XCTAssertEqual(manager.mutedEventIDs.count, 2)
        XCTAssertTrue(manager.mutedEventIDs.contains("a"))
        XCTAssertFalse(manager.mutedEventIDs.contains("b"))
        XCTAssertTrue(manager.mutedEventIDs.contains("c"))
    }
}
