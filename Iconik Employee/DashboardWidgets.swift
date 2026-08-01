import SwiftUI
import Supabase

// MARK: - Hours Widget
struct HoursWidget: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    
    // Initialize with cached values for instant display (will be validated when settings load)
    @State private var regularHours: Double = UserDefaults.standard.double(forKey: "cached_regularHours")
    @State private var overtimeHours: Double = UserDefaults.standard.double(forKey: "cached_overtimeHours")
    @State private var totalHours: Double = UserDefaults.standard.double(forKey: "cached_totalHours")
    @State private var currentWeekHours: Double = UserDefaults.standard.double(forKey: "cached_currentWeekHours")
    @State private var isLoadingHours = false
    @State private var hasInitialData = false
    @StateObject private var payPeriodService = PayPeriodService.shared
    @State private var activeHours: Double = 0
    @State private var activeEntryIncludedInTotal: Bool = false
    @State private var timer: Timer?
    @State private var listenerSetUp = false // Prevent duplicate listeners
    @State private var currentListenerPeriodStart: Date? // Track what period the listener is using
    
    // Sheet presentation states
    @State private var showingSessionSelection = false
    @State private var showingNotesInput = false
    
    // Format hours as "XXh XXm"
    private func formatHours(_ hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return "\(h)h \(m)m"
    }
    
    var body: some View {
        DashboardWidgetCard {
            headerView

            // Offline is stated as its own line rather than as a caption under
            // the title. This is payroll data on a phone that works in school
            // basements, so when the last fetch came from the cache instead of
            // the network, that belongs near the top rather than tucked beside
            // the heading.
            //
            // What this does NOT cover, stated so nobody reads more into it:
            // the first paint of this widget comes from UserDefaults before any
            // fetch resolves, and at that moment the flag still holds whatever
            // the previous session left it as. It reports the last FETCH, not
            // the age of the numbers on screen. Unchanged from before AMB.4.
            if timeTrackingService.isUsingOfflineData {
                offlineRow
            }

            if isLoadingHours {
                DashboardWidgetLoading()
            } else {
                contentView
            }
        }
        .task {
            await timeTrackingService.refreshUserAndStatus()

            // The await above is a network round trip that does not check for
            // cancellation. Leaving home during it meant onDisappear ran first,
            // invalidating a timer that was still nil, and the task then resumed
            // and installed a 1-second repeating Timer on a view that no longer
            // exists — nothing left to ever invalidate it. SwiftUI cancels a
            // .task when its view goes away, so asking is enough.
            guard !Task.isCancelled else { return }

            await MainActor.run {
                loadHoursData()
                startActiveHoursTimer()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
        // AMB.13 MOVED THE WRITES INTO THE SHEETS. This widget used to own two
        // copies of the clock-in and clock-out calls — and both swallowed their
        // failure into a bare comment, on the path this file's own source calls
        // "the app's primary way in and out of a shift". A payroll write that
        // fails silently is the worst shape on this surface, and it was here.
        //
        // Each sheet now performs its own write and reports its own failure in
        // place, which is also why `SessionSelectionView` no longer takes a
        // completion closure: it had three callers, each with their own copy of
        // this Task-and-catch, and one of those callers was dead code.
        .sheet(isPresented: $showingSessionSelection) {
            SessionSelectionView(timeTrackingService: timeTrackingService)
        }
        .sheet(isPresented: $showingNotesInput) {
            ClockOutView(timeTrackingService: timeTrackingService,
                         clockInTime: timeTrackingService.currentTimeEntry?.clockInTime)
        }
    }

    // MARK: - View Components

    private var offlineRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 11, weight: .semibold))
            Text("Offline")
                .font(.caption.weight(.semibold))
            if let lastSync = timeTrackingService.lastSyncTime {
                Text("· last synced \(lastSync.timeAgoDisplay())")
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Capsule().fill(Color.orange.opacity(0.12)))
    }

    private var contentView: some View {
        VStack(spacing: 14) {
            thisWeekSection
            payPeriodSection
        }
    }

    /// This week against 40 hours.
    ///
    /// The arithmetic below is carried over unchanged from the pre-AMB.4 widget —
    /// which week an entry belongs to, when the running entry counts, and where
    /// overtime starts are business rules, and a design phase does not get to
    /// move them (AMB plan, D12). What changed is only how they are drawn.
    @ViewBuilder
    private var thisWeekSection: some View {
        // `banked` is time already recorded; `running` is the open entry, and it
        // is zero when the fetch already counted it (activeEntryIncludedInTotal).
        let banked = currentWeekHours
        let running = activeEntryIncludedInTotal ? 0 : activeHours
        let totalWithActive = banked + running
        let overtime = max(totalWithActive - 40, 0)

        HoursMeter(
            label: "This week",
            // Under 40 the bar is a share of 40; past 40 it is full and split in
            // proportion, which is how the old bar behaved and is the only way
            // "how far past 40 am I" reads at a glance.
            //
            // THE SPLIT IS TAKEN OVER THE TOTAL, INCLUDING THE RUNNING ENTRY, and
            // that is the fix for a contradiction the review caught: the caption
            // beside this bar computes overtime from the total, so when a clock-in
            // in progress is what pushes you past 40 it said "+3h OT" while the bar
            // showed no orange at all. A bar and its own label disagreeing about
            // overtime on a payroll readout is worse than either version alone.
            //
            // The running hours are therefore marked as an OVERLAY on the trailing
            // end rather than appended as a third segment — appending would count
            // them twice, since they are already inside the split above.
            regularFraction: min(totalWithActive, 40) / max(totalWithActive, 40),
            overtimeFraction: max(totalWithActive - 40, 0) / max(totalWithActive, 40),
            activeFraction: running / max(totalWithActive, 40),
            activeMode: .overlay,
            tint: .blue,
            primaryText: overtime > 0 || activeHours > 0
                ? "\(formatHours(totalWithActive)) / 40h"
                : "\(formatHours(currentWeekHours)) / 40h",
            notes: weekNotes(overtime: overtime)
        )
    }

    /// Exactly what the old readout said, in the same precedence. The week
    /// showed OT *or* Active *or* a percentage — never two at once — so this
    /// keeps that rather than quietly starting to show both.
    private func weekNotes(overtime: Double) -> [HoursMeterNote] {
        if overtime > 0 { return [.init(text: "+\(formatHours(overtime)) OT", color: .orange)] }
        if activeHours > 0 { return [.init(text: "Active \(formatHours(activeHours))", color: .blue)] }
        return [.init(text: "\(Int((currentWeekHours / 40.0) * 100))%", color: .secondary)]
    }

    /// The pay period against 80 hours. Same rule: the numbers are the old ones.
    @ViewBuilder
    private var payPeriodSection: some View {
        let running = activeEntryIncludedInTotal ? 0 : activeHours
        let totalWithActive = totalHours + running
        // Scaled to at least 80, or to the real total when the period ran over,
        // so a period past 80 still shows the split rather than a full bar.
        let scale = max(totalWithActive, 80)

        HoursMeter(
            label: "Pay period",
            // regularHours and overtimeHours come from the payroll breakdown and
            // describe BANKED time only — they sum to totalHours, never to
            // totalWithActive. Dividing them by the same scale as `running`
            // keeps the three segments consecutive and stops the running marker
            // landing on hours that are already banked.
            regularFraction: regularHours / scale,
            overtimeFraction: overtimeHours / scale,
            activeFraction: running / scale,
            // APPENDED here, unlike the week, and the difference is in the data
            // rather than a preference: regularHours and overtimeHours come from
            // the payroll breakdown and describe BANKED time only, summing to
            // totalHours. So the running entry genuinely extends the bar past them
            // and its caption also reports banked overtime — bar and label agree.
            activeMode: .appended,
            tint: .indigo,
            primaryText: "\(formatHours(totalWithActive)) / 80h",
            notes: periodNotes
        )
    }

    /// The pay period differs from the week on purpose, and did before this
    /// phase: it shows Active AND overtime together, because in the second week
    /// of a period you can easily be both clocked in and already over.
    private var periodNotes: [HoursMeterNote] {
        var notes: [HoursMeterNote] = []
        if activeHours > 0 {
            notes.append(.init(text: "Active \(formatHours(activeHours))", color: .blue))
        }
        if overtimeHours > 0 {
            notes.append(.init(text: "\(formatHours(overtimeHours)) OT", color: .orange))
        } else if activeHours == 0 {
            notes.append(.init(text: "\(Int((totalHours / 80.0) * 100))%", color: .secondary))
        }
        return notes
    }

    // MARK: - View Components

    private var headerView: some View {
        DashboardWidgetHeader("Hours Tracking", systemImage: "clock.fill", tint: .yellow) {
            clockButton
        }
    }

    /// Clock in and clock out, from the widget header — the app's primary way in
    /// and out of a shift. Red while running (and carrying the live elapsed
    /// figure), green when not.
    private var clockButton: some View {
        Button(action: {
            if timeTrackingService.isClockIn {
                showingNotesInput = true
            } else {
                showingSessionSelection = true
            }
        }) {
            let running = timeTrackingService.isClockIn
            HStack(spacing: 5) {
                Image(systemName: running ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(running ? formatHours(activeHours) : "Clock in")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(running ? Color.red : Color.green)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill((running ? Color.red : Color.green).opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(timeTrackingService.isClockIn ? "Clock out" : "Clock in")
    }

    // MARK: - Helper Methods

    private func startActiveHoursTimer() {
        timer?.invalidate()
        updateActiveHours()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateActiveHours()
        }
    }
    
    private func updateActiveHours() {
        // The entry itself is not read — the running total comes from the
        // service's published ticker — but it still has to EXIST, or a stale
        // `elapsedTime` from a shift that has ended would keep being counted.
        if timeTrackingService.isClockIn, timeTrackingService.currentTimeEntry != nil {
            activeHours = timeTrackingService.elapsedTime / 3600.0
        } else {
            activeHours = 0
        }
    }
    
    private func loadHoursData() {
        // Only show loading if we have no cached data
        if regularHours == 0 && totalHours == 0 {
            isLoadingHours = true
        }

        // Ensure TimeTrackingService has user/org IDs
        Task {
            await timeTrackingService.refreshUserAndStatus()
        }

        // Load pay period settings FIRST, then set up listener
        payPeriodService.loadPayPeriodSettings { success in
            // Now that settings are loaded, check if we need to clear cache
            self.checkAndClearCacheIfNewPeriod()

            // Set up the listener with the correct pay period
            if !self.listenerSetUp {
                self.listenerSetUp = true
                self.setupHoursListener()
            }
        }

        // Fallback: If settings take too long, set up with defaults after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if !self.listenerSetUp {
                self.checkAndClearCacheIfNewPeriod()
                self.listenerSetUp = true
                self.setupHoursListener()
            }
        }
    }
    
    private func checkAndClearCacheIfNewPeriod() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        // Get the last cached period start date
        let lastCachedPeriodStart = UserDefaults.standard.object(forKey: "cached_period_start") as? Date
        
        // Get current pay period
        let currentPeriod = payPeriodService.getCurrentPayPeriod() ?? getDefaultPayPeriod()
        
        // Check if we're in a different pay period than cached
        let shouldClearCache = lastCachedPeriodStart == nil || 
            !calendar.isDate(lastCachedPeriodStart!, equalTo: currentPeriod.0, toGranularity: .day)
        
        if shouldClearCache {
            // Clear all cached values
            UserDefaults.standard.set(0.0, forKey: "cached_regularHours")
            UserDefaults.standard.set(0.0, forKey: "cached_overtimeHours")
            UserDefaults.standard.set(0.0, forKey: "cached_totalHours")
            UserDefaults.standard.set(0.0, forKey: "cached_currentWeekHours")
            
            // Reset state values to force reload
            regularHours = 0
            overtimeHours = 0
            totalHours = 0
            currentWeekHours = 0
            
            // Store the new period start date
            UserDefaults.standard.set(currentPeriod.0, forKey: "cached_period_start")
            UserDefaults.standard.synchronize() // Force immediate write
        }
    }
    
    private func setupHoursListener() {
        // Refresh again in case orgId was just fetched
        Task {
            await timeTrackingService.refreshUserAndStatus()
        }

        // Try to get pay period immediately if available, otherwise use default
        let (payPeriodStart, payPeriodEnd) = payPeriodService.getCurrentPayPeriod() ?? getDefaultPayPeriod()
        
        // Check if we need to restart the listener with new dates
        if let existingStart = currentListenerPeriodStart {
            let calendar = Calendar.current
            if !calendar.isDate(existingStart, equalTo: payPeriodStart, toGranularity: .day) {
                // Clear the cached values since we're in a new period
                regularHours = 0
                overtimeHours = 0
                totalHours = 0
                currentWeekHours = 0
            }
        }
        
        currentListenerPeriodStart = payPeriodStart
        
        // Format dates for queries
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        
        let payPeriodStartStr = dateFormatter.string(from: payPeriodStart)
        let payPeriodEndStr = dateFormatter.string(from: payPeriodEnd)

        // Fetch time entries for the pay period
        Task {
            do {
                let entries = try await timeTrackingService.getTimeEntries(startDate: payPeriodStartStr, endDate: payPeriodEndStr)

                // Calculate overtime breakdown
                let breakdown = self.calculateOvertimeBreakdown(entries: entries, payPeriodStart: payPeriodStart, excludeActiveEntry: false)

                await MainActor.run {
                    self.regularHours = breakdown.regular
                    self.overtimeHours = breakdown.overtime
                    self.totalHours = breakdown.total
                    self.currentWeekHours = breakdown.currentWeek
                    self.activeEntryIncludedInTotal = breakdown.includesActive

                    // Cache values for instant display next time
                    UserDefaults.standard.set(breakdown.regular, forKey: "cached_regularHours")
                    UserDefaults.standard.set(breakdown.overtime, forKey: "cached_overtimeHours")
                    UserDefaults.standard.set(breakdown.total, forKey: "cached_totalHours")
                    UserDefaults.standard.set(breakdown.currentWeek, forKey: "cached_currentWeekHours")

                    // Also save the current period start so we can validate cache later
                    if let periodStart = self.currentListenerPeriodStart {
                        UserDefaults.standard.set(periodStart, forKey: "cached_period_start")
                    }
                    UserDefaults.standard.synchronize() // Force immediate write

                    // Only set loading to false on first load
                    if self.isLoadingHours {
                        self.isLoadingHours = false
                    }

                    self.hasInitialData = true
                }
            } catch {
                await MainActor.run {
                    if self.isLoadingHours {
                        self.isLoadingHours = false
                    }
                }
            }
        }
    }
    
    private func getDefaultPayPeriod() -> (Date, Date) {
        // Use the same default calculation as PayPeriodService
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        // Reference date: 2/25/2024 (Sunday - start of a pay period)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d/yyyy"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        guard let referenceDate = dateFormatter.date(from: "2/25/2024") else {
            let now = Date()
            let twoWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -2, to: now) ?? now
            return (twoWeeksAgo, now)
        }

        let referenceStartOfDay = calendar.startOfDay(for: referenceDate)
        let targetStartOfDay = calendar.startOfDay(for: Date())

        // Calculate days between dates
        let components = calendar.dateComponents([.day], from: referenceStartOfDay, to: targetStartOfDay)
        let daysSinceReference = components.day ?? 0

        let periodLength = 14

        // Calculate complete periods elapsed
        let periodsElapsed = daysSinceReference >= 0 ?
            daysSinceReference / periodLength :
            ((daysSinceReference - periodLength + 1) / periodLength)

        // Calculate the start of the current period
        guard let periodStart = calendar.date(byAdding: .day, value: periodsElapsed * periodLength, to: referenceStartOfDay) else {
            let now = Date()
            let twoWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -2, to: now) ?? now
            return (twoWeeksAgo, now)
        }

        // Calculate the end of the period (13 days later, end of day)
        guard let tempEnd = calendar.date(byAdding: .day, value: periodLength - 1, to: periodStart),
              let periodEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: tempEnd) else {
            return (periodStart, Date())
        }

        return (periodStart, periodEnd)
    }
    
    private func calculateOvertimeBreakdown(entries: [TimeEntry], payPeriodStart: Date, excludeActiveEntry: Bool = false) -> (regular: Double, overtime: Double, total: Double, currentWeek: Double, includesActive: Bool) {
        let calendar = Calendar.current
        let now = Date()
        
        // Calculate which week of the pay period we're currently in
        let daysSincePeriodStart = calendar.dateComponents([.day], from: calendar.startOfDay(for: payPeriodStart), to: calendar.startOfDay(for: now)).day ?? 0
        let currentWeekOfPeriod = (daysSincePeriodStart / 7) + 1 // 1 for first week, 2 for second week

        // Check if active entry is already in the entries list
        var hasActiveEntry = false
        if timeTrackingService.isClockIn,
           let activeEntryId = timeTrackingService.currentTimeEntry?.id {
            hasActiveEntry = entries.contains { $0.id == activeEntryId }
        }
        
        // Group entries by week within the pay period
        var weeklyHours: [Int: Double] = [:] // Week number -> hours
        var currentWeekTotal: Double = 0
        
        for entry in entries {
            // Skip active entry if requested and it exists
            if excludeActiveEntry && timeTrackingService.isClockIn,
               let activeId = timeTrackingService.currentTimeEntry?.id,
               entry.id == activeId {
                continue
            }
            
            // Parse entry date
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            guard let dateString = entry.date,
                  let entryDate = dateFormatter.date(from: dateString) else { continue }
            
            // Calculate which week of the pay period this entry belongs to
            let entryDaysSincePeriodStart = calendar.dateComponents([.day], from: calendar.startOfDay(for: payPeriodStart), to: calendar.startOfDay(for: entryDate)).day ?? 0
            let entryWeekOfPeriod = (entryDaysSincePeriodStart / 7) + 1
            
            // Add hours to the appropriate week
            weeklyHours[entryWeekOfPeriod, default: 0] += entry.durationInHours
            
            // Check if this entry is in the current week of the pay period
            if entryWeekOfPeriod == currentWeekOfPeriod {
                currentWeekTotal += entry.durationInHours
            }
        }
        
        // Calculate regular and overtime hours
        var totalRegular: Double = 0
        var totalOvertime: Double = 0
        
        for (_, hours) in weeklyHours {
            if hours > 40 {
                totalRegular += 40
                totalOvertime += hours - 40
            } else {
                totalRegular += hours
            }
        }
        
        let total = totalRegular + totalOvertime
        
        return (regular: totalRegular, overtime: totalOvertime, total: total, currentWeek: currentWeekTotal, includesActive: hasActiveEntry)
    }
}

