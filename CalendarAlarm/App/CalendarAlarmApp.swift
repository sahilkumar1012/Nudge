import SwiftUI
import BackgroundTasks
import Combine

// =============================================================================
// NudgeApp — The app entry point.
//
// FLOW:
// 1. On launch: registers the background sync task and creates the two managers
// 2. Shows ContentView which handles the permission → event list → settings flow
// 3. When the app comes to the foreground, re-fetches events and reschedules alarms
//    (because the user may have added/removed calendar events while the app was closed)
// 4. Morning background sync is scheduled if enabled in Settings
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
}
