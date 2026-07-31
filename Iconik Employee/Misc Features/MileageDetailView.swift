//  MileageDetailView.swift
//  Iconik Employee — one trip, converted to Ambient in AMB.9
//
//  The old screen is GONE from this file: the hand-rolled card with its manual
//  dark-mode branch, the inline Save/Cancel/Edit buttons sitting halfway down the
//  content, the nav modifiers and BOTH `.alert`s attached INSIDE the ScrollView,
//  the deprecated `presentationMode`, and the in-view Supabase UPDATE.
//
//  WHAT CHANGED, and why each is in scope:
//    · EDIT IS A TOOLBAR MODE. Edit → Cancel/Save in the nav bar. An edit that
//      changes a payroll figure should be a mode you enter, not a pair of buttons
//      between two cards.
//    · SAVE IS DISABLED IN FLIGHT and shows a spinner. The old button stayed live,
//      so a second tap fired a second UPDATE.
//    · PERSONAL IS BADGED. The old read mode drew an orange "Company car" line and
//      NOTHING AT ALL for a personal trip — absence was the only signal.
//    · ONE INLINE MESSAGE INSTEAD OF TWO STACKED ALERTS. Two `.alert` modifiers on
//      one view is the shape where one swallows the other; validation and failure
//      are drawn where the mistake is.
//    · `errorMessage` IS CLEARED on entry to Save and on Cancel. It never was, so a
//      resolved failure kept re-appearing.
//    · THE SCHOOLS DEAD END IS GONE. The form tested `schoolOptions.isEmpty` and
//      drew "Loading schools..." whenever it was true — so an org with ZERO schools
//      showed a spinner forever beside an unsatisfiable "Please select a school.",
//      and a FAILED load looked identical. Three situations, three states
//      (`MileageSchoolsState`).
//    · THE WRITE MOVED TO THE SERVICE. `DailyJobReportService.updateMileage` owns
//      it, and it sends the record id EXACTLY as decoded: `daily_job_reports.id` is
//      text written by Swift's own uppercase `UUID`, so lowercasing it matched zero
//      rows — and a zero-row PostgREST UPDATE returns 200. The service now asks for
//      the written rows back and throws when there are none, which is what makes the
//      failure reach the notice below instead of dismissing as a save.
//
//  WHAT IS DELIBERATELY UNCHANGED, and named rather than silently carried:
//    · THE RATES ARE STILL CAPTURED AT PUSH TIME. A parent whose rate fetch has not
//      landed pins 0.67/0.10 for this screen's lifetime. The root now loads rates
//      before its first row can be tapped, but the parameter is still a snapshot.
//    · THE SCHOOL IS STILL STORED BY NAME, not by id — a rename orphans history.
//      That is a data-model change (`daily_job_reports.school_or_destination` is
//      text) and belongs with the reports arc, not a restyle.
//    · THERE IS STILL NO PERMISSION OR OWNERSHIP GATE on editing, and the UPDATE
//      carries no user/org filter — RLS is the only cross-tenant guard. Moving an
//      authorization boundary is not a design phase's call.
//    · THE SCREEN STILL EXPOSES 3 OF 28 COLUMNS and has no route to the full
//      report. There is no such route in the data layer to draw.
//
//  CLEARANCE: this screen is PUSHED, so it insets ITSELF — a container's root inset
//  is not inherited by what it pushes (see Navigation/BottomTabBar.swift).

import SwiftUI

struct MileageDetailView: View {
    let record: MileageReportsViewModel.MileageRecordWrapper
    let personalRate: Double
    let companyRate: Double

    // Local copies of the record data for editing.
    @State private var schoolName: String
    /// THE VEHICLE IS HELD AS THE TYPE, not as its label.
    ///
    /// It used to be a `String?` carrying "Personal"/"Company" and the save path
    /// mapped it back with `MileageVehicle.from(choiceLabel:) ?? .personal` — so a
    /// label the form no longer offers (a rename, a localisation, a typo) resolved
    /// silently to PERSONAL and wrote a company trip at the personal rate. That is a
    /// payroll figure changed by a string comparison. The label is now derived FROM
    /// the type for the choice row and parsed back only inside that row's binding,
    /// where an unrecognised label changes nothing at all.
    @State private var vehicle: MileageVehicle
    @State private var milesText: String

    @State private var isEditing = false
    @State private var isSaving = false
    /// Validation and failure are one line, drawn under the form.
    @State private var noticeMessage: String?

    @State private var schoolOptions: [MileageSchoolItem] = []
    @State private var schoolsState: MileageSchoolsState = .loading
    @State private var hasRequestedSchools = false

    @Environment(\.dismiss) private var dismiss

    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""

    private var tint: Color { MileageStyle.tint }

    init(record: MileageReportsViewModel.MileageRecordWrapper, personalRate: Double, companyRate: Double) {
        self.record = record
        self.personalRate = personalRate
        self.companyRate = companyRate
        _schoolName = State(initialValue: record.schoolName)
        _vehicle = State(initialValue: MileageVehicle.from(storage: record.vehicleType))
        _milesText = State(initialValue: MileageFigures.oneDecimal(record.totalMileage))
    }

    // MARK: - Derived

