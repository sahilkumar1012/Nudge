import SwiftUI
import BackgroundTasks
import Combine

@main
struct CalendarAlarmApp: App {
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
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    calendarManager.fetchEvents()
                    notificationManager.scheduleAlarms(
                        for: calendarManager.upcomingEvents,
                        mutedIDs: calendarManager.mutedEventIDs
                    )
                }
        }
    }
}
