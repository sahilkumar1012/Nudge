import SwiftUI
import Combine

// =============================================================================
// ContentView — The main screen of the app.
//
// REDESIGN NOTES:
// - Replaced flat StatPill with a compact hero card showing all 3 stats inline
// - Added gradient accent header with app icon + title inline with settings
// - Sync row now uses a subtle surface card instead of raw HStack
// - StatPill labels are now single-line with truncation-safe sizing
// - Soft depth via layered shadows and background materials
// =============================================================================

struct ContentView: View {
    @EnvironmentObject var calendarManager: CalendarManager
    @EnvironmentObject var notificationManager: NotificationManager

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
            ZStack(alignment: .top) {
                // Subtle gradient backdrop behind the header area
                LinearGradient(
                    colors: [Color.blue.opacity(0.08), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
                .ignoresSafeArea(edges: .top)

                List {
                    // Stats card — full-width, single card row
                    Section {
                        statsCard
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                        syncRow
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    // Events grouped by day
                    EventListInlineView()
                        .environmentObject(calendarManager)
                        .environmentObject(notificationManager)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Nudge")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                syncCalendar()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
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

    // MARK: - Stats Card (replaces three loose StatPills)

    private var statsCard: some View {
        HStack(spacing: 0) {
            StatCell(
                icon: "calendar",
                value: "\(calendarManager.todayEvents.count)",
                label: "Today",
                color: .blue
            )

            Divider()
                .frame(height: 36)
                .padding(.vertical, 4)

            StatCell(
                icon: "bell.fill",
                value: "\(notificationManager.scheduledCount)",
                label: "Alarms",
                color: .orange
            )

            Divider()
                .frame(height: 36)
                .padding(.vertical, 4)

            StatCell(
                icon: "clock.fill",
                value: nextEventTime,
                label: "Next",
                color: .green
            )
        }
        .padding(.vertical, 12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }

    // MARK: - Sync Row

    private var syncRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: calendarManager.isLoading
                    ? "arrow.triangle.2.circlepath"
                    : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(calendarManager.isLoading ? .orange : .green)
                Text(calendarManager.isLoading
                    ? "Loading..."
                    : "\(calendarManager.upcomingEvents.count) upcoming event\(calendarManager.upcomingEvents.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                            .font(.caption.weight(.bold))
                    }
                    Text(isSyncing ? "Syncing…" : "Sync")
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isSyncing
                        ? AnyShapeStyle(Color.gray)
                        : AnyShapeStyle(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .clipShape(Capsule())
                .shadow(color: .blue.opacity(isSyncing ? 0 : 0.30), radius: 6, y: 3)
            }
            .disabled(isSyncing)
        }
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
        calendarManager.forceRefresh {
            notificationManager.scheduleAlarms(
                for: calendarManager.upcomingEvents,
                mutedIDs: calendarManager.mutedEventIDs
            )
            isSyncing = false
        }
    }
}

// MARK: - Stat Cell (used inside the unified stats card)

/// One third of the stats card. Icon + value + label stacked vertically.
struct StatCell: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }
}


#Preview {
    ContentView()
        .environmentObject(CalendarManager())
        .environmentObject(NotificationManager())
}
