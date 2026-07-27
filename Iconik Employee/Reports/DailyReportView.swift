//  DailyReportView.swift
//  Iconik Employee — the daily job report, converted in AMB.7
//
//  Replaces Misc Features/DailyJobReportView.swift, deleted in the same commit.
//
//  THE DESIGN IS NOT COPIED FROM A MOCKUP — IT IS IMPORTED FROM ONE.
//      Every piece of chrome on this screen comes from Reports/ReportFormKit.swift
//      and every rule from Reports/ReportRules.swift and ReportSchoolLink.swift,
//      which are the SAME files the lab's ReportProposalMockup draws and runs.
//      There is therefore nothing to "match": this screen cannot have different
//      padding, a different checkbox, a different confirm layout or a different
//      school-ownership rule, because it does not own any of them. That is the
//      answer to the operator's question — how do you build it exactly as
//      designed rather than treating the design as inspiration.
//
//      scripts/test_report_rules.sh compiles those real files and runs them.
//
//  WHAT THE APPROVED DESIGN IS (v3, after two rejections)
//      ONE SCREEN. Nothing collapses, nothing expands. Ten peer sections with
//      the same heading, the same card and a status on the right of each, because
//      "nothing is secondary. it is all important" — a wrong school or vehicle is
//      a payroll error and a missing job description is a billing error.
//
//  WHAT THIS PHASE DELIBERATELY DID NOT BUILD, and why it is not a silent gap
//      · No draft and no autosave for the report itself. The mockup draws a draft
//        strip and marks it PROPOSED; drawing "Draft saved" here when nothing is
//        saved would be a lie, so the strip is NOT ported. Real draft persistence
//        is a data-layer change and is arc DJR.1.
//      · No offline handling. The live form has none, the mockup adds none.
//      · The mockup's success screen is not ported: on a real submit this screen
//        posts the shell's toast notification and the shell jumps to Home, which
//        is the shipped behaviour and is kept exactly.

import SwiftUI
import CoreLocation
import MapKit
import Supabase

/// A photo on the report, and where it came from.
///
/// The `sourceURL` is what stops an attached note's photos being uploaded a
/// SECOND time: the old form downloaded them for display, re-uploaded every one
/// as a brand-new storage object, and then also appended the note's original
/// URLs — so a note with three photos put six entries on the report and three
/// duplicate objects in the bucket. A photo that already has a URL is already in
/// storage.
struct ReportPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    /// Non-nil when this photo is already in storage — it came from a note.
    var sourceURL: String?
    /// Which note put it here, so switching notes can take its photos back.
    var noteID: UUID?
}

/// A photographer the report can be filed under. Moved here from the deleted
/// DailyJobReportView, which was its only home and its only user.
struct PhotographerOption: Identifiable {
    let id: String            // user id
    let firstName: String
    let lastName: String

    var displayName: String { "\(firstName) \(lastName)" }
}

struct DailyReportView: View {

    /// True when this screen was PUSHED (from the reports list) rather than
    /// opened as its own feature from the shell.
    ///
    /// A SAFE-AREA INSET ONLY INSETS THE VIEW IT IS APPLIED TO. The shell insets
    /// a feature's ROOT for the floating tab bar; that inset does not travel
    /// into what the root pushes, so a pushed screen must do it itself — and a
    /// screen that did BOTH would reserve 168pt instead of 84. This app has paid
    /// for that lesson four times, and every wrong version of it built cleanly.
    var isPushed = false

    // MARK: - Stored account data

    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""
    @AppStorage("userLastName") private var storedUserLastName: String = ""
    @AppStorage("userHomeAddress") private var storedUserHomeAddress: String = ""
    /// The local photoshoot-note scratchpad, shared with PhotoshootNotesView and
    /// the iPad dashboard widget. Unchanged storage — a single JSON blob.
    @AppStorage("photoshootNotes") private var storedNotesData: Data = Data()

    // MARK: - What the app fills in

    @State private var reportDate = Date()
    @State private var photographers: [PhotographerOption] = []
    @State private var selectedPhotographerID: String = ""
    @StateObject private var schedule = ReportSchedule()
    /// Which session this report is for. The rule — first unreported session,
    /// once per date, a manual pick latches — lives in the tested type.
    @State private var sessionPick = SessionAutoSelect()
    /// The session as it was when it was picked. See `session`.
    @State private var pickedSession: Session?
    /// Which schools are on the report and who put them there. Tested type.
    @State private var link = ReportSchoolLink()
    @State private var schoolOptions: [SchoolItem] = []
    /// Every school this screen has ever seen, by id. Accumulates; never shrinks.
    @State private var knownSchools: [String: SchoolItem] = [:]
    @State private var isLoadingSchools = true
    /// The number and the one rule about it: a typed value is never overwritten.
    @State private var mileage = ReportMileage()
    @State private var isCalculatingMileage = false
    /// No default; both options take a second tap. Tested type.
    @State private var vehicle = VehicleSelection()

    // MARK: - The work

    @State private var shot: Set<String> = []
    @State private var extras: Set<String> = []
    @State private var cardsScanned: String?
    @State private var jobBox: String?
    @State private var sportsBackground: String?
    @State private var notes = ""
    @State private var photos: [ReportPhoto] = []

    // MARK: - Photoshoot note attachment

    @State private var photoshootNotes: [PhotoshootNote] = []
    @State private var attachedNoteID: UUID?
    /// The attached note as it was when it was attached.
    ///
    /// The blob this comes from is SHARED and re-read on every appearance, and
    /// three screens write it. If the note is submitted or deleted elsewhere
    /// while it is attached here, resolving it only through the blob loses its
    /// photos and its text — silently, because a photo that is already in
    /// storage is never in the upload count either. The snapshot is what the
    /// report falls back to.
    @State private var attachedNoteSnapshot: PhotoshootNote?
    /// The photographer chose "No photoshoot note". Distinct from never having
    /// chosen, which is what auto-attach is allowed to act on.
    @State private var hasDeclinedNote = false
    /// URLs from the attached note the photographer has removed from the grid.
    /// The report's photo list is the note's list MINUS these — derived from the
    /// note, not from what downloaded.
    @State private var droppedNoteURLs: Set<String> = []

    // MARK: - Sheets, alerts, submission

