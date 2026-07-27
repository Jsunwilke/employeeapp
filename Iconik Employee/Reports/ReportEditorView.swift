//  ReportEditorView.swift
//  Iconik Employee — editing a filed daily job report, converted in AMB.7
//
//  Replaces Misc Features/EditDailyJobReportView.swift, deleted in the same
//  commit.
//
//  A DELIBERATE DECISION, NAMED RATHER THAN SLIPPED IN
//      This screen was NOT among the batch-2 mockups the operator approved —
//      the mockup's list rows pushed nowhere, so the editor was never drawn. D10
//      is a hard gate on designing a surface the operator has not seen.
//
//      What it gets instead is the design the operator DID approve, applied to
//      the same fields: the same `ReportSection` chrome, the same
//      `ReportMultiSelect` for the same 22 and 12 options, the same
//      `ReportChoiceRow` for the same three scan questions, and the same
//      `ReportVehiclePicker`. Nothing here is invented — the alternative was a
//      raw `Form` of checkboxes sitting one push away from the converted create
//      screen, which is the "widget and the screen it opens are two different
//      design languages" problem this arc keeps writing down.
//
//      Structure the operator has not seen is deliberately NOT introduced: the
//      section order follows the fields this screen has always had, Update stays
//      at the bottom of the scroll where it has always been, and the trash stays
//      in the bar with its own wording.
//
//  TWO THINGS THAT CHANGE, BOTH ON PURPOSE
//      1. THE VEHICLE NOW TAKES THE TWO-STEP HERE TOO. The create form guards
//         this field with a confirmation because it sets mileage reimbursement;
//         the edit form guarded the same value with nothing. The record's stored
//         vehicle arrives already confirmed, so nothing is re-asked on open —
//         only a CHANGE takes the second tap.
//      2. UPDATE IS DISABLED UNTIL THE RECORD HAS LOADED. A failed load left
//         this form showing its defaults with no error, and pressing Update then
//         wrote those defaults over the real record (finding R11). A loading
//         state and a disabled button is the in-scope half of that.
//
//  AND ONE THAT DELIBERATELY DOES NOT
//      An edit still cannot CLEAR a field back to empty (finding R10): the
//      update path writes a column only when it is non-nil and this form turns
//      an emptied field into nil, so the old value survives in the shared
//      database. Fixing that means changing what the WRITE sends, which is a
//      data-layer change on a table the web app also reads — out of scope for a
//      design phase (D12). Recorded, unfixed, deliberately.

import SwiftUI

struct ReportEditorView: View {

    let reportID: String

    @Environment(\.dismiss) private var dismiss

    // Loaded record
    @State private var loaded: DailyJobReport?
    @State private var isLoading = true

    // Editable fields
    @State private var reportDate = Date()
    @State private var mileage = ReportMileage()
    @State private var vehicle = VehicleSelection()
    @State private var destination = ""
    @State private var jobNotes = ""
    @State private var photoshootNoteText = ""
    @State private var shot: Set<String> = []
    @State private var extras: Set<String> = []
    @State private var cardsScanned: String?
    @State private var jobBox: String?
    @State private var sportsBackground: String?
    @State private var photoURLs: [String] = []

    @State private var isSubmitting = false
    @State private var isDeleting = false
    @State private var showDeleteAlert = false
    @State private var failure = ""
    @State private var openPhotoURL: String?
    @FocusState private var fieldFocused: Bool

