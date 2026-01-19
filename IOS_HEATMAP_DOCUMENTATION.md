# Schedule Heat Map Feature - iOS Implementation Guide

This document provides comprehensive technical specifications for implementing the Schedule Heat Map feature in the Focal Point iOS app.

---

## 1. Feature Overview

The Schedule Heat Map is a **visual intensity indicator** displayed in the week view calendar header. It shows the total staffing needs (workload intensity) for each day using color-coded indicators.

**Visual Components:**
1. A **4px colored gradient bar** at the bottom of each day column header
2. A **colored badge** showing the total staffing number (bottom-right of header cell)
3. **Tooltip/popover** showing breakdown on tap/long-press

**Purpose:**
- At-a-glance understanding of which days are busy vs light
- Quick identification of understaffed or overstaffed days
- Visual cue for scheduling decisions

---

## 2. Color Mapping & Thresholds

| Total Staff Needed | Color | Hex Code | Meaning |
|-------------------|-------|----------|---------|
| 0 | Transparent | - | No sessions |
| 1-3 | Green | `#22c55e` | Light load |
| 4-6 | Yellow | `#eab308` | Medium load |
| 7-9 | Orange | `#f97316` | High load |
| 10+ | Red | `#ef4444` | Critical load |

**Color Function Logic (Swift):**
```swift
func getHeatMapColor(total: Int) -> Color {
    if total == 0 { return .clear }
    if total <= 3 { return Color(hex: "#22c55e") }  // Green - Light
    if total <= 6 { return Color(hex: "#eab308") }  // Yellow - Medium
    if total <= 9 { return Color(hex: "#f97316") }  // Orange - High
    return Color(hex: "#ef4444")                     // Red - Critical
}
```

**Color Extension Helper:**
```swift
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
```

---

## 3. Data Models

### Session Structure (relevant fields)
```swift
struct Session: Codable, Identifiable {
    let id: String
    let organizationId: String
    let date: String                    // "YYYY-MM-DD" format
    let startTime: String               // "HH:mm" or "HH:mm:ss" format
    let endTime: String                 // "HH:mm" or "HH:mm:ss" format
    let schoolId: String?
    let schoolName: String?
    let photographersNeeded: Int        // Default: 1
    let posersNeeded: Int               // Default: 0
    let helpersNeeded: Int              // Default: 0
    let isTimeOff: Bool                 // Exclude from heat map if true
    let status: String?                 // "scheduled", "completed", etc.

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case date
        case startTime = "start_time"
        case endTime = "end_time"
        case schoolId = "school_id"
        case schoolName = "school_name"
        case photographersNeeded = "photographers_needed"
        case posersNeeded = "posers_needed"
        case helpersNeeded = "helpers_needed"
        case isTimeOff = "is_time_off"
        case status
    }

    // Handle null values with defaults
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        organizationId = try container.decode(String.self, forKey: .organizationId)
        date = try container.decode(String.self, forKey: .date)
        startTime = try container.decode(String.self, forKey: .startTime)
        endTime = try container.decode(String.self, forKey: .endTime)
        schoolId = try container.decodeIfPresent(String.self, forKey: .schoolId)
        schoolName = try container.decodeIfPresent(String.self, forKey: .schoolName)
        photographersNeeded = try container.decodeIfPresent(Int.self, forKey: .photographersNeeded) ?? 1
        posersNeeded = try container.decodeIfPresent(Int.self, forKey: .posersNeeded) ?? 0
        helpersNeeded = try container.decodeIfPresent(Int.self, forKey: .helpersNeeded) ?? 0
        isTimeOff = try container.decodeIfPresent(Bool.self, forKey: .isTimeOff) ?? false
        status = try container.decodeIfPresent(String.self, forKey: .status)
    }
}
```

### Staffing Totals Structure
```swift
struct DayStaffingTotals {
    let photographers: Int
    let posers: Int
    let helpers: Int

    var total: Int {
        photographers + posers + helpers
    }

    var isEmpty: Bool {
        total == 0
    }

    var breakdownText: String {
        "Photographers: \(photographers), Posers: \(posers), Helpers: \(helpers)"
    }
}
```

---

## 4. Calculation Algorithm

