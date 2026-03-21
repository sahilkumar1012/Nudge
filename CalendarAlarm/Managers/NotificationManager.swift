import AlarmKit
import SwiftUI
import Combine

// MARK: - Alarm Metadata
// Must be nonisolated to satisfy AlarmMetadata protocol in Xcode 26
nonisolated struct CalendarAlarmMetadata: AlarmMetadata {
    var eventId: String
    var calendarName: String
}

// MARK: - NotificationManager (AlarmKit)
@MainActor
class NotificationManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var scheduledCount = 0

    @AppStorage("alarmLeadTimeMinutes") var alarmLeadTimeMinutes: Int = 0
    @AppStorage("snoozeMinutes") var snoozeMinutes: Int = 5

    private let alarmManager = AlarmManager.shared

    // Map event ID → AlarmKit UUID for cancellation
    private var scheduledAlarms: [String: UUID] = [:]

    init() {
        Task {
            await checkAuthorization()
            observeAlarmUpdates()
        }
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
            // Send user to Settings if previously denied
            isAuthorized = false
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
        @unknown default:
            isAuthorized = false
        }
    }

    // MARK: - Observe live alarm updates

    private func observeAlarmUpdates() {
        Task {
            for await alarms in alarmManager.alarmUpdates {
                scheduledCount = alarms.count
            }
        }
    }

    // MARK: - Schedule Alarms

    func scheduleAlarms(for events: [CalendarEvent], mutedIDs: Set<String> = []) {
        Task {
            await removeAllAlarms()

            var count = 0
            for event in events {
                guard !event.isAllDay else { continue }
                guard !mutedIDs.contains(event.id) else { continue }

                let triggerDate = event.startDate.addingTimeInterval(
                    -Double(alarmLeadTimeMinutes * 60)
                )
                guard triggerDate > Date() else { continue }
                guard count < 64 else { break }

                await scheduleAlarmKitAlarm(for: event, triggerDate: triggerDate)
                count += 1
            }

            scheduledCount = count
        }
    }

    private func scheduleAlarmKitAlarm(for event: CalendarEvent, triggerDate: Date) async {
        // Use typealias as shown in Apple's WWDC session
        typealias AlarmConfiguration = AlarmManager.AlarmConfiguration<CalendarAlarmMetadata>

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
            title: LocalizedStringResource(stringLiteral: event.title),
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .countdown
        )

        // AlarmAttributes is generic — must specify metadata type explicitly
        let attributes = AlarmAttributes<CalendarAlarmMetadata>(
            presentation: AlarmPresentation(alert: alertPresentation),
            tintColor: Color(event.calendarColor)
        )

        // preAlert: countdown shown before alarm fires (nil = no pre-alarm countdown UI)
        // postAlert: snooze window duration after alarm fires
        let countdownDuration = Alarm.CountdownDuration(
            preAlert: nil,
            postAlert: TimeInterval(snoozeMinutes * 60)
        )

        // Fixed schedule — fires at exact calendar event time
        let schedule = Alarm.Schedule.fixed(triggerDate)

        let configuration = AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes
        )

        do {
            try await alarmManager.schedule(id: alarmID, configuration: configuration)
            scheduledAlarms[event.id] = alarmID
        } catch {
            print("AlarmKit schedule error for '\(event.title)': \(error.localizedDescription)")
        }
    }

    // MARK: - Snooze

    func scheduleSingleAlarm(for event: CalendarEvent) {
        Task {
            let snoozeDate = Date().addingTimeInterval(Double(snoozeMinutes * 60))
            await scheduleAlarmKitAlarm(for: event, triggerDate: snoozeDate)
        }
    }

    // MARK: - Test Alarm

    func scheduleTestAlarm() {
        Task {
            let testEvent = CalendarEvent(
                id: "test_alarm_\(UUID().uuidString)",
                title: "🔔 Test Alarm",
                startDate: Date().addingTimeInterval(5), // fires in 5 seconds
                endDate: Date().addingTimeInterval(65),
                calendarName: "Calendar Alarm",
                calendarColor: .red,
                location: nil,
                notes: "This is a test alarm to preview the experience.",
                isAllDay: false
            )
            await scheduleAlarmKitAlarm(for: testEvent, triggerDate: Date().addingTimeInterval(5))
        }
    }

    // MARK: - Cancel

    func cancelAlarm(for eventId: String) {
        Task {
            guard let alarmID = scheduledAlarms[eventId] else { return }
            try? await alarmManager.stop(id: alarmID)
            scheduledAlarms.removeValue(forKey: eventId)
        }
    }

    func removeAllAlarms() async {
        for (_, alarmID) in scheduledAlarms {
            try? await alarmManager.stop(id: alarmID)
        }
        scheduledAlarms.removeAll()
        scheduledCount = 0
    }

    // Sync wrapper for UI buttons
    func removeAllAlarms() {
        Task { await removeAllAlarms() }
    }
}
