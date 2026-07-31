//  ScheduleView.swift
//  Iconik Employee — the schedule
//
//  Replaces SlingWeeklyView (deleted in the same commit). Same data, same
//  manager tools, new shape: the screen leads with a live countdown to the next
//  call time, and the photographer picks how the rest is read —
//
//    Day       one day at a time from a capsule strip. Best on a shoot day.
//    Timeline  a continuous time-gutter scroll anchored on today, with finished
//              days behind a grey band. Best for planning a stretch.
//
//  The choice is per-user (@AppStorage) and sticks.
//
//  Everything the old screen could do, this does: the realtime session listener,
//  time off, My/All filtering, publish-a-day and create for managers, offline
//  state, and per-day occurrences of multi-day jobs.
//
//  PUB.1 (2026-07-25) changed two things about WHAT this screen shows.
//    Drafts are visible to everyone, so a photographer can see what work is
//    coming, grouped under their own heading and never mixed in with announced
//    shifts. Who is on a draft is dropped before anything renders unless the
//    viewer can edit the schedule — see DraftCrew.
//    The staffing temperature is gone for everyone: the heat-coloured dot per
//    day, its breakdown popover, and the long press that was supposed to open
//    the popover but never fired — it was attached to a Button, whose own
//    gesture wins, inside a horizontal ScrollView whose scroll gesture competes
//    for the same touch. The dot that means "you are on this day" stays.
//
//  Deliberately NOT carried over: the per-card weather fetch. It was keyed off
//  `session.location`, which is hard-coded to nil in the Session model, so it
//  could never fire. Weather lives in the shift detail, where it reads the
//  school's real coordinates.

import SwiftUI

struct ScheduleView: View {
    // MARK: Services

    // @ObservedObject, not a plain let: the offline / last-synced banner reads
    // this service's @Published connectivity state and has to be invalidated by it.
    @ObservedObject private var sessionService = SessionService.shared
    private let timeOffService = TimeOffService.shared
    private let userManager = UserManager.shared
    @ObservedObject private var organizationService = OrganizationService.shared
    // Observed, not read statically: the index bakes in whether this viewer may
    // see a draft's crew, and permissions load ASYNCHRONOUSLY after sign-in. An
    // index built before they land would keep a scheduler's drafts redacted —
    // and a redacted session must never reach the editor, which seeds its crew
    // picker from exactly that array.
    @ObservedObject private var permissionsService = PermissionsService.shared
    // PSH.2: a tapped session/job-box push parks a PendingDeepLink here; this screen
    // consumes it once the session list can answer for it. Plain let, NOT
    // @ObservedObject (review round): observing the whole manager re-evaluated the
    // app's largest view body on every keyboard/tab/overlay change.
    private let tabBarManager = TabBarManager.shared

    // MARK: Data

    @State private var sessions: [Session] = []
    @State private var timeOff: [TimeOffCalendarEntry] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var isListening = false
    private let subscriptionId = UUID()

    // MARK: View state

    @AppStorage("scheduleLayout") private var layoutRaw = ScheduleLayout.day.rawValue
    @AppStorage("scheduleMode") private var modeRaw = ScheduleMode.myShifts.rawValue
    @AppStorage("userOrganizationID") private var organizationID: String = ""

    @State private var weekOffset = 0
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var pushedSession: Session?
    @State private var selectedTimeOff: TimeOffCalendarEntry?
    @State private var showCreateSession = false
    /// The timeline anchors on today once, not every time this screen re-appears.
    @State private var hasAnchored = false
    /// Timeline history starts folded into one "Earlier" row, so the screen
    /// opens at today and the past is a tap away instead of a scroll above it.
    /// Deliberately not persisted: each arrival at the timeline starts folded.
    @State private var showPastDays = false
    @State private var hasStarted = false
    /// A one-minute clock. The countdown card ticks per second inside its own
    /// TimelineView, but that never re-renders this screen — so without this the
    /// countdown, the focus accent and the NOW badges would stay on whatever they
    /// were when the view last happened to redraw. One re-render a minute is cheap now that day
    /// queries are index lookups.
    @State private var clockTick = Date()
    @State private var index = ScheduleIndex()

    // Manager publishing
    @State private var isPublishingDay = false
    @State private var publishMessage: String?