### Step 1: Filter sessions for a specific day
```swift
func getSessionsForDay(day: Date, allSessions: [Session]) -> [Session] {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone.current
    let dayString = formatter.string(from: day)

    return allSessions.filter { session in
        // Exclude time-off entries from heat map
        guard !session.isTimeOff else { return false }
        return session.date == dayString
    }
}
```

### Step 2: Calculate staffing totals for a day
```swift
func getStaffingTotalsForDay(day: Date, sessions: [Session]) -> DayStaffingTotals {
    let daySessions = getSessionsForDay(day: day, allSessions: sessions)

    var photographers = 0
    var posers = 0
    var helpers = 0

    for session in daySessions {
        photographers += session.photographersNeeded
        posers += session.posersNeeded
        helpers += session.helpersNeeded
    }

    return DayStaffingTotals(
        photographers: photographers,
        posers: posers,
        helpers: helpers
    )
}
```

### Step 3: Generate week days array
```swift
func generateWeekDays(from startOfWeek: Date) -> [Date] {
    let calendar = Calendar.current
    return (0..<7).compactMap { dayOffset in
        calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek)
    }
}

func getStartOfWeek(for date: Date) -> Date {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    return calendar.date(from: components) ?? date
}
```

---

## 5. API / Database Schema

### Supabase Table: `sessions`

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| `id` | UUID | auto | Primary key |
| `organization_id` | UUID | required | FK to organizations |
| `date` | DATE | required | Session date (YYYY-MM-DD) |
| `start_time` | TIME | required | Start time (HH:mm:ss) |
| `end_time` | TIME | required | End time (HH:mm:ss) |
| `school_id` | UUID | nullable | FK to schools |
| `school_name` | TEXT | nullable | Denormalized school name |
| `photographers_needed` | INTEGER | 1 | Number of photographers required |
| `posers_needed` | INTEGER | 0 | Number of posers required |
| `helpers_needed` | INTEGER | 0 | Number of helpers required |
| `is_time_off` | BOOLEAN | false | If true, this is time-off not a session |
| `status` | TEXT | 'scheduled' | Session status |

### API Query (Supabase Swift)
```swift
import Supabase

class SessionService {
    let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    func fetchSessions(
        organizationId: String,
        startDate: String,
        endDate: String
    ) async throws -> [Session] {
        let response: [Session] = try await supabase
            .from("sessions")
            .select("""
                id,
                organization_id,
                date,
                start_time,
                end_time,
                school_id,
                school_name,
                photographers_needed,
                posers_needed,
                helpers_needed,
                is_time_off,
                status
            """)
            .eq("organization_id", value: organizationId)
            .gte("date", value: startDate)
            .lte("date", value: endDate)
            .execute()
            .value

        return response
    }
}
```

### Query for a single week
```swift
func fetchSessionsForWeek(weekStartDate: Date) async throws -> [Session] {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    let startDate = formatter.string(from: weekStartDate)
    let endDate = formatter.string(from: Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate)!)

    return try await sessionService.fetchSessions(
        organizationId: currentOrganizationId,
        startDate: startDate,
        endDate: endDate
    )
}
```

---

## 6. UI Implementation

### Week View Header Layout (ASCII representation)
```
┌─────────┬─────────┬─────────┬─────────┬─────────┬─────────┬─────────┐
│   Mon   │   Tue   │   Wed   │   Thu   │   Fri   │   Sat   │   Sun   │
│   15    │   16    │   17    │   18    │   19    │   20    │   21    │
│         │         │    [5]  │   [12]  │    [3]  │         │         │
│ ▓▓▓░░░░ │ ░░░░░░░ │ ▓▓▓▓▓░░ │ ▓▓▓▓▓▓▓ │ ▓▓░░░░░ │ ░░░░░░░ │ ░░░░░░░ │
└─────────┴─────────┴─────────┴─────────┴─────────┴─────────┴─────────┘
  Green      None     Yellow     Red      Green     None      None
```

### Visual Elements Specifications

#### 1. Gradient Bar (bottom of header cell)
- **Height:** 4 points
- **Width:** 100% of cell width
- **Gradient:** heatMapColor → transparent (leading to trailing)
- **Visibility:** Hidden when `total == 0`

