import SwiftUI
import BackgroundTasks
import CoreSpotlight
import Combine

// =============================================================================
// NudgeApp — The app entry point.
//
// FLOW:
// 1. On launch: registers the background sync task and creates the two managers
// 2. Indexes the app in Spotlight with keywords like "calendar", "alarm", "meeting"
//    so it appears when users search for those terms (like Teams, Google Calendar do)
// 3. Shows ContentView which handles the permission → event list → settings flow
// 4. When the app comes to the foreground, re-fetches events and reschedules alarms
// 5. Morning background sync is scheduled if enabled in Settings
// =============================================================================

@main
struct NudgeApp: App {
    // CalendarManager: reads events from the phone's calendar
    @StateObject private var calendarManager = CalendarManager()
    // NotificationManager: schedules AlarmKit alarms for those events
    @StateObject private var notificationManager = NotificationManager()

    init() {
        // Register the background sync task with iOS (must happen before app finishes launching)
        BackgroundSyncManager.shared.registerBackgroundTask()
        // Index the app in Spotlight so it shows up when searching "calendar", "alarm", etc.
        indexInSpotlight()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(calendarManager)
                .environmentObject(notificationManager)
                .onAppear {
                    // Schedule the morning auto-sync if user has it enabled
                    BackgroundSyncManager.shared.scheduleMorningSyncIfEnabled()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Every time the app comes to the foreground, refresh events
                    // and reschedule alarms in case the calendar changed
                    calendarManager.fetchEvents()
                    notificationManager.scheduleAlarms(
                        for: calendarManager.upcomingEvents,
                        mutedIDs: calendarManager.mutedEventIDs
                    )
                }
        }
    }

    // MARK: - Spotlight Indexing
    // Registers the app with CoreSpotlight so it appears in iOS search results
    // when users type "calendar", "alarm", "meeting", "event", "nudge", etc.
    // This is the same mechanism Teams, Google Calendar, etc. use.
    private func indexInSpotlight() {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .application)
        attributeSet.displayName = "Nudge"
        attributeSet.contentDescription = "Calendar alarm app — get loud reminders for every meeting and event"
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
        item.expirationDate = .distantFuture  // Never expire from Spotlight index

        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error = error {
                print("Spotlight indexing error: \(error.localizedDescription)")
            }
        }
    }
}
