import EventKit
import SwiftUI
import Combine

// =============================================================================
// CalendarManager — Reads events from the user's phone calendar.
//
// FLOW:
// 1. On init, checks if we have calendar permission and starts a 5-min auto-refresh timer
// 2. When the user grants permission (or it was already granted), fetchEvents() is called
// 3. fetchEvents() queries EventKit for all events from now to N days ahead
// 4. Events are converted from Apple's EKEvent → our CalendarEvent model
// 5. The UI observes `upcomingEvents` and `todayEvents` via @Published
//
// Also manages "muted events" — events the user has silenced (no alarm).
// Muted event IDs are persisted in UserDefaults so they survive app restarts.
// =============================================================================

class CalendarManager: ObservableObject {
    // Apple's EventKit store — our gateway to the device's calendar data
    private let eventStore = EKEventStore()

    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var upcomingEvents: [CalendarEvent] = []   // Events from now to N days ahead
    @Published var todayEvents: [CalendarEvent] = []      // Events happening today only
    @Published var isLoading = false

    // How many days ahead to look for events (configurable in Settings)
    @AppStorage("lookAheadDays") var lookAheadDays: Int = 7

    // Set of event IDs the user has muted (no alarm will fire for these)
    @Published var mutedEventIDs: Set<String> = []

    private static let mutedKey = "mutedEventIDs"
    private var refreshTimer: Timer?   // Auto-refreshes events every 5 minutes

    init() {
        loadMutedEvents()
        checkAuthorizationStatus()
        startAutoRefresh()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: - Authorization
    // Check current calendar permission status (granted, denied, or not yet asked)

    func checkAuthorizationStatus() {
        if #available(iOS 17.0, *) {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        } else {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }
    }

    // Ask the user for calendar access. iOS shows a system prompt.
    // If granted, we immediately fetch events.
    func requestAccess() {
        if #available(iOS 17.0, *) {
            // iOS 17+ requires "full access" request
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.checkAuthorizationStatus()
                    if granted {
                        self?.fetchEvents()
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.checkAuthorizationStatus()
                    if granted {
                        self?.fetchEvents()
                    }
                }
            }
        }
    }

    // MARK: - Fetch Events
    // Queries the device calendar for events and updates our published arrays.
    // Called on launch, on manual sync, on foreground return, and every 5 minutes.

    func fetchEvents() {
        // Don't try to fetch if we don't have permission
        guard authorizationStatus == .authorized || authorizationStatus == .fullAccess else {
            return
        }

        isLoading = true

        // Calculate the date range to query — hard cap at 7 days max
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let cappedDays = min(lookAheadDays, 7)  // Never look more than 7 days ahead
        let endDate = Calendar.current.date(byAdding: .day, value: cappedDays, to: startOfToday)!
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)!

        // EventKit predicate: "give me all events between now and N days from now"
        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: endDate,
            calendars: nil   // nil = search ALL calendars on the device
        )

        // Separate predicate for today's events (used for the "Today" stat pill)
        let todayPredicate = eventStore.predicateForEvents(
            withStart: startOfToday,
            end: endOfToday,
            calendars: nil
        )

        // Run the queries (EventKit returns EKEvent arrays)
        let ekEvents = eventStore.events(matching: predicate)
        let ekTodayEvents = eventStore.events(matching: todayPredicate)

        // Convert to our CalendarEvent model and sort by start time
        DispatchQueue.main.async { [weak self] in
            self?.upcomingEvents = ekEvents
                .map { CalendarEvent.from(ekEvent: $0) }
                .sorted { $0.startDate < $1.startDate }

            self?.todayEvents = ekTodayEvents
                .map { CalendarEvent.from(ekEvent: $0) }
                .sorted { $0.startDate < $1.startDate }

            self?.isLoading = false
        }
    }

    // MARK: - Auto Refresh
    // Automatically re-fetches events every 5 minutes (300 seconds)
    // so the event list stays current without user interaction.

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.fetchEvents()
        }
    }

    // Called by the Sync button and pull-to-refresh
    func forceRefresh() {
        fetchEvents()
    }

    // MARK: - Muted Events
    // Users can mute individual events so no alarm fires for them.
    // Muted event IDs are saved to UserDefaults for persistence.

    private func loadMutedEvents() {
        if let saved = UserDefaults.standard.array(forKey: Self.mutedKey) as? [String] {
            mutedEventIDs = Set(saved)
        }
    }

    private func saveMutedEvents() {
        UserDefaults.standard.set(Array(mutedEventIDs), forKey: Self.mutedKey)
    }

    func isEventMuted(_ eventID: String) -> Bool {
        mutedEventIDs.contains(eventID)
    }

    // Toggle mute on/off for a specific event (called when user taps the bell icon)
    func toggleMute(for eventID: String) {
        if mutedEventIDs.contains(eventID) {
            mutedEventIDs.remove(eventID)
        } else {
            mutedEventIDs.insert(eventID)
        }
        saveMutedEvents()
    }

    func setMute(_ muted: Bool, for eventID: String) {
        if muted {
            mutedEventIDs.insert(eventID)
        } else {
            mutedEventIDs.remove(eventID)
        }
        saveMutedEvents()
    }

    // Convenience: all events that have alarms enabled (not muted)
    var enabledEvents: [CalendarEvent] {
        upcomingEvents.filter { !mutedEventIDs.contains($0.id) }
    }
}

// Helper extension: treats both .authorized (iOS 16) and .fullAccess (iOS 17+) as granted
extension EKAuthorizationStatus {
    var isGranted: Bool {
        switch self {
        case .authorized:
            return true
        case .fullAccess:
            return true
        default:
            return false
        }
    }
}
