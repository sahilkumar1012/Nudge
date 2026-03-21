import AlarmKit
import SwiftUI
import Combine

// =============================================================================
// NotificationManager — Schedules and manages alarms using Apple's AlarmKit.
//
// FLOW:
// 1. On init, checks if AlarmKit is authorized and starts observing alarm updates
// 2. When scheduleAlarms() is called (on sync, foreground return, settings change):
//    a. Removes all existing alarms
//    b. Loops through upcoming events, skipping all-day and muted ones
//    c. For each event, schedules an AlarmKit alarm at (startTime - leadTime)
//    d. iOS handles the full alarm experience: sound, vibration, lock-screen UI
// 3. AlarmKit alarms behave like the native Clock app — they fire even in Do Not
//    Disturb, show a full-screen dismiss/snooze interface, and play alarm sound.
//
// iOS limits: max 64 pending alarms at a time.
// =============================================================================

// MARK: - Alarm Metadata
// Custom metadata attached to each alarm. AlarmKit requires this to conform
// to AlarmMetadata. We store the event ID and calendar name so we can
// identify which event an alarm belongs to.
// Must be nonisolated to satisfy AlarmMetadata protocol in Xcode 26.
nonisolated struct NudgeAlarmMetadata: AlarmMetadata {
    var eventId: String
    var calendarName: String
}

// MARK: - NotificationManager
@MainActor
class NotificationManager: ObservableObject {
    @Published var isAuthorized = false    // Whether the user has granted alarm permission
    @Published var scheduledCount = 0      // Number of currently scheduled alarms

    // User preferences (persisted via @AppStorage / UserDefaults)
    @AppStorage("alarmLeadTimeMinutes") var alarmLeadTimeMinutes: Int = 0  // How many minutes before event to fire alarm
    @AppStorage("snoozeMinutes") var snoozeMinutes: Int = 5                // How long snooze lasts

    // AlarmKit's shared manager — the system API for scheduling/cancelling alarms
    private let alarmManager = AlarmManager.shared

    // Tracks which alarms we've scheduled: eventID → AlarmKit UUID
    // We need this mapping to cancel specific alarms later
    private var scheduledAlarms: [String: UUID] = [:]

    init() {
        Task {
            await checkAuthorization()
            observeAlarmUpdates()
        }
    }

    // MARK: - Authorization
    // Check if the user has granted AlarmKit permission

    func checkAuthorization() async {
        switch alarmManager.authorizationState {
        case .authorized:
            isAuthorized = true
        case .notDetermined, .denied:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
    }

    // Request AlarmKit permission from the user.
    // If previously denied, opens iOS Settings so they can re-enable it.
    func requestAuthorization() async {
        switch alarmManager.authorizationState {
        case .notDetermined:
            do {
                let state = try await alarmManager.requestAuthorization()
                isAuthorized = state == .authorized
            } catch {
                print("AlarmKit authorization error: \(error.localizedDescription)")
                isAuthorized = false
            }
        case .authorized:
            isAuthorized = true
        case .denied:
            isAuthorized = false
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
        @unknown default:
            isAuthorized = false
        }
    }

    // MARK: - Observe Live Alarm Updates
    // Listens for changes to scheduled alarms (e.g. user dismissed one via system UI)
    // and keeps our scheduledCount in sync.

    private func observeAlarmUpdates() {
        Task {
            for await alarms in alarmManager.alarmUpdates {
                scheduledCount = alarms.count
            }
        }
    }

    // MARK: - Schedule Alarms
    // Main entry point: takes a list of calendar events and schedules an alarm for each.
    // Called after every sync, foreground return, or settings change.

    func scheduleAlarms(for events: [CalendarEvent], mutedIDs: Set<String> = []) {
        Task {
            // Clear all existing alarms first (fresh schedule each time)
            await removeAllAlarms()

            var count = 0
            for event in events {
                guard !event.isAllDay else { continue }           // Skip all-day events
                guard !mutedIDs.contains(event.id) else { continue } // Skip muted events

                // Calculate when the alarm should fire (event start minus lead time)
                let triggerDate = event.startDate.addingTimeInterval(
                    -Double(alarmLeadTimeMinutes * 60)
                )
                guard triggerDate > Date() else { continue }  // Skip events already past
                guard count < 64 else { break }               // iOS limit: 64 pending alarms

                await scheduleAlarmKitAlarm(for: event, triggerDate: triggerDate)
                count += 1
            }

            scheduledCount = count
        }
    }

    // Schedules a single AlarmKit alarm for one event.
    // This configures the full alarm experience: title, buttons, tint color,
    // snooze duration, and the exact trigger time.
    private func scheduleAlarmKitAlarm(for event: CalendarEvent, triggerDate: Date) async {
        typealias AlarmConfiguration = AlarmManager.AlarmConfiguration<NudgeAlarmMetadata>

        let alarmID = UUID()

        // Configure the alarm UI buttons shown on the lock screen
        let stopButton = AlarmButton(
            text: "Dismiss",
            textColor: .white,
            systemImageName: "xmark.circle.fill"
        )

        let snoozeButton = AlarmButton(
            text: "Snooze \(snoozeMinutes) min",
            textColor: .white,
            systemImageName: "clock.arrow.circlepath"
        )

        // The alert presentation defines what the user sees when the alarm fires
        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: event.title),
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .countdown   // Snooze button shows a countdown timer
        )