    private var layout: ScheduleLayout { ScheduleLayout(rawValue: layoutRaw) ?? .day }
    private var mode: ScheduleMode { ScheduleMode(rawValue: modeRaw) ?? .myShifts }
    private var canEdit: Bool { Permissions.has("schedule", level: .edit) }
    /// Whether a draft's crew must be dropped before it renders. The schedulers
    /// who can edit keep it; everyone else sees the work without the names.
    private var hideDraftCrew: Bool { DraftCrew.isHiddenFromViewer }

    // MARK: - Body

    var body: some View {
        ZStack {
            AmbientBackdrop()

            if isLoading && sessions.isEmpty {
                loadingState
            } else if !errorMessage.isEmpty && sessions.isEmpty {
                errorState
            } else {
                content
            }
        }
        .navigationTitle(layout == .day ? Formatters.relativeDay(selectedDay) : "Schedule")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    modeMenu
                    if canEdit {
                        Button { showCreateSession = true } label: { Image(systemName: "plus") }
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateSession) { CreateSessionView() }
        .sheet(item: $selectedTimeOff) { entry in
            TimeOffDetailView(
                timeOffEntry: entry,
                onCancel: { selectedTimeOff = nil; loadTimeOff() }
            )
        }
        .ambientPush(item: $pushedSession) { session in
            // `session` is already an index occurrence, so it is redacted. The
            // supporting list is not — it is the raw feed — and the detail reads
            // it for "other jobs at this school today", which feeds both the
            // coworker list and the message-crew recipients. Redact it here, at
            // the same boundary.
            ShiftDetailView(session: session,
                            allSessions: DraftCrew.redacted(sessions, hidingDraftCrew: hideDraftCrew),
                            currentUserID: userManager.getCurrentUserID(),
                            crewHidden: hideDraftCrew)
                .id(session.dayOccurrenceKey)
        }
        .onAppear(perform: start)
        .onDisappear {
            sessionService.stopListeningToSessions(subscriptionId: subscriptionId)
            isListening = false
            organizationService.stopListening()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            isListening = false
            loadSessions()
        }
        // PSH.2 deep link: consume when the link lands, and again when sessions arrive —
        // the push tap usually beats the load. The consume rules (emitted value, async
        // mutation hop, expiry) live in TabBarManager.consumePendingDeepLink.
        .onReceive(tabBarManager.$pendingSession) { pending in
            consumePending(pending, in: sessions)
        }
        .onChange(of: sessions) { newSessions in
            consumePending(tabBarManager.pendingSession, in: newSessions)
        }
        .onChange(of: weekOffset) { _ in loadTimeOff() }
        .onChange(of: modeRaw) { _ in rebuildIndex() }
        .onChange(of: permissionsService.areaLevels) { _ in rebuildIndex() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { clockTick = $0 }
        // errorMessage is only rendered as a full-screen state when there is
        // nothing to show at all; a failed refresh or publish on a populated
        // screen would otherwise be silent.
        .alert("Something went wrong", isPresented: Binding(
            get: { !errorMessage.isEmpty && !sessions.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("OK", role: .cancel) { errorMessage = "" }
        } message: {
            Text(errorMessage)
        }
        .tint(focusAccent)
    }

    @ViewBuilder
    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    if let banner = statusBanner { banner }

                    if let focus = focusSession {
                        ScheduleCountdownCard(session: focus, tint: ScheduleStyle.accent(for: focus))
                            .padding(.horizontal, 18)
                            .onTapGesture { pushedSession = focus }
                    }

                    layoutSwitch

                    switch layout {
                    case .day:
                        weekStrip
                        dayHeader
                        dayList
                    case .timeline:
                        ScheduleTimeline(
                            days: timelineDays,
                            showPast: $showPastDays,
                            items: { items(on: $0) },
                            drafts: { drafts(on: $0) },
                            hours: { hours(on: $0) },
                            onSelectShift: { pushedSession = $0 },
                            onSelectTimeOff: { selectedTimeOff = $0 }
                        )
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .refreshable { await refresh() }
            // Anchoring on today has to survive the load order: onAppear fires
            // before the session listener has called back, so there is nothing
            // to scroll to yet — and once the data lands, the past days are
            // inserted ABOVE today, which pushes today off screen. So we try on
            // appear, try again whenever the day list changes, and only stop
            // once a scroll actually had somewhere to go.
            .onAppear { anchorOnToday(proxy, animated: false) }
            .onChange(of: timelineDays.count) { _ in anchorOnToday(proxy, animated: false) }
            .onChange(of: layoutRaw) { _ in
                hasAnchored = false
                // Fold history back down: arriving at the timeline always
                // starts at today, however it was left.
                showPastDays = false
                anchorOnToday(proxy, animated: true)
                // The two layouts read different date ranges: switching to
                // Timeline without this showed six weeks of shifts against one
                // week of time off, and dropped time-off-only days entirely.
                loadTimeOff()
            }
        }
    }

    // MARK: - Focus

    /// The shift the screen is "about" on a given day: the one in progress, else
    /// the next one to start that day, else that day's first shift.
    ///
    /// It used to pick whichever shift started EARLIEST on the selected day,
    /// which mis-states a day carrying three different jobs — it would read as
    /// the 8am job all the way through the evening one. Following the live or
    /// next shift instead means the answer is "what am I on, or what's next",
    /// which stays true as the day moves.
    private func focusShift(on day: Date, now: Date) -> Session? {
        let dayShifts = shifts(on: day)
        if let live = dayShifts.first(where: { session in
            guard let start = session.startDate, let end = session.endDate else { return false }
            return start <= now && now <= end
        }) { return live }
        if let next = dayShifts.first(where: { ($0.startDate ?? .distantPast) > now }) { return next }
        return dayShifts.first
    }

    /// What the countdown card is about, and what the screen's accents follow.
    ///
    /// It used to tint the BACKGROUND too. D14 (2026-07-30) retired that: the
    /// operator does not want the app changing colour by job, so the schedule
    /// takes the same single wash as every other screen. The job colour survives
    /// on the session cards, the countdown and the chrome below — identity, not
    /// page colour.
    private var focusSession: Session? {
        let now = clockTick
        let day = layout == .day ? selectedDay : Calendar.current.startOfDay(for: now)
        return focusShift(on: day, now: now) ?? nextShift(after: now)
    }

    /// The focus shift's colour, used for this screen's controls and its
    /// manager Publish button. Not the background — see `focusSession`.
    private var focusAccent: Color {
        guard let focus = focusSession else { return .indigo }
        return ScheduleStyle.accent(for: focus)
    }

    private func nextShift(after date: Date) -> Session? {
        index.occurrences.first { ($0.startDate ?? .distantPast) > date }
    }

    // MARK: - Chrome

    private var layoutSwitch: some View {
        HStack(spacing: 4) {
            ForEach(ScheduleLayout.allCases) { option in
                Button {
                    withAnimation(AmbientMotion.gentle) { layoutRaw = option.rawValue }
                    AmbientHaptics.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.symbol).font(.system(size: 11, weight: .semibold))
                        Text(option.title).font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background {
                        if layout == option {
                            Capsule().fill(.thickMaterial)
                                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                        }
                    }
                    .foregroundStyle(layout == option ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modeMenu: some View {
        Menu {
            Picker("Show", selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue })) {
                ForEach(ScheduleMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
        } label: {
            Image(systemName: mode == .myShifts ? "person.crop.circle.fill" : "person.2.circle.fill")
        }
    }

    /// Offline / stale-data state, and the result of a publish. Only appears when
    /// there is something to say.
    @ViewBuilder
    private var statusBanner: (some View)? {
        if let publishMessage {
            banner(text: publishMessage, systemImage: "checkmark.circle.fill", tint: .green)
        } else if sessionService.isUsingOfflineData {
            banner(text: sessionService.lastSyncTime.map { "Offline · last synced \($0.timeAgoDisplay())" } ?? "Offline",
                   systemImage: "icloud.slash", tint: .orange)
        } else if !sessionService.isConnected {
            banner(text: "No connection", systemImage: "wifi.slash", tint: .orange)
        } else {
            nil as EmptyView?
        }
    }

    private func banner(text: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
            Text(text).font(.footnote.weight(.medium))
            Spacer()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12), in: Capsule())
        .padding(.horizontal, 18)
    }

    // MARK: - Day layout

    /// A continuously scrolling strip of days, centred on the one you're looking
    /// at — three weeks of them, so you can drift a few days either way without
    /// paging and without losing the week you came from.
    ///
    /// Restored to the lab's behaviour 2026-07-25. AMB.1 shipped a fixed
    /// seven-day HStack with chevrons instead: the capsules were the lab's, but
    /// the interaction was not, and the operator noticed. The chevrons stay as a
    /// fast jump for moving whole weeks at a time; scrolling is for the days
    /// either side of the one in front of you.
    private var weekStrip: some View {
        let week = week(offset: weekOffset)
        return VStack(spacing: 8) {
            HStack {
                Button { step(-1) } label: { Image(systemName: "chevron.left").font(.footnote.weight(.bold)) }
                Spacer()
                Text(weekLabel(week))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { step(1) } label: { Image(systemName: "chevron.right").font(.footnote.weight(.bold)) }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 26)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(selectableDays, id: \.self) { date in
                            dayCapsule(date).id(date)
                        }
                    }
                    .padding(.horizontal, 18)
                    .ambientScrollTargets()
                }
                .ambientCarousel(margin: 18)
                .onAppear { proxy.scrollTo(selectedDay, anchor: .center) }
                .onChange(of: selectedDay) { day in
                    withAnimation(AmbientMotion.gentle) { proxy.scrollTo(day, anchor: .center) }
                }
                .onChange(of: weekOffset) { _ in
                    withAnimation(AmbientMotion.gentle) { proxy.scrollTo(selectedDay, anchor: .center) }
                }
            }
        }
    }

    /// Three weeks around the visible one — the week concept without a pager.
    private var selectableDays: [Date] {
        (-1...1).flatMap { week(offset: weekOffset + $0) }
    }

    private func dayCapsule(_ date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDay)
        let isToday = Calendar.current.isDateInToday(date)
        let mine = !shifts(on: date).isEmpty

        return Button {
            withAnimation(AmbientMotion.snappy) {
                selectedDay = date
                // The strip scrolls into the weeks either side, so tapping there
                // has to move the window too — otherwise the header's week label
                // describes a week you are no longer looking at.
                weekOffset = weekOffset(containing: date)
            }
            AmbientHaptics.selection()
        } label: {
            VStack(spacing: 3) {
                Text(Formatters.weekdayNarrow.string(from: date))
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.7)
                Text(Formatters.dayNumber.string(from: date))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                // One signal: whether YOU are on this day. The org's staffing
                // load used to sit beside it as a heat-coloured dot; PUB.1
                // removed it for everyone, managers included, since there is no
                // second copy of this strip on iOS.
                Circle()
                    .fill(Color.primary.opacity(isSelected ? 0.9 : 0.55))
                    .frame(width: 5, height: 5)
                    .opacity(mine ? 1 : 0)
                    .frame(height: 5)
            }
            // Fixed, not maxWidth: .infinity. The old seven-across HStack divided
            // the screen between exactly seven capsules, so .infinity was right
            // there — but inside a horizontal scroll it collapses each capsule to
            // its content width, which crams three weeks onto one screen at a
            // size nothing is readable or tappable at. 52x74 is the lab's size:
            // about six days visible, thumb-sized, the rest a scroll away.
            .frame(width: 52, height: 74)
            .background {
                if isSelected {
                    // ambient-allow: the selected-day chip in the week strip is
                    // a selection state on a control, not a content card.
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.thickMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                }
            }
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5)
                }
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Formatters.longDate.string(from: date)))
        // The strip draws drafts nowhere — they are not shifts and they are not
        // yours — but a day carrying only drafts would otherwise read as empty
        // to VoiceOver as well as by eye, so the count is spoken.
        .accessibilityValue(Text(capsuleAccessibilityValue(for: date)))
    }

    private func capsuleAccessibilityValue(for date: Date) -> String {
        let shiftCount = shifts(on: date).count
        let draftCount = drafts(on: date).count
        var parts = ["\(shiftCount) shifts"]
        if draftCount > 0 { parts.append("\(draftCount) not published") }
        return parts.joined(separator: ", ")
    }

    private var dayHeader: some View {
        let dayShifts = shifts(on: selectedDay)
        let dayOff = timeOffEntries(on: selectedDay)
        // Not `drafts(on:)`: that bucket is empty in My Shifts, and publishing a
        // day is an org-level action that must not vanish because of a view
        // filter. Reading it off `dayShifts` would fail for a different reason —
        // drafts no longer live there at all.
        let unpublished = index.unpublishedDays.contains(Formatters.isoDate.string(from: selectedDay))

        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Formatters.longDate.string(from: selectedDay))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(daySummary(shifts: dayShifts.count, timeOff: dayOff.count,
                                drafts: drafts(on: selectedDay).count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            // Managers publish a whole day at once, as before.
            if canEdit && unpublished && organizationService.organizationHasPublishing {
                Button {
                    publishDay()
                } label: {
                    HStack(spacing: 8) {
                        if isPublishingDay {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "paperplane.fill").font(.system(size: 12, weight: .semibold))
                        }
                        Text("Publish this day")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(focusAccent, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isPublishingDay)
            }
        }
        .padding(.horizontal, 18)
    }

    private func daySummary(shifts: Int, timeOff: Int, drafts: Int) -> String {
        if shifts == 0 && timeOff == 0 && drafts == 0 { return "Clear" }
        var parts: [String] = []
        if shifts > 0 {
            let total = self.shifts(on: selectedDay).reduce(0.0) { sum, session in
                guard let start = session.startDate, let end = session.endDate, end > start else { return sum }
                return sum + end.timeIntervalSince(start)
            }
            parts.append("\(shifts) shift\(shifts == 1 ? "" : "s") · \(Formatters.duration(total))")
        }
        if timeOff > 0 { parts.append("\(timeOff) time off") }
        // Counted apart from shifts, and never folded into their hours: a draft
        // is not work you have been given, so a day of nothing but drafts must
        // not read "1 shift" — and must not read "Clear" either.
        if drafts > 0 { parts.append("\(drafts) not published") }
        return parts.joined(separator: " · ")
    }

    private var dayList: some View {
        LazyVStack(spacing: 14) {
            let dayItems = items(on: selectedDay)
            let dayDrafts = drafts(on: selectedDay)
            if dayItems.isEmpty && dayDrafts.isEmpty {
                AmbientEmptyState(title: "Clear day",
                                  message: mode == .myShifts
                                      ? "You have nothing scheduled."
                                      : "Nothing scheduled for anyone.",
                                  systemImage: "moon.stars.fill")
                    .padding(.top, 10)
            }
            ForEach(dayItems) { item in
                switch item {
                case .shift(let session):
                    Button { pushedSession = session } label: {
                        ScheduleShiftRow(session: session, standing: ShiftStanding.of(session, now: clockTick))
                    }
                    .buttonStyle(.plain)
                    .ambientScrollFade()
                case .timeOff(let entry):
                    Button { selectedTimeOff = entry } label: {
                        ScheduleTimeOffRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .ambientScrollFade()
                }
            }
            if !dayDrafts.isEmpty {
                ScheduleDraftHeading(count: dayDrafts.count)
                    .padding(.top, dayItems.isEmpty ? 4 : 6)
                ForEach(dayDrafts, id: \.dayOccurrenceKey) { session in
                    Button { pushedSession = session } label: {
                        ScheduleShiftRow(session: session, standing: ShiftStanding.of(session, now: clockTick))
                    }
                    .buttonStyle(.plain)
                    .ambientScrollFade()
                }
            }
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Timeline layout

    /// Centred on today: a week of history above, today always present even when
    /// clear (it's the scroll anchor), then six weeks ahead. Built with the index
    /// rather than re-filtering 49 days on every render.
    private var timelineDays: [Date] { index.timelineDays }

    /// Scroll the timeline so today is the first thing you see.
    ///
    /// `hasAnchored` is only set once there was real content to anchor to —
    /// otherwise the first (empty) attempt would count as done and today would
    /// never come into view. Once it has succeeded it stays put, so popping back
    /// from a shift doesn't throw away where you were reading.
    private func anchorOnToday(_ proxy: ScrollViewProxy, animated: Bool) {
        guard layout == .timeline, !hasAnchored else { return }
        // Nothing loaded yet: today is the only row, so there is nothing above
        // it to scroll past. Wait for the data and try again.
        guard timelineDays.count > 1 else { return }

        // Two attempts: the lazy stack may not have realized today's pinned
        // header on the first hop, and scrollTo to an unrealized id silently does
        // nothing. hasAnchored is only set after the second, so a miss still
        // leaves the onChange(timelineDays) retry armed.
        scroll(proxy, animated: animated, after: 0.15)
        scroll(proxy, animated: animated, after: 0.45) { hasAnchored = true }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool, after delay: TimeInterval,
                        then completion: (() -> Void)? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if animated {
                withAnimation(AmbientMotion.gentle) { proxy.scrollTo(ScheduleTimeline.anchorID, anchor: .top) }
            } else {
                proxy.scrollTo(ScheduleTimeline.anchorID, anchor: .top)
            }
            completion?()
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().scaleEffect(1.3)
            Text("Loading your schedule…").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorState: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.orange)
            Text("Couldn't load the schedule").font(.headline)
            Text(errorMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again") { loadSessions() }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    /// Matching on the RAW feed and redacting at the push boundary mirrors what a manual
    /// tap does; the consume rules themselves live in TabBarManager.consumePendingDeepLink.
    private func consumePending(_ pending: PendingDeepLink?, in currentSessions: [Session]) {
        tabBarManager.consumePendingDeepLink(\.pendingSession, emitted: pending,
                                             in: currentSessions, id: { $0.id }) { match in
            pushedSession = DraftCrew.redacted([match], hidingDraftCrew: hideDraftCrew).first ?? match
        }
    }

    private func start() {
        // onDisappear always stops the org listener, so it has to be restarted on
        // EVERY appear — the previous once-only guard meant that after Schedule →
        // shift → back, session-type colours and organizationHasPublishing (which
        // gates both Publish buttons) stopped updating for the app's lifetime.
        userManager.initializeOrganizationID()
        let orgID = userManager.getCachedOrganizationID()
        if !orgID.isEmpty {
            organizationService.startListeningToOrganization(organizationID: orgID)
        }
        if sessions.isEmpty || !isListening { loadSessions() }

        // The rest is first-run only: re-fetching time off on every pop back from
        // a shift is wasted work.
        guard !hasStarted else { return }
        hasStarted = true
        loadTimeOff()
    }

    private func loadSessions() {
        if sessions.isEmpty { isLoading = true }
        errorMessage = ""

        guard isListening == false else { return }

        let orgID = organizationID.isEmpty ? userManager.getCachedOrganizationID() : organizationID
        guard !orgID.isEmpty else {
            isLoading = false
            errorMessage = "Organization ID not found"
            return
        }

        isListening = true
        sessionService.startListeningToSessions(
            subscriptionId: subscriptionId,
            organizationID: orgID,
            // Everyone, not just schedulers (PUB.1 / P1). Drafts are what is
            // coming; the app decides what of a draft may be SHOWN, and it does
            // that in DraftCrew, not by refusing to fetch.
            includeUnpublished: true
        ) { incoming in
            DispatchQueue.main.async {
                self.sessions = incoming
                self.rebuildIndex()
                self.isLoading = false
            }
        }
    }

    private func loadTimeOff() {
        let visible = week(offset: weekOffset)
        let calendar = Calendar.current
        // Timeline reads further ahead than one week, so widen the window to match.
        let start = layout == .timeline
            ? calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: Date())) ?? Date()
            : (visible.first ?? Date())
        let end = layout == .timeline
            ? calendar.date(byAdding: .day, value: 42, to: calendar.startOfDay(for: Date())) ?? Date()
            : (visible.last ?? Date())

        Task {
            let entries = await timeOffService.getTimeOffForCalendar(dateRange: (start: start, end: end))
            await MainActor.run {
                self.timeOff = entries
                self.rebuildIndex()
            }
        }
    }

    private func refresh() async {
        loadTimeOff()
        let orgID = organizationID.isEmpty ? userManager.getCachedOrganizationID() : organizationID
        guard !orgID.isEmpty else { return }
        do {
            let fresh = try await sessionService.fetchSessions(
                organizationID: orgID,
                includeUnpublished: true,
                forceRefresh: true
            )
            await MainActor.run {
                self.sessions = fresh
                self.rebuildIndex()
            }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }

    private func publishDay() {
        isPublishingDay = true
        let orgID = organizationID.isEmpty ? userManager.getCachedOrganizationID() : organizationID
        let dayKey = Formatters.isoDate.string(from: selectedDay)

        Task {
            do {
                try await sessionService.publishSessionsForDate(organizationID: orgID, date: dayKey)
                await MainActor.run {
                    isPublishingDay = false
                    publishMessage = "Published every shift on this day."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { publishMessage = nil }
                }
            } catch {
                await MainActor.run {
                    isPublishingDay = false
                    errorMessage = "Couldn't publish: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Queries

    // Every one of these was recomputed from the full session list on each
    // access — and the timeline asks about ~50 days per body evaluation, inside
    // a TimelineView that re-runs every minute and while rows are being created
    // mid-scroll. Each call also allocated a fresh Session per day occurrence.
    // They now read a prebuilt index (see rebuildIndex) and are O(1).

    private func shifts(on day: Date) -> [Session] {
        index.shiftsByDay[Formatters.isoDate.string(from: day)] ?? []
    }

    private func timeOffEntries(on day: Date) -> [TimeOffCalendarEntry] {
        index.timeOffByDay[Formatters.isoDate.string(from: day)] ?? []
    }

    private func items(on day: Date) -> [ScheduleItem] {
        index.itemsByDay[Formatters.isoDate.string(from: day)] ?? []
    }

    /// A day's unpublished work. Kept in its own bucket rather than mixed into
    /// `items` so it can be grouped under its own heading, left out of the
    /// countdown and the day's hours, and never counted as a shift.
    private func drafts(on day: Date) -> [Session] {
        index.draftsByDay[Formatters.isoDate.string(from: day)] ?? []
    }

    private func hours(on day: Date) -> TimeInterval {
        index.hoursByDay[Formatters.isoDate.string(from: day)] ?? 0
    }

    // MARK: - Index

    /// Fold the session and time-off lists into per-day buckets once, whenever
    /// the data or the My/All filter changes. Scrolling then costs dictionary
    /// lookups instead of a full scan per day per frame.
    private func rebuildIndex() {
        index = ScheduleIndex.build(
            sessions: sessions,
            timeOff: timeOff,
            mode: mode,
            viewerID: userManager.getCurrentUserIDUnified(),
            viewerEmail: UserDefaults.standard.string(forKey: "userEmail"),
            hideDraftCrew: hideDraftCrew
        )
    }

    // MARK: - Week math

    private func week(offset: Int) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        guard let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: today),
              let start = calendar.date(byAdding: .day, value: 7 * offset, to: sunday) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Which week offset a date falls in, relative to the current week.
    private func weekOffset(containing date: Date) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        guard let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) else { return 0 }
        let days = calendar.dateComponents([.day], from: sunday, to: calendar.startOfDay(for: date)).day ?? 0
        return Int(floor(Double(days) / 7.0))
    }

    private func weekLabel(_ week: [Date]) -> String {
        guard let first = week.first, let last = week.last else { return "" }
        return "\(Formatters.monthDay.string(from: first)) – \(Formatters.monthDay.string(from: last))"
    }

    private func step(_ delta: Int) {
        withAnimation(AmbientMotion.snappy) {
            weekOffset += delta
            let candidates = week(offset: weekOffset)
            if let first = candidates.first {
                let weekday = Calendar.current.component(.weekday, from: selectedDay) - 1
                selectedDay = candidates.indices.contains(weekday) ? candidates[weekday] : first
            }
        }
        AmbientHaptics.impact(.soft)
    }
}

// MARK: - Filter

/// Whose shifts the schedule shows. Previously declared in SlingWeeklyView,
/// which this file replaces.
enum ScheduleMode: String, CaseIterable {
    case myShifts = "My Shifts"
    case allShifts = "All Shifts"
}

// MARK: - Layout choice

enum ScheduleLayout: String, CaseIterable, Identifiable {
    case day, timeline
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .timeline: return "Timeline"
        }
    }

    var symbol: String {
        switch self {
        case .day: return "square.fill.text.grid.1x2"
        case .timeline: return "list.bullet.indent"
        }
    }
}

// MARK: - Unified item

/// One thing on a day: a shift (always a day occurrence) or a time-off entry.
enum ScheduleItem: Identifiable {
    case shift(Session)
    case timeOff(TimeOffCalendarEntry)

    var id: String {
        switch self {
        case .shift(let session): return "shift-\(session.dayOccurrenceKey)"
        case .timeOff(let entry): return "off-\(entry.id)"
        }
    }

    /// All-day time off sorts to the top of a day; everything else by start time.
    var sortKey: Date {
        switch self {
        case .shift(let session): return session.startDate ?? .distantPast
        case .timeOff(let entry):
            guard entry.isPartialDay else { return .distantPast }
            return Session.parseDateTime(date: Formatters.isoDate.string(from: entry.date),
                                         time: entry.startTime) ?? .distantPast
        }
    }
}

// MARK: - Per-day index

/// The schedule folded into per-day buckets, built once per data/filter change.
///
/// Before this existed, every day cell recomputed its own answer by scanning the
/// whole session list and allocating a `Session` copy per day occurrence. The
/// timeline asks about roughly fifty days per body evaluation, and it does that
/// inside a minute-ticking `TimelineView` and again as lazy rows are created
/// during a scroll — so the same scan ran hundreds of times a second while your
/// thumb was moving. That was the scroll stutter.
struct ScheduleIndex {
    var shiftsByDay: [String: [Session]] = [:]
    var timeOffByDay: [String: [TimeOffCalendarEntry]] = [:]
    var itemsByDay: [String: [ScheduleItem]] = [:]
    /// Unpublished work, per day, kept apart from `shiftsByDay` on purpose
    /// (PUB.1): a draft is not a shift you have been given, so it is not counted
    /// as one, not tinted by, and not counted down to. Populated in All Shifts
    /// only — My Shifts is what has been announced to YOU.
    var draftsByDay: [String: [Session]] = [:]
    /// Days carrying unpublished work, whatever the My/All filter says. Drives
    /// the manager's publish-a-day button, which acts on the whole day.
    var unpublishedDays: Set<String> = []
    var hoursByDay: [String: TimeInterval] = [:]
    /// A week of history that had work, today (always), then six weeks ahead.
    var timelineDays: [Date] = []
    /// Every visible occurrence in start order — what "next shift" reads.
    /// Published only: the countdown card is about YOUR next call time and must
    /// never count something that has not been announced.
    var occurrences: [Session] = []

    static func build(
        sessions: [Session],
        timeOff: [TimeOffCalendarEntry],
        mode: ScheduleMode,
        viewerID: String?,
        viewerEmail: String?,
        hideDraftCrew: Bool
    ) -> ScheduleIndex {
        var index = ScheduleIndex()
        let formatter = Formatters.isoDate

        for session in sessions {
            for occurrence in session.dayOccurrences() {
                let isDraft = !occurrence.isPublished

                // Whether the day has unpublished work is an ORG-level question,
                // like the old staffing total was: "Publish this day" publishes
                // every shift on it, so the button must not appear and disappear
                // with the My/All filter.
                if isDraft { index.unpublishedDays.insert(occurrence.date) }

                // MY SHIFTS SHOWS ONLY WHAT HAS BEEN ANNOUNCED TO YOU. A draft is
                // not that — for anyone, scheduler included. Operator decision
                // 2026-07-25, overriding the plan's P6, which had drafts appear in
                // both modes on the reasoning that an unassigned draft cannot
                // belong to "mine": true, but the conclusion was backwards. It put
                // the whole org's planned work into the one view whose entire job
                // is to answer "what am I doing", which muddles the schedule
                // instead of informing it. Drafts live in All Shifts.
                if isDraft && mode == .myShifts { continue }

                // Answered from the UNREDACTED occurrence, before any crew is
                // dropped — otherwise a draft would test as "not mine" for the
                // very viewer the filter is for.
                if mode == .myShifts {
                    guard let viewerID,
                          occurrence.isUserAssigned(userID: viewerID, userEmail: viewerEmail) else { continue }
                }

                let shown = DraftCrew.redacted(occurrence, hidingDraftCrew: hideDraftCrew)

                if isDraft {
                    index.draftsByDay[shown.date, default: []].append(shown)
                    continue
                }

                index.shiftsByDay[shown.date, default: []].append(shown)
                index.occurrences.append(shown)
                if let start = shown.startDate, let end = shown.endDate, end > start {
                    index.hoursByDay[shown.date, default: 0] += end.timeIntervalSince(start)
                }
            }
        }

        for entry in timeOff {
            if mode == .myShifts, entry.photographerId != viewerID { continue }
            index.timeOffByDay[formatter.string(from: entry.date), default: []].append(entry)
        }

        for key in index.shiftsByDay.keys {
            index.shiftsByDay[key]?.sort { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        }
        for key in index.draftsByDay.keys {
            index.draftsByDay[key]?.sort { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        }
        for key in index.timeOffByDay.keys {
            index.timeOffByDay[key]?.sort { $0.startTime < $1.startTime }
        }
        index.occurrences.sort { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }

        for key in Set(index.shiftsByDay.keys).union(index.timeOffByDay.keys) {
            let shifts = (index.shiftsByDay[key] ?? []).map(ScheduleItem.shift)
            let off = (index.timeOffByDay[key] ?? []).map(ScheduleItem.timeOff)
            index.itemsByDay[key] = (off + shifts).sorted { $0.sortKey < $1.sortKey }
        }

        // Timeline window, resolved here so the view never re-filters 49 days.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // A day of nothing but drafts is still a day with something on it —
        // dropping it here would take the timeline back to hiding exactly the
        // work this change exists to show.
        func hasWork(_ date: Date) -> Bool {
            let key = formatter.string(from: date)
            return index.itemsByDay[key]?.isEmpty == false
                || index.draftsByDay[key]?.isEmpty == false
        }
        let past = (1...7)
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .filter(hasWork)
            .sorted()
        let future = (1...42)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .filter(hasWork)
        index.timelineDays = past + [today] + future

        return index
    }
}
