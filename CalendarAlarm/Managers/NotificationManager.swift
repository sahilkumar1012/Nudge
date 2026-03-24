import AlarmKit
import SwiftUI
import UserNotifications
import Combine

// =============================================================================
// NotificationManager — Schedules and manages alarms using Apple's AlarmKit.
//
// FLOW:
// 1. On init, checks if AlarmKit is authorized and starts observing alarm updates
// 2. When scheduleAlarms() is called (on sync, foreground return, settings change):
//    a. Cancels ALL existing alarms (both in-memory and persisted IDs)
//    b. Groups events by trigger time — events starting at the same minute
//       are merged into ONE alarm (max 2 event names shown)
//    c. Schedules one AlarmKit alarm per unique trigger time
//    d. Persists alarm IDs to UserDefaults so they survive app restarts
// 3. AlarmKit alarms behave like the native Clock app — they fire even in Do Not
//    Disturb, show a full-screen dismiss/snooze interface, and play alarm sound.
//
// BUG FIXES:
// - Alarm IDs are persisted in UserDefaults so removeAllAlarms() works after restart
// - Events at the same time are grouped into a single alarm (no alarm spam)
// - A scheduling lock prevents double-scheduling from rapid sync taps
// - Hard cap of 7 days look-ahead regardless of settings
//
// iOS limits: max 64 pending alarms at a time.
// =============================================================================