        // Alarm attributes: visual presentation + calendar-colored tint
        let attributes = AlarmAttributes<NudgeAlarmMetadata>(
            presentation: AlarmPresentation(alert: alertPresentation),
            tintColor: Color(event.calendarColor)
        )

        // Countdown durations:
        // - preAlert: countdown shown BEFORE alarm fires (nil = no pre-alarm UI)
        // - postAlert: how long snooze lasts after alarm fires
        let countdownDuration = Alarm.CountdownDuration(
            preAlert: nil,
            postAlert: TimeInterval(snoozeMinutes * 60)
        )

        // Fixed schedule: fires at exactly the calculated trigger time
        let schedule = Alarm.Schedule.fixed(triggerDate)

        let configuration = AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes
        )

        // Submit the alarm to the system
        do {
            try await alarmManager.schedule(id: alarmID, configuration: configuration)
            scheduledAlarms[event.id] = alarmID
        } catch {
            print("AlarmKit schedule error for '\(event.title)': \(error.localizedDescription)")
        }
    }

    // MARK: - Snooze
    // Reschedules a single alarm for N minutes from now (used by snooze functionality)

    func scheduleSingleAlarm(for event: CalendarEvent) {
        Task {
            let snoozeDate = Date().addingTimeInterval(Double(snoozeMinutes * 60))
            await scheduleAlarmKitAlarm(for: event, triggerDate: snoozeDate)
        }
    }

    // MARK: - Test Alarm
    // Fires a test alarm in 5 seconds so the user can preview the alarm experience.
    // Creates a dummy CalendarEvent and schedules it via the same AlarmKit path.

    func scheduleTestAlarm() {
        Task {
            let testEvent = CalendarEvent(
                id: "test_alarm_\(UUID().uuidString)",
                title: "🔔 Test Alarm",
                startDate: Date().addingTimeInterval(5),
                endDate: Date().addingTimeInterval(65),
                calendarName: "Nudge",
                calendarColor: .red,
                location: nil,
                notes: "This is a test alarm to preview the experience.",
                isAllDay: false
            )
            await scheduleAlarmKitAlarm(for: testEvent, triggerDate: Date().addingTimeInterval(5))
        }
    }

    // MARK: - Cancel
    // Cancel a specific alarm by event ID

    func cancelAlarm(for eventId: String) {
        Task {
            guard let alarmID = scheduledAlarms[eventId] else { return }
            try? await alarmManager.stop(id: alarmID)
            scheduledAlarms.removeValue(forKey: eventId)
        }
    }

    // Cancel ALL scheduled alarms (async version, used internally)
    func removeAllAlarms() async {
        for (_, alarmID) in scheduledAlarms {
            try? await alarmManager.stop(id: alarmID)
        }
        scheduledAlarms.removeAll()
        scheduledCount = 0
    }

    // Cancel ALL scheduled alarms (sync wrapper, used by UI buttons)
    func removeAllAlarms() {
        Task { await removeAllAlarms() }
    }
}
