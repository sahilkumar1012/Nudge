import SwiftUI
import Combine
import StoreKit

// =============================================================================
// SettingsView — The settings screen, accessible via the gear icon.
//
// Sections:
// 1. Alarm Settings — lead time (how early to fire), snooze duration, all-day toggle
// 2. Calendar — how many days ahead to look for events
// 3. Morning Sync — enable/disable daily auto-sync and configure the time
// 4. Status — shows current alarm count and permission status
// 5. Actions — test alarm, refresh, and remove all alarms
// 6. About — app version
// =============================================================================

struct SettingsView: View {
    @EnvironmentObject var calendarManager: CalendarManager
    @EnvironmentObject var notificationManager: NotificationManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.requestReview) var requestReview

    @AppStorage("lookAheadDays") private var lookAheadDays: Int = 7
    @AppStorage("alarmLeadTimeMinutes") private var alarmLeadTimeMinutes: Int = 0
    @AppStorage("snoozeMinutes") private var snoozeMinutes: Int = 5
    @AppStorage("includeAllDayEvents") private var includeAllDayEvents: Bool = false
    @AppStorage("morningSyncEnabled") private var morningSyncEnabled: Bool = false

    @State private var showRemoveConfirmation = false
    @State private var showRemovedAlert = false

    @State private var morningSyncTime: Date = {
        let hour = UserDefaults.standard.integer(forKey: "morningSyncHour")
        let minute = UserDefaults.standard.integer(forKey: "morningSyncMinute")
        let hasSet = UserDefaults.standard.bool(forKey: "morningSyncTimeSet")
        var components = DateComponents()
        components.hour = hasSet ? hour : 7
        components.minute = hasSet ? minute : 0
        return Calendar.current.date(from: components) ?? Date()
    }()

    var body: some View {
        NavigationStack {
            List {
                // Alarm Settings
                Section {
                    Picker("Alert Before Event", selection: $alarmLeadTimeMinutes) {
                        Text("At event time").tag(0)
                        Text("1 minute before").tag(1)
                        Text("5 minutes before").tag(5)
                        Text("10 minutes before").tag(10)
                        Text("15 minutes before").tag(15)
                        Text("30 minutes before").tag(30)
                    }

                    Picker("Snooze Duration", selection: $snoozeMinutes) {
                        Text("1 minute").tag(1)
                        Text("3 minutes").tag(3)
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("15 minutes").tag(15)
                    }

                    Toggle("Include All-Day Events", isOn: $includeAllDayEvents)
                } header: {
                    Label("Alarm Settings", systemImage: "bell.fill")
                } footer: {
                    Text("Alarms use Apple's default ringtone sound. Make sure your iPhone is not on silent.")
                }

                // Calendar Settings
                Section {
                    Picker("Look Ahead", selection: $lookAheadDays) {
                        Text("1 day").tag(1)
                        Text("3 days").tag(3)
                        Text("7 days").tag(7)
                    }
                } header: {
                    Label("Calendar", systemImage: "calendar")
                } footer: {
                    Text("How far ahead to look for events. Maximum 7 days.")
                }

                // Morning Sync
                Section {
                    Toggle("Sync Every Morning", isOn: $morningSyncEnabled)
                        .onChange(of: morningSyncEnabled) { _, enabled in
                            if enabled {
                                BackgroundSyncManager.shared.scheduleMorningSyncIfEnabled()
                            } else {
                                BackgroundSyncManager.shared.cancelScheduledSync()
                            }
                        }

                    if morningSyncEnabled {
                        DatePicker(
                            "Sync Time",
                            selection: $morningSyncTime,
                            displayedComponents: .hourAndMinute
                        )
                        .onChange(of: morningSyncTime) { _, newTime in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newTime)
                            UserDefaults.standard.set(comps.hour ?? 7, forKey: "morningSyncHour")
                            UserDefaults.standard.set(comps.minute ?? 0, forKey: "morningSyncMinute")
                            UserDefaults.standard.set(true, forKey: "morningSyncTimeSet")
                            BackgroundSyncManager.shared.scheduleMorningSyncIfEnabled()
                        }
                    }
                } header: {
                    Label("Morning Sync", systemImage: "sunrise.fill")
                } footer: {
                    Text("Automatically sync your calendar and reschedule alarms every morning, even if the app isn't open. Requires Background App Refresh to be enabled in iOS Settings.")
                }

                // Status
                Section {
                    HStack {
                        Text("Scheduled Alarms")
                        Spacer()
                        Text("\(notificationManager.scheduledCount)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Calendar Access")
                        Spacer()
                        Image(systemName: calendarManager.authorizationStatus.isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(calendarManager.authorizationStatus.isGranted ? .green : .red)
                    }

                    HStack {
                        Text("Notifications")
                        Spacer()
                        Image(systemName: notificationManager.isAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(notificationManager.isAuthorized ? .green : .red)
                    }
                } header: {
                    Label("Status", systemImage: "info.circle")
                }

                // Actions
                Section {
                    Button {
                        notificationManager.scheduleTestAlarm()
                    } label: {
                        Label("Test Alarm (fires in 5 sec)", systemImage: "bell.and.waves.left.and.right")
                    }

                    Button {
                        calendarManager.forceRefresh {
                            notificationManager.scheduleAlarms(
                                for: calendarManager.upcomingEvents,
                                mutedIDs: calendarManager.mutedEventIDs
                            )
                        }
                    } label: {
                        Label("Refresh & Reschedule All Alarms", systemImage: "arrow.clockwise")
                    }

                    Button(role: .destructive) {
                        showRemoveConfirmation = true
                    } label: {
                        Label("Remove All Alarms", systemImage: "bell.slash")
                    }
                } header: {
                    Label("Actions", systemImage: "gear")
                } footer: {
                    Text("Test Alarm schedules a real AlarmKit alarm that fires in 5 seconds so you can experience exactly how event alarms will look and sound.")
                }

                // Support & Info
                Section {
                    Link(destination: URL(string: "https://www.codeharmony.dev/nudge/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }

                    Link(destination: URL(string: "mailto:sahilpcs@hotmail.com?subject=Nudge%20Feedback")!) {
                        Label("Contact Support", systemImage: "envelope.fill")
                    }

                    Button {
                        requestReview()
                    } label: {
                        Label("Rate Nudge", systemImage: "star.fill")
                    }
                } header: {
                    Label("Support", systemImage: "questionmark.circle")
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("About", systemImage: "info.circle")
                } footer: {
                    Text("Nudge reads your calendar events and triggers alarms so you never miss a meeting.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: lookAheadDays) { _, _ in reschedule() }
            .onChange(of: alarmLeadTimeMinutes) { _, _ in reschedule() }
            .onChange(of: snoozeMinutes) { _, _ in reschedule() }
            .onChange(of: includeAllDayEvents) { _, _ in reschedule() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        calendarManager.forceRefresh {
                            notificationManager.scheduleAlarms(
                                for: calendarManager.upcomingEvents,
                                mutedIDs: calendarManager.mutedEventIDs
                            )
                        }
                        dismiss()
                    }
                }
            }
            .alert("Remove All Alarms?", isPresented: $showRemoveConfirmation) {
                Button("Remove All", role: .destructive) {
                    notificationManager.removeAllAlarms()
                    showRemovedAlert = true
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will clear all \(notificationManager.scheduledCount) scheduled alarm\(notificationManager.scheduledCount == 1 ? "" : "s"). You won't be nudged until you sync again.")
            }
            .alert("All Alarms Removed", isPresented: $showRemovedAlert) {
                Button("Re-sync Now") {
                    calendarManager.forceRefresh {
                        notificationManager.scheduleAlarms(
                            for: calendarManager.upcomingEvents,
                            mutedIDs: calendarManager.mutedEventIDs
                        )
                    }
                }
                Button("Later", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("All alarms have been cleared. Tap Re-sync to reschedule alarms for your upcoming events.")
            }
        }
    }

    // Re-fetch events and reschedule alarms when any setting changes
    private func reschedule() {
        calendarManager.forceRefresh {
            notificationManager.scheduleAlarms(
                for: calendarManager.upcomingEvents,
                mutedIDs: calendarManager.mutedEventIDs
            )
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environmentObject(CalendarManager())
        .environmentObject(NotificationManager())
}