// MARK: - Hours meter

/// One line of small print under a meter — overtime, the running entry, or the
/// plain percentage.
struct HoursMeterNote: Identifiable {
    let text: String
    let color: Color
    var id: String { text }
}

/// A labelled hours bar: how much is logged, how much of that is still running,
/// and how much of it is overtime.
///
/// The fractions are computed by the caller rather than in here, because what
/// counts as regular and what counts as overtime is a payroll rule that lives
/// with the data (AMB plan, D12). This view only draws what it is given, which
/// also means the two meters on this widget can scale differently — the week
/// against a fixed 40, the period against 80 or the real total, whichever is
/// larger — without this file knowing why.
struct HoursMeter: View {
    let label: String
    /// THREE CONSECUTIVE SEGMENTS, in this order, summing to the total fill:
    /// banked regular time, banked overtime, then the entry running right now.
    ///
    /// Two earlier cuts of this got it wrong, both worth recording because both
    /// made a FALSE claim about payroll data rather than merely looking wrong.
    /// The first drew the running band past the filled edge onto the empty
    /// track, invisible in light mode, and suppressed it entirely in overtime.
    /// The second made it a slice cut out of the fill — but the pay period's
    /// regular/overtime figures describe BANKED hours only, so that slice
    /// landed on already-banked, clocked-out time and labelled it as running.
    ///
    /// Three plain segments cannot say anything untrue: whatever is banked is
    /// banked, and the running entry is what extends past it.
    let regularFraction: Double
    let overtimeFraction: Double
    let activeFraction: Double
    /// Whether the running entry EXTENDS the bar or merely marks its trailing end.
    ///
    /// Both are needed because the two meters are fed differently. The pay period's
    /// regular/overtime come from the payroll breakdown and cover banked time only,
    /// so the running entry is extra length (.appended). The week's split is taken
    /// over the total, so the running hours are already inside it and marking them
    /// again as a segment would count them twice (.overlay).
    let activeMode: ActiveMode
    let tint: Color

