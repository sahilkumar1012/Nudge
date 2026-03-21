# Nudge 🔔

**Never miss a meeting again.** Nudge reads your iPhone calendar and fires real alarms (not just notifications) when events are about to start — even in Do Not Disturb.

Built with **SwiftUI** + **AlarmKit** (iOS 26+). Fully offline, no account needed.

---

## Features

- ⏰ **Real Alarms** — Uses Apple's AlarmKit so alarms fire like the native Clock app (sound, vibration, lock screen UI, survives Do Not Disturb)
- 📅 **Calendar Sync** — Reads all events from every calendar on your device via EventKit
- 🔄 **Manual Sync** — Pull-to-refresh or tap the Sync button to refresh events & reschedule alarms
- 🌅 **Morning Auto-Sync** — Configurable daily background sync via BGAppRefreshTask
- 🔕 **Per-Event Mute** — Tap the bell icon to silence alarms for specific events
- ⏳ **Lead Time** — Fire alarm 0–30 minutes before event start
- 💤 **Snooze** — Configurable snooze duration (1–15 minutes)
- 🧪 **Test Alarm** — Preview exactly how alarms sound/look from Settings
- 🔍 **Spotlight Search** — App appears when you search "calendar", "meeting", "alarm" in iOS search
- 🎨 **Dark & Light Icons** — Adaptive app icon for both themes

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    NudgeApp                          │
│              (App entry point)                       │
│  • Registers background sync task                   │
│  • Donates Spotlight activities                      │
│  • Creates CalendarManager + NotificationManager     │
└──────────┬──────────────────┬───────────────────────┘
           │                  │
    ┌──────▼──────┐    ┌──────▼──────────┐
    │ CalendarMgr │    │ NotificationMgr  │
    │             │    │                  │
    │ • EventKit  │───▶│ • AlarmKit       │
    │ • Fetch     │    │ • Schedule       │
    │ • Muted IDs │    │ • Group by time  │
    │ • 5min auto │    │ • Persist UUIDs  │
    └──────┬──────┘    └────────┬─────────┘
           │                    │
    ┌──────▼────────────────────▼─────────┐
    │         BackgroundSyncManager        │
    │  • BGAppRefreshTask (morning sync)   │
    │  • Fetches events + schedules alarms │
    │  • Runs even when app is closed      │
    └─────────────────────────────────────┘
```

---

## Project Structure

```
CalendarAlarm/
├── App/
│   └── CalendarAlarmApp.swift       # Entry point (NudgeApp), Spotlight indexing
├── Models/
│   └── CalendarEvent.swift          # Event data model (from EKEvent)
├── Managers/
│   ├── CalendarManager.swift        # EventKit: fetch events, manage muted IDs
│   ├── NotificationManager.swift    # AlarmKit: schedule/cancel/group alarms
│   └── BackgroundSyncManager.swift  # BGAppRefreshTask: daily morning sync
├── Views/
│   ├── ContentView.swift            # Main screen: stats, sync button, event list
│   ├── EventListView.swift          # Events grouped by day, per-event bell toggle
│   ├── SettingsView.swift           # Lead time, snooze, sync time, test alarm
│   └── PermissionsView.swift        # Calendar + AlarmKit permission requests
├── Extensions/
│   └── Date+Extensions.swift        # Date helpers (startOfDay, relativeString, etc.)
├── Assets.xcassets/                 # App icon (dark + light), accent color
└── Info.plist                       # Permissions, background modes, Spotlight config
```

---

## How It Works

### Alarm Scheduling Flow

1. **Sync** → `CalendarManager.fetchEvents()` queries EventKit for next 7 days
2. **Filter** → Skip all-day events, muted events, and past events
3. **Group** → Events firing at the same minute are merged into ONE alarm
   - 1 event: `"Team Standup"`
   - 2 events: `"Team Standup & Design Review"`
   - 3+ events: `"Team Standup & Design Review + 1 more"`
4. **Schedule** → Each group gets one `AlarmManager.schedule()` call via AlarmKit
5. **Persist** → Alarm UUIDs saved to UserDefaults (so they can be cancelled after app restart)

### Why AlarmKit (not UNUserNotification)?

| | UNUserNotification | AlarmKit |
|---|---|---|
| Do Not Disturb | Silenced ❌ | Fires through ✅ |
| Lock screen | Banner only | Full-screen alarm UI ✅ |
| Sound | Limited duration | Loops until dismissed ✅ |
| Snooze | Must build yourself | Built-in ✅ |

---

## Permissions

| Permission | Why | Prompt |
|---|---|---|
| **Calendar (Full Access)** | Read events from all calendars | On first launch |
| **AlarmKit** | Schedule real alarms that bypass DND | On first launch |
| **Background App Refresh** | Morning auto-sync | System setting |

---

## Configuration (Settings Screen)

| Setting | Options | Default |
|---|---|---|
| **Alert Before Event** | At event time, 1/5/10/15/30 min before | At event time |
| **Snooze Duration** | 1, 3, 5, 10, 15 minutes | 5 minutes |
| **Look Ahead** | 1, 3, or 7 days | 7 days |
| **Morning Sync** | On/Off + time picker | Off, 7:00 AM |

---

## Getting Started

### Prerequisites

- **Xcode 26+** (for AlarmKit support)
- **iOS 26+** device or simulator
- An Apple Developer account (for device testing)

### Setup

```bash
git clone https://github.com/sahilkumar1012/Nudge.git
cd Nudge
open CalendarAlarm.xcodeproj
```

1. Open in Xcode
2. Select your Team in **Signing & Capabilities**
3. Connect your iPhone or pick a simulator
4. Hit **⌘R** to build and run

### Testing on Device

1. **Settings → About Phone** → Tap Build Number 7 times (enable Developer Mode)
2. **Settings → Developer → Developer Mode** → Enable, reboot
3. Connect via USB, trust the computer
4. In Xcode: select your device from the toolbar dropdown → Run

### Test the Alarm

1. Open the app → Grant calendar + alarm permissions
2. Go to **Settings → Actions → Test Alarm (fires in 5 sec)**
3. Lock your phone — you should see a full-screen alarm in 5 seconds

---

## Key Technical Decisions

- **AlarmKit over UNUserNotification** — Alarms must fire in DND and show full-screen UI. AlarmKit is the only iOS API that does this (introduced WWDC 2025).
- **Group alarms by trigger minute** — Prevents alarm spam when you have 5 meetings at 10 AM. One alarm, combined title.
- **Persist alarm UUIDs in UserDefaults** — Fixes the bug where `removeAllAlarms()` couldn't cancel old alarms after app restart.
- **Hard cap 7 days** — More than 7 days creates too many alarms (iOS allows max 64 pending).
- **CoreSpotlight + NSUserActivity** — Makes the app appear in iOS Spotlight when searching "calendar", "meeting", etc.
- **BGAppRefreshTask for morning sync** — Uses UNUserNotification (not AlarmKit) as background tasks can't access @MainActor APIs.

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI + Material-style components |
| Calendar | EventKit (CalendarContract equivalent) |
| Alarms | AlarmKit (iOS 26+) |
| Background | BGAppRefreshTask + UNUserNotification |
| Storage | UserDefaults + @AppStorage |
| Search | CoreSpotlight + NSUserActivity |

---

## License

MIT
