import BackgroundTasks
import EventKit
import UserNotifications
import SwiftUI
import Combine

// =============================================================================
// BackgroundSyncManager — Syncs calendar events automatically every morning.
//
// FLOW:
// 1. On app launch, registerBackgroundTask() is called to register with iOS
// 2. If morning sync is enabled in Settings, scheduleMorningSyncIfEnabled()
//    submits a BGAppRefreshTaskRequest for the configured time (default 7:00 AM)
// 3. When iOS wakes the app at that time, handleBackgroundSync() runs:
//    a. Fetches upcoming events from EventKit
//    b. Schedules local notifications for each event (as backup to AlarmKit)
//    c. Reschedules the NEXT morning sync
// 4. iOS controls when the task actually runs — it may be slightly delayed
//    based on device usage patterns and battery level.
//
// NOTE: This uses UNUserNotification (not AlarmKit) because background tasks
// cannot access AlarmKit's @MainActor APIs. These notifications serve as a
// fallback safety net alongside AlarmKit alarms scheduled in the foreground.
// =============================================================================

class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()
    static let taskIdentifier = "com.nudge.morningsync"

    private init() {}

    // MARK: - Registration
    // Called once at app startup to tell iOS about our background task.
    // Must be called before the app finishes launching (in NudgeApp.init).

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handleBackgroundSync(task: refreshTask)
        }
    }

    // MARK: - Schedule Next Morning Sync
    // Submits a request to iOS to wake our app at the configured morning time.
    // If sync is disabled in Settings, cancels any existing request.

    func scheduleMorningSyncIfEnabled() {
        let enabled = UserDefaults.standard.bool(forKey: "morningSyncEnabled")
        guard enabled else {
            cancelScheduledSync()
            return
        }

        // Read the configured sync time from UserDefaults (default: 7:00 AM)
        let hour = UserDefaults.standard.integer(forKey: "morningSyncHour")
        let minute = UserDefaults.standard.integer(forKey: "morningSyncMinute")
        let syncHour = (hour == 0 && minute == 0 && !UserDefaults.standard.bool(forKey: "morningSyncTimeSet")) ? 7 : hour
        let syncMinute = (hour == 0 && minute == 0 && !UserDefaults.standard.bool(forKey: "morningSyncTimeSet")) ? 0 : minute

        // Build the next sync date/time
        let now = Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = syncHour
        components.minute = syncMinute
        components.second = 0

        guard var nextSync = Calendar.current.date(from: components) else { return }

        // If the configured time already passed today, schedule for tomorrow
        if nextSync <= now {
            nextSync = Calendar.current.date(byAdding: .day, value: 1, to: nextSync)!
        }

        // Submit the background task request to iOS
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = nextSync

        do {
            try BGTaskScheduler.shared.submit(request)
            print("Morning sync scheduled for \(nextSync)")
        } catch {
            print("Failed to schedule morning sync: \(error.localizedDescription)")
        }
    }

    // Cancel any pending morning sync request
    func cancelScheduledSync() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    }

    // MARK: - Handle Background Sync
    // This runs when iOS wakes the app at the scheduled time.
    // It fetches events, schedules notification-based alarms, and queues the next sync.

    private func handleBackgroundSync(task: BGAppRefreshTask) {
        // IMPORTANT: Schedule the next sync FIRST, before doing any work.
        // If we crash or time out, at least tomorrow's sync is already queued.
        scheduleMorningSyncIfEnabled()

        let eventStore = EKEventStore()
        let status = EKEventStore.authorizationStatus(for: .event)

        // Can't do anything without calendar permission
        guard status == .authorized || status == .fullAccess else {
            task.setTaskCompleted(success: false)
            return
        }

        // iOS may kill us if we take too long — handle that gracefully
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Fetch upcoming events from the device calendar — hard cap 7 days
        let lookAheadDays = UserDefaults.standard.integer(forKey: "lookAheadDays")
        let days = min(max(lookAheadDays, 1), 7)  // Clamp between 1 and 7

        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: days, to: now)!

        let predicate = eventStore.predicateForEvents(withStart: now, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)

        // Load muted event IDs (events the user silenced)
        let mutedIDs: Set<String>
        if let saved = UserDefaults.standard.array(forKey: "mutedEventIDs") as? [String] {
            mutedIDs = Set(saved)
        } else {
            mutedIDs = []
        }

        // Clear old notifications and schedule fresh ones
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let alarmLeadTime = UserDefaults.standard.integer(forKey: "alarmLeadTimeMinutes")
        let soundEnabled = UserDefaults.standard.object(forKey: "alarmSoundEnabled") as? Bool ?? true

        // Schedule a local notification for each qualifying event
        var count = 0
        for ekEvent in events {
            guard !ekEvent.isAllDay else { continue }   // Skip all-day events

            let eventId = ekEvent.eventIdentifier ?? UUID().uuidString
            guard !mutedIDs.contains(eventId) else { continue }   // Skip muted events

            // Calculate when the notification should fire
            let startDate = ekEvent.startDate ?? now
            let triggerDate = startDate.addingTimeInterval(-Double(alarmLeadTime * 60))
            guard triggerDate > now else { continue }    // Skip past events
            guard count < 64 else { break }              // iOS limit: 64 pending notifications

            // Build the notification content
            let content = UNMutableNotificationContent()
            content.title = "🔔 \(ekEvent.title ?? "Event")"

            let formatter = DateFormatter()
            formatter.timeStyle = .short
            content.subtitle = formatter.string(from: startDate)

            var bodyParts: [String] = []
            bodyParts.append("📅 \(ekEvent.calendar?.title ?? "Calendar")")
            if let loc = ekEvent.location, !loc.isEmpty { bodyParts.append("📍 \(loc)") }
            content.body = bodyParts.joined(separator: "\n")

            content.categoryIdentifier = "ALARM_CATEGORY"
            content.userInfo = ["eventId": eventId]
            content.interruptionLevel = .timeSensitive   // Breaks through Focus modes
            if soundEnabled { content.sound = .defaultCritical }

            // Schedule the notification at the exact trigger time
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: triggerDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: "alarm_\(eventId)", content: content, trigger: trigger)
            center.add(request)

            count += 1
        }

        // Done — tell iOS the task completed successfully
        task.setTaskCompleted(success: true)
    }
}
