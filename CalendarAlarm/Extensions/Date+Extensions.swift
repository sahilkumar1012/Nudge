import Foundation
import Combine

// =============================================================================
// Date+Extensions — Convenience helpers used throughout the app.
//
// These extensions add common date operations so we don't repeat
// the same DateFormatter/Calendar boilerplate everywhere.
// =============================================================================

extension Date {
    // Midnight at the start of this date (e.g. Mar 21 00:00:00)
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    // Midnight at the start of the NEXT day
    var endOfDay: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
    }

    // True if this date falls within today
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    // True if this date falls within tomorrow
    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(self)
    }

    // Short time string like "10:30 AM"
    var shortTimeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    // Friendly day label: "Today", "Tomorrow", or "Friday, Mar 21"
    var relativeDayString: String {
        if isToday { return "Today" }
        if isTomorrow { return "Tomorrow" }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: self)
    }
}