// MARK: - Alarm Metadata
// Custom metadata attached to each alarm so we can identify what it's for.
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
    @AppStorage("alarmLeadTimeMinutes") var alarmLeadTimeMinutes: Int = 0  // Minutes before event to fire
    @AppStorage("snoozeMinutes") var snoozeMinutes: Int = 5                // Snooze duration
    @AppStorage("includeAllDayEvents") var includeAllDayEvents: Bool = false

    // AlarmKit's shared manager — the system API for scheduling/cancelling alarms
    private let alarmManager = AlarmManager.shared

    // In-memory map: a key (eventID or group key) → AlarmKit UUID
    private var scheduledAlarms: [String: UUID] = [:]

    // UserDefaults key for persisting alarm UUIDs across app restarts
    private static let persistedAlarmsKey = "persistedAlarmUUIDs"

    // Prevents double-scheduling if sync is tapped rapidly
    private var isScheduling = false

    init() {
        // Load alarm IDs from previous session so we can cancel them
        loadPersistedAlarmIDs()
        Task {
            await checkAuthorization()
            observeAlarmUpdates()
        }
    }

    // MARK: - Persist Alarm IDs
    // Save/load alarm UUIDs to UserDefaults so we can cancel them even after app restart.

    private func loadPersistedAlarmIDs() {
        guard let saved = UserDefaults.standard.dictionary(forKey: Self.persistedAlarmsKey) as? [String: String] else { return }
        for (key, uuidString) in saved {
            if let uuid = UUID(uuidString: uuidString) {
                scheduledAlarms[key] = uuid
            }
        }
    }

    private func persistAlarmIDs() {
        let toSave = scheduledAlarms.mapValues { $0.uuidString }
        UserDefaults.standard.set(toSave, forKey: Self.persistedAlarmsKey)
    }

    private func clearPersistedAlarmIDs() {
        UserDefaults.standard.removeObject(forKey: Self.persistedAlarmsKey)
    }

    // MARK: - Authorization

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

    // Request AlarmKit permission. If denied, opens iOS Settings.
    // Also requests UNUserNotification auth for background sync fallback.
    func requestAuthorization() async {
        // Request UNUserNotification authorization (needed for background sync notifications)
        let center = UNUserNotificationCenter.current()
        try? await center.requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])

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
    // Keeps scheduledCount in sync when user dismisses alarms via system UI.

    private func observeAlarmUpdates() {
        Task {
            for await alarms in alarmManager.alarmUpdates {
                scheduledCount = alarms.count
            }
        }
    }

    // MARK: - Schedule Alarms (Main Entry Point)
    // Takes a list of calendar events, groups by trigger time, and schedules
    // ONE alarm per unique trigger minute. This is the fix for alarm spam.

    func scheduleAlarms(for events: [CalendarEvent], mutedIDs: Set<String> = []) {
        // Prevent double-scheduling from rapid taps
        guard !isScheduling else { return }
        isScheduling = true

        Task {
            // Step 1: Cancel ALL existing alarms (clean slate every time)
            await removeAllAlarms()

            // Step 2: Filter events — skip all-day, muted, and past events
            // Hard cap at 7 days regardless of lookAheadDays setting
            let maxDate = Date().addingTimeInterval(7 * 24 * 60 * 60)
            let eligibleEvents = events.filter { event in
                (includeAllDayEvents || !event.isAllDay)
                && !mutedIDs.contains(event.id)
                && event.startDate <= maxDate
            }

            // Step 3: Calculate trigger date for each event
            let leadSeconds = Double(alarmLeadTimeMinutes * 60)
            let now = Date()

            struct EventWithTrigger {
                let event: CalendarEvent
                let triggerDate: Date
            }

            let eventsWithTriggers = eligibleEvents.compactMap { event -> EventWithTrigger? in
                var effectiveStart = event.startDate
                // All-day events start at midnight — fire alarm at 8 AM instead
                if event.isAllDay {
                    if let morning = Foundation.Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: event.startDate) {
                        effectiveStart = morning
                    }
                }
                let trigger = effectiveStart.addingTimeInterval(-leadSeconds)
                guard trigger > now else { return nil }  // Skip past triggers
                return EventWithTrigger(event: event, triggerDate: trigger)
            }

            // Step 4: Group events by trigger minute (events within the same minute = 1 alarm)
            // This prevents 5 alarms firing simultaneously for overlapping meetings
            let grouped = Dictionary(grouping: eventsWithTriggers) { item -> String in
                let components = Foundation.Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: item.triggerDate
                )
                return "\(components.year!)-\(components.month!)-\(components.day!)-\(components.hour!)-\(components.minute!)"
            }

            // Step 5: Schedule one alarm per group
            var count = 0
            for (groupKey, group) in grouped.sorted(by: { $0.value.first!.triggerDate < $1.value.first!.triggerDate }) {
                guard count < 64 else { break }  // iOS limit: 64 pending alarms

                // Build a combined title showing up to 2 event names
                let title = buildGroupTitle(events: group.map { $0.event })
                let triggerDate = group.first!.triggerDate
                let firstEvent = group.first!.event

                await scheduleAlarmKitAlarm(
                    key: groupKey,
                    title: title,
                    tintColor: firstEvent.calendarColor,
                    calendarName: firstEvent.calendarName,
                    triggerDate: triggerDate
                )
                count += 1
            }

            // Step 6: Persist alarm IDs and update count
            persistAlarmIDs()
            scheduledCount = count
            isScheduling = false
        }
    }

    // Builds a combined title for grouped events:
    // 1 event:  "Team Standup"
    // 2 events: "Team Standup & Design Review"
    // 3+ events: "Team Standup & Design Review + 1 more"
    private func buildGroupTitle(events: [CalendarEvent]) -> String {
        switch events.count {
        case 1:
            return events[0].title
        case 2:
            return "\(events[0].title) & \(events[1].title)"
        default:
            let extra = events.count - 2
            return "\(events[0].title) & \(events[1].title) + \(extra) more"
        }
    }

    // Schedules a single AlarmKit alarm with the given title and trigger time.
    private func scheduleAlarmKitAlarm(
        key: String,
        title: String,
        tintColor: Color,
        calendarName: String,
        triggerDate: Date
    ) async {
        typealias AlarmConfiguration = AlarmManager.AlarmConfiguration<NudgeAlarmMetadata>

        let alarmID = UUID()

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

        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .countdown
        )

        let attributes = AlarmAttributes<NudgeAlarmMetadata>(
            presentation: AlarmPresentation(alert: alertPresentation),
            tintColor: tintColor
        )

        let countdownDuration = Alarm.CountdownDuration(
            preAlert: nil,
            postAlert: TimeInterval(snoozeMinutes * 60)
        )

        let schedule = Alarm.Schedule.fixed(triggerDate)

        let configuration = AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes
        )

        do {
            try await alarmManager.schedule(id: alarmID, configuration: configuration)
            scheduledAlarms[key] = alarmID
        } catch {
            print("AlarmKit schedule error for '\(title)': \(error.localizedDescription)")
        }
    }

    // MARK: - Snooze

    func scheduleSingleAlarm(for event: CalendarEvent) {
        Task {
            let snoozeDate = Date().addingTimeInterval(Double(snoozeMinutes * 60))
            await scheduleAlarmKitAlarm(
                key: "snooze_\(event.id)",
                title: event.title,
                tintColor: event.calendarColor,
                calendarName: event.calendarName,
                triggerDate: snoozeDate
            )
            persistAlarmIDs()
        }
    }

    // MARK: - Test Alarm
    // Fires a test alarm in 5 seconds to preview the experience.

    func scheduleTestAlarm() {
        Task {
            await scheduleAlarmKitAlarm(
                key: "test_\(UUID().uuidString)",
                title: "🔔 Test Alarm",
                tintColor: .red,
                calendarName: "Nudge",
                triggerDate: Date().addingTimeInterval(5)
            )
            persistAlarmIDs()
        }
    }

    // MARK: - Cancel

    func cancelAlarm(for eventId: String) {
        Task {
            guard let alarmID = scheduledAlarms[eventId] else { return }
            try? await alarmManager.stop(id: alarmID)
            scheduledAlarms.removeValue(forKey: eventId)
            persistAlarmIDs()
        }
    }

    // Cancel ALL scheduled alarms — including orphaned alarms from previous sessions
    // that we may not have in our tracking dictionary.
    // Reads the current alarm list directly from AlarmKit and cancels everything.
    func removeAllAlarms() async {
        // First: cancel everything in our tracking dictionary
        for (_, alarmID) in scheduledAlarms {
            try? await alarmManager.stop(id: alarmID)
        }

        // Second: cancel ANY orphaned alarms we don't know about.
        // Use a timeout to prevent hanging if alarmUpdates doesn't emit.
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await currentAlarms in self.alarmManager.alarmUpdates {
                    for alarm in currentAlarms {
                        try? await self.alarmManager.stop(id: alarm.id)
                    }
                    break  // Read one snapshot only
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 second timeout
            }
            // Return as soon as either task completes
            await group.next()
            group.cancelAll()
        }

        scheduledAlarms.removeAll()
        clearPersistedAlarmIDs()
        scheduledCount = 0
    }

    // Sync wrapper for UI buttons (e.g. "Remove All Alarms" in Settings)
    func removeAllAlarms() {
        Task { await removeAllAlarms() }
    }
}
