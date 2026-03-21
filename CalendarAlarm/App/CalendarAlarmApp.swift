import SwiftUI
import BackgroundTasks
import CoreSpotlight
import Combine

// =============================================================================
// NudgeApp — The app entry point.
//
// FLOW:
// 1. On launch: registers the background sync task and creates the two managers
// 2. Donates NSUserActivity with keywords like "calendar", "alarm", "meeting"
//    so the app appears in Spotlight suggestions (like Teams, Google Calendar)
// 3. Shows ContentView which handles the permission → event list → settings flow
// 4. When the app comes to the foreground, re-fetches events and reschedules alarms
// 5. Morning background sync is scheduled if enabled in Settings
// =============================================================================

@main
struct NudgeApp: App {
    @StateObject private var calendarManager = CalendarManager()
    @StateObject private var notificationManager = NotificationManager()

    init() {
        BackgroundSyncManager.shared.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(calendarManager)
                .environmentObject(notificationManager)
                .onAppear {
                    BackgroundSyncManager.shared.scheduleMorningSyncIfEnabled()
                    // Donate user activities for Spotlight — this is how the app
                    // appears in the suggestions bar when you type "calendar"
                    donateSpotlightActivities()
                    indexInSpotlight()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    calendarManager.fetchEvents()
                    notificationManager.scheduleAlarms(
                        for: calendarManager.upcomingEvents,
                        mutedIDs: calendarManager.mutedEventIDs
                    )
                    // Re-donate on every foreground so Spotlight keeps ranking us
                    donateSpotlightActivities()
                }
        }
    }

    // MARK: - NSUserActivity Donation
    // This is the PRIMARY mechanism that makes the app appear in the Spotlight
    // suggestions bar (the row of app icons) when users search "calendar",
    // "alarm", "meeting", etc. — same approach Teams and Google Calendar use.
    //
    // We donate multiple activities with different titles and keyword sets
    // to maximize the chance of appearing for various search terms.
    private func donateSpotlightActivities() {
        // Activity 1: "View Calendar" — matches searches like "calendar", "events"
        let calendarActivity = NSUserActivity(activityType: "com.nudge.viewCalendar")
        calendarActivity.title = "View Calendar Events"
        calendarActivity.isEligibleForSearch = true
        calendarActivity.isEligibleForPrediction = true
        calendarActivity.persistentIdentifier = "com.nudge.viewCalendar"
        calendarActivity.keywords = Set([
            "calendar", "calendars", "events", "event",
            "schedule", "appointments", "upcoming"
        ])
        let calendarAttributes = CSSearchableItemAttributeSet(contentType: .item)
        calendarAttributes.contentDescription = "View and manage your calendar event alarms"
        calendarAttributes.displayName = "Nudge — Calendar Events"
        calendarActivity.contentAttributeSet = calendarAttributes
        calendarActivity.becomeCurrent()

        // Activity 2: "Meeting Alarm" — matches "alarm", "meeting", "reminder"
        let alarmActivity = NSUserActivity(activityType: "com.nudge.meetingAlarm")
        alarmActivity.title = "Meeting Alarm"
        alarmActivity.isEligibleForSearch = true
        alarmActivity.isEligibleForPrediction = true
        alarmActivity.persistentIdentifier = "com.nudge.meetingAlarm"
        alarmActivity.keywords = Set([
            "alarm", "alarms", "meeting", "meetings",
            "reminder", "reminders", "alert", "nudge", "notification"
        ])
        let alarmAttributes = CSSearchableItemAttributeSet(contentType: .item)
        alarmAttributes.contentDescription = "Never miss a meeting — loud alarms for every calendar event"
        alarmAttributes.displayName = "Nudge — Meeting Alarms"
        alarmActivity.contentAttributeSet = alarmAttributes
        alarmActivity.becomeCurrent()
    }

    // MARK: - CoreSpotlight Indexing (backup)
    // Also indexes the app as a searchable item for deeper content search.
    private func indexInSpotlight() {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .application)
        attributeSet.displayName = "Nudge"
        attributeSet.contentDescription = "Calendar alarm app — loud reminders for every meeting and event"
        attributeSet.keywords = [
            "calendar", "alarm", "meeting", "event", "reminder",
            "schedule", "nudge", "alert", "notification",
            "appointments", "events", "meetings", "calendar alarm"
        ]

        let item = CSSearchableItem(
            uniqueIdentifier: "com.nudge.app",
            domainIdentifier: "com.nudge",
            attributeSet: attributeSet
        )
        item.expirationDate = .distantFuture

        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error = error {
                print("Spotlight indexing error: \(error.localizedDescription)")
            }
        }
    }
}