    @State private var showSchoolPicker = false
    @State private var showImagePicker = false
    @State private var tempImage: UIImage?
    @State private var isSubmitting = false
    @State private var errorMessage = ""
    /// How many photos were lost on a submit that otherwise succeeded. Set
    /// instead of leaving immediately, so the message is on a screen that is
    /// still there to show it.
    @State private var pendingPhotoLoss: Int?
    /// Median mileage this photographer has claimed at a school before, per
    /// school id. Loaded once per school, only used for the advisory.
    @State private var usualMiles: [String: Double] = [:]
    /// Which route measurement is current. See `recalculateMileage`.
    @State private var mileageRun = 0
    /// How many legs of the last route could not be measured — the geocoder or
    /// the directions request failed, which offline means ALL of them. Having an
    /// address is not the same as the leg being measured, and treating them as
    /// the same put a confident 0.0 under a full route.
    @State private var unmeasuredLegs = 0
    /// How many legs that route had, so a PARTIAL failure can be told apart from
    /// a total one. Reporting a partial as total sent the photographer looking
    /// for signal when a real, merely short, figure was already on screen.
    @State private var lastRouteLegs = 0
    /// The route the figure on screen was actually measured along.
    ///
    /// Without this, refusing to overwrite a failed measurement with zero left a
    /// number measured for a DIFFERENT route sitting there as though it were
    /// current — plausible, unreviewable, and submitted. A stale measured figure
    /// is byte-identical to a fresh one, which is the "failure indistinguishable
    /// from a legitimate value" shape in a new place.
    @State private var measuredRoute: [String] = []
    /// `reapplyLinkedSchools` runs once — see its own note.
    @State private var hasReappliedSchools = false
    @FocusState private var fieldFocused: Bool
    @ObservedObject private var tabBarManager = TabBarManager.shared

    /// The daily job report's own colour (D11) and the wash behind this screen.
    private var feature: Color { FeatureTheme.color(for: "dailyJobReport") }

    // MARK: - Derived

    private var dateKey: String { Formatters.isoDate.string(from: reportDate) }

    /// Schools on the report, resolved in ROUTE order — the order they were
    /// added, which is the order the mileage is calculated along.
    ///
    /// Resolved through `knownSchools`, which only ever GROWS. The report stores
    /// school ids, and resolving them through the live `schoolOptions` array
    /// meant that anything which emptied that array — a failed refresh, a failed
    /// reload — silently took every school off the report, leaving a submit with
    /// no destination and no mileage.
    private var stops: [SchoolItem] {
        link.stops.compactMap { knownSchools[$0] }
    }

    /// The session this report is for.
    ///
    /// Resolved from the live list, falling back to the one that was PICKED.
    /// Deriving it from `schedule.sessions` alone was a regression on the form
    /// this replaced, which held the session itself: a refresh that delivers a
    /// list without it — an offline first fetch answering with nothing, or a
    /// realtime refetch after an admin unassigns or unpublishes the session —
    /// made this nil, so the card flipped to "off-schedule", no row read as
    /// selected, and submit filed `session_id` and `session_name` as NULL.
    private var session: Session? {
        guard let id = sessionPick.selection else { return nil }
        // The snapshot is only trusted for the session it was taken FOR. Every
        // writer pairs the two today; checking it here means a future edit that
        // forgets to cannot silently file the wrong session link.
        return schedule.sessions.first { $0.id == id }
            ?? (pickedSession?.id == id ? pickedSession : nil)
    }

    private var selectedPhotographer: PhotographerOption? {
        photographers.first { $0.id == selectedPhotographerID }
    }

    /// Local drafts available to attach. A submitted note is not offered.
    private var availableNotes: [PhotoshootNote] {
        photoshootNotes.filter { $0.status == .draft }
    }

    private var attachedNote: PhotoshootNote? {
        guard let id = attachedNoteID else { return nil }
        return photoshootNotes.first { $0.id == id } ?? attachedNoteSnapshot
    }

    /// The note is still in the shared blob, so its text can still be edited.
    private var attachedNoteIsLive: Bool {
        attachedNoteID.map { id in photoshootNotes.contains { $0.id == id } } ?? false
    }

    private var miles: Double { mileage.value }

    /// Stops that can be measured — they carry coordinates, or an address to
    /// geocode. A school with neither contributes no leg.
    private var measurableStops: [SchoolItem] {
        stops.filter { stop in
            if let coordinates = stop.coordinates, !coordinates.isEmpty { return true }
            return !stop.address.isEmpty
        }
    }

    /// Stops the route cannot include. Silently dropping these produced a
    /// confident 0.0 with the full route still printed underneath it.
    private var unmeasurableStops: [SchoolItem] {
        stops.filter { stop in !measurableStops.contains { $0.id == stop.id } }
    }

    /// What is wrong with the mileage figure, if anything.
    ///
    /// ONE notice with an explicit precedence, because three independent labels
    /// stacked: two of them ended in the identical instruction, and a partial
    /// failure was announced with the wording for a total one. A screen that
    /// says the same thing twice, or says the wrong one of two true things, is
    /// the same defect as a screen that says nothing.
    private enum MileageNotice: Equatable {
        case none
        case noHomeAddress
        case routeFailed
        /// Legs that failed, plus any stop that can never be in the figure —
        /// they are different problems with different answers, and this
        /// message's instruction ("check it") does not duplicate the other's.
        case routePartial(legs: Int, excluded: [String])
        case stopsWithoutLocation([String])
    }

    private var mileageNotice: MileageNotice {
        guard !mileage.isOverridden, !isCalculatingMileage else { return .none }
        if storedUserHomeAddress.isEmpty { return .noHomeAddress }
        if unmeasuredLegs > 0 {
            // A total failure and the stops message give the SAME instruction —
            // type it in yourself — so showing both would say it twice, and the
            // total failure takes precedence alone. A PARTIAL failure says
            // "check it", a different instruction, so it carries the excluded
            // stops rather than hiding them: a stop with no location is
            // permanently out of the figure and no retry will ever include it.
            guard unmeasuredLegs < lastRouteLegs else { return .routeFailed }
            return .routePartial(legs: unmeasuredLegs, excluded: unmeasurableStops.map(\.name))
        }
        if !unmeasurableStops.isEmpty {
            return .stopsWithoutLocation(unmeasurableStops.map(\.name))
        }
        return .none
    }