    enum ActiveMode { case appended, overlay }
    let primaryText: String
    let notes: [HoursMeterNote]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    /// The total and its small print, kept together so the one-line and stacked
    /// layouts cannot drift apart.
    private var readoutValues: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(primaryText)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ForEach(notes) { note in
                Text(note.text)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(note.color)
                    .lineLimit(1)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The worst case is the pay period while clocked in AND over 80
            // hours: label, total, "Active 2h 30m" and "0h 15m OT" all at once.
            // At normal sizes that fits on one line; at accessibility sizes it
            // cannot, at any scale factor, so the readout stacks instead of
            // shrinking the payroll figure to nothing.
            //
            // The label carries NO layout priority on purpose. Giving it
            // priority made the NUMBERS the first thing to be truncated, which
            // is precisely backwards on a widget about hours worked.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.subheadline.weight(.medium))
                    readoutValues
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(label)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    readoutValues
                }
                .minimumScaleFactor(0.75)
            }

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))

                    // One continuous run, clipped to a single capsule. Drawn as
                    // separate offset capsules, a small overtime segment
                    // rendered as a lozenge floating in the middle of the bar.
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(tint.gradient)
                            .frame(width: width * clamp(regularFraction))
                        if overtimeFraction > 0 {
                            Rectangle()
                                .fill(Color.orange.gradient)
                                .frame(width: width * clamp(overtimeFraction))
                        }
                        if activeFraction > 0, activeMode == .appended {
                            // Lighter shade of the same tint, not a white wash:
                            // it has to read as "this part is still going" on a
                            // pale track in daylight.
                            Rectangle()
                                .fill(tint.opacity(0.45))
                                .frame(width: width * clamp(activeFraction))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: width)
                    .overlay(alignment: .leading) {
                        // The trailing slice of the fill that is still running.
                        // Lightened ON TOP, so it reads the same whether it sits
                        // over the regular segment, the overtime one, or across
                        // the join between them.
                        if activeFraction > 0, activeMode == .overlay {
                            let filled = clamp(regularFraction + overtimeFraction)
                            let active = clamp(min(activeFraction, filled))
                            Rectangle()
                                .fill(Color.white.opacity(0.4))
                                .frame(width: width * active)
                                .offset(x: width * clamp(filled - active))
                        }
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(accessibilityValue)
        }
    }

    /// The bar is decorative to VoiceOver; the numbers beside it are the content.
    private var accessibilityValue: String {
        ([primaryText] + notes.map(\.text)).joined(separator: ", ")
    }
}

