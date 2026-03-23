import SwiftUI
import Combine

// =============================================================================
// PermissionsView — Shown on first launch (or if permissions are revoked).
//
// The app needs two permissions to work:
// 1. Calendar Access — to read events from the user's phone calendar
// 2. Alarm/Notification Permission — so AlarmKit can fire alarms
//
// Each permission is shown as a tappable card. Once both are granted,
// a "Get Started" button appears which triggers the first event sync.
// =============================================================================

struct PermissionsView: View {
    @EnvironmentObject var calendarManager: CalendarManager
    @EnvironmentObject var notificationManager: NotificationManager

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 80))
                .foregroundStyle(.red, .orange)
                .symbolEffect(.bounce, options: .repeating.speed(0.5))

            Text("Nudge")
                .font(.largeTitle.bold())

            Text("Never miss a meeting again.\nGet loud alarm reminders for every calendar event.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            // Permission Cards
            VStack(spacing: 16) {
                PermissionCard(
                    icon: "calendar",
                    title: "Calendar Access",
                    description: "Read your events to schedule alarms",
                    isGranted: calendarManager.authorizationStatus.isGranted,
                    action: { calendarManager.requestAccess() }
                )

                PermissionCard(
                    icon: "bell.fill",
                    title: "Notifications",
                    description: "Alarm notification when events start",
                    isGranted: notificationManager.isAuthorized,
                    action: { Task { await notificationManager.requestAuthorization() } }                )
            }
            .padding(.horizontal, 24)

            Spacer()

            if calendarManager.authorizationStatus.isGranted && notificationManager.isAuthorized {
                Button {
                    calendarManager.fetchEvents()
                    notificationManager.scheduleAlarms(
                        for: calendarManager.upcomingEvents,
                        mutedIDs: calendarManager.mutedEventIDs
                    )
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer().frame(height: 40)
        }
    }
}

// PermissionCard — A tappable card for a single permission request.
// Shows icon, title, description, and a checkmark when granted.

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isGranted ? .green : .orange)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isGranted ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: isGranted ? "checkmark.circle.fill" : "arrow.right.circle")
                    .font(.title3)
                    .foregroundColor(isGranted ? .green : .blue)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
        .disabled(isGranted)
    }
}

#Preview {
    PermissionsView()
        .environmentObject(CalendarManager())
        .environmentObject(NotificationManager())
}