    /// Is the figure well out of line with what this photographer usually claims
    /// at this school? Only meaningful for a single-stop day.
    private var mileageLooksOff: Bool {
        guard stops.count == 1, let usual = usualMiles[stops[0].id], usual > 0 else { return false }
        return abs(miles - usual) / usual > 0.5
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature, intensity: 0.3)
            form
        }
        .modifier(PushedTabBarClearance(active: isPushed))
        .navigationTitle("Daily Job Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Submit lives in the bar and is NEVER blocked by a warning —
                // the one thing it validates is the vehicle, exactly as before.
                Button(action: attemptSubmit) {
                    if isSubmitting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("Submit").font(.body.weight(.semibold))
                    }
                }
                .disabled(isSubmitting)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldFocused = false }
            }
        }
        .onAppear(perform: load)
        .onDisappear { schedule.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            // Re-subscribe when the app returns to the foreground. This must NOT
            // reset auto-select — a listener re-fire that clobbers a manual pick
            // is the bug SessionAutoSelect's latch exists to prevent.
            schedule.start(for: reportDate, onChange: runAutoSelect)
            // Coming back to the app is the commonest moment to have signal
            // again. Nothing else re-measures — the only other trigger is a
            // route change — so without this a failed measurement stayed failed
            // for the life of the screen.
            // Not while a typed value is in the field: the spinner would appear
            // under their own number on every return to the app, and a failed
            // run would quietly move the "Use N" button to "Use 0.0".
            if unmeasuredLegs > 0 && !mileage.isOverridden { recalculateMileage() }
        }
        // The route changed, so the calculated figure changes. ReportMileage is
        // what guarantees this cannot clobber a value the photographer typed.
        .onChange(of: link) { _ in
            recalculateMileage()
            loadUsualMileage()
        }
        .onChange(of: reportDate) { newDate in
            // A new date is a different day's sessions, so auto-select starts
            // over — and "which sessions have I already reported" is re-asked,
            // because the answer is per-day.
            sessionPick.dateChanged()
            link.set(nil, for: .session)
            schedule.start(for: newDate, onChange: runAutoSelect)
            refreshReported()
        }
        .alert("Error", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("OK", role: .cancel) { errorMessage = "" }
        } message: {
            Text(errorMessage)
        }
        .alert("Report submitted", isPresented: Binding(
            get: { pendingPhotoLoss != nil },
            set: { if !$0 { pendingPhotoLoss = nil } }
        )) {
            Button("OK") {
                pendingPhotoLoss = nil
                finishAndGoHome()
            }
        } message: {
            let lost = pendingPhotoLoss ?? 0
            Text("\(lost) photo\(lost == 1 ? "" : "s") could not be uploaded, so \(lost == 1 ? "it is" : "they are") not attached to the report. Everything else was filed.")
        }
        .sheet(isPresented: $showSchoolPicker) {
            ReportSchoolPickerSheet(
                schools: $schoolOptions,
                chosen: link.stops,
                organizationID: storedUserOrganizationID,
                onPick: { school in
                    knownSchools[school.id] = school
                    withAnimation(AmbientMotion.snappy) { link.addStop(school.id) }
                    showSchoolPicker = false
                },
                onCancel: { showSchoolPicker = false })
                .onDisappear { rememberSchools() }
        }
        .sheet(isPresented: $showImagePicker) {
            // One image per presentation, photo library only — unchanged. The
            // camera is Photoshoot Notes' capability and stays there.
            ImagePicker(selectedImage: $tempImage)
                .onDisappear {
                    if let image = tempImage {
                        photos.append(ReportPhoto(image: image))
                        tempImage = nil
                    }
                }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                whenSection
                sessionSection
                schoolsSection
                mileageSection
                shotSection
                extrasSection
                scanSection
                noteAttachmentSection
                notesSection
                photosSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .ambientNoBounceWhenShort()
    }

    // MARK: - Section chrome, delegated not duplicated

    private func section<Content: View>(_ title: String, status: String,
                                        statusTint: Color? = nil,
                                        @ViewBuilder content: @escaping () -> Content) -> some View {
        AmbientFormSection(title: title, status: status, statusTint: statusTint, content: content)
    }

    // MARK: - 1. Date and photographer

    private var whenSection: some View {
        section("Date and photographer", status: Formatters.relativeDay(reportDate)) {
            VStack(spacing: 0) {
                HStack {
                    Text("Date").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    DatePicker("", selection: $reportDate, displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(.vertical, 7)

                Divider()

                HStack {
                    Text("Photographer").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    if photographers.isEmpty {
                        HStack(spacing: 6) {
                            Text("Loading photographers…").font(.subheadline).foregroundStyle(.tertiary)
                            ProgressView().scaleEffect(0.7)
                        }
                    } else {
                        Picker("", selection: $selectedPhotographerID) {
                            ForEach(photographers) { person in
                                Text(person.displayName).tag(person.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: selectedPhotographerID) { _ in
                            // "Already reported" is keyed on the photographer, so
                            // a change re-asks the question before auto-select
                            // can use the answer.
                            refreshReported()
                        }
                    }
                }
                .padding(.vertical, 7)
            }
        }
    }

    // MARK: - 2. Session

    /// THE SESSION LINK — `session_id` / `session_name` on the row. It is what
    /// ties a report to the schedule and what fills the school in. Off-schedule
    /// is a first-class choice, not a fallback.
    private var sessionSection: some View {
        section("Session",
                status: session == nil ? "off-schedule" : "linked",
                statusTint: session == nil ? nil : feature) {
            VStack(alignment: .leading, spacing: 2) {
                if schedule.isLoadingSessions {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Checking your schedule…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                ForEach(schedule.sessions) { option in
                    sessionRow(option)
                }
                sessionRow(nil)

                Divider()

                if let session {
                    Label("Filled in \(session.schoolName) below. Change anything it got wrong.",
                          systemImage: "arrow.turn.down.right")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if schedule.sessions.isEmpty && !schedule.isLoadingSessions {
                    Text("Nothing scheduled for this day. The report still files normally.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Not linked to the schedule. The report still files normally.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if schedule.reportedLookupFailed && !schedule.sessions.isEmpty {
                    // Auto-select ran against an answer we do not have, so a
                    // session it offered may already be filed. Saying so is the
                    // difference between "nothing is filed" and "we could not
                    // find out" — the distinction this app lost a feature to.
                    Label("Couldn't check which of these you have already reported.",
                          systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                if !schedule.sessions.isEmpty {
                    // The live form's green "N sessions scheduled today" line,
                    // kept — minus the hardcoded "today", which it printed even
                    // on a back-dated report.
                    Text("\(schedule.sessions.count) session\(schedule.sessions.count == 1 ? "" : "s") scheduled")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// `nil` renders the off-schedule row.
    private func sessionRow(_ option: Session?) -> some View {
        let on = sessionPick.selection == option?.id
        let reported = option.map { schedule.reportedSessionIDs.contains($0.id) } ?? false
        return Button {
            withAnimation(AmbientMotion.snappy) {
                sessionPick.pick(option?.id)
                pickedSession = option
                // Picking a session REPLACES its school; choosing off-schedule
                // removes it. A school added by hand, or one the photoshoot note
                // is holding, is never touched. Tested rule.
                link.set(schoolID(for: option), for: .session)
                attachNoteMatching(option)
            }
            AmbientHaptics.selection()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? AnyShapeStyle(feature) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(option?.reportDisplayLabel ?? "No scheduled session (off-schedule)")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if reported {
                        Text("You already filed a report for this one")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }

    /// The school a SESSION points at.
    ///
    /// Prefers the session's own `school_id` and falls back to matching by name,
    /// which is what the deleted form did and what this conversion had dropped:
    /// resolving by name alone means a school renamed after the session was
    /// created puts NO school on the report, so the route is not drawn and the
    /// mileage stays at zero. The id is the robust key; the name is the legacy
    /// one.
    /// Picking a session attaches a matching photoshoot note, which the deleted
    /// form did and this conversion had dropped. Only when nothing is attached
    /// yet — a deliberate choice is never overridden.
    private func attachNoteMatching(_ session: Session?) {
        guard attachedNoteID == nil, !hasDeclinedNote, let session else { return }
        guard let match = availableNotes.first(where: { $0.school == session.schoolName }) else { return }
        attach(match)
    }

    /// Apply whatever the session and the note point at, once the school list
    /// exists to resolve it against.
    ///
    /// BOTH sources need this, and only the note got it last round. A session
    /// tapped while "Loading schools…" is on screen resolves to nil, and
    /// `runAutoSelect` then refuses to touch the link because a manual pick has
    /// LATCHED — so the school never arrived, the route had no stops, and the
    /// report filed 0.0 miles.
    ///
    /// Runs ONCE. The `noteSchool == nil` guard alone was a coincidence of the
    /// call site rather than a property of the function: the photographer can
    /// restore that state any time by removing the chip, and a second call would
    /// then undo a deliberate removal.
    private func reapplyLinkedSchools() {
        guard !hasReappliedSchools, !schoolOptions.isEmpty else { return }
        hasReappliedSchools = true
        if sessionPick.selection != nil, link.sessionSchool == nil {
            link.set(schoolID(for: session), for: .session)
        }
        if let note = attachedNote, link.noteSchool == nil {
            link.set(schoolID(named: note.school), for: .note)
        }
    }

    private func schoolID(for session: Session?) -> String? {
        guard let session else { return nil }
        if let byID = schoolOptions.first(where: { $0.id == session.school_id })?.id { return byID }
        return schoolID(named: session.schoolName)
    }

    /// The school a NOTE points at. A note carries a school NAME and no id —
    /// that is the shape of the model, not a shortcut.
    private func schoolID(named name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        return schoolOptions.first { $0.name == name }?.id
    }

    // MARK: - 3. Schools

    private var schoolsSection: some View {
        section("Schools",
                status: stops.isEmpty ? "none yet" : "\(stops.count) selected",
                statusTint: stops.isEmpty ? nil : feature) {
            VStack(alignment: .leading, spacing: 10) {
                if isLoadingSchools && schoolOptions.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Loading schools…").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if stops.isEmpty {
                    Text("No schools on this report yet — an off-schedule day still needs one.")
                        .font(.subheadline).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    AmbientFlowLayout(spacing: 7, lineSpacing: 7) {
                        ForEach(stops) { school in
                            HStack(spacing: 6) {
                                Text(school.name).font(.system(size: 13, weight: .semibold))
                                Button {
                                    withAnimation(AmbientMotion.snappy) { link.removeStop(school.id) }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(school.name)")
                            }
                            .foregroundStyle(feature)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            // ambient-allow: a token chip is a control, not a card.
                            .background(Capsule().fill(feature.opacity(0.13)))
                        }
                    }
                }

                Button { showSchoolPicker = true } label: {
                    Label("Add a school", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(feature)
                }
                .buttonStyle(.plain)
                .disabled(schoolOptions.isEmpty)
            }
        }
    }

    // MARK: - 4. Mileage and vehicle

    private var mileageSection: some View {
        section("Mileage and vehicle",
                status: vehicle.confirmed == nil
                    ? String(format: "%.1f mi · vehicle needed", miles)
                    : String(format: "%.1f mi · %@", miles, vehicle.confirmed!.rawValue.capitalized),
                statusTint: (mileageLooksOff || vehicle.confirmed == nil) ? .orange : feature) {
            mileageBody
        }
    }

    private var mileageBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Total").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                TextField(String(format: "%.1f", mileage.calculated),
                          text: Binding(get: { mileage.displayText },
                                        set: { mileage.type($0) }))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .frame(width: 84)
                    .focused($fieldFocused)
                Text("miles").font(.subheadline).foregroundStyle(.secondary)
            }

            Divider()

            // Vehicle lives WITH the mileage — one decision, not two sections —
            // and the two-step confirmation appears inline, directly under the
            // buttons that raised it.
            ReportVehiclePicker(selection: $vehicle, tint: feature)

            if isCalculatingMileage && !mileage.isOverridden {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Calculating route distances…").font(.caption).foregroundStyle(.secondary)
                }
            }

            // The route, always — but only what was actually MEASURED, and only
            // when there is a route at all. Printing "Home → Lincoln → Home"
            // above a 0.0 that skipped Lincoln is the screen contradicting
            // itself, which is the thing this line exists to prevent.
            if !measurableStops.isEmpty && !mileage.isOverridden && !storedUserHomeAddress.isEmpty {
                Text((["Home"] + measurableStops.map(\.name) + ["Home"]).joined(separator: " → "))
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            mileageNoticeLabel
            // A typed value the report cannot read is the one case where "you
            // typed this, it won't be overwritten" would be a lie.
            if mileage.typedIsUnreadable {
                Label(String(format: "That is not a number the report can use — it will file %.1f miles.", miles),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if mileage.isOverridden && !mileage.typedIsUnreadable {
                HStack(spacing: 6) {
                    Text("You typed this — it won't be overwritten.")
                        .font(.caption).foregroundStyle(.orange)
                    Button {
                        withAnimation(AmbientMotion.snappy) { mileage.useCalculated() }
                        // Handing the number back to the route is the moment to
                        // measure it again, if the last attempt failed.
                        if unmeasuredLegs > 0 { recalculateMileage() }
                    } label: {
                        Text("Use \(String(format: "%.1f", mileage.calculated))")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
            }
            if mileageLooksOff, let usual = stops.first.flatMap({ usualMiles[$0.id] }) {
                Label(String(format: "You usually claim %.1f at %@", usual, stops.first?.name ?? ""),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 5 and 6. The two lists

    @ViewBuilder
    private var mileageNoticeLabel: some View {
        switch mileageNotice {
        case .none:
            EmptyView()
        case .noHomeAddress:
            Label("No home address on your profile, so the route cannot be measured. Type the mileage in yourself.",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .routeFailed:
            HStack(alignment: .top, spacing: 6) {
                Label("The route couldn't be measured — no signal, most likely. Type the mileage in yourself.",
                      systemImage: "wifi.exclamationmark")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { recalculateMileage() }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.plain)
                    .foregroundStyle(feature)
            }
        case .routePartial(let count, let excluded):
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Label("\(count) leg\(count == 1 ? "" : "s") of this route couldn't be measured, so the figure is short. Check it before submitting.",
                          systemImage: "wifi.exclamationmark")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { recalculateMileage() }
                        .font(.caption.weight(.bold))
                        .buttonStyle(.plain)
                        .foregroundStyle(feature)
                }
                if !excluded.isEmpty { stopsWithoutLocationLabel(excluded) }
            }
        case .stopsWithoutLocation(let names):
            // On its own this IS the whole problem, so it carries the
            // instruction. Under a partial failure that line already says
            // "check it", and this one only has to say a retry will not help.
            stopsWithoutLocationLabel(names, instruction: "Type the mileage in yourself.")
        }
    }

    private func stopsWithoutLocationLabel(_ names: [String],
                                           instruction: String = "No retry will change that.") -> some View {
        Label("\(names.joined(separator: ", ")) \(names.count == 1 ? "has" : "have") no address or coordinates on file, so \(names.count == 1 ? "it is" : "they are") not in this figure. \(instruction)",
              systemImage: "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var shotSection: some View {
        listSection(title: "What did you shoot?",
                    groups: ReportOptions.jobDescriptionGroups,
                    selection: $shot,
                    tint: .orange)
    }

    private var extrasSection: some View {
        listSection(title: "Anything extra?",
                    groups: ReportOptions.extraItemGroups,
                    selection: $extras,
                    tint: .pink)
    }

    private func listSection(title: String, groups: [(String, [String])],
                             selection: Binding<Set<String>>, tint: Color) -> some View {
        section(title,
                status: selection.wrappedValue.isEmpty
                    ? "select all that apply"
                    : "\(selection.wrappedValue.count) selected",
                statusTint: selection.wrappedValue.isEmpty ? nil : tint) {
            ReportMultiSelect(groups: groups, selection: selection, tint: tint)
        }
    }

    // MARK: - 7. Cards and job box

    private var scanSection: some View {
        let answered = [cardsScanned, jobBox, sportsBackground].compactMap { $0 }.count
        return section("Cards and job box",
                       status: "\(answered) of 3 answered",
                       statusTint: answered == 3 ? .teal : nil) {
            VStack(alignment: .leading, spacing: 14) {
                AmbientChoiceRow(title: "Cards scanned",
                                options: ReportOptions.yesNo, selection: $cardsScanned)
                AmbientChoiceRow(title: "Job box and camera cards turned in",
                                options: ReportOptions.yesNoNA, selection: $jobBox)
                AmbientChoiceRow(title: "Sports background shot",
                                options: ReportOptions.yesNoNA, selection: $sportsBackground)
            }
        }
    }

    // MARK: - 8. Photoshoot note

    /// Attaching a note fills the school in, COPIES the note's photos onto the
    /// report, and its text is editable here and saved on every keystroke. On a
    /// successful submit the note is consumed.
    private var noteAttachmentSection: some View {
        section("Photoshoot note",
                status: attachedNote == nil ? "none attached" : "attached",
                statusTint: attachedNote == nil ? nil : feature) {
            VStack(alignment: .leading, spacing: 10) {
                if availableNotes.isEmpty {
                    Text("No photoshoot notes available.")
                        .font(.subheadline).foregroundStyle(.tertiary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(availableNotes) { note in
                            noteRow(note)
                        }
                        noteRow(nil)
                    }
                }

                if let attached = attachedNote, !attachedNoteIsLive {
                    // The note has left the shared blob — submitted or deleted
                    // elsewhere. Its TEXT is still filed with the report; its
                    // photos are only still there if it was submitted, because
                    // deleting a note deletes its storage objects. The message
                    // says exactly that rather than promising both.
                    Divider()
                    Label("This note is no longer in your notes list. Its text will still be filed with this report; any photos it had may already have been removed.",
                          systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if !attached.noteText.isEmpty {
                        Text(attached.noteText)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let attached = attachedNote {
                    let attachedID = attached.id
                    Divider()
                    Text(attached.school.isEmpty ? "Note" : "Note for \(attached.school)")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    // THE ONLY AUTOSAVE ON THIS SCREEN, and it is the live
                    // behaviour: every keystroke writes back to the shared blob.
                    // Resolved by ID on every read and every write. Submitting
                    // REMOVES this note while the field can still be first
                    // responder, so an index captured when the body was built is
                    // a crash waiting for one more keystroke. Same hazard the
                    // notes screen was fixed for; this was its second site.
                    TextEditor(text: Binding(
                        get: { photoshootNotes.first { $0.id == attachedID }?.noteText ?? "" },
                        set: { newValue in
                            guard let index = photoshootNotes.firstIndex(where: { $0.id == attachedID })
                            else { return }
                            photoshootNotes[index].noteText = newValue
                            // The snapshot is a FALLBACK, not a second story —
                            // it has to keep up, or a note that later left the
                            // blob would file the text as it was before editing.
                            attachedNoteSnapshot = photoshootNotes[index]
                            savePhotoshootNotes()
                        }))
                        .frame(minHeight: 72)
                        .font(.subheadline)
                        .scrollContentBackground(.hidden)
                        .focused($fieldFocused)
                    let carried = attached.photoURLs.filter { !droppedNoteURLs.contains($0) }.count
                    if carried > 0 {
                        Label("\(carried) photo\(carried == 1 ? "" : "s") from this note will be copied onto the report.",
                              systemImage: "photo.on.rectangle.angled")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// `nil` renders the "don't attach one" row.
    private func noteRow(_ note: PhotoshootNote?) -> some View {
        let on = attachedNoteID == note?.id
        return Button {
            withAnimation(AmbientMotion.snappy) { attach(note) }
            AmbientHaptics.selection()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? AnyShapeStyle(feature) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.map { noteLabel($0) } ?? "No photoshoot note")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note, !note.noteText.isEmpty {
                        Text(note.noteText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }

    private func noteLabel(_ note: PhotoshootNote) -> String {
        let time = Formatters.shortTime.string(from: note.timestamp)
        return note.school.isEmpty ? "\(time) — no school yet" : "\(time) — \(note.school)"
    }

    // MARK: - 9. Notes

    private var notesSection: some View {
        section("Notes",
                status: notes.isEmpty ? "nothing written" : "\(notes.count) characters",
                statusTint: notes.isEmpty ? nil : feature) {
            TextEditor(text: $notes)
                .frame(minHeight: 96)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .focused($fieldFocused)
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Anything the lab or the next photographer needs to know.")
                            .font(.subheadline).foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - 10. Photos

    private var photosSection: some View {
        section("Photos",
                status: photos.isEmpty ? "none attached" : "\(photos.count) attached",
                statusTint: photos.isEmpty ? nil : feature) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(photos) { photo in
                    Image(uiImage: photo.image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76)
                        // ambient-allow: a photo thumbnail is content, not a card.
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(AmbientMotion.snappy) {
                                    if let url = photo.sourceURL { droppedNoteURLs.insert(url) }
                                    photos.removeAll { $0.id == photo.id }
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.white, .black.opacity(0.55))
                                    .padding(3)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove photo")
                        }
                }
                Button { showImagePicker = true } label: {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.4),
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(height: 76)
                        .overlay(Image(systemName: "plus").font(.title3).foregroundStyle(.secondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add photo")
            }
        }
    }

    // MARK: - Loading

    private func load() {
        loadPhotoshootNotes()
        loadPhotographers()
        loadSchools()
        schedule.start(for: reportDate, onChange: runAutoSelect)
    }

    private func loadPhotoshootNotes() {
        // A corrupt blob currently wipes every visible draft with no message
        // (finding R5). Not repaired here — it is shared storage three screens
        // write, and repairing it belongs with that storage, not with a restyle.
        photoshootNotes = (try? JSONDecoder().decode([PhotoshootNote].self, from: storedNotesData)) ?? []
        // Auto-select ONLY when there is exactly one, which is the live rule.
        if attachedNoteID == nil, !hasDeclinedNote, availableNotes.count == 1 {
            attach(availableNotes[0])
        }
    }

    private func savePhotoshootNotes() {
        if let encoded = try? JSONEncoder().encode(photoshootNotes) {
            storedNotesData = encoded
        }
    }

    private func loadPhotographers() {
        guard !storedUserOrganizationID.isEmpty else {
            errorMessage = "Unable to load photographers: not signed in or organization not found"
            return
        }
        Task {
            do {
                let members = try await TeamService.shared.getTeamMembers(organizationID: storedUserOrganizationID)
                await MainActor.run {
                    let people = members
                        .map { PhotographerOption(id: $0.id, firstName: $0.firstName, lastName: $0.lastName ?? "") }
                        .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
                    self.photographers = people
                    if self.selectedPhotographerID.isEmpty {
                        // Exact first+last match on the stored name, else the first.
                        let mine = people.first {
                            $0.firstName == self.storedUserFirstName && $0.lastName == self.storedUserLastName
                        }
                        self.selectedPhotographerID = (mine ?? people.first)?.id ?? ""
                    }
                    self.refreshReported()
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    private func loadSchools() {
        guard !storedUserOrganizationID.isEmpty else {
            isLoadingSchools = false
            errorMessage = "Unable to load schools: not signed in or organization not found"
            return
        }
        Task {
            do {
                let schools = try await SchoolService.shared.getSchools(organizationID: storedUserOrganizationID)
                await MainActor.run {
                    self.schoolOptions = ReportSchoolItem.make(from: schools)
                    self.rememberSchools()
                    self.isLoadingSchools = false
                    // A session or a note may already be chosen but unresolvable
                    // until now — a single draft note auto-attaches BEFORE this
                    // returns, so without this its school never reaches the
                    // report and an off-schedule day files with no school at all.
                    self.runAutoSelect()
                    self.reapplyLinkedSchools()
                    self.recalculateMileage()
                    self.loadUsualMileage()
                }
            } catch {
                await MainActor.run {
                    self.isLoadingSchools = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Fold the current option list into the cache the report resolves through.
    private func rememberSchools() {
        for school in schoolOptions { knownSchools[school.id] = school }
    }

    private func refreshReported() {
        guard let photographer = selectedPhotographer else { return }
        Task {
            await schedule.refreshReported(photographerFirstName: photographer.firstName,
                                           organizationID: storedUserOrganizationID)
            await MainActor.run { runAutoSelect() }
        }
    }

    /// Runs the tested rule, then applies whatever it chose through the other
    /// tested rule. Both are safe to call repeatedly — auto-select runs at most
    /// once per date and never overrides a manual pick.
    private func runAutoSelect() {
        // Every gate here is one the live form had, for the same reason:
        //   · latched — a manual pick is never overridden by a listener re-fire
        //   · already run for this date — it decides once per date
        //   · schools loaded — a session must be able to resolve to a school, or
        //     the one deciding call would fill in nothing and never come back
        //   · photographer known and "already reported" answered — otherwise the
        //     first run offers a session that has already been filed
        guard !sessionPick.isLatched,
              sessionPick.ranFor != dateKey,
              !schedule.isLoadingSessions,
              schedule.hasCheckedReported,
              !schoolOptions.isEmpty else { return }

        sessionPick.run(for: dateKey, sessions: schedule.autoSelectCandidates)
        pickedSession = sessionPick.selection.flatMap { id in
            schedule.sessions.first { $0.id == id }
        }
        // Only the deciding call touches the school list, so a school the
        // photographer removed by hand is not silently put back by a refresh.
        link.set(schoolID(for: session), for: .session)
        attachNoteMatching(session)
    }

    // MARK: - Mileage

    private func recalculateMileage() {
        // Every recalculation gets a number. A slow route measured for a school
        // list the photographer has since changed must not land on top of the
        // current one — the live form had no such guard, so an in-flight
        // calculation could overwrite the figure for a different route.
        mileageRun += 1
        let run = mileageRun

        // NOTHING IS RESET HERE. Clearing `measuredRoute` on the way in made the
        // "keep the figure" branch below UNREACHABLE — the comparison at the end
        // could only ever see an empty array — so a failed re-check destroyed
        // the measurement it was written to protect: background the app for a
        // banner in a dead-signal area and an accurate 9.1 became 0.0, which
        // submits. Clearing `unmeasuredLegs` here would be the same mistake one
        // step further on: the kept figure's "this is short" warning would
        // vanish with it. The state describes the FIGURE ON SCREEN, so only
        // something that changes the figure may change it — and while a run is
        // in flight `mileageNotice` is `.none` anyway.
        guard !storedUserHomeAddress.isEmpty else {
            // No home address means no route to measure. The live form CLEARED
            // the field here, wiping a typed value; ReportMileage leaves a typed
            // value alone and simply has nothing calculated to offer.
            mileage.recalculate(to: 0)
            forgetMeasuredRoute()
            isCalculatingMileage = false
            return
        }

        let route: [String] = [storedUserHomeAddress]
            + measurableStops.map { stop -> String in
                if let coordinates = stop.coordinates, !coordinates.isEmpty { return coordinates }
                return stop.address
            }
            + [storedUserHomeAddress]

        guard route.count > 2 else {
            // Nothing measurable to route between. The figure is zero and no leg
            // failed, so there is nothing outstanding to warn about or retry.
            mileage.recalculate(to: 0)
            forgetMeasuredRoute()
            isCalculatingMileage = false
            return
        }

        isCalculatingMileage = true
        Task {
            var total = 0.0
            var failed = 0
            for index in 0..<(route.count - 1) {
                if let leg = await ReportRoute.miles(from: route[index], to: route[index + 1]) {
                    total += leg
                } else {
                    failed += 1
                }
            }
            await MainActor.run {
                guard run == self.mileageRun else { return }
                self.isCalculatingMileage = false

                if failed < route.count - 1 {
                    // Something was measured. Even a partial figure describes
                    // THIS route, so it is recorded as such.
                    self.mileage.recalculate(to: total)
                    self.measuredRoute = route
                    self.unmeasuredLegs = failed
                    self.lastRouteLegs = route.count - 1
                } else if route != self.measuredRoute {
                    // Nothing was measured AND this is not the route the figure
                    // on screen was measured along. Keeping it would show a
                    // number for a route that no longer exists — plausible,
                    // unreviewable, and submitted. Zero is honest, and the
                    // notice says why and offers a retry.
                    self.mileage.recalculate(to: 0)
                    self.measuredRoute = []
                    self.unmeasuredLegs = failed
                    self.lastRouteLegs = route.count - 1
                }
                // The remaining case — nothing measured, same route as the
                // figure already on screen — is a failed RE-check of a number
                // that is still there. THE COUNTERS ARE LEFT ALONE TOO: the
                // notice describes the FIGURE, not the last attempt, and
                // overwriting them relabelled a kept partial figure as a total
                // failure, throwing away the accurate "this is short" warning.
            }
        }
    }

    /// There is no measured figure any more, so nothing is outstanding.
    private func forgetMeasuredRoute() {
        measuredRoute = []
        unmeasuredLegs = 0
        lastRouteLegs = 0
    }

    /// What this photographer usually claims at a single-stop school, so a
    /// figure well out of line with it can be flagged in place. Read-only, cached
    /// per school for the life of the screen.
    private func loadUsualMileage() {
        guard stops.count == 1, let school = stops.first,
              usualMiles[school.id] == nil,
              let photographer = selectedPhotographer,
              !storedUserOrganizationID.isEmpty else { return }

        let end = Date()
        guard let start = Calendar.current.date(byAdding: .month, value: -12, to: end) else { return }
        let schoolID = school.id
        let schoolName = school.name
        let firstName = photographer.firstName
        let organizationID = storedUserOrganizationID

        Task {
            do {
                let past = try await DailyJobReportService.shared.getReportsForSchool(
                    schoolName: schoolName, organizationID: organizationID,
                    startDate: start, endDate: end)
                let mine = past
                    .filter { $0.your_name == firstName && $0.total_mileage > 0 }
                    .map(\.total_mileage)
                    .sorted()
                guard mine.count >= 3 else { return }     // too few to be a norm
                let median = mine[mine.count / 2]
                await MainActor.run { usualMiles[schoolID] = median }
            } catch {
                print("⚠️ DailyReportView: mileage history lookup failed — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Attaching a note

    private func attach(_ note: PhotoshootNote?) {
        // Recorded BEFORE the guard. With two or more drafts the screen opens
        // with nothing attached and "No photoshoot note" already drawn as the
        // selection, so tapping it is a no-op — and the decision was lost.
        if note == nil { hasDeclinedNote = true }
        guard attachedNoteID != note?.id else { return }
        // Anything the PREVIOUS note put here goes with it. Switching notes used
        // to leave the old note's photos on the report, so the report
        // accumulated the photos of every note the photographer looked at.
        photos.removeAll { $0.noteID != nil }
        droppedNoteURLs.removeAll()
        attachedNoteID = note?.id
        attachedNoteSnapshot = note
        // Same rule as the session: replace this source's school, remove it when
        // you choose none, leave everything else alone.
        link.set(schoolID(named: note?.school), for: .note)
        if let note { importPhotos(from: note) }
    }

    /// Photos on a note are shown on the report by downloading each URL.
    ///
    /// THIS IS DISPLAY ONLY, and that distinction is the whole point. What ends
    /// up on the report is the NOTE's own URL list minus anything the
    /// photographer deleted — never the set of downloads that happened to
    /// succeed. An earlier version of this fix derived the report's photos from
    /// the downloaded thumbnails, so one failed download on a weak connection
    /// dropped a photo from the report silently, and submitting before the
    /// downloads landed dropped ALL of them — and the note is deleted on submit,
    /// so those photos had nowhere else to be.
    ///
    /// A photo that already has a URL is already in storage, which is what stops
    /// submit uploading it a second time.
    private func importPhotos(from note: PhotoshootNote) {
        let noteID = note.id
        for urlString in note.photoURLs {
            guard let url = URL(string: urlString) else { continue }
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) else { return }
                await MainActor.run {
                    // Still the same note, and not already here. Identity is the
                    // URL, so there is no full-resolution re-encode to compare
                    // bytes — the old form ran a PNG encode of every image
                    // against every other one, on the main actor.
                    guard attachedNoteID == noteID,
                          !photos.contains(where: { $0.sourceURL == urlString }) else { return }
                    photos.append(ReportPhoto(image: image, sourceURL: urlString, noteID: noteID))
                }
            }
        }
    }

    // MARK: - Submitting

    /// Tell the shell the report landed and let it take the photographer home.
    /// The screen never dismisses itself — that is the shipped behaviour.
    private func finishAndGoHome() {
        NotificationCenter.default.post(name: Notification.Name("ShowReportSuccessToast"), object: nil)
        tabBarManager.selectedTab = "home"
    }

    /// The ONE thing validated before submit, unchanged: the vehicle. A report
    /// with no school, no mileage and no job descriptions still submits.
    private func attemptSubmit() {
        guard let chosen = vehicle.confirmed else {
            errorMessage = "Please select whether this was your Personal vehicle or a Company vehicle before submitting."
            return
        }
        submit(vehicleType: chosen.rawValue)
    }

    private func submit(vehicleType: String) {
        guard let currentUserID = UserManager.shared.getCurrentUserIDUnified() else {
            errorMessage = "User not signed in."
            return
        }
        isSubmitting = true
        errorMessage = ""

        // EVERY field is read HERE, before anything is awaited. The form stays
        // live while photos upload — only the Submit button is disabled — and
        // reading half the fields before the upload and half after produced a
        // row whose date and session were the new ones and whose school was the
        // old one.
        let note = attachedNote
        // Is this note still in the shared list — i.e. still ours to consume?
        // `status` cannot answer: everything offered is a draft, and the
        // snapshot freezes that value at attach time.
        let noteIsLive = attachedNoteIsLive
        let organizationID = storedUserOrganizationID
        let stopNames = stops.map(\.name).joined(separator: ", ")
        // Always store a destination: when a session is picked but its school did
        // not resolve to a SchoolItem, fall back to the session's own name so the
        // destination is never lost.
        let destination = stopNames.isEmpty ? session?.schoolName : stopNames
        let yourName = selectedPhotographer?.firstName ?? ""
        let submittedDate = reportDate
        let submittedSession = session
        let submittedMiles = miles
        let submittedShot = shot
        let submittedExtras = extras
        let submittedCards = cardsScanned
        let submittedJobBox = jobBox
        let submittedBackground = sportsBackground
        let submittedNotes = notes
        // Photos already carrying a URL came from the attached note and are
        // already in storage; only the rest are uploaded.
        let toUpload = photos.filter { $0.sourceURL == nil }.map(\.image)
        // The note's OWN list is authoritative — not the downloads that
        // succeeded — and anything on the grid that carries a URL is added
        // after it, in case the note has left the shared blob since. Minus
        // whatever the photographer deleted. Order is the note's order first,
        // which is the order they were taken in.
        var existingURLs: [String] = []
        for url in (note?.photoURLs ?? []) where !droppedNoteURLs.contains(url) {
            existingURLs.append(url)
        }
        for url in photos.compactMap(\.sourceURL)
        where !droppedNoteURLs.contains(url) && !existingURLs.contains(url) {
            existingURLs.append(url)
        }

        Task {
            var photoURLs: [String] = []
            var failedUploads = 0

            if !toUpload.isEmpty && !organizationID.isEmpty {
                let result = await ReportPhotoUpload.upload(
                    toUpload, folder: "\(organizationID)/\(currentUserID)")
                photoURLs = result.urls
                failedUploads = result.failed
            } else if !toUpload.isEmpty && organizationID.isEmpty {
                failedUploads = toUpload.count
            }

            photoURLs.append(contentsOf: existingURLs)

            let report = DailyJobReport(
                id: UUID().uuidString.lowercased(),
                organizationID: organizationID,
                userId: currentUserID,
                date: submittedDate,
                yourName: yourName,
                schoolOrDestination: destination,
                sessionId: submittedSession?.id,
                sessionName: submittedSession?.reportDisplayLabel,
                totalMileage: submittedMiles,
                vehicleType: vehicleType,
                jobDescriptions: submittedShot.isEmpty ? nil : Array(submittedShot),
                extraItems: submittedExtras.isEmpty ? nil : Array(submittedExtras),
                cardsScannedChoice: submittedCards,
                jobBoxAndCameraCards: submittedJobBox,
                sportsBackgroundShot: submittedBackground,
                jobDescriptionText: submittedNotes.isEmpty ? nil : submittedNotes,
                photoshootNoteID: note?.id.uuidString.lowercased(),
                photoshootNoteText: note?.noteText,
                photoURLs: photoURLs.isEmpty ? nil : photoURLs,
                reportType: "standard")

            do {
                let created = try await DailyJobReportService.shared.createReport(report)

                // Linked only while the note is still in the shared list.
                // `attachToReport` is an unconditional UPDATE of
                // `daily_report_id`, so touching a note that has already left —
                // submitted or deleted on ANOTHER SCREEN OF THIS DEVICE — would
                // repoint a row this report has no claim on, on the shared
                // database. It cannot see a note submitted on a DIFFERENT
                // device: the drafts live in this device's own UserDefaults and
                // nothing reconciles them, which is part of what the photoshoot-
                // note repair (findings R1/R2/R3/R8) has to settle.
                if let note, noteIsLive {
                    do {
                        try await PhotoshootNoteService.shared.attachToReport(noteId: note.id,
                                                                             reportId: created.id)
                    } catch {
                        print("⚠️ DailyReportView: failed to link note to report — \(error.localizedDescription)")
                    }
                }

                await MainActor.run {
                    self.isSubmitting = false

                    // The used note is consumed now that its content is in the
                    // report. Its PHOTOS are deliberately not deleted — their
                    // URLs were copied onto the report above.
                    if let note, let index = self.photoshootNotes.firstIndex(where: { $0.id == note.id }) {
                        self.photoshootNotes.remove(at: index)
                        self.attachedNoteID = nil
                        self.savePhotoshootNotes()
                        Task { try? await PhotoshootNoteService.shared.deleteNote(id: note.id) }
                    }

                    if failedUploads > 0 {
                        // The report is filed either way — that is the shipped
                        // behaviour and this phase does not change it. What
                        // changes is that the loss is SAID.
                        //
                        // And it is said BEFORE leaving: raising an alert in the
                        // same update that switches the tab puts the message on
                        // a screen the shell is tearing down, which is the
                        // silent loss this was written to remove. Going home
                        // waits for the acknowledgement.
                        self.pendingPhotoLoss = failedUploads
                    } else {
                        self.finishAndGoHome()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSubmitting = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Clearance for a pushed screen

/// Leaves room for the floating tab bar, but only when this screen was pushed.
///
/// Split into a modifier so the branch is fixed at the call site and can never
/// flip at runtime — a `_ConditionalContent` identity switch mid-animation is
/// its own class of bug. Same shape as `AmbientGlow` in the design system.
struct PushedTabBarClearance: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            // Reads the shell's own state, so a pushed screen does not have to
            // be told whether the bar is up or whether the keyboard is showing.
            content.tabBarClearance()
        } else {
            content
        }
    }
}

// MARK: - Route measurement

/// Driving distance between two waypoints, each either a "lat,lng" pair or a
/// street address. Lifted verbatim in behaviour from the deleted form — real
/// MKDirections driving routes, not straight lines — and wrapped in async so the
/// caller is a loop rather than a DispatchGroup.
enum ReportRoute {

    static func miles(from origin: String, to destination: String) async -> Double? {
        guard let start = await coordinate(for: origin),
              let end = await coordinate(for: destination) else { return nil }
        return await drive(from: start, to: end)
    }

    /// A waypoint written as "lat,lng" needs no geocoding at all, which is why
    /// schools carrying coordinates are preferred over their addresses.
    ///
    /// Deliberately NOT an overload of `coordinate(for:)` — a sync and an async
    /// function with the same name resolve to the async one inside an async
    /// context, so the "fast path" would have called itself forever.
    private static func parseCoordinate(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func coordinate(for text: String) async -> CLLocationCoordinate2D? {
        if let parsed = parseCoordinate(text) { return parsed }
        let placemarks = try? await CLGeocoder().geocodeAddressString(text)
        return placemarks?.first?.location?.coordinate
    }

    private static func drive(from origin: CLLocationCoordinate2D,
                              to destination: CLLocationCoordinate2D) async -> Double? {
        let request = MKDirections.Request()
        request.transportType = .automobile
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        guard let response = try? await MKDirections(request: request).calculate(),
              let route = response.routes.first else { return nil }
        return route.distance * 0.000621371
    }
}

// MARK: - Photo upload

/// Uploading a report's photos, and counting what did not make it.
///
/// The live form set an error alert inside its upload loop and then submitted
/// anyway, so a failed photo produced an error AND a success with the photo
/// silently missing (finding R34). The submit behaviour is unchanged — a photo
/// failure has never blocked a report and this phase does not change that — but
/// the count comes back so the caller can SAY what was lost.
enum ReportPhotoUpload {

    /// - Parameters:
    ///   - folder: the directory prefix inside the `daily-reports` bucket. Each
    ///     caller keeps the layout it already writes — the standard report uses
    ///     `org/user`, the template form `template-reports/user` — because the
    ///     objects already in storage are addressed by those paths.
    ///   - maxDimension: nil uploads the image as-is, which is what the standard
    ///     report has always done. The template path downsamples, so it passes a
    ///     number. Deliberately not harmonised: that would change the bytes this
    ///     phase stores, and a design phase does not do that quietly.
    static func upload(_ images: [UIImage], folder: String,
                       maxDimension: CGFloat? = nil) async -> (urls: [String], failed: Int) {
        let storage = SupabaseManager.shared.client.storage
        var urls: [String] = []
        var failed = 0

        for image in images {
            let encoded: Data? = maxDimension.map {
                image.downsampledJPEGData(maxDimension: $0, quality: 0.8)
            } ?? image.jpegData(compressionQuality: 0.8)
            guard let data = encoded else {
                failed += 1
                continue
            }
            let path = "\(folder)/\(Date().timeIntervalSince1970)_\(UUID().uuidString.lowercased()).jpg"
            do {
                _ = try await storage.from("daily-reports").upload(path, data: data)
                // Signed URL, one year — the app's existing expiry everywhere.
                let signed = try await storage.from("daily-reports")
                    .createSignedURL(path: path, expiresIn: 31_536_000)
                urls.append(signed.absoluteString)
            } catch {
                print("❌ ReportPhotoUpload: \(error.localizedDescription)")
                failed += 1
            }
        }
        return (urls, failed)
    }
}