// MARK: - Mileage Widget
struct MileageWidget: View {
    let userName: String
    // Initialize with cached values for instant display
    @State private var currentPeriodMileage: Double = UserDefaults.standard.double(forKey: "cached_currentPeriodMileage")
    @State private var monthMileage: Double = UserDefaults.standard.double(forKey: "cached_monthMileage")
    @State private var yearMileage: Double = UserDefaults.standard.double(forKey: "cached_yearMileage")
    @State private var isLoading = false
    @State private var hasInitialData = false
    @StateObject private var mileageViewModel: MileageReportsViewModel

    init(userName: String) {
        self.userName = userName
        self._mileageViewModel = StateObject(wrappedValue: MileageReportsViewModel.shared)
    }
    
    var body: some View {
        DashboardWidgetCard {
            DashboardWidgetHeader("Mileage", systemImage: "car.fill", tint: .orange) {
                NavigationLink(destination: MileageReportsView(userName: userName)) {
                    Text("View all")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AmbientStyle.brand)
                }
            }

            if isLoading {
                DashboardWidgetLoading()
            } else {
                // The pay period leads: it is the number that turns into money
                // on the next cheque, and it is what people open this for.
                //
                // The caption is NOT decoration. The approved mockup drew this
                // number bare, and porting that faithfully left the only
                // unlabelled figure on the widget sitting directly above two
                // labelled ones — which makes it read as a grand total rather
                // than as this pay period. The old widget captioned all three.
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pay period")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(Int(currentPeriodMileage))")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                        Text("mi")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        // The miles figure is a fixed 30pt and does not grow with
                        // Dynamic Type, but the currency beside it does — without
                        // these the money wrapped or crushed the miles at
                        // accessibility sizes.
                        Text(Formatters.currency(reimbursement(mileageViewModel.currentPeriodSplit,
                                                               cachedMiles: currentPeriodMileage)))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.green)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .minimumScaleFactor(0.7)
                }

                // Only when there IS company mileage, exactly as before — a
                // photographer who only ever drives their own car should not be
                // shown a permanent "Company 0".
                if mileageViewModel.currentPeriodSplit.hasCompany {
                    AmbientPillRow(pills: [
                        .init(text: "Personal \(Int(mileageViewModel.currentPeriodPersonalMiles))",
                              systemImage: "person.fill", tint: .orange),
                        .init(text: "Company \(Int(mileageViewModel.currentPeriodCompanyMiles))",
                              systemImage: "building.2.fill", tint: .teal),
                    ], density: .compact)
                }

                Divider().opacity(0.4)

                HStack(alignment: .top) {
                    mileageStat("This month", miles: monthMileage,
                                pay: reimbursement(mileageViewModel.monthSplit, cachedMiles: monthMileage))
                    Spacer()
                    mileageStat("This year", miles: yearMileage,
                                pay: reimbursement(mileageViewModel.yearSplit, cachedMiles: yearMileage),
                                trailing: true)
                }

                // The only place the app says where mileage comes from. This
                // widget is read-only and there is no other affordance, so
                // without this line it looks broken rather than derived.
                Text("Enter mileage via Daily Job Reports")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .task {
            await MainActor.run {
                loadMileageData()
            }
        }
    }

    /// A period's miles with its money underneath. The dollars are not optional
    /// decoration — two of the three figures on this widget were dropped by the
    /// first design, on a screen whose entire job is "what am I owed".
    private func mileageStat(_ caption: String, miles: Double, pay: Double,
                             trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Int(miles)) mi")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
            // `Formatters.currency`, not the `String(format: "$%.2f")` this widget
            // used to spell it with: that one has no thousands separator, so a
            // four-figure year total read "$1234.50". Deleting the private helper is
            // the point — `Formatters.currency`'s own doc names this exact call site
            // as the one it replaced (AMB.9), and a second spelling left beside it is
            // how there came to be four.
            Text(Formatters.currency(pay))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.green)
                .monospacedDigit()
        }
    }


    private func loadMileageData() {
        // Only show loading if we have no cached data
        if currentPeriodMileage == 0 && monthMileage == 0 && yearMileage == 0 {
            isLoading = true
        }

        // Listen for changes to the view model
        mileageViewModel.listenForMileageUpdates {
            DispatchQueue.main.async {
                self.currentPeriodMileage = self.mileageViewModel.currentPeriodMileage
                self.monthMileage = self.mileageViewModel.monthMileage
                self.yearMileage = self.mileageViewModel.yearMileage
                
                // Cache values for instant display next time
                UserDefaults.standard.set(self.currentPeriodMileage, forKey: "cached_currentPeriodMileage")
                UserDefaults.standard.set(self.monthMileage, forKey: "cached_monthMileage")
                UserDefaults.standard.set(self.yearMileage, forKey: "cached_yearMileage")

                if self.isLoading {
                    self.isLoading = false
                }
                self.hasInitialData = true
            }
        }
        
        // Trigger initial load (also refreshes personal + company rates)
        mileageViewModel.loadRecords()
    }

    /// Reimbursement for a bucket. Once the split has loaded, use its vehicle-aware
    /// total; before then (cold start), estimate from the cached total miles at the
    /// personal rate so miles and dollars appear together instead of a bare $0.00.
    private func reimbursement(_ split: VehicleRates.Split, cachedMiles: Double) -> Double {
        split.totalMiles > 0 ? split.totalCompensation : cachedMiles * mileageViewModel.personalRate
    }
}

// MARK: - Upcoming Shifts Widget
struct UpcomingShiftsWidget: View {
    let sessions: [Session]
    let isLoading: Bool
    let weatherDataBySession: [String: WeatherData]
    let onRefresh: () -> Void
    let onSessionTap: (Session) -> Void