#### 2. Badge (bottom-right corner)
- **Shape:** Rounded rectangle
- **Corner Radius:** 8 points
- **Size:** Dynamic based on content (~20-28pt width, 16-18pt height)
- **Background Color:** heatMapColor
- **Text Color:** White
- **Font:** System bold, 10-11pt
- **Padding:** Horizontal 6pt, Vertical 2pt
- **Position:** 4pt from bottom and right edges
- **Visibility:** Hidden when `total == 0`

#### 3. Tooltip/Popover (on tap or long-press)
- **Content:** "Photographers: X, Posers: Y, Helpers: Z"
- **Trigger:** Tap on badge or long-press on header cell

### SwiftUI Implementation

```swift
struct WeekViewHeader: View {
    let weekDays: [Date]
    let sessions: [Session]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                DayHeaderCell(
                    day: day,
                    staffing: getStaffingTotalsForDay(day: day, sessions: sessions)
                )
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct DayHeaderCell: View {
    let day: Date
    let staffing: DayStaffingTotals

    @State private var showingPopover = false

    private var heatMapColor: Color {
        getHeatMapColor(total: staffing.total)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(day)
    }

    var body: some View {
        VStack(spacing: 2) {
            // Day of week (Mon, Tue, etc.)
            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption2)
                .foregroundColor(.secondary)

            // Day number
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 16, weight: isToday ? .bold : .medium))
                .foregroundColor(isToday ? .blue : .primary)

            Spacer()

            // Heat map gradient bar
            if staffing.total > 0 {
                LinearGradient(
                    colors: [heatMapColor, heatMapColor.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 4)
            }
        }
        .frame(height: 60)
        .overlay(alignment: .bottomTrailing) {
            // Staffing badge
            if staffing.total > 0 {
                StaffingBadge(
                    total: staffing.total,
                    color: heatMapColor
                )
                .padding(4)
                .onTapGesture {
                    showingPopover = true
                }
                .popover(isPresented: $showingPopover) {
                    StaffingPopover(staffing: staffing)
                }
            }
        }
        .background(isToday ? Color.blue.opacity(0.05) : Color.clear)
    }
}

struct StaffingBadge: View {
    let total: Int
    let color: Color

    var body: some View {
        Text("\(total)")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(8)
    }
}

struct StaffingPopover: View {
    let staffing: DayStaffingTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Staffing Breakdown")
                .font(.headline)

            HStack {
                Label("\(staffing.photographers)", systemImage: "camera.fill")
                Text("Photographers")
            }

            HStack {
                Label("\(staffing.posers)", systemImage: "person.fill")
                Text("Posers")
            }

            HStack {
                Label("\(staffing.helpers)", systemImage: "hands.sparkles.fill")
                Text("Helpers")
            }

            Divider()

            HStack {
                Text("Total:")
                    .fontWeight(.bold)
                Spacer()
                Text("\(staffing.total)")
                    .fontWeight(.bold)
            }
        }
        .padding()
        .frame(width: 200)
    }
}
```

---

## 7. Edge Cases & Considerations

### 1. Time-Off Exclusion
Sessions where `is_time_off == true` should **NOT** count toward heat map totals. These represent employee time-off requests, not actual sessions requiring staffing.

### 2. Blocked Dates
If a date is blocked at the organization level, hide the heat map indicators for that day. Check against `organization_settings.blocked_dates` if applicable.

### 3. Multi-Photographer Sessions
Each session has its own `photographers_needed` count. Sum them all - don't try to deduplicate. If there are 3 sessions each needing 2 photographers, the total is 6.

### 4. Default Values
When decoding from API, handle null values:
- `photographers_needed`: Default to **1** if null
- `posers_needed`: Default to **0** if null
- `helpers_needed`: Default to **0** if null
- `is_time_off`: Default to **false** if null

### 5. Performance
- Calculate totals when sessions load or change, not on every render
- Consider caching results in a dictionary keyed by date string
- Use `@Published` or Combine to trigger UI updates efficiently

```swift
class HeatMapCache: ObservableObject {
    @Published var staffingByDay: [String: DayStaffingTotals] = [:]

    func updateCache(sessions: [Session], weekDays: [Date]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var newCache: [String: DayStaffingTotals] = [:]
        for day in weekDays {
            let dateString = formatter.string(from: day)
            newCache[dateString] = getStaffingTotalsForDay(day: day, sessions: sessions)
        }

        DispatchQueue.main.async {
            self.staffingByDay = newCache
        }
    }
}
```