    /// The choice row takes plain strings — the kit does not know this enum exists —
    /// so the labels are generated from the cases and parsed back through
    /// `MileageVehicle.from(choiceLabel:)`, which returns nil for anything the form
    /// does not offer. A nil is IGNORED rather than defaulted: the selection simply
    /// does not move, and nothing on the save path ever maps a label to a vehicle.
    /// One direction of mapping, and the labels are defined once, in MileageRules.
    private var vehicleChoice: Binding<String?> {
        Binding(get: { vehicle.choiceLabel },
                set: { newValue in
                    guard let newValue, let picked = MileageVehicle.from(choiceLabel: newValue) else { return }
                    vehicle = picked
                })
    }

    private var rate: Double {
        VehicleRates.rate(forVehicleType: vehicle.storageValue,
                          personalRate: personalRate,
                          companyCarRate: companyRate)
    }

    /// What the hero shows while the field is being typed into. An unreadable field
    /// reads as zero miles here and is REJECTED by Save — it is not written.
    private var miles: Double {
        Double(milesText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    MileageDetailHero(school: schoolName,
                                      date: record.date,
                                      miles: miles,
                                      vehicle: vehicle,
                                      rate: rate,
                                      tint: tint)

                    if isEditing {
                        MileageEditForm(schoolName: $schoolName,
                                        vehicleChoice: vehicleChoice,
                                        milesText: $milesText,
                                        schools: schoolOptions,
                                        schoolsState: schoolsState,
                                        validationMessage: noticeMessage,
                                        retrySchools: { loadSchools(force: true) },
                                        tint: tint)
                    } else {
                        MileageDetailReadRows(school: schoolName, vehicle: vehicle, miles: miles)
                        if let noticeMessage {
                            MileageInlineNotice(message: noticeMessage)
                        }
                    }

                    MileageEditFootnote()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        // A PUSHED screen insets itself: a safe-area inset does not travel out of
        // the shell's navigation container into what it pushes.
        .tabBarClearance()
        .navigationTitle("Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { cancelEditing() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { save() }
                        .font(.body.weight(.semibold))
                }
            }
        } else {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { beginEditing() }
            }
        }
    }

    // MARK: - Mode

    private func beginEditing() {
        noticeMessage = nil
        withAnimation(AmbientMotion.snappy) { isEditing = true }
        loadSchools()
    }

    private func cancelEditing() {
        schoolName = record.schoolName
        vehicle = MileageVehicle.from(storage: record.vehicleType)
        milesText = MileageFigures.oneDecimal(record.totalMileage)
        // Cleared on Cancel: a message about an edit that no longer exists is noise.
        noticeMessage = nil
        withAnimation(AmbientMotion.snappy) { isEditing = false }
    }

    // MARK: - Save

    private func save() {
        guard !isSaving else { return }
        // Cleared on ENTRY, so a second attempt is not judged by the first one's
        // message.
        noticeMessage = nil

        let validation = MileageEditValidation.evaluate(school: schoolName,
                                                        vehicle: vehicle,
                                                        milesText: milesText)
        guard case .valid(let school, let vehicle, let miles) = validation else {
            noticeMessage = validation.message
            return
        }

        milesText = MileageFigures.oneDecimal(miles)
        isSaving = true

        Task {
            do {
                try await DailyJobReportService.shared.updateMileage(recordId: record.id,
                                                                    schoolName: school,
                                                                    vehicleType: vehicle.storageValue,
                                                                    totalMileage: miles)
                await MainActor.run {
                    isSaving = false
                    AmbientHaptics.impact(.medium)
                    // Success pops. The list reloads on reappearance.
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    // Edit mode STAYS: the typed values are still on screen and the
                    // save can be tried again.
                    noticeMessage = "Couldn't save this trip — \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Schools

    /// Loaded through `SchoolService`, which either returns or throws — so "no
    /// schools" and "the load failed" are distinguishable. `DatabaseManager`'s
    /// refresh is deliberately not used: it calls back only when the data CHANGED
    /// and its failure path calls back with an empty array, which is how a spinner
    /// runs forever and a failure reads as an empty organisation.
    private func loadSchools(force: Bool = false) {
        guard force || !hasRequestedSchools else { return }
        hasRequestedSchools = true
        schoolsState = .loading

        Task {
            do {
                let schools = try await SchoolService.shared.getSchools(organizationID: storedUserOrganizationID)
                let items = schools
                    .map { MileageSchoolItem(id: $0.id, name: $0.name) }
                    .sorted { $0.name.lowercased() < $1.name.lowercased() }
                await MainActor.run {
                    schoolOptions = items
                    schoolsState = items.isEmpty ? .empty : .ready
                    // Keep the report's own school selected when it is one of them;
                    // when it is not, the typed value stands rather than being
                    // silently blanked.
                    if let matched = items.first(where: { $0.name == record.schoolName }) {
                        schoolName = matched.name
                    }
                }
            } catch {
                await MainActor.run {
                    schoolsState = .failed("Couldn't load your organization's schools — \(error.localizedDescription)")
                }
            }
        }
    }
}

// We need this struct for the school picker
// (`Components/SearchableSchoolPicker.swift`'s mileage variant takes it).
struct MileageSchoolItem: Identifiable, Hashable {
    let id: String
    let name: String
}