    var body: some View {
        DashboardWidgetCard {
            DashboardWidgetHeader("Upcoming Shifts", systemImage: "calendar", tint: .red) {
                HStack(spacing: 10) {
                    if !sessions.isEmpty {
                        Text("\(sessions.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AmbientStyle.brand)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh shifts")
                }
            }

            if isLoading {
                DashboardWidgetLoading()
            } else if sessions.isEmpty {
                DashboardWidgetEmpty(
                    systemImage: "calendar.badge.exclamationmark",
                    title: "No upcoming shifts",
                    // The filter is startOfToday up to startOfToday + 3 days, so
                    // the old "Next 2 days" was wrong by a day. Corrected here to
                    // match the code rather than changing the code to match it.
                    message: "Nothing scheduled for you in the next 3 days."
                )
            } else {
                VStack(spacing: 8) {
                    // Key by per-day occurrence: a multi-day session yields one row
                    // per day, all sharing the same session id.
                    ForEach(sessions.prefix(3), id: \.dayOccurrenceKey) { session in
                        Button(action: { onSessionTap(session) }) {
                            ShiftWidgetRow(
                                session: session,
                                weatherData: getWeatherForSession(session)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                if sessions.count > 3 {
                    // Without this the fourth shift is unreachable from home.
                    NavigationLink(destination: ScheduleView()) {
                        HStack(spacing: 4) {
                            Spacer()
                            Text("View all (\(sessions.count) shifts)")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                            Spacer()
                        }
                        .foregroundStyle(AmbientStyle.brand)
                        .padding(.top, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func getWeatherForSession(_ session: Session) -> WeatherData? {
        guard let sessionDate = session.startDate,
              let location = session.location,
              !location.isEmpty else {
            return nil
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: sessionDate)
        let cacheKey = "\(location)-\(dateString)"
        
        return weatherDataBySession[cacheKey]
    }
}

// MARK: - Shift row

/// A shift as home draws it, in the schedule's own vocabulary.
///
/// This replaces `CompactShiftRow`, and the point of the replacement is not the
/// styling. The old row painted its colour rail from
/// `positionColorMap[session.position]`, but `Session.position` returns
/// `session_types.first` — a session TYPE id such as "sports" — while
/// `positionColorMap` is keyed by JOB TITLES ("Photographer 1", "Delivery").
/// The lookup missed, its inline fallback map was keyed by job titles too and
/// missed as well, and every row fell through to `.blue`. Nearly every shift on
/// the dashboard was blue no matter what colour the scheduler chose.
///
/// It now uses `ScheduleStyle.accent(for:)` — the scheduler's `session_color`,
/// the same source the converted schedule reads — which is what makes home and
/// the schedule finally agree about what a job looks like.
struct ShiftWidgetRow: View {
    let session: Session
    let weatherData: WeatherData?

    var body: some View {
        let accent = ScheduleStyle.accent(for: session)
        return HStack(spacing: 12) {
            // When, in a gutter: the day above the times. The widget spans
            // today, tomorrow AND the day after — that is the range the view
            // model filters to — so a row without a day says the wrong thing
            // two thirds of the time.
            VStack(spacing: 1) {
                Text(dayLabel)
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(isToday ? accent : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(session.startDate.map { Formatters.shortTime.string(from: $0) } ?? "—")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Rectangle()
                    .fill(accent.opacity(0.35))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                Text(session.endDate.map { Formatters.shortTime.string(from: $0) } ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 58)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(session.schoolName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let weather = weatherData, let iconName = weather.iconSystemName {
                        HStack(spacing: 3) {
                            Image(systemName: iconName)
                                .font(.caption)
                                .foregroundStyle(weather.conditionColor)
                            Text(weather.temperatureString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .fixedSize()
                    }
                }
                // Types, plus the multi-day "Day N of M" marker, exactly as the
                // schedule assembles them — one definition, so the two screens
                // cannot drift apart again.
                ScheduleTypePills(session: session, density: .compact)
                if !session.photographers.isEmpty {
                    AmbientAvatarStack(subjects: ScheduleStyle.avatarSubjects(session.photographers),
                                       size: 20, maxVisible: 4)
                }
            }
            Spacer(minLength: 0)
        }
        .ambientCard(density: .compact, border: .hairline(accent.opacity(0.35)))
    }

    private var isToday: Bool {
        guard let start = session.startDate else { return false }
        return Calendar.current.isDateInToday(start)
    }

    /// "Today" / "Tomorrow" / "Wed 30" — short enough for a 58pt gutter, which
    /// `Formatters.relativeDay` is not (it falls back to a full weekday name).
    private var dayLabel: String {
        guard let start = session.startDate else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(start) { return "Today" }
        if calendar.isDateInTomorrow(start) { return "Tomorrow" }
        return "\(Formatters.weekdayShort.string(from: start)) \(Formatters.dayNumber.string(from: start))"
    }
}

// MARK: - iPad Widgets

struct SportsRostersWidget: View {
    @State private var todaysSportsShoots: [SportsShoot] = []
    @State private var isLoading = true
    @State private var loadTask: Task<Void, Never>?
    @ObservedObject var tabBarManager: TabBarManager
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    @Environment(\.scenePhase) private var scenePhase

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }
    
    var body: some View {
        DashboardWidgetCard {
            DashboardWidgetHeader("Sports Rosters", systemImage: "sportscourt", tint: .orange) {
                DashboardHeaderLink("View all") {
                    tabBarManager.selectedTab = "sportsShoot"
                }
            }

            if isLoading {
                DashboardWidgetLoading()
            } else if todaysSportsShoots.isEmpty {
                DashboardWidgetEmpty(
                    systemImage: "sportscourt",
                    title: "No sports rosters today",
                    message: "Rosters appear here on the day of the shoot."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(todaysSportsShoots.prefix(3)) { shoot in
                        shootRow(shoot)
                    }
                }

                if todaysSportsShoots.count > 3 {
                    let extra = todaysSportsShoots.count - 3
                    DashboardMoreRow(title: "\(extra) more roster\(extra == 1 ? "" : "s") today") {
                        tabBarManager.selectedTab = "sportsShoot"
                    }
                }
            }
        }
        .onAppear {
            loadSportsRosters()
        }
        .onDisappear {
            // Cancel any ongoing load task when view disappears
            loadTask?.cancel()
            loadTask = nil
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background || newPhase == .inactive {
                // Cancel loading when going to background to prevent crashes
                loadTask?.cancel()
                loadTask = nil
            } else if newPhase == .active {
                // Reload data when returning to foreground
                loadSportsRosters()
            }
        }
    }

    private func loadSportsRosters() {
        // Cancel any previous load task
        loadTask?.cancel()
        guard !storedUserOrganizationID.isEmpty else {
            self.isLoading = false
            return
        }

        isLoading = true

        // Fetch all sports shoots for the organization
        loadTask = Task {
            // Check for cancellation before network call
            guard !Task.isCancelled else {
                await MainActor.run {
                    self.isLoading = false
                }
                return
            }
            do {
                let shoots = try await SportsShootService.shared.fetchAllSportsShoots(forOrganization: storedUserOrganizationID)

                // Check for cancellation after network call
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.isLoading = false
                    }
                    return
                }

                // Filter for today's shoots - use date components to ignore timezone
                let calendar = Calendar.current
                let todayComponents = calendar.dateComponents([.year, .month, .day], from: Date())

                print("📅 SportsRosterWidget: Today's components - Year: \(todayComponents.year ?? 0), Month: \(todayComponents.month ?? 0), Day: \(todayComponents.day ?? 0)")
                print("📅 SportsRosterWidget: Fetched \(shoots.count) total shoots")

                await MainActor.run {
                    self.todaysSportsShoots = shoots.filter { shoot in
                        let shootComponents = calendar.dateComponents([.year, .month, .day], from: shoot.shootDate)
                        let isToday = shootComponents.year == todayComponents.year &&
                                     shootComponents.month == todayComponents.month &&
                                     shootComponents.day == todayComponents.day
                        let isNotArchived = !shoot.isArchived

                        print("📅 Shoot: \(shoot.schoolName) - Year: \(shootComponents.year ?? 0), Month: \(shootComponents.month ?? 0), Day: \(shootComponents.day ?? 0) -> IsToday: \(isToday), IsNotArchived: \(isNotArchived)")

                        return isNotArchived && isToday
                    }.sorted { $0.shootDate < $1.shootDate }

                    print("✅ SportsRosterWidget: Showing \(self.todaysSportsShoots.count) rosters for today")
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.todaysSportsShoots = []
                    self.isLoading = false
                }
            }
        }
    }
    
    /// The route is said OUT LOUD, because two rows that look the same open two
    /// different tools and the only thing that decides it is whether the shoot is
    /// linked to Production. The old row said "View" for the Captura side; naming
    /// the tool is clearer and was approved with the design.
    private func shootRow(_ shoot: SportsShoot) -> some View {
        Button {
            // Routing unchanged: linked to Production opens FP Sports, otherwise
            // the Captura roster.
            TabBarManager.shared.selectedSportsShoot = shoot
            tabBarManager.selectedTab = shoot.galleryId != nil ? "focalPointSports" : "sportsShoot"
        } label: {
            HStack(spacing: 12) {
                Image(systemName: getSportsIcon(for: shoot.sportName))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.orange.opacity(0.16)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(shoot.schoolName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(shoot.sportName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("·").foregroundStyle(.tertiary)
                        Text(dateFormatter.string(from: shoot.shootDate))
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)

                AmbientBadge(text: shoot.galleryId != nil ? "FP Sports" : "Captura",
                             systemImage: shoot.galleryId != nil ? "bolt.fill" : "sportscourt.fill",
                             tint: shoot.galleryId != nil ? .green : .blue)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .ambientCard(density: .compact, border: .hairline(Color.orange.opacity(0.25)))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func getSportsIcon(for sportName: String) -> String {
        let sessionTypeString = sportName.lowercased()
        
        if sessionTypeString.contains("basketball") {
            return "basketball"
        } else if sessionTypeString.contains("football") {
            return "football"
        } else if sessionTypeString.contains("soccer") {
            return "soccerball"
        } else if sessionTypeString.contains("baseball") || sessionTypeString.contains("softball") {
            return "baseball"
        } else if sessionTypeString.contains("tennis") {
            return "tennis.racket"
        } else if sessionTypeString.contains("golf") {
            return "flag"
        } else if sessionTypeString.contains("swim") {
            return "drop"
        } else if sessionTypeString.contains("track") || sessionTypeString.contains("cross country") {
            return "figure.run"
        } else if sessionTypeString.contains("volleyball") {
            return "volleyball"
        } else {
            return "sportscourt"
        }
    }
}

struct ClassGroupsWidget: View {
    @StateObject private var service = ClassGroupJobService.shared
    @State private var organizationId: String?
    @State private var todaysJobs: [ClassGroupJob] = []
    @State private var isLoading = true
    @State private var showingCreateJob = false
    @ObservedObject var tabBarManager: TabBarManager
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    private func jobRow(_ job: ClassGroupJob) -> some View {
        Button {
            // Both the id AND the type, so the Groups screen opens on the right
            // segment. Unchanged from before the conversion.
            tabBarManager.selectedClassGroupJobId = job.id
            tabBarManager.selectedClassGroupJobType = job.jobType
            tabBarManager.selectedTab = "classGroups"
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(job.schoolName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(dateFormatter.string(from: job.sessionDate))
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                AmbientPillRow(pills: pills(for: job), density: .compact)
            }
            .ambientCard(density: .compact, border: .hairline(Color.purple.opacity(0.25)))
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// A job with nothing added yet is the case worth reading first, so it takes the
    /// warning colour rather than being a quiet zero. The nouns are the job type's
    /// own, singular and plural — a "class" is not a "club".
    private func pills(for job: ClassGroupJob) -> [AmbientPill] {
        var pills: [AmbientPill] = []
        if job.classGroupCount > 0 {
            let noun = job.classGroupCount == 1
                ? ClassGroupJobType.countNoun(job.jobType)
                : ClassGroupJobType.countNounPlural(job.jobType)
            pills.append(.init(text: "\(job.classGroupCount) \(noun)",
                               systemImage: "person.3", tint: .blue))
        } else {
            pills.append(.init(text: "No \(ClassGroupJobType.countNounPlural(job.jobType)) added",
                               systemImage: "exclamationmark.triangle.fill", tint: .orange))
        }
        if job.totalImageCount > 0 {
            pills.append(.init(text: "\(job.totalImageCount)", systemImage: "photo", tint: .green))
        }
        pills.append(.init(text: ClassGroupJobType.badgeLabel(job.jobType), tint: .purple))
        return pills
    }

    var body: some View {
        DashboardWidgetCard {
            DashboardWidgetHeader("Group Jobs", systemImage: "person.3.fill", tint: .purple) {
                // The widget's only write action, and it stays a filled button
                // rather than a text link — it is the one thing you can DO here.
                Button {
                    showingCreateJob = true
                } label: {
                    Label("Add jobs", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        // ambient-allow: a filled action button, not a card.
                        .background(Capsule().fill(Color.purple))
                }
                .buttonStyle(.plain)
            }

            if isLoading {
                DashboardWidgetLoading()
            } else if todaysJobs.isEmpty {
                DashboardWidgetEmpty(
                    systemImage: "person.3.fill",
                    title: "No group jobs today",
                    message: "Add the classes, clubs or candids you are shooting.",
                    actionTitle: "Add group jobs",
                    tint: .purple,
                    action: { showingCreateJob = true }
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(todaysJobs.prefix(3)) { job in
                        jobRow(job)
                    }
                }

                if todaysJobs.count > 3 {
                    DashboardMoreRow(title: "View all (\(todaysJobs.count) jobs)") {
                        // Clearing BOTH selections is what makes the Groups screen
                        // open on its full list rather than on a stale job.
                        tabBarManager.selectedClassGroupJobId = nil
                        tabBarManager.selectedClassGroupJobType = nil
                        tabBarManager.selectedTab = "classGroups"
                    }
                }
            }
        }
        .onAppear {
            loadClassGroupJobs()
        }
        .sheet(isPresented: $showingCreateJob) {
            CreateClassGroupJobView(initialJobType: "classGroups") { _ in
                // Refresh jobs after creation
                loadClassGroupJobs()
            }
        }
    }
    
    private func loadClassGroupJobs() {
        isLoading = true
        
        UserManager.shared.getCurrentUserOrganizationID { orgId in
            guard let organizationId = orgId else {
                self.isLoading = false
                return
            }
            
            self.organizationId = organizationId
            
            // Fetch all jobs for the organization
            service.fetchAllClassGroupJobs(forOrganization: organizationId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let jobs):
                        // Filter for today's jobs
                        let calendar = Calendar.current
                        let today = calendar.startOfDay(for: Date())
                        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

                        self.todaysJobs = jobs.filter { job in
                            job.sessionDate >= today && job.sessionDate < tomorrow
                        }.sorted { $0.sessionDate < $1.sessionDate }

                    case .failure:
                        self.todaysJobs = []
                    }
                    
                    self.isLoading = false
                }
            }
        }
    }
}

struct PhotoshootNotesWidget: View {
    // Access the same storage as PhotoshootNotesView
    @AppStorage("photoshootNotes") private var storedNotesData: Data = Data()
    @State private var notes: [PhotoshootNote] = []
    @State private var selectedNote: PhotoshootNote? = nil
    @State private var schoolOptions: [SchoolItem] = []
    @State private var todaySessions: [Session] = []
    @State private var isLoading = false
    @State private var showingFullView = false

    private let sessionService = SessionService.shared
    private let subscriptionId = UUID()
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
    
    private var todayDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }

    // Helper to get selected school for a note
    private func getSelectedSchool(for note: PhotoshootNote) -> SchoolItem {
        if let match = schoolOptions.first(where: { $0.name == note.school }) {
            return match
        }
        if let first = schoolOptions.first {
            print("⚠️ School '\(note.school)' not found in options, using first available: '\(first.name)'")
            return first
        }
        print("⚠️ No schools available for note, using fallback 'Unknown' school")
        return SchoolItem(id: "unknown", name: "Unknown", address: "", coordinates: nil)
    }

    /// One note in the strip. Selection is the card's own `highlighted` state plus a
    /// strong border, rather than a hand-rolled tint — same vocabulary as every other
    /// selected thing in the app now.
    private func noteChip(_ note: PhotoshootNote) -> some View {
        let isSelected = selectedNote?.id == note.id
        return Button {
            selectedNote = note
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(dateFormatter.string(from: note.timestamp))
                        .font(.caption2.weight(.semibold)).monospacedDigit()
                    if note.photoURLs.count > 0 {
                        Image(systemName: "photo").font(.system(size: 9))
                        Text("\(note.photoURLs.count)").font(.caption2)
                    }
                    Spacer(minLength: 0)
                    // Green submitted, blue synced, orange not yet — unchanged.
                    Circle().fill(syncColor(for: note)).frame(width: 6, height: 6)
                }
                .foregroundStyle(.secondary)

                Text(note.school.isEmpty ? "No school" : note.school)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(note.noteText.isEmpty ? "(No content)" : note.noteText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .frame(width: 132, height: 76, alignment: .topLeading)
            .ambientCard(density: .compact,
                         state: isSelected ? .highlighted : .normal,
                         border: isSelected ? .strong(Color.blue)
                                            : .hairline(Color.primary.opacity(0.07)))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func syncColor(for note: PhotoshootNote) -> Color {
        if note.status == .submitted { return .green }
        return note.syncedToServer ? .blue : .orange
    }

    private func syncLabel(for note: PhotoshootNote) -> String {
        if note.status == .submitted { return "Submitted" }
        return note.syncedToServer ? "Synced" : "Not synced"
    }

    /// The editor. THIS WIDGET IS THE ONLY ONE ON THE DASHBOARD THAT WRITES DATA, and
    /// every binding below still writes straight through to the stored note on each
    /// keystroke, exactly as before — the conversion changed how it looks, not when it
    /// saves.
    @ViewBuilder
    private func noteEditor(_ note: PhotoshootNote) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "building.columns.fill")
                    .font(.caption).foregroundStyle(.secondary)
                if schoolOptions.isEmpty {
                    Text("Loading schools…")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ProgressView().scaleEffect(0.7)
                } else {
                    Picker("", selection: Binding(
                        get: { getSelectedSchool(for: note) },
                        set: { newSchool in
                            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                                notes[index].school = newSchool.name
                                selectedNote = notes[index]
                                saveNotes()
                            }
                        }
                    )) {
                        ForEach(schoolOptions, id: \.id) { school in
                            Text(school.name).tag(school)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .labelsHidden()
                }
                Spacer(minLength: 0)
                AmbientBadge(text: syncLabel(for: note), tint: syncColor(for: note))
            }

            TextEditor(text: Binding(
                get: { note.noteText },
                set: { newValue in
                    if let index = notes.firstIndex(where: { $0.id == note.id }) {
                        notes[index].noteText = newValue
                        selectedNote = notes[index]
                        saveNotes()
                    }
                }
            ))
            .font(.subheadline)
            .frame(height: 96)
            // iOS 16.0+, and this app's floor is 16.6, so no availability dance.
            .scrollContentBackground(.hidden)
            .padding(8)
            // ambient-allow: a text input, not a card. An input needs an opaque fill
            // to read as writable; a material would let the ambient wash through the
            // thing you are typing into.
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1))

            HStack(spacing: 12) {
                Text("\(note.noteText.count) characters")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                if note.photoURLs.count > 0 {
                    Label("\(note.photoURLs.count) photo\(note.photoURLs.count == 1 ? "" : "s")",
                          systemImage: "photo")
                        .font(.caption2).foregroundStyle(.blue)
                }
                Spacer()
                Button {
                    deleteNote(note)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }

    var body: some View {
        DashboardWidgetCard {
            DashboardWidgetHeader("Photoshoot Notes", systemImage: "note.text", tint: .blue) {
                HStack(spacing: 14) {
                    Button(action: createNewNote) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 19))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New note")

                    Button {
                        showingFullView = true
                    } label: {
                        Image(systemName: "arrow.up.forward.circle")
                            .font(.system(size: 19))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open all notes")
                }
            }

            if notes.isEmpty {
                DashboardWidgetEmpty(
                    systemImage: "note.text",
                    title: "No notes yet",
                    message: "Notes you write on a job are kept here until they sync.",
                    actionTitle: "Add note",
                    tint: .blue,
                    action: createNewNote
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Newest first, five shown — unchanged.
                        ForEach(notes.sorted(by: { $0.timestamp > $1.timestamp }).prefix(5)) { note in
                            noteChip(note)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .ambientNoBounceWhenShort()

                if let note = selectedNote {
                    noteEditor(note)
                }
            }
        }
        .onAppear {
            loadNotes()
            loadSchoolOptions()
            loadScheduleForToday()
        }
        .onDisappear {
            sessionService.stopListeningToSessions(subscriptionId: subscriptionId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            // Re-subscribe when app returns to foreground
            loadScheduleForToday()
        }
        .sheet(isPresented: $showingFullView) {
            NavigationView {
                PhotoshootNotesView()
                    .navigationBarTitle("Photoshoot Notes", displayMode: .inline)
                    .navigationBarItems(
                        leading: Button("Done") {
                            showingFullView = false
                        }
                    )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createNewNote() {
        // Get user info from AppStorage
        let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let userID = UserDefaults.standard.string(forKey: "userID") ?? ""
        let photographerName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)

        let newNote = PhotoshootNote(
            id: UUID(),
            timestamp: Date(),
            school: "",
            noteText: "",
            photoURLs: [],
            status: .draft,
            submittedAt: nil,
            dailyReportId: nil,
            syncedToServer: false,
            lastSyncedAt: nil,
            photographerName: photographerName.isEmpty ? "Unknown" : photographerName,
            photographerID: userID,
            shootType: "photoshoot"
        )
        notes.append(newNote)
        selectedNote = newNote

        // Try to set school from today's schedule
        setSchoolFromSchedule(for: newNote)

        saveNotes()
    }
    
    private func deleteNote(_ note: PhotoshootNote) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes.remove(at: index)
            if selectedNote?.id == note.id {
                selectedNote = nil
            }
            saveNotes()
        }
    }
    
    private func loadNotes() {
        if let decoded = try? JSONDecoder().decode([PhotoshootNote].self, from: storedNotesData) {
            notes = decoded
        }
    }
    
    private func saveNotes() {
        if let encoded = try? JSONEncoder().encode(notes) {
            storedNotesData = encoded
        }
    }
    
    private func loadSchoolOptions() {
        Task {
            guard let orgID = await withCheckedContinuation({ continuation in
                UserManager.shared.getCurrentUserOrganizationID { orgID in
                    continuation.resume(returning: orgID)
                }
            }) else { return }

            do {
                let supabase = SupabaseManager.shared.client

                struct SchoolRecord: Decodable {
                    let id: String
                    let value: String?
                    let school_address: String?
                    let coordinates: String?
                }

                let schools: [SchoolRecord] = try await supabase
                    .from("schools")
                    .select("id, value, school_address, coordinates")
                    .eq("organization_id", value: orgID)
                    .eq("type", value: "school")
                    .execute()
                    .value

                await MainActor.run {
                    var temp: [SchoolItem] = []
                    for school in schools {
                        if let value = school.value,
                           let address = school.school_address {
                            let item = SchoolItem(id: school.id, name: value, address: address, coordinates: school.coordinates)
                            temp.append(item)
                        }
                    }
                    temp.sort { $0.name.lowercased() < $1.name.lowercased() }
                    self.schoolOptions = temp

                    // Auto-set school for selected note if empty
                    if let note = self.selectedNote, note.school.isEmpty {
                        self.setSchoolFromSchedule(for: note)
                    }
                }
            } catch {
                print("Error loading school options: \(error.localizedDescription)")
            }
        }
    }
    
    private func loadScheduleForToday() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        guard let currentUserID = UserManager.shared.getCurrentUserID() else { return }

        // Get current user email for fallback matching
        let currentUserEmail = UserDefaults.standard.string(forKey: "userEmail")

        let organizationID = UserDefaults.standard.string(forKey: "userOrganizationID") ?? ""
        guard !organizationID.isEmpty else {
            return
        }

        // Use startListeningToSessions with immediate removal for one-time fetch
        sessionService.startListeningToSessions(
            subscriptionId: subscriptionId,
            organizationID: organizationID,
            includeUnpublished: false  // Dashboard shows only published sessions
        ) { sessions in
            let sessionsForToday = sessions.filter { session in
                guard let sessionDate = session.startDate else { return false }
                let isToday = sessionDate >= startOfDay && sessionDate < endOfDay
                let isUserAssigned = session.isUserAssigned(userID: currentUserID, userEmail: currentUserEmail)
                return isToday && isUserAssigned
            }

            DispatchQueue.main.async {
                self.todaySessions = sessionsForToday

                // Auto-set school for selected note if needed
                if let note = self.selectedNote, note.school.isEmpty {
                    self.setSchoolFromSchedule(for: note)
                }
            }
        }

        // Remove listener after first callback for one-time fetch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            sessionService.stopListeningToSessions(subscriptionId: subscriptionId)
        }
    }
    
    private func setSchoolFromSchedule(for note: PhotoshootNote) {
        guard !todaySessions.isEmpty && !schoolOptions.isEmpty else { return }
        
        let sortedSessions = todaySessions.sorted { (a, b) -> Bool in
            guard let aStart = a.startDate, let bStart = b.startDate else { return false }
            return aStart < bStart
        }
        
        if let firstSession = sortedSessions.first,
           schoolOptions.contains(where: { $0.name == firstSession.schoolName }) {
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index].school = firstSession.schoolName
                selectedNote = notes[index]
                saveNotes()
            }
        }
    }
}

// MARK: - Tasks Widget
struct TasksWidget: View {
    @StateObject private var viewModel = TasksViewModel()
    @ObservedObject var tabBarManager: TabBarManager
    @State private var showingCreateTask = false
    @State private var selectedTask: TaskItem? = nil

    private var urgentTasks: [TaskItem] {
        // Get tasks ASSIGNED to current user (not tasks they created for others)
        let currentUserId = (UserManager.shared.getCurrentUserIDUnified() ?? "").lowercased()
        return viewModel.tasks
            .filter { task in
                task.status != .completed &&
                task.assignedTo.contains { $0.lowercased() == currentUserId }
            }
            .sorted { lhs, rhs in
                // Sort overdue first, then by priority, then by due date
                if lhs.isOverdue != rhs.isOverdue {
                    return lhs.isOverdue
                }
                if lhs.priority != rhs.priority {
                    return lhs.priority.sortOrder > rhs.priority.sortOrder
                }
                if let lhsDue = lhs.dueDate, let rhsDue = rhs.dueDate {
                    return lhsDue < rhsDue
                }
                return lhs.createdAt > rhs.createdAt
            }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        DashboardWidgetCard {
            DashboardWidgetHeader("Tasks", systemImage: "checklist", tint: .green) {
                HStack(spacing: 12) {
                    // The widget's only write action. Dropping it would leave
                    // home able to complete a task but never to add one.
                    Button(action: { showingCreateTask = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 19))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New task")

                    Button(action: { tabBarManager.selectedTab = "tasks" }) {
                        Text("View all")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AmbientStyle.brand)
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.isLoading && viewModel.tasks.isEmpty {
                DashboardWidgetLoading()
            } else if urgentTasks.isEmpty {
                DashboardWidgetEmpty(
                    systemImage: "checkmark.circle",
                    title: "No tasks",
                    message: "You're all caught up!"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(urgentTasks) { task in
                        TaskPreviewRow(
                            task: task,
                            onToggleComplete: {
                                viewModel.toggleTaskCompletion(task)
                            },
                            onOpen: { selectedTask = task }
                        )
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadTasks()
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .sheet(isPresented: $showingCreateTask) {
            CreateTaskView(onTaskCreated: { newTask in
                viewModel.createTask(newTask)
                showingCreateTask = false
            })
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task, onTaskUpdated: { updatedTask in
                viewModel.updateTask(updatedTask)
            })
        }
    }
}

// MARK: - Task Preview Row
struct TaskPreviewRow: View {
    let task: TaskItem
    let onToggleComplete: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // The checkbox is a real control and stays outside the row's own tap
            // target — ticking a task off from home must never open it instead.
            Button(action: onToggleComplete) {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(task.status == .completed ? Color.green : Color.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(task.status == .completed ? "Mark not done" : "Mark done")

            // The priority spine is gone (operator, 2026-07-25). It did not read
            // right on a card, and the Tasks screen drops it in the same pass —
            // these two rows are the same object seen twice. Priority still
            // reaches the row through the trailing glyph below.
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    AmbientBadge(text: task.status.displayName, tint: statusColor)

                    if let dueDate = task.dueDate {
                        Label(relativeDateString(from: dueDate),
                              systemImage: task.isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                            .font(.caption2)
                            .foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
                    }

                    if !task.subtasks.isEmpty {
                        let completed = task.subtasks.filter { $0.completed }.count
                        Label("\(completed)/\(task.subtasks.count)", systemImage: "checklist")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            // Carries what the spine used to, the same way the Tasks card does:
            // urgent and high only.
            if task.priority == .urgent || task.priority == .high {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(priorityColor)
            }
        }
        .ambientCard(density: .compact, border: .hairline(Color.primary.opacity(0.07)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    private var priorityColor: Color {
        switch task.priority {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .todo: return .gray
        case .inProgress: return .blue
        case .completed: return .green
        }
    }

    private func relativeDateString(from date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}