import SwiftUI
import EventKit
import Combine

// =============================================================================
// CalendarEvent — The main data model for a calendar event.
//
// Each CalendarEvent represents one event from the user's phone calendar.
// It holds all the info we need: title, times, which calendar it belongs to,
// and helpers for display (formatted time strings, "happening now" checks, etc.).
//
// We create these from Apple's EKEvent objects using the static `from(ekEvent:)` method.
// =============================================================================

struct CalendarEvent: Identifiable, Equatable {
    let id: String              // Unique identifier from EventKit (or UUID if unavailable)
    let title: String           // Event title (e.g. "Team Standup")
    let startDate: Date         // When the event starts
    let endDate: Date           // When the event ends
    let calendarName: String    // Which calendar this belongs to (e.g. "Work", "Personal")
    let calendarColor: Color    // The calendar's color (used for visual indicators in the UI)
    let location: String?       // Optional event location
    let notes: String?          // Optional event notes
    let isAllDay: Bool          // Whether this is an all-day event (we skip alarms for these)

    // Shared formatters (DateFormatter is expensive to create)
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    // Returns true if the event is currently happening (we're between start and end time)
    var isHappeningNow: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }

    // Returns true if the event hasn't started yet
    var isUpcoming: Bool {
        return startDate > Date()
    }

    // Seconds until the event starts (negative if already started)
    var timeUntilStart: TimeInterval {
        return startDate.timeIntervalSinceNow
    }

    // Human-readable time range, e.g. "10:00 AM – 11:00 AM" or "All Day"
    var formattedTime: String {
        if isAllDay {
            return "All Day"
        }
        return "\(Self.timeFormatter.string(from: startDate)) – \(Self.timeFormatter.string(from: endDate))"
    }

    // Human-readable date, e.g. "Mar 21, 2026"
    var formattedDate: String {
        Self.dateFormatter.string(from: startDate)
    }

    // Friendly relative time like "In 30 mins", "In 2 hrs", "Now"
    var relativeTimeString: String {
        let interval = timeUntilStart
        if interval < 0 {
            return "Now"
        } else if interval < 60 {
            return "In less than a minute"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "In \(minutes) min\(minutes == 1 ? "" : "s")"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "In \(hours) hr\(hours == 1 ? "" : "s")"
        } else {
            let days = Int(interval / 86400)
            return "In \(days) day\(days == 1 ? "" : "s")"
        }
    }

    // Converts an Apple EventKit event (EKEvent) into our CalendarEvent model.
    // This is the bridge between Apple's calendar API and our app's data layer.
    static func from(ekEvent: EKEvent) -> CalendarEvent {
        return CalendarEvent(
            id: ekEvent.eventIdentifier ?? UUID().uuidString,
            title: ekEvent.title ?? "Untitled Event",
            startDate: ekEvent.startDate,
            endDate: ekEvent.endDate,
            calendarName: ekEvent.calendar?.title ?? "Unknown",
            calendarColor: Color(cgColor: ekEvent.calendar?.cgColor ?? UIColor.systemBlue.cgColor),
            location: ekEvent.location,
            notes: ekEvent.notes,
            isAllDay: ekEvent.isAllDay
        )
    }
}
