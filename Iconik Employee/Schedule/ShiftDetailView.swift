import SwiftUI
import MessageUI
import MapKit
import CoreLocation
import Supabase

// MARK: - Model Structs

struct CoworkerProfile: Identifiable {
    let id: String
    let name: String
    let photoURL: String
}

struct CoworkerContactInfo: Identifiable {
    let id: String
    let name: String
    let phoneNumber: String
}

struct TravelPlan {
    var travelDuration: TimeInterval = 0
    var readyTime: TimeInterval = 0
    var suggestedLeaveTime: Date?
    var suggestedWakeupTime: Date?
    var arrivalTime: Date?
    var isCalculating: Bool = false
    var errorMessage: String = ""
}

struct LocationPhoto: Identifiable, Hashable {
    var id: String { url }
    let url: String
    let label: String
}

// MARK: - Main View

struct ShiftDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var session: Session
    @State private var allSessions: [Session]
    let currentUserID: String?

    /// The day-row this view was opened on (CREW.2). Both entry points hand us a day
    /// OCCURRENCE — a copy carrying one day's date/time and that day's own crew. The
    /// realtime listener, though, delivers the whole session, whose date/time are the
    /// FIRST day's and whose crew is every day's unioned. Remembering the day lets us
    /// re-apply it on every update, so a multi-day shoot opened on day 2 stays on day 2.
    @State private var viewedDayID: String?

    /// Whether the session this view is HOLDING had its crew dropped (PUB.1).
    ///
    /// A fact about the data, passed in by whoever redacted it and refreshed by the
    /// listener that redacts it again — deliberately NOT a fresh read of
    /// `Permissions`. Those two answers can disagree: permissions load
    /// asynchronously, so a screen built moments earlier can be holding a redacted
    /// session while a live permission check now says this viewer is a scheduler.
    /// Trusting the live check there would offer Edit on a session whose crew array
    /// is empty, and the editor seeds its crew picker from that array.
    @State private var crewHidden: Bool

    // Primary initializer for Session
    init(session: Session, allSessions: [Session], currentUserID: String?, crewHidden: Bool) {
        self._session = State(initialValue: session)
        self._allSessions = State(initialValue: allSessions)
        self._viewedDayID = State(initialValue: Self.dayID(matching: session))
        self._crewHidden = State(initialValue: crewHidden)
        self.currentUserID = currentUserID
    }

    /// The day-row currently being shown: the one `viewedDayID` pins, falling back to
    /// the row matching this occurrence's date.
    private var viewedDay: SessionDay? {
        if let id = viewedDayID, let day = session.days.first(where: { $0.id == id }) {
            return day
        }
        return session.day(onDate: session.date)
    }

    /// The id of the day-row a given occurrence represents, or nil for a session with
    /// no day rows. `Session.with(day:)` copies the day's date and times onto the
    /// occurrence, so match on those; fall back to the first row on that date.
    private static func dayID(matching occurrence: Session) -> String? {
        let exact = occurrence.days.first {
            $0.date == occurrence.date
                && ($0.start_time ?? "") == occurrence.start_time
                && ($0.end_time ?? "") == occurrence.end_time
        }
        return (exact ?? occurrence.day(onDate: occurrence.date))?.id
    }
    
    // State properties
    @State private var coworkerProfiles: [CoworkerProfile] = []
    @State private var coworkerContacts: [CoworkerContactInfo] = []
    /// Crew on this shift with no phone number on file — named in the composer
    /// rather than silently dropped.
    @State private var crewWithoutNumbers: [String] = []
    @State private var isShowingMessageComposer = false
    @State private var messageBody: String = ""
    @State private var isLoadingContacts = false
    @State private var showEditSession = false
    @AppStorage("userRole") private var userRole: String = "employee"
    @State private var employeeProfile: CoworkerProfile? = nil
    @State private var isPublishing = false
    @ObservedObject private var organizationService = OrganizationService.shared
    // Observed so this screen can RECOVER when permissions arrive. `crewHidden` is
    // seeded once from init and re-asserted from a value the listener captured
    // once, and this view's identity (`.id(dayOccurrenceKey)`) does not change
    // when permissions do — so without this, a scheduler who opened a draft
    // before their permissions loaded would have Edit and Publish hidden for the
    // whole life of the pushed screen, with no way back but leaving it.
    @ObservedObject private var permissionsService = PermissionsService.shared
    @State private var locationPhotos: [LocationPhoto] = []
    @State private var weatherData: WeatherData?
    @State private var weatherErrorMessage: String?
    @State private var isLoadingWeather: Bool = false
    @State private var travelPlan = TravelPlan()
    @State private var userHomeAddress: String = ""
    @State private var schoolAddress: String = ""
    @State private var errorMessage: String = ""
    @State private var showSuccessMessage: Bool = false
    @State private var successMessage: String = ""
    @State private var showingMapsOptions = false
    @State private var showingShareSheet = false
    @State private var showingAddToCalendar = false
    @State private var showingYearbookChecklist = false
    
    // Job box state
    @State private var jobBoxes: [JobBox] = []
    @State private var jobBoxListener: ListenerRegistrationWrapper?
    @State private var latestJobBoxStatus: JobBoxStatus = .unknown
    @State private var latestJobBoxScannedBy: String = ""
    @State private var latestJobBoxTimestamp: Date?

    // State for photo detail management
    @State private var selectedPhoto: LocationPhoto? = nil
    @State private var showingPhotoDetail = false

    // Real-time listener (using SessionService)
    @State private var sessionListenerActive: Bool = false

    // Unique subscription ID for this view instance (prevents overwriting other subscribers)
    private let subscriptionId = UUID()
    
    // Loading state for initial data
    @State private var isInitializing = true
    
    // Services
    private let weatherService = WeatherService()
    private let sessionService = SessionService.shared
    
    var body: some View {
        ZStack(alignment: .bottom) {
            AmbientBackdrop(tint: accent)

            if isInitializing {
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.3)
                    Text("Loading shift…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        hero
                        factsRow
                        if session.dayCount > 1 { daySwitcher }
                        notesCards
                        crewCard
                        jobBoxCard
                        weatherCard
                        travelCard
                        locationPhotosCard
                        Spacer(minLength: 96)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                }
                .ambientNoBounceWhenShort()

                actionBar
            }
        }
        .navigationTitle(session.schoolName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    // `!isRedactedDraft` as well as the permission check: Edit
                    // seeds its crew picker from `session.photographers`, so
                    // opening it on a session whose crew was dropped would let a
                    // save write that empty crew over the real one.
                    if Permissions.has("schedule", level: .edit) && !isRedactedDraft {
                        if organizationService.organizationHasPublishing && !session.isPublished {
                            Button(action: publishSession) {
                                if isPublishing {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Text("Publish")
                                }
                            }
                            .disabled(isPublishing)
                        }
                        Button("Edit") { showEditSession = true }
                    }
                }
            }
        }
        .tint(accent)
        .sheet(isPresented: $showEditSession) {
            EditSessionView(session: session)
        }
        .onAppear {
            loadInitialData()
        }
        .onDisappear {
            jobBoxListener?.remove()
            sessionService.stopListeningToSessions(subscriptionId: subscriptionId)
            sessionListenerActive = false
            NotificationCenter.default.removeObserver(self)
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            startSessionListener()
        }
        // Restarting the listener is the recovery, not just flipping `crewHidden`:
        // the session this view holds may have had its crew dropped, and no local
        // flag can put that back. The restart re-fetches, so the session and the
        // fact of whether it was redacted are replaced together, as everywhere else.
        .onChange(of: permissionsService.areaLevels) { _ in
            startSessionListener()
        }
        .alert(isPresented: .constant(!errorMessage.isEmpty)) {
            Alert(title: Text("Error"),
                  message: Text(errorMessage),
                  dismissButton: .default(Text("OK")) { errorMessage = "" })
        }
        .alert(isPresented: $showSuccessMessage) {
            Alert(title: Text("Success"),
                  message: Text(successMessage),
                  dismissButton: .default(Text("OK")))
        }
        .confirmationDialog("Get Directions", isPresented: $showingMapsOptions, titleVisibility: .visible) {
            Button("Apple Maps") { openInAppleMaps() }
            Button("Google Maps") { openInGoogleMaps() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose a maps application")
        }
        .sheet(isPresented: $isShowingMessageComposer) {
            messageComposerView
        }
        .sheet(isPresented: $showingPhotoDetail, onDismiss: { selectedPhoto = nil }) {
            if let photo = selectedPhoto {
                PhotoDetailView(imageURL: photo.url, label: photo.label)
            }
        }
        .sheet(isPresented: $showingYearbookChecklist) {
            NavigationView {
                YearbookChecklistViewForSession(
                    schoolId: session.schoolId,
                    schoolName: session.schoolName,
                    sessionContext: YearbookSessionContext(
                        sessionId: session.id,
                        photographerId: currentUserID ?? "",
                        photographerName: currentUserPhotographerInfo?.name ?? "Unknown",
                        sessionDate: session.startDate ?? Date()
                    )
                )
            }
        }
        .overlay {
            if isLoadingContacts {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.3)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Loading contacts…")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    // ambient-allow: a modal loading HUD floating over a dimmed
                    // backdrop, not a card in a list.
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }

    // MARK: - Presentation helpers

    private var accent: Color { ScheduleStyle.accent(for: session) }

    /// This shift is unpublished AND this viewer may not see who is on it — so
    /// the screen shows the work without the people (PUB.1). A scheduler opening
    /// the same draft gets the ordinary screen, crew and all, because they are
    /// the ones who have to staff it.
    private var isRedactedDraft: Bool {
        !session.isPublished && crewHidden
    }

    /// The day-row being shown. Multi-day jobs can be switched between days
    /// in-place; everything derived from the day (crew, notes, weather, travel)
    /// follows the switch.
    private var activeDay: SessionDay? { viewedDay }

    // MARK: - Hero

    /// Carries the job's identity — title, every discipline, then when it runs.
    /// Height follows content, so a three-type job is never clipped.
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: heroColors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Image(systemName: ScheduleStyle.symbol(for: session))
                .font(.system(size: 120, weight: .semibold))
                .foregroundStyle(.white.opacity(0.14))
                .offset(x: 30, y: 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            VStack(alignment: .leading, spacing: 10) {
                Text(session.schoolName.isEmpty ? "Session" : session.schoolName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)

                AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(session.sessionType, id: \.self) { type in
                        HStack(spacing: 5) {
                            Image(systemName: ScheduleStyle.typeSymbol(type, in: session))
                                .font(.system(size: 10, weight: .bold))
                            Text(ScheduleStyle.typeName(type, in: session))
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.24)))
                    }
                    if let label = session.multiDayLabel {
                        Text(label)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.black.opacity(0.22)))
                    }
                    if !session.isPublished {
                        Text("DRAFT")
                            .font(.system(size: 11, weight: .heavy))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.black.opacity(0.3)))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    if let start = session.startDate {
                        Text(Formatters.longDate.string(from: start))
                            .font(.caption.weight(.semibold))
                            .opacity(0.85)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ScheduleStyle.timeRange(session))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        if let duration = ScheduleStyle.duration(session) {
                            Text(duration).font(.subheadline.weight(.semibold)).opacity(0.9)
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 200)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .ambientParallax(0.35)
        // ambient-allow: the detail hero is a full-bleed gradient banner that
        // parallaxes under the nav bar, not a glass card.
        .shadow(color: accent.opacity(0.3), radius: 20, y: 10)
        .padding(.top, 6)
    }

    private var heroColors: [Color] {
        let colors = ScheduleStyle.typeColors(for: session)
        return colors.count > 1 ? colors : [accent, accent.opacity(0.55)]
    }

    // MARK: - Facts

    private var factsRow: some View {
        HStack(spacing: 10) {
            // "On crew" is a count of PEOPLE, and on a redacted draft it would
            // read 0 — which is not "hidden", it's a false statement about who
            // is staffed. The tile is dropped rather than zeroed. The other two
            // are counts of NEED, not of people, so they stay on a draft: they
            // are the useful part of knowing what is coming.
            if !isRedactedDraft {
                AmbientStatTile(value: session.photographers.count, label: "On crew",
                                systemImage: "person.2.fill", tint: accent)
            }
            AmbientStatTile(value: session.dayCount, label: session.dayCount == 1 ? "Day" : "Days",
                            systemImage: "calendar", tint: accent)
            AmbientStatTile(value: session.photographersNeeded + session.posersNeeded + session.helpersNeeded,
                            label: "Needed", systemImage: "person.badge.plus", tint: accent)
        }
    }

    // MARK: - Multi-day switcher

    /// Switching days here moves the whole screen onto that day — crew, notes,
    /// weather and the travel plan all follow, the same way opening the shift
    /// from that day in the schedule would.
    private var daySwitcher: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Runs \(session.dayCount) days")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(session.sortedDays.enumerated()), id: \.element.id) { index, day in
                        let isActive = day.id == activeDay?.id
                        Button {
                            selectDay(day)
                        } label: {
                            VStack(spacing: 2) {
                                Text("DAY \(index + 1)").font(.system(size: 9, weight: .heavy))
                                Text(dayShortLabel(day))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                if let range = dayTimeRange(day) {
                                    Text(range).font(.system(size: 10)).opacity(0.8)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(isActive ? AnyShapeStyle(accent) : AnyShapeStyle(.ultraThinMaterial),
                                        in: Capsule())
                            .foregroundStyle(isActive ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func selectDay(_ day: SessionDay) {
        guard day.id != activeDay?.id else { return }
        withAnimation(AmbientMotion.snappy) {
            viewedDayID = day.id
            session = occurrence(for: day)
        }
        AmbientHaptics.selection()
        // Everything derived from the day has to be recomputed.
        travelPlan = TravelPlan()
        weatherData = nil
        weatherErrorMessage = nil
        loadCoworkerPhotos()
        loadWeatherData()
        calculateTravelPlan()
    }

    /// Build the occurrence for a day WITHOUT chaining off the current one.
    ///
    /// `session` is already narrowed to a single day, so its `photographers` are
    /// that day's crew. `Session.with(day:)` falls back to the receiver's crew
    /// when a day-row carries none — chaining it therefore handed the NEW day the
    /// PREVIOUS day's crew, which then fed the coworker list and the message-crew
    /// recipients. Rebuilding against the union of every day's crew matches what
    /// decoding a full session produces, so switching days in place and opening
    /// the same day from the schedule now agree.
    private func occurrence(for day: SessionDay) -> Session {
        if day.photographers != nil { return session.with(day: day) }

        var seen = Set<String>()
        var union: [SessionPhotographer] = []
        for person in session.days.flatMap({ $0.photographers ?? [] }) where !seen.contains(person.id) {
            seen.insert(person.id)
            union.append(person)
        }
        let fallbackCrew = union.isEmpty ? session.photographers : union

        return Session(
            id: session.id,
            organization_id: session.organization_id,
            school_id: session.school_id,
            school_name: session.school_name,
            date: day.date,
            start_time: day.start_time ?? "",
            end_time: day.end_time ?? "",
            days: session.days,
            session_types: session.session_types,
            custom_session_type: session.custom_session_type,
            photographers: fallbackCrew,
            notes: session.notes,
            status: session.status,
            session_color: session.session_color,
            is_published: session.is_published,
            is_time_off: session.is_time_off,
            has_class_group_job: session.has_class_group_job,
            has_class_candids: session.has_class_candids,
            has_sports_job: session.has_sports_job,
            photographers_needed: session.photographers_needed,
            posers_needed: session.posers_needed,
            helpers_needed: session.helpers_needed,
            created_at: session.created_at,
            updated_at: session.updated_at,
            created_by: session.created_by
        )
    }

    private func dayShortLabel(_ day: SessionDay) -> String {
        guard let date = Session.parseDateTime(date: day.date, time: "00:00") else { return day.date }
        return Formatters.monthDay.string(from: date)
    }

    /// "9:00 AM – 12:00 PM" for a day, or nil if it has no times.
    private func dayTimeRange(_ day: SessionDay) -> String? {
        guard let startString = day.start_time,
              let start = Session.parseDateTime(date: day.date, time: startString) else { return nil }
        guard let endString = day.end_time,
              let end = Session.parseDateTime(date: day.date, time: endString) else {
            return Formatters.shortTime.string(from: start)
        }
        return "\(Formatters.shortTime.string(from: start))–\(Formatters.shortTime.string(from: end))"
    }

    // MARK: - Notes

    @ViewBuilder
    private var notesCards: some View {
        if let dayNotes = activeDay?.day_notes, !dayNotes.isEmpty {
            AmbientNoteCard(title: "Notes for this day", text: dayNotes, accent: accent)
        }
        if let sessionNotes = session.notes, !sessionNotes.isEmpty {
            AmbientNoteCard(title: "Session notes", text: sessionNotes, accent: .secondary)
        }
        if let userInfo = currentUserPhotographerInfo,
           let personal = userInfo.notes, !personal.isEmpty {
            AmbientNoteCard(title: "Your notes", text: personal, accent: .blue)
        }
    }

    // MARK: - Crew

    /// This day's crew. Anyone who scanned the job box is ringed, which is how
    /// you find out who has the gear without asking.
    ///
    /// On a draft this viewer may not staff, the whole card is replaced rather
    /// than emptied: an empty crew list reads "nobody is assigned", which is a
    /// different — and probably false — statement from "not announced yet". The
    /// "also at this school today" list goes with it, since it is the same
    /// question asked sideways.
    @ViewBuilder
    private var crewCard: some View {
        if isRedactedDraft { draftCrewCard } else { staffedCrewCard }
    }

    private var draftCrewCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Crew")
            Text("Not announced yet")
                .font(.subheadline.weight(.semibold))
            Text("This shift hasn't been published, so who is working it isn't set. You'll see the crew — and your own assignment — once it is.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private var staffedCrewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AmbientSectionTitle("Crew on this day", trailing: "\(session.photographers.count)")

            if session.photographers.isEmpty {
                Text("Nobody assigned to this day yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(session.photographers, id: \.id) { person in
                HStack(spacing: 12) {
                    AmbientAvatar(
                        name: person.name,
                        imageURL: photoURL(for: person),
                        size: 40,
                        ringColor: isMatchingUser(profileName: person.name, scannedByName: latestJobBoxScannedBy)
                            ? jobBoxHighlightColor : nil
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name).font(.subheadline.weight(.semibold))
                        if let notes = person.notes, !notes.isEmpty {
                            Text(notes).font(.caption).foregroundStyle(.secondary)
                        } else if isMatchingUser(profileName: person.name, scannedByName: latestJobBoxScannedBy) {
                            Text("Has the job box").font(.caption).foregroundStyle(jobBoxHighlightColor)
                        }
                    }
                    Spacer()
                }
            }

            // Crew from OTHER jobs at this school today — people you'll actually
            // run into, who aren't on your session row.
            let others = sameDayCoworkersAtSchool()
            if !others.isEmpty {
                Divider().padding(.vertical, 2)
                AmbientSectionTitle("Also at this school today")
                ForEach(others, id: \.id) { person in
                    HStack(spacing: 12) {
                        AmbientAvatar(name: person.name, imageURL: photoURL(for: person), size: 32)
                        Text(person.name).font(.subheadline)
                        Spacer()
                    }
                }
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private func photoURL(for person: SessionPhotographer) -> String? {
        if person.id == currentUserID { return employeeProfile?.photoURL }
        return coworkerProfiles.first { $0.id == person.id }?.photoURL
    }

    // MARK: - Job box

    @ViewBuilder
    private var jobBoxCard: some View {
        if latestJobBoxStatus != .unknown {
            let step = statusToStep(latestJobBoxStatus)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    AmbientSectionTitle("Job box")
                    if let box = jobBoxes.sorted(by: { $0.timestampDate > $1.timestampDate }).first,
                       !box.boxNumber.isEmpty {
                        Text("#\(box.boxNumber)")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(jobBoxHighlightColor)
                    }
                }

                // Four states, drawn as a track that fills — you read progress
                // from the shape before you read any label.
                HStack(spacing: 0) {
                    ForEach(Array(jobBoxSteps.enumerated()), id: \.offset) { index, title in
                        let number = index + 1
                        let done = step >= number
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(done ? jobBoxHighlightColor : Color(.tertiarySystemFill))
                                    .frame(width: 28, height: 28)
                                if done {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                } else {
                                    Text("\(number)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(title)
                                .font(.system(size: 10, weight: done ? .semibold : .regular))
                                .foregroundStyle(done ? .primary : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .top) {
                            if index < jobBoxSteps.count - 1 {
                                Rectangle()
                                    .fill(step > number ? jobBoxHighlightColor : Color(.tertiarySystemFill))
                                    .frame(height: 2)
                                    .padding(.leading, 20)
                                    .offset(x: 24, y: 13)
                            }
                        }
                    }
                }

                // The job box is tracked by SESSION id, not by crew, so this line
                // is the one place a person's name reaches a draft without going
                // anywhere near `photographers` — and the whole point of the
                // redaction is that no name is attached to unannounced work. The
                // box's progress itself is about equipment and stays.
                if !latestJobBoxScannedBy.isEmpty && !isRedactedDraft {
                    HStack(spacing: 4) {
                        Text("Last scanned by")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(latestJobBoxScannedBy)
                            .font(.caption.weight(.semibold))
                        if let timestamp = latestJobBoxTimestamp {
                            Text("· \(jobBoxTimestampFormatter.string(from: timestamp))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .ambientCard(density: .roomy, fillWidth: true)
        }
    }

    private var jobBoxSteps: [String] { ["Packed", "Picked up", "Left job", "Turned in"] }

    private var jobBoxHighlightColor: Color {
        switch latestJobBoxStatus {
        case .pickedUp: return .blue
        case .leftJob: return .orange
        case .turnedIn: return .green
        default: return .gray
        }
    }

    private var jobBoxTimestampFormatter: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"; return f
    }

    // MARK: - Weather

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                AmbientSectionTitle("Weather")
                if isLoadingWeather { ProgressView().scaleEffect(0.7) }
            }

            if let weather = weatherData {
                WeatherBar(weather: weather, errorMessage: weatherErrorMessage)
            } else if let message = weatherErrorMessage, !message.isEmpty {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            } else if !isLoadingWeather {
                Button {
                    loadWeatherData()
                } label: {
                    Label("Load forecast", systemImage: "cloud.sun.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(accent.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    // MARK: - Travel

    private var travelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                AmbientSectionTitle("Getting there")
                Spacer()
                if travelPlan.isCalculating {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button { calculateTravelPlan() } label: {
                        Image(systemName: "arrow.clockwise").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                }
            }

            if !travelPlan.errorMessage.isEmpty {
                Text(travelPlan.errorMessage).font(.footnote).foregroundStyle(.secondary)
            } else if travelPlan.isCalculating {
                Text("Calculating…").font(.footnote).foregroundStyle(.secondary)
            } else if let leave = travelPlan.suggestedLeaveTime, let arrival = travelPlan.arrivalTime {
                VStack(spacing: 10) {
                    if let wakeup = travelPlan.suggestedWakeupTime, travelPlan.readyTime > 0, isFirstShiftOfDay() {
                        travelRow("Wake up", Formatters.shortTime.string(from: wakeup), "bed.double.fill", .indigo, prominent: true)
                    }
                    travelRow("Leave by", Formatters.shortTime.string(from: leave), "figure.walk", .green, prominent: true)
                    travelRow("Arrive", Formatters.shortTime.string(from: arrival), "mappin.and.ellipse", .orange, prominent: false)
                    travelRow("Drive time", formatDuration(travelPlan.travelDuration), "car.fill", .red, prominent: false)
                    if travelPlan.readyTime > 0 && isFirstShiftOfDay() {
                        travelRow("Getting ready", formatDuration(travelPlan.readyTime), "clock.fill", .purple, prominent: false)
                    }
                }
            } else {
                Button { calculateTravelPlan() } label: {
                    Label("Plan the drive", systemImage: "car.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(accent.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private func travelRow(_ label: String, _ value: String, _ systemImage: String,
                           _ tint: Color, prominent: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint.opacity(0.14)))
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(prominent
                      ? .system(size: 18, weight: .bold, design: .rounded)
                      : .system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    // MARK: - Location photos

    @ViewBuilder
    private var locationPhotosCard: some View {
        if !locationPhotos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                AmbientSectionTitle("Location photos", trailing: "\(locationPhotos.count)")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(locationPhotos) { photo in
                            Button {
                                selectedPhoto = photo
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    showingPhotoDetail = true
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    AsyncImage(url: URL(string: photo.url)) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().scaledToFill()
                                        case .failure:
                                            Image(systemName: "photo").foregroundStyle(.secondary)
                                        default:
                                            ProgressView()
                                        }
                                    }
                                    .frame(width: 118, height: 92)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    Text(photo.label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 118, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .ambientCard(density: .roomy, fillWidth: true)
        }
    }

    // MARK: - Floating action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                showingMapsOptions = true
            } label: {
                Label("Directions", systemImage: "car.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(schoolAddress.isEmpty && (session.location ?? "").isEmpty)
            .opacity(schoolAddress.isEmpty && (session.location ?? "").isEmpty ? 0.4 : 1)

            // No message action on a draft this viewer cannot see the crew of.
            // This is the loudest of the five crew readers: it would text people
            // about a shoot that has not been announced to anyone.
            if !isRedactedDraft {
                Button {
                    messageCoworkers()
                } label: {
                    Image(systemName: "message.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 48, height: 46)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }

            // schoolId is non-optional, so the old `!= nil` test was always true
            // and this showed even for a session with no school attached.
            if !session.schoolId.isEmpty {
                Button {
                    showingYearbookChecklist = true
                } label: {
                    Image(systemName: "list.clipboard")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 48, height: 46)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        // Room for the app's floating tab bar (AMB.4), which overlays every screen
        // including a pushed one. The clearance goes on the CONTENT rather than the
        // container: the bar's material still runs to the bottom of the screen (it
        // ignores the safe area on purpose), but the buttons sit above the capsule
        // instead of underneath it.
        //
        // It cannot come from the shell. `tabBarClearance` insets a navigation
        // container's ROOT, and this is a PUSHED screen — the root's safe area is
        // not this view's. Any pushed screen with something anchored to the bottom
        // has to ask for this itself.
        .padding(.bottom, 12 + TabBarMetrics.clearance)
        .background(.ultraThinMaterial)
        .clipShape(TopRoundedRectangle(radius: 24))
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Message composer

    /// Three outcomes, each stated plainly. Previously two of them showed
    /// nothing at all — the sheet only opened when a number was found.
    private var messageComposerView: some View {
        Group {
            if !coworkerContacts.isEmpty && MFMessageComposeViewController.canSendText() {
                MessageComposeView(
                    recipients: coworkerContacts.map { $0.phoneNumber },
                    body: messageBody,
                    isShowing: $isShowingMessageComposer
                )
            } else {
                composerFallback
            }
        }
    }

    private var composerFallback: some View {
        NavigationView {
            List {
                if coworkerContacts.isEmpty && crewWithoutNumbers.isEmpty {
                    Section {
                        Label("You're the only one on this shift", systemImage: "person.fill")
                            .font(.headline)
                    } footer: {
                        Text("There's nobody else scheduled at \(session.schoolName) on this day, so there's no one to message.")
                    }
                } else if coworkerContacts.isEmpty {
                    Section {
                        ForEach(crewWithoutNumbers, id: \.self) { name in
                            Label(name, systemImage: "person.crop.circle.badge.exclamationmark")
                        }
                    } header: {
                        Text("No phone numbers on file")
                    } footer: {
                        Text("These coworkers are on the shift but have no phone number saved on their profile, so they can't be texted from here.")
                    }
                } else {
                    Section {
                        ForEach(coworkerContacts) { contact in
                            HStack {
                                Text(contact.name)
                                Spacer()
                                Text(contact.phoneNumber)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Crew")
                    } footer: {
                        Text(MFMessageComposeViewController.canSendText()
                             ? ""
                             : "This device can't send texts, so the numbers are listed instead.")
                    }

                    if !crewWithoutNumbers.isEmpty {
                        Section {
                            ForEach(crewWithoutNumbers, id: \.self) { name in
                                Label(name, systemImage: "person.crop.circle.badge.exclamationmark")
                                    .foregroundStyle(.secondary)
                            }
                        } header: {
                            Text("No number on file")
                        }
                    }
                }
            }
            .navigationTitle("Message crew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { isShowingMessageComposer = false }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: - Job box step mapping

    private func statusToStep(_ status: JobBoxStatus) -> Int {
        switch status {
        case .packed: return 1
        case .pickedUp: return 2
        case .leftJob: return 3
        case .turnedIn: return 4
        case .unknown: return 0
        }
    }
    
    // MARK: - Job Box Methods
    
    // Start listening for job box updates
    private func startJobBoxListener() {
        // Remove any existing listener
        jobBoxListener?.remove()

        // Convert Session to ICSEvent for JobBoxService compatibility
        let compatibilityEvent = ICSEvent(
            id: session.id,
            summary: "\(session.employeeName) - \(session.getSessionTypeDisplayName()) - \(session.schoolName)",
            startDate: session.startDate,
            endDate: session.endDate,
            description: session.description,
            location: session.location,
            url: nil
        )

        // Start a new listener
        jobBoxListener = JobBoxService.shared.listenForJobBoxes(forShift: compatibilityEvent, organizationID: session.organizationID) { jobBoxes in
            self.jobBoxes = jobBoxes

            // Find the latest job box record based on timestamp
            if let latestBox = jobBoxes.sorted(by: { $0.timestampDate > $1.timestampDate }).first {
                self.latestJobBoxStatus = latestBox.jobBoxStatus
                self.latestJobBoxScannedBy = latestBox.scannedBy
                self.latestJobBoxTimestamp = latestBox.timestampDate
            }
        }
    }
    
    // Set up notification observer for job box updates
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("didReceiveJobBoxNotification"),
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let shiftUid = userInfo["shiftUid"] as? String else {
                return
            }
            
            // Check if the notification is for this shift
            let currentShiftUid = self.session.id
            
            if shiftUid == currentShiftUid {
                // Process the notification to update UI
                if let notificationInfo = JobBoxService.shared.processJobBoxNotification(userInfo: userInfo) {
                    self.latestJobBoxStatus = notificationInfo.status
                    self.latestJobBoxScannedBy = notificationInfo.scannedBy
                    
                    // Use the current time for the timestamp if not provided in the notification
                    // In a production app, we would ideally get this from the notification
                    self.latestJobBoxTimestamp = Date()
                }
            }
        }
    }
    
    // MARK: - Properties
    
    // Get the current user's photographer info from the session
    private var currentUserPhotographerInfo: (name: String, notes: String?)? {
        guard let userID = currentUserID else { return nil }
        return session.getPhotographerInfo(for: userID)
    }
    
    private var displayEmployeeName: String {
        if let userInfo = currentUserPhotographerInfo {
            return userInfo.name
        }
        return session.employeeName.isEmpty ? "Employee" : session.employeeName // Fallback with defensive check
    }
    
    // MARK: - Helper Methods
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours) hr"
            } else {
                return "\(hours) hr \(mins) min"
            }
        }
    }
    
    private func isFirstShiftOfDay() -> Bool {
        guard let currentShiftDate = session.startDate else { return false }

        // This keys on the employee NAME, so it needs one to key on. A shift
        // with no crew on it — a draft whose crew this viewer can't see, or any
        // unstaffed session — would otherwise match every other nameless shift
        // that day and pick an arbitrary one as "first". Fall back to the same
        // answer the function already gives when it can't tell.
        guard !session.employeeName.isEmpty else { return true }

        let calendar = Calendar.current
        let _ = calendar.startOfDay(for: currentShiftDate)

        // Find all sessions for the same employee on the same day
        let employeeSessions = allSessions.filter { evt in
            guard let eventDate = evt.startDate,
                  evt.employeeName == self.session.employeeName else {
                return false
            }
            
            // Check if the session is on the same day
            return calendar.isDate(eventDate, inSameDayAs: currentShiftDate)
        }
        
        // Sort sessions by start time
        let sortedSessions = employeeSessions.sorted { (a, b) -> Bool in
            guard let aStart = a.startDate, let bStart = b.startDate else {
                return false
            }
            return aStart < bStart
        }
        
        // Check if the current session is the first one
        if let firstSession = sortedSessions.first,
           let firstSessionDate = firstSession.startDate,
           let currentSessionDate = session.startDate {
            
            // Compare times using timeIntervalSince1970 to handle possible millisecond differences
            let isFirst = abs(firstSessionDate.timeIntervalSince1970 - currentSessionDate.timeIntervalSince1970) < 60 // Within a minute
            return isFirst
        }
        
        return true // If we can't determine, assume it's the first shift
    }
    
    private func loadEmployeeProfile() {
        // Use current user's ID directly instead of querying by name
        guard let userID = currentUserID else {
            print("🔐 Cannot load employee profile: no current user ID")
            return
        }

        Task {
            do {
                let supabase = SupabaseManager.shared.client

                struct UserRecord: Decodable {
                    let id: String
                    let photo_url: String?
                    let first_name: String?
                    let last_name: String?
                }

                let users: [UserRecord] = try await supabase
                    .from("users")
                    .select("id, photo_url, first_name, last_name")
                    .eq("id", value: userID)
                    .limit(1)
                    .execute()
                    .value

                await MainActor.run {
                    if let user = users.first {
                        let firstName = user.first_name ?? ""
                        let lastName = user.last_name ?? ""
                        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)

                        self.employeeProfile = CoworkerProfile(
                            id: userID,
                            name: fullName.isEmpty ? self.displayEmployeeName : fullName,
                            photoURL: user.photo_url ?? ""
                        )
                    } else {
                        self.employeeProfile = CoworkerProfile(
                            id: userID,
                            name: self.displayEmployeeName,
                            photoURL: ""
                        )
                    }
                }
            } catch {
                print("⚠️ Employee profile unavailable: \(error.localizedDescription)")
            }
        }
    }
    
    private func loadCoworkerPhotos() {
        coworkerProfiles = []

        // Get all photographers from the session (excluding current user)
        guard let currentUserID = currentUserID else { return }

        // Get organization ID to comply with security rules
        let orgID = UserManager.shared.getCachedOrganizationID()
        guard !orgID.isEmpty else {
            print("🔐 Cannot load coworker photos: no organization ID found")
            return
        }

        // Collect all photographer IDs to fetch
        var photographerIDs: Set<String> = []
        var photographerNameMap: [String: String] = [:]

        for photographer in session.photographers {
            guard photographer.id != currentUserID else { continue }
            photographerIDs.insert(photographer.id)
            photographerNameMap[photographer.id] = photographer.name
        }

        // Also check for coworkers from other sessions on the same day/location
        for photographer in sameDayCoworkersAtSchool() {
            guard photographer.id != currentUserID else { continue }
            photographerIDs.insert(photographer.id)
            photographerNameMap[photographer.id] = photographer.name
        }

        // Fetch all coworker photos in one batch
        Task {
            do {
                let supabase = SupabaseManager.shared.client

                struct UserRecord: Decodable {
                    let id: String
                    let photo_url: String?
                }

                // Batch fetch all photographer profiles
                for photographerID in photographerIDs {
                    let users: [UserRecord] = try await supabase
                        .from("users")
                        .select("id, photo_url")
                        .eq("id", value: photographerID)
                        .limit(1)
                        .execute()
                        .value

                    let photoURL = users.first?.photo_url ?? ""
                    let photographerName = photographerNameMap[photographerID] ?? "Unknown"

                    await MainActor.run {
                        let profile = CoworkerProfile(
                            id: photographerID,
                            name: photographerName,
                            photoURL: photoURL
                        )
                        if !self.coworkerProfiles.contains(where: { $0.id == photographerID }) {
                            self.coworkerProfiles.append(profile)
                        }
                    }
                }
            } catch {
                print("⚠️ Coworker photos unavailable: \(error.localizedDescription)")
                // Still add profiles with empty photoURLs as fallback
                await MainActor.run {
                    for photographerID in photographerIDs {
                        let photographerName = photographerNameMap[photographerID] ?? "Unknown"
                        let profile = CoworkerProfile(
                            id: photographerID,
                            name: photographerName,
                            photoURL: ""
                        )
                        if !self.coworkerProfiles.contains(where: { $0.id == photographerID }) {
                            self.coworkerProfiles.append(profile)
                        }
                    }
                }
            }
        }
    }
    
    private func loadLocationPhotos() {
        Task {
            do {
                let supabase = SupabaseManager.shared.client

                guard let orgID = await withCheckedContinuation({ continuation in
                    UserManager.shared.getCurrentUserOrganizationID { orgID in
                        continuation.resume(returning: orgID)
                    }
                }) else {
                    print("🔐 Cannot load location photos: no organization ID found")
                    return
                }

                struct SchoolRecord: Decodable {
                    let id: String
                    let location_photos: [[String: String]]?
                }

                let schools: [SchoolRecord] = try await supabase
                    .from("schools")
                    .select("id, location_photos")
                    .eq("organization_id", value: orgID)
                    .eq("value", value: self.session.schoolName)
                    .limit(1)
                    .execute()
                    .value

                guard let school = schools.first,
                      let photoDicts = school.location_photos else {
                    return
                }

                // Map each dictionary to a LocationPhoto
                let photos = photoDicts.compactMap { dict -> LocationPhoto? in
                    if let url = dict["url"], let label = dict["label"] {
                        return LocationPhoto(url: url, label: label)
                    }
                    return nil
                }

                await MainActor.run {
                    self.locationPhotos = photos
                }
            } catch {
                print("⚠️ Location photos unavailable: \(error.localizedDescription)")
            }
        }
    }
    
    private func loadUserHomeAddress() {
        // First try AppStorage (synced from UserProfileService)
        let storedHomeAddress = UserDefaults.standard.string(forKey: "userHomeAddress") ?? ""

        if !storedHomeAddress.isEmpty {
            self.userHomeAddress = storedHomeAddress
            print("✅ Home address loaded from AppStorage: \(storedHomeAddress)")
            if !self.schoolAddress.isEmpty {
                self.calculateTravelPlan()
            }
            return
        }

        // Then try UserProfileService cached profile
        if let profile = UserProfileService.shared.currentUserProfile,
           !profile.homeAddress.isEmpty {
            self.userHomeAddress = profile.homeAddress
            print("✅ Home address loaded from cached profile: \(profile.homeAddress)")
            if !self.schoolAddress.isEmpty {
                self.calculateTravelPlan()
            }
            return
        }

        // Finally, fetch fresh from Supabase
        Task {
            do {
                guard let userId = UserManager.shared.getCurrentUserIDUnified() else {
                    print("❌ Cannot load home address: User not signed in")
                    return
                }

                print("🔄 Fetching user profile for home address...")
                let profile = try await UserProfileService.shared.fetchUserProfile(uid: userId)

                await MainActor.run {
                    self.userHomeAddress = profile.homeAddress
                    print("✅ Home address fetched from Supabase: \(profile.homeAddress)")

                    if !self.schoolAddress.isEmpty && !self.userHomeAddress.isEmpty {
                        self.calculateTravelPlan()
                    }
                }
            } catch {
                print("❌ Failed to fetch home address: \(error.localizedDescription)")
            }
        }
    }
    
    private func loadSchoolAddress() async {
        do {
            // Use SchoolService to fetch school data from Supabase
            guard let school = try await SchoolService.shared.getSchool(schoolId: session.schoolId) else {
                // Fall back to session location if school not found
                if let location = session.location, !location.isEmpty {
                    await MainActor.run {
                        self.schoolAddress = location
                        if !self.userHomeAddress.isEmpty {
                            self.calculateTravelPlan()
                        }
                    }
                } else {
                    await MainActor.run {
                        self.travelPlan.errorMessage = "School location not found"
                    }
                }
                return
            }

            await MainActor.run {
                // First try to use coordinates for maximum accuracy
                if let coords = school.parsedCoordinates {
                    self.schoolAddress = "\(coords.lat),\(coords.lng)"
                }
                // Fall back to address field
                else if let address = school.address, !address.isEmpty {
                    self.schoolAddress = address
                }
                // Fall back to session location
                else if let location = self.session.location, !location.isEmpty {
                    self.schoolAddress = location
                }
                else {
                    self.travelPlan.errorMessage = "School location not found"
                    return
                }

                // Calculate travel plan if we already have the user home address
                if !self.userHomeAddress.isEmpty {
                    self.calculateTravelPlan()
                }
            }
        } catch {
            print("⚠️ Error loading school address: \(error)")
            await MainActor.run {
                self.travelPlan.errorMessage = "Could not load school data"
            }
        }
    }
    
    private func loadWeatherData() {
        guard let sessionDate = session.startDate else { return }

        // Only load weather if the session is within the next 7 days
        let calendar = Calendar.current
        let now = Date()
        let sevenDaysFromNow = calendar.date(byAdding: .day, value: 7, to: now) ?? now

        if sessionDate > sevenDaysFromNow {
            weatherErrorMessage = "Weather forecast only available for next 7 days"
            return // Don't attempt to load weather for dates more than 7 days away
        }

        isLoadingWeather = true

        // Load school data to get the best location for weather
        Task {
            let (latitude, longitude, addressFallback) = await loadSchoolDataForWeather()

            // Use coordinates if available for maximum accuracy
            if let lat = latitude, let lng = longitude {
                self.weatherService.getWeatherData(latitude: lat, longitude: lng, date: sessionDate) { weatherData, errorMessage in
                    DispatchQueue.main.async {
                        self.weatherData = weatherData
                        self.weatherErrorMessage = errorMessage
                        self.isLoadingWeather = false
                    }
                }
            }
            // Use address if coordinates not available
            else if !addressFallback.isEmpty {
                self.weatherService.getWeatherData(for: addressFallback, date: sessionDate) { weatherData, errorMessage in
                    DispatchQueue.main.async {
                        self.weatherData = weatherData
                        self.weatherErrorMessage = errorMessage
                        self.isLoadingWeather = false
                    }
                }
            }
            // Final fallback to school name
            else {
                self.weatherService.getWeatherData(for: self.session.schoolName, date: sessionDate) { weatherData, errorMessage in
                    DispatchQueue.main.async {
                        self.weatherData = weatherData
                        self.weatherErrorMessage = errorMessage
                        self.isLoadingWeather = false
                    }
                }
            }
        }
    }
    
    private func loadSchoolDataForWeather() async -> (lat: Double?, lng: Double?, address: String) {
        do {
            // Use SchoolService to fetch school data from Supabase
            guard let school = try await SchoolService.shared.getSchool(schoolId: session.schoolId) else {
                // Use session location if no school document found
                if let location = session.location, !location.isEmpty {
                    return (nil, nil, location)
                }
                return (nil, nil, "")
            }

            // First priority: Use coordinates for maximum accuracy
            if let coords = school.parsedCoordinates {
                return (coords.lat, coords.lng, "")
            }

            // Second priority: city + state for weather data (good for geocoding)
            if let city = school.city, !city.isEmpty,
               let state = school.state, !state.isEmpty {
                return (nil, nil, "\(city), \(state)")
            }

            // Third priority: street address
            if let street = school.street, !street.isEmpty,
               let city = school.city, !city.isEmpty {
                return (nil, nil, "\(street), \(city)")
            }

            // Fourth priority: address field
            if let address = school.address, !address.isEmpty {
                return (nil, nil, address)
            }

            // Final fallback: session location
            if let location = session.location, !location.isEmpty {
                return (nil, nil, location)
            }

            return (nil, nil, "")
        } catch {
            print("⚠️ School data for weather unavailable: \(error.localizedDescription)")
            return (nil, nil, "")
        }
    }
    
    private func calculateTravelPlan() {
        // Check for required data
        guard !userHomeAddress.isEmpty else {
            travelPlan.errorMessage = "Home address not available"
            return
        }
        
        guard !schoolAddress.isEmpty else {
            travelPlan.errorMessage = "School address not available"
            return
        }
        
        guard let startTime = determineStartTime() else {
            travelPlan.errorMessage = "Could not determine start time"
            return
        }
        
        // Set calculating state
        travelPlan.isCalculating = true
        travelPlan.errorMessage = ""
        
        // Use MapKit to calculate the route and travel time
        calculateTravelTime(from: userHomeAddress, to: schoolAddress) { duration, error in
            DispatchQueue.main.async {
                self.travelPlan.isCalculating = false
                
                if let error = error {
                    self.travelPlan.errorMessage = "Travel calculation error: \(error.localizedDescription)"
                    return
                }
                
                guard let travelDuration = duration else {
                    self.travelPlan.errorMessage = "Could not calculate travel time"
                    return
                }
                
                // Store the travel time
                self.travelPlan.travelDuration = travelDuration
                
                // Calculate arrival time (30 minutes before start time)
                let arrivalTime = startTime.addingTimeInterval(-30 * 60)
                self.travelPlan.arrivalTime = arrivalTime
                
                // Calculate leave time (travel duration before arrival time)
                let leaveTime = arrivalTime.addingTimeInterval(-travelDuration)
                self.travelPlan.suggestedLeaveTime = leaveTime
                
                // Only calculate wake-up time if:
                // 1. This is the first shift of the day
                // 2. The user has a ready time set
                if self.isFirstShiftOfDay() && self.travelPlan.readyTime > 0 {
                    // Calculate wake-up time (ready time before leave time)
                    let wakeupTime = leaveTime.addingTimeInterval(-self.travelPlan.readyTime)
                    self.travelPlan.suggestedWakeupTime = wakeupTime
                } else {
                    self.travelPlan.suggestedWakeupTime = nil
                }
            }
        }
    }
    
    // Determine the actual start time from either shift notes or session time
    private func determineStartTime() -> Date? {
        // Check shift notes for a start time
        if let notes = session.description, !notes.isEmpty {
            // First try simple scanning for a line with "Start Time" followed by a number
            let lines = notes.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            
            for line in lines {
                // Check if line contains "Start Time" or similar
                if line.lowercased().contains("start time") || line.lowercased().contains("start at") || line.lowercased().contains("begins at") {
                    // Try to extract number after any separator like ":", "-", or just spaces
                    // First extract everything after "start time" (case insensitive)
                    if let range = line.range(of: "time", options: .caseInsensitive) {
                        let afterTime = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                        
                        // Look for first number in this substring
                        let numberPattern = "\\d{1,2}(?::\\d{2})?"  // Matches "8", "8:00", "12", "12:30" etc.
                        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []),
                           let match = regex.firstMatch(in: String(afterTime), options: [], range: NSRange(afterTime.startIndex..<afterTime.endIndex, in: afterTime)),
                           let matchRange = Range(match.range, in: afterTime) {
                            
                            let timeStr = String(afterTime[matchRange])
                            
                            // If it's just a number like "8", assume it's an hour
                            if let hour = Int(timeStr) {
                                // Convert to Date
                                let calendar = Calendar.current
                                if let sessionDate = session.startDate {
                                    var dateComponents = calendar.dateComponents([.year, .month, .day], from: sessionDate)
                                    dateComponents.hour = hour
                                    dateComponents.minute = 0
                                    if let date = calendar.date(from: dateComponents) {
                                        return date
                                    }
                                }
                            }
                            
                            // If it's a time like "8:00", parse it
                            let formats = ["h:mm", "H:mm"]
                            for format in formats {
                                let formatter = DateFormatter()
                                formatter.dateFormat = format
                                
                                if let date = formatter.date(from: timeStr) {
                                    // We have a time without a date, so need to set the date to the session date
                                    let calendar = Calendar.current
                                    if let sessionDate = session.startDate {
                                        let startTimeComponents = calendar.dateComponents([.hour, .minute], from: date)
                                        var sessionDateComponents = calendar.dateComponents([.year, .month, .day], from: sessionDate)
                                        sessionDateComponents.hour = startTimeComponents.hour
                                        sessionDateComponents.minute = startTimeComponents.minute
                                        
                                        if let finalDate = calendar.date(from: sessionDateComponents) {
                                            return finalDate
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // If we get here, we found a line with "Start Time" but couldn't parse it
                    // Let's try a more aggressive approach to extract any number
                    let numberPattern = "\\d{1,2}"  // Match any 1 or 2 digit number
                    if let regex = try? NSRegularExpression(pattern: numberPattern, options: []),
                       let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..<line.endIndex, in: line)),
                       let matchRange = Range(match.range, in: line) {
                        
                        let timeStr = String(line[matchRange])
                        
                        if let hour = Int(timeStr) {
                            // Convert to Date
                            let calendar = Calendar.current
                            if let sessionDate = session.startDate {
                                var dateComponents = calendar.dateComponents([.year, .month, .day], from: sessionDate)
                                dateComponents.hour = hour
                                dateComponents.minute = 0
                                if let date = calendar.date(from: dateComponents) {
                                    return date
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Fall back to the session start time
        return session.startDate
    }

    // Calculate travel time between two addresses using MapKit
    private func calculateTravelTime(from origin: String, to destination: String, completion: @escaping (TimeInterval?, Error?) -> Void) {
        // Check if inputs are coordinate strings in format "latitude,longitude"
        let originCoordinate = parseCoordinateString(origin)
        let destinationCoordinate = parseCoordinateString(destination)
        
        // If both are already coordinates, skip geocoding
        if let originCoord = originCoordinate, let destCoord = destinationCoordinate {
            // Create a route request directly
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: originCoord))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
            request.transportType = .automobile
            
            // Calculate the route
            let directions = MKDirections(request: request)
            directions.calculate { response, error in
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                if let route = response?.routes.first {
                    // Return the expected travel time
                    let travelTimeSeconds = route.expectedTravelTime
                    completion(travelTimeSeconds, nil)
                } else {
                    let error = NSError(domain: "TravelPlanning", code: -2, userInfo: [NSLocalizedDescriptionKey: "No route found"])
                    completion(nil, error)
                }
            }
            return
        }
        
        // If one or both aren't coordinates, continue with geocoding
        let geocoder = CLGeocoder()
        var geocodedOriginCoordinate: CLLocationCoordinate2D?
        var geocodedDestinationCoordinate: CLLocationCoordinate2D?
        
        let group = DispatchGroup()
        var geocodeError: Error?
        
        // Geocode origin address if needed
        if originCoordinate == nil {
            group.enter()
            geocoder.geocodeAddressString(origin) { placemarks, error in
                defer { group.leave() }
                
                if let error = error {
                    geocodeError = error
                    return
                }
                
                if let location = placemarks?.first?.location {
                    geocodedOriginCoordinate = location.coordinate
                }
            }
        } else {
            geocodedOriginCoordinate = originCoordinate
        }
        
        // Geocode destination address if needed
        if destinationCoordinate == nil {
            group.enter()
            geocoder.geocodeAddressString(destination) { placemarks, error in
                defer { group.leave() }
                
                if let error = error {
                    geocodeError = error
                    return
                }
                
                if let location = placemarks?.first?.location {
                    geocodedDestinationCoordinate = location.coordinate
                }
            }
        } else {
            geocodedDestinationCoordinate = destinationCoordinate
        }
        
        group.notify(queue: .global()) {
            // Check for geocoding errors
            if let error = geocodeError {
                completion(nil, error)
                return
            }
            
            // Use the geocoded coordinates or the parsed coordinates
            let finalOriginCoord = geocodedOriginCoordinate ?? originCoordinate
            let finalDestinationCoord = geocodedDestinationCoordinate ?? destinationCoordinate
            
            // Check if both coordinates were obtained
            guard let originCoord = finalOriginCoord, let destinationCoord = finalDestinationCoord else {
                let error = NSError(domain: "TravelPlanning", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not geocode addresses"])
                completion(nil, error)
                return
            }
            
            // Create a route request
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: originCoord))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destinationCoord))
            request.transportType = .automobile
            
            // Calculate the route
            let directions = MKDirections(request: request)
            directions.calculate { response, error in
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                if let route = response?.routes.first {
                    // Return the expected travel time
                    let travelTimeSeconds = route.expectedTravelTime
                    completion(travelTimeSeconds, nil)
                } else {
                    let error = NSError(domain: "TravelPlanning", code: -2, userInfo: [NSLocalizedDescriptionKey: "No route found"])
                    completion(nil, error)
                }
            }
        }
    }
    
    // Helper function to parse coordinate strings in format "latitude,longitude"
    private func parseCoordinateString(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else {
            return nil
        }
        
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    // Message coworkers implementation
    /// Open the composer. It ALWAYS presents now: the old version only showed
    /// the sheet when it managed to find at least one phone number, so a shift
    /// with no coworkers — or a crew whose numbers aren't on file — looked like
    /// a dead button. The sheet itself explains which of those it is.
    private func messageCoworkers() {
        messageBody = createMessageText()

        guard coworkerContacts.isEmpty else {
            isShowingMessageComposer = true
            return
        }

        isLoadingContacts = true
        loadCoworkerPhoneNumbers { _ in
            DispatchQueue.main.async {
                self.isLoadingContacts = false
                self.isShowingMessageComposer = true
            }
        }
    }

    // Helper to create the message text
    private func createMessageText() -> String {
        return "Hey crew, "
    }
    
    /// The people this shift can message: this day's crew plus anyone working
    /// another job at the same school today, minus yourself, deduped by id.
    private func messagingCrew() -> [SessionPhotographer] {
        var seen = Set<String>()
        var crew: [SessionPhotographer] = []
        for person in session.photographers + sameDayCoworkersAtSchool() {
            guard person.id != currentUserID, !seen.contains(person.id) else { continue }
            seen.insert(person.id)
            crew.append(person)
        }
        return crew
    }

    /// Look phone numbers up by USER ID.
    ///
    /// This used to query `users` by first name — one round trip per coworker,
    /// matching `first_name == "Jason"` — so a nickname, a casing difference or
    /// two people sharing a first name silently produced no recipient. The
    /// session already carries each photographer's user id, which is exact, so
    /// it's one query keyed on that. Anyone without a number on file is recorded
    /// and named in the composer instead of vanishing.
    private func loadCoworkerPhoneNumbers(completion: @escaping (Bool) -> Void = { _ in }) {
        coworkerContacts = []
        crewWithoutNumbers = []

        let crew = messagingCrew()
        guard !crew.isEmpty else {
            completion(false)
            return
        }

        Task {
            do {
                let supabase = SupabaseManager.shared.client

                struct UserContact: Decodable {
                    let id: String
                    let phone: String?
                }

                let ids = crew.map { $0.id }
                let users: [UserContact] = try await supabase
                    .from("users")
                    .select("id, phone")
                    .in("id", values: ids)
                    .execute()
                    .value

                let phonesByID = Dictionary(uniqueKeysWithValues: users.map { ($0.id.lowercased(), $0.phone) })

                var contacts: [CoworkerContactInfo] = []
                var missing: [String] = []
                for person in crew {
                    if let phone = phonesByID[person.id.lowercased()] ?? nil, !phone.isEmpty {
                        contacts.append(CoworkerContactInfo(id: person.id, name: person.name, phoneNumber: phone))
                    } else {
                        missing.append(person.name)
                    }
                }

                await MainActor.run {
                    self.coworkerContacts = contacts
                    self.crewWithoutNumbers = missing
                    completion(!contacts.isEmpty)
                }
            } catch {
                print("⚠️ Coworker contacts unavailable: \(error.localizedDescription)")
                await MainActor.run {
                    self.crewWithoutNumbers = crew.map { $0.name }
                    completion(false)
                }
            }
        }
    }

    // Action Methods
    
    private func openInAppleMaps() {
        // Prefer school coordinates/address over session location
        let locationToUse = !schoolAddress.isEmpty ? schoolAddress : (session.location ?? "")
        guard !locationToUse.isEmpty else { return }
        
        // Check if it's coordinates (lat,lon format)
        if let coordinates = parseCoordinateString(locationToUse) {
            // Use coordinates directly for more accuracy
            let mapsString = "http://maps.apple.com/?ll=\(coordinates.latitude),\(coordinates.longitude)&q=\(session.schoolName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            if let url = URL(string: mapsString) {
                UIApplication.shared.open(url)
            }
        } else {
            // Use as address
            let addressString = locationToUse.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let mapsString = "http://maps.apple.com/?address=\(addressString)"
            if let url = URL(string: mapsString) {
                UIApplication.shared.open(url)
            }
        }
    }
    
    private func openInGoogleMaps() {
        // Prefer school coordinates/address over session location
        let locationToUse = !schoolAddress.isEmpty ? schoolAddress : (session.location ?? "")
        guard !locationToUse.isEmpty else { return }
        
        // Check if it's coordinates (lat,lon format)
        if let coordinates = parseCoordinateString(locationToUse) {
            // Use coordinates directly for more accuracy
            let mapsString = "comgooglemaps://?center=\(coordinates.latitude),\(coordinates.longitude)&q=\(coordinates.latitude),\(coordinates.longitude)&label=\(session.schoolName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            
            if let url = URL(string: mapsString), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                // Fallback to browser if Google Maps app is not installed
                let webURL = URL(string: "https://maps.google.com/?q=\(coordinates.latitude),\(coordinates.longitude)")!
                UIApplication.shared.open(webURL)
            }
        } else {
            // Use as address
            let addressString = locationToUse.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let mapsString = "comgooglemaps://?q=\(addressString)"
            
            if let url = URL(string: mapsString), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                // Fallback to browser if Google Maps app is not installed
                let webURL = URL(string: "https://maps.google.com/?q=\(addressString)")!
                UIApplication.shared.open(webURL)
            }
        }
    }
    
    
    /// Crew of OTHER jobs at this school on the SAME day (CREW.2). Matches on any of
    /// the other session's day-rows — not only its first — and takes that day's own
    /// crew, so a second multi-day job contributes the right people on each of its days.
    private func sameDayCoworkersAtSchool() -> [SessionPhotographer] {
        let dayStr = session.date
        return allSessions.compactMap { other -> Session? in
            guard other.id != session.id,
                  other.schoolName == session.schoolName,
                  let day = other.day(onDate: dayStr) else { return nil }
            return other.with(day: day)
        }.flatMap { $0.photographers }
    }

    // Check if a user profile name matches the job box scanner name
    private func isMatchingUser(profileName: String, scannedByName: String) -> Bool {
        // Don't attempt to match if scannedByName is empty
        if scannedByName.isEmpty {
            return false
        }
        
        // Get first names for comparison
        let profileFirstName = firstName(from: profileName).lowercased()
        let scannedByFirstName = firstName(from: scannedByName).lowercased()
        
        // Guard against empty strings
        if profileFirstName.isEmpty || scannedByFirstName.isEmpty {
            return false
        }
        
        // Perform exact match (case insensitive)
        return profileFirstName == scannedByFirstName
    }
    
    // Extract first name from a full name
    func firstName(from fullName: String) -> String {
        // Return empty string for empty input
        if fullName.isEmpty {
            return ""
        }
        
        // Clean the input - remove any leading/trailing whitespace
        let cleanedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Special case for "from" which appears in logs
        if cleanedName == "from" {
            return ""
        }
        
        // If the name contains ellipsis, only use the part before it
        if cleanedName.contains("...") {
            let components = cleanedName.components(separatedBy: "...")
            let nameBeforeEllipsis = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            // Get the first part of the name
            let firstPart = nameBeforeEllipsis.components(separatedBy: .whitespaces).first ?? nameBeforeEllipsis
            return firstPart
        }
        
        // Otherwise just get the first name (first part before any whitespace)
        let firstPart = cleanedName.components(separatedBy: .whitespaces).first ?? cleanedName
        return firstPart
    }
    
    // MARK: - Publishing
    
    private func publishSession() {
        isPublishing = true
        
        Task {
            do {
                try await sessionService.publishSession(sessionId: session.id)
                
                // Wait a moment for the real-time listeners to update
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                await MainActor.run {
                    isPublishing = false
                    // Show success feedback
                    self.showSuccessMessage = true
                    self.successMessage = "Session published successfully!"
                    
                    // Dismiss after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.presentationMode.wrappedValue.dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to publish session: \(error.localizedDescription)"
                    isPublishing = false
                }
            }
        }
    }
    
    // MARK: - Initial Data Loading
    
    private func loadInitialData() {
        print("🔄 ShiftDetailView: Starting data load for session: \(session.id)")
        print("🔄 ShiftDetailView: Session school: \(session.schoolName)")
        print("🔄 ShiftDetailView: Session employee: \(session.employeeName)")
        print("🔄 ShiftDetailView: Current user ID: \(currentUserID ?? "nil")")
        
        // Start loading all data asynchronously
        loadEmployeeProfile()
        loadCoworkerPhotos()
        loadLocationPhotos()
        loadUserHomeAddress()
        Task { await loadSchoolAddress() }
        loadWeatherData()
        startJobBoxListener()
        setupNotificationObserver()
        startSessionListener()
        
        // Set a minimum loading time to prevent flashing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🔄 ShiftDetailView: Finished loading for session: \(self.session.id)")
            self.isInitializing = false
        }
    }
    
    // MARK: - Real-time Session Updates
    
    private func startSessionListener() {
        // Listen for updates to the specific session using organization-wide listener with client-side filtering
        let organizationID = session.organizationID
        guard !organizationID.isEmpty else {
            print("❌ Cannot start session listener: no organization ID")
            return
        }

        // Captured out here, not read inside the callback: this is the SECOND
        // place a session enters the view layer, and the feed it listens to is
        // the raw one. Without redacting here, opening a draft would show no
        // crew for a moment and then have the listener put it straight back.
        let hideDraftCrew = DraftCrew.isHiddenFromViewer

        sessionService.startListeningToSessions(
            subscriptionId: subscriptionId,
            organizationID: organizationID,
            // Everyone, since PUB.1 — a draft has to keep updating while you are
            // looking at it, whether or not you are allowed to see its crew.
            includeUnpublished: true
        ) { sessions in
            DispatchQueue.main.async {
                // Filter for the specific session we're viewing
                if let raw = sessions.first(where: { $0.id == self.session.id }) {
                    let updatedSession = DraftCrew.redacted(raw, hidingDraftCrew: hideDraftCrew)
                    // The session we hold and the fact of whether it was redacted
                    // are replaced together — they must never drift apart.
                    self.crewHidden = hideDraftCrew
                    // Re-apply the day this view was opened on (CREW.2). The feed carries
                    // the WHOLE session — the first day's date/time and every day's crew
                    // unioned — so assigning it straight through would silently move the
                    // view (and its weather, travel plan and coworkers) onto day 1.
                    if let dayID = self.viewedDayID,
                       let day = updatedSession.days.first(where: { $0.id == dayID }) {
                        self.session = updatedSession.with(day: day)
                    } else {
                        // The day isn't in this payload (deleted, or a stale cached copy
                        // that arrives before the network fetch). Take the session as-is
                        // but KEEP viewedDayID, so a later payload can restore the day
                        // instead of pinning the view to day 1 forever.
                        self.session = updatedSession
                    }

                    // Reload related data that might have changed
                    self.loadCoworkerPhotos()
                    self.loadWeatherData()

                    // Update this session in allSessions array if it exists
                    if let index = self.allSessions.firstIndex(where: { $0.id == updatedSession.id }) {
                        self.allSessions[index] = updatedSession
                    }
                }
            }
        }
    }
}

// MARK: - Message Compose View

struct MessageComposeView: UIViewControllerRepresentable {
    var recipients: [String]
    var body: String
    @Binding var isShowing: Bool
    
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients
        controller.body = body
        return controller
    }
    
    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        var parent: MessageComposeView
        
        init(_ parent: MessageComposeView) {
            self.parent = parent
        }
        
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            parent.isShowing = false
        }
    }
    
    static var canSendText: Bool {
        MFMessageComposeViewController.canSendText()
    }
}