### 6. Filtering Considerations
If the app supports filtering sessions by:
- Team member
- School
- Session type

The heat map should respect these filters and only show totals for visible/filtered sessions.

---

## 8. Accessibility

### VoiceOver Support
```swift
.accessibilityLabel(accessibilityLabel(for: day, staffing: staffing))

func accessibilityLabel(for day: Date, staffing: DayStaffingTotals) -> String {
    let dayName = day.formatted(.dateTime.weekday(.wide))
    let monthDay = day.formatted(.dateTime.month().day())

    if staffing.total == 0 {
        return "\(dayName), \(monthDay), no sessions scheduled"
    }

    let intensity: String
    switch staffing.total {
    case 1...3: intensity = "light"
    case 4...6: intensity = "medium"
    case 7...9: intensity = "heavy"
    default: intensity = "critical"
    }

    return "\(dayName), \(monthDay), \(staffing.total) staff needed, \(intensity) workload"
}
```

### Color Blind Considerations
- The number badge provides redundant information (not color-only)
- Consider adding optional patterns or shapes for different intensity levels
- Use sufficient contrast ratios

---

## 9. Data Refresh

The heat map should update when:
- Sessions are loaded initially on view appear
- A session is created, updated, or deleted
- User navigates to a different week
- Pull-to-refresh is triggered
- Real-time subscription receives an update (if implemented)

### Real-time Updates (Optional)
```swift
func subscribeToSessionChanges() {
    supabase
        .channel("sessions")
        .onPostgresChange(
            event: .all,
            schema: "public",
            table: "sessions",
            filter: "organization_id=eq.\(organizationId)"
        ) { [weak self] payload in
            Task {
                await self?.refreshSessions()
            }
        }
        .subscribe()
}
```

---

## 10. Complete ViewModel Example

```swift
import SwiftUI
import Combine

@MainActor
class WeekScheduleViewModel: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var currentWeekStart: Date = Date()
    @Published var isLoading = false
    @Published var error: Error?

    private let sessionService: SessionService
    private var cancellables = Set<AnyCancellable>()

    var weekDays: [Date] {
        generateWeekDays(from: currentWeekStart)
    }

    init(sessionService: SessionService) {
        self.sessionService = sessionService
        self.currentWeekStart = getStartOfWeek(for: Date())
    }

    func loadSessions() async {
        isLoading = true
        error = nil

        do {
            sessions = try await fetchSessionsForWeek(weekStartDate: currentWeekStart)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func staffingForDay(_ day: Date) -> DayStaffingTotals {
        getStaffingTotalsForDay(day: day, sessions: sessions)
    }

    func heatMapColorForDay(_ day: Date) -> Color {
        getHeatMapColor(total: staffingForDay(day).total)
    }

    func goToNextWeek() {
        if let nextWeek = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart) {
            currentWeekStart = nextWeek
            Task { await loadSessions() }
        }
    }

    func goToPreviousWeek() {
        if let prevWeek = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart) {
            currentWeekStart = prevWeek
            Task { await loadSessions() }
        }
    }
}
```

---

## 11. Verification Checklist

After implementation, verify:

- [ ] Heat map colors match thresholds:
  - 0 = transparent/no indicator
  - 1-3 = green (#22c55e)
  - 4-6 = yellow (#eab308)
  - 7-9 = orange (#f97316)
  - 10+ = red (#ef4444)
- [ ] Time-off sessions (`is_time_off = true`) are excluded from totals
- [ ] Badge shows correct total count
- [ ] Gradient bar displays at bottom of header cell
- [ ] Tapping badge shows staffing breakdown popover
- [ ] Heat map updates when sessions change
- [ ] Works correctly when navigating between weeks
- [ ] Respects any active filters (if applicable)
- [ ] VoiceOver reads appropriate accessibility labels
- [ ] Handles null values with correct defaults
- [ ] Performs well with large session counts

---

## 12. Reference: Web Implementation

The web app implementation can be found in:
- **Component:** `src/components/calendar/WeekView.js`
- **Color function:** Lines 229-236
- **Staffing calculation:** Lines 181-227
- **Header rendering:** Lines 1360-1392

These can be referenced for exact behavior matching if needed.
