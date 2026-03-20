import SwiftUI
import Combine

// MARK: - EventListInlineView
// Renders directly inside ContentView's List — no nested List/ScrollView

struct EventListInlineView: View {
    @EnvironmentObject var calendarManager: CalendarManager
    @EnvironmentObject var notificationManager: NotificationManager

    var body: some View {
        if calendarManager.isLoading {
            HStack {
                Spacer()
                ProgressView("Loading events...")
                Spacer()
            }
            .listRowBackground(Color.clear)
        } else if calendarManager.upcomingEvents.isEmpty {
            emptyState
        } else {
            ForEach(groupedEvents, id: \.key) { day, events in
                Section {
                    ForEach(events) { event in
                        EventRow(
                            event: event,
                            isAlarmEnabled: !calendarManager.isEventMuted(event.id),
                            onToggleAlarm: {
                                calendarManager.toggleMute(for: event.id)
                                notificationManager.scheduleAlarms(
                                    for: calendarManager.upcomingEvents,
                                    mutedIDs: calendarManager.mutedEventIDs
                                )
                            }
                        )
                    }
                } header: {
                    Text(day)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("No Upcoming Events")
                .font(.title3.bold())

            Text("Your calendar is clear! Events will appear here when you have them scheduled.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .listRowBackground(Color.clear)
    }

    private var groupedEvents: [(key: String, value: [CalendarEvent])] {
        let grouped = Dictionary(grouping: calendarManager.upcomingEvents) { event in
            event.formattedDate
        }
        return grouped.sorted { first, second in
            guard let firstEvent = first.value.first,
                  let secondEvent = second.value.first else { return false }
            return firstEvent.startDate < secondEvent.startDate
        }
    }
}

// MARK: - EventListView (kept for backwards compatibility)
// This is the original standalone version — keep it if used elsewhere

struct EventListView: View {
    @EnvironmentObject var calendarManager: CalendarManager
    @EnvironmentObject var notificationManager: NotificationManager

    var body: some View {
        List {
            EventListInlineView()
                .environmentObject(calendarManager)
                .environmentObject(notificationManager)
        }
        .listStyle(.insetGrouped)
        .refreshable {
            calendarManager.forceRefresh()
            notificationManager.scheduleAlarms(
                for: calendarManager.upcomingEvents,
                mutedIDs: calendarManager.mutedEventIDs
            )
        }
    }
}

// MARK: - Event Row (unchanged from original)

struct EventRow: View {
    let event: CalendarEvent
    let isAlarmEnabled: Bool
    let onToggleAlarm: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Color indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(event.calendarColor)
                .frame(width: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body.bold())
                    .foregroundColor(isAlarmEnabled ? .primary : .secondary)
                    .lineLimit(2)
                    .strikethrough(!isAlarmEnabled, color: .secondary)

                Text(event.formattedTime)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text(event.calendarName)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(event.calendarColor.opacity(0.8))
                    .cornerRadius(4)
            }

            Spacer()

            // Time badge + alarm toggle
            VStack(spacing: 6) {
                if event.isHappeningNow {
                    Text("NOW")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .cornerRadius(6)
                } else {
                    Text(event.relativeTimeString)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fontWeight(.medium)
                }

                Button {
                    onToggleAlarm()
                } label: {
                    Image(systemName: isAlarmEnabled ? "bell.fill" : "bell.slash.fill")
                        .font(.body)
                        .foregroundColor(isAlarmEnabled ? .orange : .gray)
                        .symbolEffect(.bounce, value: isAlarmEnabled)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .opacity(isAlarmEnabled ? 1.0 : 0.7)
    }
}

#Preview {
    EventListView()
        .environmentObject(CalendarManager())
        .environmentObject(NotificationManager())
}
