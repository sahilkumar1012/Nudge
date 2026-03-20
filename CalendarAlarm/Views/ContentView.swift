import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var calendarManager: CalendarManager
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var alarmState: AlarmState

    @State private var showSettings = false
    @State private var isSyncing = false

    var body: some View {
        Group {
            if !calendarManager.authorizationStatus.isGranted || !notificationManager.isAuthorized {
                PermissionsView()
            } else {
                mainContent
            }
        }
        .onAppear {
            if calendarManager.authorizationStatus.isGranted {
                calendarManager.fetchEvents()
            }
        }
    }

    private var mainContent: some View {
        NavigationStack {
            List {
                // Stats + Sync as a non-row header section
                Section {
                    statsRow
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    syncRow
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                // Events grouped by day — reuses EventListView's logic inline
                EventListInlineView()
                    .environmentObject(calendarManager)
                    .environmentObject(notificationManager)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Calendar Alarm")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                syncCalendar()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .fontWeight(.medium)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(calendarManager)
                    .environmentObject(notificationManager)
            }
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatPill(
                icon: "calendar",
                value: "\(calendarManager.todayEvents.count)",
                label: "Today",
                color: .blue
            )
            StatPill(
                icon: "bell.fill",
                value: "\(notificationManager.scheduledCount)",
                label: "Alarms",
                color: .orange
            )
            StatPill(
                icon: "clock",
                value: nextEventTime,
                label: "Next",
                color: .green
            )
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Sync Row

    private var syncRow: some View {
        HStack(spacing: 10) {
            Label(
                calendarManager.isLoading
                    ? "Loading..."
                    : "\(calendarManager.upcomingEvents.count) upcoming events",
                systemImage: calendarManager.isLoading
                    ? "arrow.triangle.2.circlepath"
                    : "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                syncCalendar()
            } label: {
                HStack(spacing: 5) {
                    if isSyncing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                    }
                    Text(isSyncing ? "Syncing" : "Sync")
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSyncing ? Color.gray : Color.blue)
                .clipShape(Capsule())
            }
            .disabled(isSyncing)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    private var nextEventTime: String {
        guard let next = calendarManager.upcomingEvents.first(where: { $0.isUpcoming }) else {
            return "—"
        }
        return next.relativeTimeString
    }

    private func syncCalendar() {
        isSyncing = true
        calendarManager.forceRefresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            notificationManager.scheduleAlarms(
                for: calendarManager.upcomingEvents,
                mutedIDs: calendarManager.mutedEventIDs
            )
            isSyncing = false
        }
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView()
        .environmentObject(CalendarManager())
        .environmentObject(NotificationManager())
        .environmentObject(AlarmState())
}