    private var feature: Color { FeatureTheme.color(for: "myDailyJobReports") }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature, intensity: 0.3)
            content
        }
        // Always pushed from the reports list, so it insets itself past the
        // floating tab bar — the shell's inset stops at the list.
        .tabBarClearance()
        .navigationTitle("Edit Job Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showDeleteAlert = true } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .disabled(isDeleting || isLoading)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldFocused = false }
            }
        }
        // This copy DIFFERS from the list screen's delete alert, and both are
        // kept verbatim rather than harmonised — that difference is recorded in
        // the parity inventory, not invented here.
        .alert("Delete Report", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { deleteReport() }
        } message: {
            Text("Are you sure you want to delete this report? This action cannot be undone.")
        }
        .sheet(item: $openPhotoURL) { url in
            PhotoDetailView(imageURL: url, label: "Photo")
        }
        .onAppear(perform: loadReport)
        .disabled(isDeleting)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading report…").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            form
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !failure.isEmpty { failureBanner }
                if isTemplateReport { templateBanner }
                detailsSection
                listSection(title: "What did you shoot?",
                            groups: ReportOptions.jobDescriptionGroups,
                            selection: $shot, tint: .orange)
                listSection(title: "Anything extra?",
                            groups: ReportOptions.extraItemGroups,
                            selection: $extras, tint: .pink)
                scanSection
                jobNotesSection
                photoshootNoteSection
                if isTemplateReport { templateFieldsSection }
                if !photoURLs.isEmpty { photosSection }
                updateButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .ambientNoBounceWhenShort()
    }

    // MARK: - Template reports

    /// A template report can be opened here — the list shows every report and
    /// always did. What it could not do before was SAY so, or show any of what
    /// the template actually captured.
    private var isTemplateReport: Bool {
        (loaded?.report_type ?? "standard") == "template"
    }

    private var templateBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text.below.ecg").font(.footnote).foregroundStyle(feature)
            VStack(alignment: .leading, spacing: 2) {
                Text(loaded?.template_name ?? "Template report")
                    .font(.subheadline.weight(.semibold))
                Text("This report was filed from a template. Its own answers are below and are read-only here — templates are authored in the web app.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .ambientCard(density: .compact, border: .hairline(feature.opacity(0.4)), fillWidth: true)
    }

    /// The template's captured answers, rendered generically as key/value rows.
    ///
    /// This capability existed ONLY in TemplateReportListView — 558 lines,
    /// compiled, shipped and unreachable. The inventory said to build it
    /// somewhere real or drop it knowingly; this is somewhere real.
    private var templateFieldsSection: some View {
        let entries = (loaded?.form_data ?? [:])
            .filter { !Self.hiddenFormKeys.contains($0.key) }
            .map { ($0.key, Self.describe($0.value)) }
            .filter { !$0.1.isEmpty }
            .sorted { $0.0 < $1.0 }
        return ReportSection(title: "Template answers",
                             status: "\(entries.count)",
                             statusTint: entries.isEmpty ? nil : feature) {
            if entries.isEmpty {
                Text("This report stored no template answers.")
                    .font(.subheadline).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(entries, id: \.0) { key, value in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(value)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// Plumbing the photographer did not type, so it is not shown back to them.
    private static let hiddenFormKeys: Set<String> = ["session_id", "session_name", "photoURLs"]

    private static func describe(_ value: AnyCodable) -> String {
        switch value.value {
        case let text as String: return text
        case let flag as Bool: return flag ? "Yes" : "No"
        case let number as Int: return "\(number)"
        case let number as Double: return String(format: "%g", number)
        case let list as [Any]: return list.map { "\($0)" }.joined(separator: ", ")
        default: return ""
        }
    }

    // MARK: - Sections

    private var detailsSection: some View {
        ReportSection(title: "Report details",
                      status: vehicle.confirmed == nil
                        ? String(format: "%.1f mi", mileage.value)
                        : String(format: "%.1f mi · %@", mileage.value, vehicle.confirmed!.rawValue.capitalized),
                      statusTint: feature) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Date").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    DatePicker("", selection: $reportDate, displayedComponents: .date)
                        .labelsHidden()
                }

                Divider()

                HStack(spacing: 10) {
                    Text("Total").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    TextField("0.0", text: Binding(get: { mileage.displayText },
                                                   set: { mileage.type($0) }))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .frame(width: 84)
                        .focused($fieldFocused)
                    Text("miles").font(.subheadline).foregroundStyle(.secondary)
                }

                Divider()

                ReportVehiclePicker(selection: $vehicle, tint: feature)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("School / destination")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("School or destination", text: $destination)
                        .font(.subheadline)
                        .focused($fieldFocused)
                }
            }
        }
    }

    private func listSection(title: String, groups: [(String, [String])],
                             selection: Binding<Set<String>>, tint: Color) -> some View {
        ReportSection(title: title,
                      status: selection.wrappedValue.isEmpty
                        ? "select all that apply"
                        : "\(selection.wrappedValue.count) selected",
                      statusTint: selection.wrappedValue.isEmpty ? nil : tint) {
            ReportMultiSelect(groups: groups, selection: selection, tint: tint)
        }
    }

    private var scanSection: some View {
        let answered = [cardsScanned, jobBox, sportsBackground].compactMap { $0 }.count
        return ReportSection(title: "Cards and job box",
                             status: "\(answered) of 3 answered",
                             statusTint: answered == 3 ? .teal : nil) {
            VStack(alignment: .leading, spacing: 14) {
                ReportChoiceRow(title: "Cards scanned",
                                options: ReportOptions.yesNo, selection: $cardsScanned)
                ReportChoiceRow(title: "Job box and camera cards turned in",
                                options: ReportOptions.yesNoNA, selection: $jobBox)
                ReportChoiceRow(title: "Sports background shot",
                                options: ReportOptions.yesNoNA, selection: $sportsBackground)
            }
        }
    }

    private var jobNotesSection: some View {
        ReportSection(title: "Job notes",
                      status: jobNotes.isEmpty ? "nothing written" : "\(jobNotes.count) characters",
                      statusTint: jobNotes.isEmpty ? nil : feature) {
            TextEditor(text: $jobNotes)
                .frame(minHeight: 88)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .focused($fieldFocused)
        }
    }

    private var photoshootNoteSection: some View {
        ReportSection(title: "Photoshoot note info",
                      status: photoshootNoteText.isEmpty ? "nothing written" : "\(photoshootNoteText.count) characters",
                      statusTint: photoshootNoteText.isEmpty ? nil : feature) {
            TextEditor(text: $photoshootNoteText)
                .frame(minHeight: 88)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .focused($fieldFocused)
        }
    }

    /// VIEW-ONLY, exactly as before — this screen can neither add, delete nor
    /// reorder a report's photos. Each opens a detail sheet.
    private var photosSection: some View {
        ReportSection(title: "Attached photos",
                      status: "\(photoURLs.count)",
                      statusTint: feature) {
            // The grid is built here rather than through `StoragePhotoGallery`,
            // which draws its OWN "Photos (N)" headline and its own horizontal
            // padding — both doubled inside a section that already has a title
            // and a count. Tapping still opens the same detail view.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                      spacing: 8) {
                ForEach(photoURLs, id: \.self) { url in
                    StorageImageView(imageURL: url, width: nil, height: 100, contentMode: .fill)
                        .contentShape(Rectangle())
                        .onTapGesture { openPhotoURL = url }
                }
            }
        }
    }

    private var updateButton: some View {
        VStack(spacing: 8) {
            Button(action: submitUpdate) {
                HStack(spacing: 8) {
                    if isSubmitting { ProgressView().tint(.white).scaleEffect(0.8) }
                    Text(isSubmitting ? "Updating…" : "Update Report")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                // ambient-allow: a filled primary action is a control, not a card.
                .background(Capsule().fill(loaded == nil ? Color.gray : feature))
            }
            .buttonStyle(.plain)
            // The record must have loaded before this can overwrite it.
            .disabled(isSubmitting || loaded == nil)

            Text("An emptied field keeps its previous value — clearing one is not yet possible.")
                .font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }

    private var failureBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(.orange)
            Text(failure)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .ambientCard(density: .compact,
                     border: .hairline(Color.orange.opacity(0.45)),
                     fillWidth: true)
    }

    // MARK: - Data

    private func loadReport() {
        guard loaded == nil else { return }
        isLoading = true
        Task {
            do {
                let report = try await DailyJobReportService.shared.getReport(reportId: reportID)
                await MainActor.run {
                    guard let report else {
                        isLoading = false
                        failure = "That report could not be found."
                        return
                    }
                    apply(report)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    failure = "That report could not be loaded: \(error.localizedDescription)"
                }
            }
        }
    }

    private func apply(_ report: DailyJobReport) {
        loaded = report
        reportDate = report.date
        mileage = ReportMileage(calculated: report.total_mileage)
        // The stored vehicle arrives already CONFIRMED, so opening the screen
        // asks nothing — only changing it takes the second tap.
        vehicle = VehicleSelection(confirmed: VehicleSelection.Vehicle(rawValue: report.vehicle_type ?? "personal"))
        destination = report.school_or_destination ?? ""
        jobNotes = report.job_description_text ?? ""
        photoshootNoteText = report.photoshoot_note_text ?? ""
        shot = Set(report.job_descriptions ?? [])
        extras = Set(report.extra_items ?? [])
        // Unanswered stays unanswered. The old form defaulted these to "Yes" /
        // "NA" / "NA" on load, so opening a report that had never answered them
        // and pressing Update INVENTED three answers.
        cardsScanned = report.cards_scanned_choice
        jobBox = report.job_box_and_camera_cards
        sportsBackground = report.sports_background_shot
        photoURLs = report.photo_urls ?? []
    }

    private func submitUpdate() {
        guard let original = loaded else { return }
        guard let currentUserID = UserManager.shared.getCurrentUserIDUnified() else {
            failure = "User not signed in."
            return
        }
        isSubmitting = true
        failure = ""

        let updated = DailyJobReport(
            id: original.id,
            organizationID: original.organization_id,
            userId: currentUserID,
            date: reportDate,
            // Carried forward from the RECORD, not from the signed-in user's
            // stored first name. The old form rewrote this column from
            // AppStorage on every update — and it is the column the manager
            // drill-down queries by, so rewriting it could hide a report.
            yourName: original.your_name,
            schoolOrDestination: destination.isEmpty ? nil : destination,
            sessionId: original.session_id,
            sessionName: original.session_name,
            totalMileage: mileage.value,
            vehicleType: vehicle.confirmed?.rawValue ?? original.vehicle_type ?? "personal",
            jobDescriptions: shot.isEmpty ? nil : Array(shot),
            extraItems: extras.isEmpty ? nil : Array(extras),
            cardsScannedChoice: cardsScanned,
            jobBoxAndCameraCards: jobBox,
            sportsBackgroundShot: sportsBackground,
            jobDescriptionText: jobNotes.isEmpty ? nil : jobNotes,
            photoshootNoteText: photoshootNoteText.isEmpty ? nil : photoshootNoteText,
            photoURLs: photoURLs.isEmpty ? nil : photoURLs,
            // EVERY template column is carried forward from the record. The old
            // editor passed none of them, and `reportType` is non-optional with
            // a default of "standard" — so pressing Update on a template report
            // silently RECLASSIFIED it on the shared table, leaving its
            // template_id and form_data orphaned behind a standard label.
            templateId: original.template_id,
            templateName: original.template_name,
            templateVersion: original.template_version,
            reportType: original.report_type ?? "standard",
            smartFieldsUsed: original.smart_fields_used,
            formData: original.form_data)

        Task {
            do {
                try await DailyJobReportService.shared.updateReport(updated)
                await MainActor.run {
                    isSubmitting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    failure = "That report could not be saved: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteReport() {
        isDeleting = true
        Task {
            do {
                try await DailyJobReportService.shared.deleteReport(reportId: reportID)
                await MainActor.run {
                    isDeleting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    // A failed delete used to print to the console and leave the
                    // screen exactly as it was.
                    failure = "That report could not be deleted: \(error.localizedDescription)"
                }
            }
        }
    }
}
