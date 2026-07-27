//  TemplateReportView.swift
//  Iconik Employee — the dynamic template form, converted in AMB.7
//
//  Replaces Misc Features/TemplateFormView.swift, deleted in the same commit.
//
//  IT IS A PUSHED SCREEN NOW, NOT A SHEET WITH A PAINTED-ON NAV BAR
//      The live version was presented as a sheet, owned no navigation container,
//      and drew a blue gradient strip with a fake "Back" chevron to stand in for
//      one — while swipe-to-dismiss stayed enabled behind it, so a filled form
//      could be thrown away by a gesture the fake bar knew nothing about. Here
//      it is a real push with a real bar, and Submit sits where it sits on the
//      standard report.
//
//  THE ONE THING THIS DESIGN ADDS: WHY SUBMIT IS DISABLED
//      The live form disabled Submit whenever any field failed validation and
//      said NOTHING — no per-field error, no message, a button greyed to 60%.
//      With required fields scattered across four auto-generated sections, a
//      photographer could be left tapping a dead button with no way to find out
//      which field was the problem. The strip above the fields names them.
//
//  FOUR PERMANENT BLOCKS, FIXED IN THE VIEW RATHER THAN IN THE SERVICE
//      Each of these made a whole template permanently unsubmittable, so the
//      strip above would otherwise have listed a field the photographer cannot
//      possibly satisfy. All four are fixed HERE — `TemplateService` is
//      untouched, and its `validateField` has no other caller in the app.
//
//      R15  An untouched OPTIONAL number field failed validation, because the
//           number case asks "is this a Double, Int or String" and nil is none
//           of them — regardless of whether the field was required at all.
//      R14  A required FILE field could never be satisfied: photos were written
//           to a view-level array and never to the field's own key.
//      R32  multiselect and radio ignored `readOnly` — they showed the AUTO pill
//           and still took taps.
//      R31  A field with both a basic type and a smart config rendered TWICE, in
//           two different sections, because the four buckets overlapped.
//
//      And read-only fields no longer block submission at all. The live rule
//      blocked on them, which is not a rule so much as a dead end: a field the
//      photographer cannot edit cannot be the thing they fix.
//
//  RECORDED, NOT FIXED — these need the data layer and are not this phase's
//      R16  `weather_conditions` and `current_location` are permanent
//           placeholders, and those placeholder STRINGS are what get saved.
//      R17  This form has no school picker, so its `school_name` smart field
//           always renders its fallback and its mileage always renders 0.0.
//      R22  This form's mileage smart field measures straight-line distance
//           while the standard report drives a real route — and both write the
//           same `total_mileage` column.
//      R26  Template reports store "First Last" where the manager drill-down
//           queries by first name, so they never appear in it.
//      R30  Non-primitive `form_data` values are persisted as null.

import SwiftUI

struct TemplateReportView: View {

    let template: ReportTemplate

    @Environment(\.dismiss) private var dismiss
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""

    @StateObject private var templateService = TemplateService.shared
    @State private var formData: [String: Any] = [:]
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var tempImage: UIImage?

    @StateObject private var schedule = ReportSchedule()
    @State private var sessionPick = SessionAutoSelect()

    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var failure = ""
    @FocusState private var fieldFocused: Bool

    private var feature: Color { FeatureTheme.color(for: "customDailyReports") }

    // MARK: - Sections
    //
    // Auto-derived from field TYPE, and rendered ALPHABETICALLY — which is why
    // "Basic Information" precedes "Report Details" by accident rather than by
    // design. Kept as it shipped so the operator can see it and decide.
    //
    // The buckets are MUTUALLY EXCLUSIVE now: each field is claimed by exactly
    // one, in precedence order. They used to overlap, so a field that was both
    // basic and smart appeared in two sections at once.

    private var sections: [(String, [TemplateField])] {
        var claimed = Set<String>()
        func take(_ predicate: (TemplateField) -> Bool) -> [TemplateField] {
            let picked = template.fields.filter { !claimed.contains($0.id) && predicate($0) }
            claimed.formUnion(picked.map(\.id))
            return picked
        }

        let basic = take { field in
            ["date_auto", "time_auto", "user_name"].contains(field.type)
                || ["photographer", "date", "time"].contains(field.id.lowercased())
        }
        let media = take { ["file", "location"].contains($0.type) }
        let smart = take { $0.smartConfig != nil }
        let data = take { _ in true }

        var built: [(String, [TemplateField])] = []
        if !basic.isEmpty { built.append(("Basic Information", basic)) }
        if !data.isEmpty { built.append(("Report Details", data)) }
        if !smart.isEmpty { built.append(("Calculated Fields", smart)) }
        if !media.isEmpty { built.append(("Media & Location", media)) }
        return built.sorted { $0.0 < $1.0 }
    }

    // MARK: - Validation

    /// A field that stands between the photographer and Submit.
    ///
    /// Read-only fields are excluded: they cannot be edited, so listing one as
    /// "still needed" tells someone to do something impossible.
    private var blocking: [TemplateField] {
        template.fields.filter { !isValid($0) }
    }

    private func isValid(_ field: TemplateField) -> Bool {
        if field.readOnly == true { return true }
        let value = formData[field.id]
        // An untouched optional field is fine, whatever its type. Asking the
        // service about it is what made an optional number block forever.
        if !field.required, value == nil { return true }
        return templateService.validateField(field, value: value)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature, intensity: 0.7)
            content
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: submit) {
                    if isSubmitting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("Submit").font(.body.weight(.semibold))
                    }
                }
                .disabled(isSubmitting || !blocking.isEmpty)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldFocused = false }
            }
        }
        .onAppear(perform: load)
        .onDisappear { schedule.stop() }
        .alert("Report Submitted", isPresented: $showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your daily report has been submitted successfully.")
        }
        .alert("Error", isPresented: Binding(
            get: { !failure.isEmpty },
            set: { if !$0 { failure = "" } }
        )) {
            Button("OK", role: .cancel) { failure = "" }
        } message: {
            Text(failure)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $tempImage)
                .onDisappear {
                    if let image = tempImage {
                        selectedImages.append(image)
                        tempImage = nil
                        syncPhotoFields()
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if template.fields.isEmpty {
            VStack(spacing: 12) {
                AmbientEmptyState(
                    title: "No Fields Available",
                    message: "This template doesn't contain any fields to display.",
                    systemImage: "doc.text",
                    actionTitle: "Go Back",
                    actionIcon: "chevron.left",
                    action: { dismiss() },
                    actionTint: feature)
            }
            .padding(.horizontal, 16)
        } else {
            form
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                blockingStrip
                ReportSessionPicker(schedule: schedule, pick: $sessionPick, tint: feature)
                ForEach(sections, id: \.0) { name, fields in
                    VStack(alignment: .leading, spacing: 8) {
                        AmbientSectionTitle(name, trailing: "\(fields.count)")
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(fields) { field in
                                fieldRow(field)
                            }
                        }
                        .ambientCard(density: .roomy, fill: .surface,
                                     border: .hairline(Color.primary.opacity(0.10)),
                                     fillWidth: true)
                    }
                }
                footerNote
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .ambientNoBounceWhenShort()
    }

    private var header: some View {
        let automatic = template.fields.filter { $0.readOnly == true }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(template.fields.count) field\(template.fields.count == 1 ? "" : "s") · \(automatic) automatic")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("v\(template.version)").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            Text("Every required field has to be filled in before this form will submit. The automatic ones fill themselves in and never hold it up.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    /// The state that should exist and did not.
    @ViewBuilder
    private var blockingStrip: some View {
        if blocking.isEmpty {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Ready to submit").font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                Spacer(minLength: 0)
            }
            .ambientCard(density: .compact, fillWidth: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text("\(blocking.count) field\(blocking.count == 1 ? "" : "s") still needed")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.orange)
                AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(blocking) { field in
                        AmbientBadge(text: field.label, tint: .orange)
                    }
                }
            }
            .ambientCard(density: .compact,
                         border: .hairline(Color.orange.opacity(0.4)), fillWidth: true)
        }
    }

    private var footerNote: some View {
        Text("Leaving this screen discards everything typed — there is no draft.")
            .font(.caption2).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
    }

    // MARK: - Fields

    private func fieldRow(_ field: TemplateField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(field.label).font(.subheadline.weight(.medium))
                if field.required && field.readOnly != true {
                    Text("*").font(.subheadline.weight(.bold)).foregroundStyle(.red)
                }
                if field.readOnly == true { AmbientBadge(text: "Auto", tint: .blue) }
                Spacer(minLength: 0)
            }
            control(field)
        }
    }

    @ViewBuilder
    private func control(_ field: TemplateField) -> some View {
        let readOnly = field.readOnly == true

        switch field.type {
        case "mileage", "date_auto", "time_auto", "user_name", "school_name",
             "photo_count", "weather_conditions", "current_location":
            readOnlyWell(templateService.calculateSmartField(field, formData: formData))

        case "textarea":
            TextEditor(text: text(field))
                .frame(minHeight: 74)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .focused($fieldFocused)
                .padding(8)
                // ambient-allow: an input well, not a card.
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1)))
                .disabled(readOnly)

        case "number", "currency":
            TextField(field.placeholder ?? (field.type == "currency" ? "0.00" : "0"), text: number(field))
                .keyboardType(.decimalPad)
                .font(.subheadline)
                .focused($fieldFocused)
                .padding(.horizontal, 10).padding(.vertical, 9)
                // ambient-allow: an input well, not a card.
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1)))
                .disabled(readOnly)

        case "select":
            Picker("", selection: text(field)) {
                // A blank first row, so a choice can be un-made.
                Text("Select \(field.label.lowercased())").tag("")
                ForEach(field.options ?? [], id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(readOnly)

        case "multiselect":
            VStack(alignment: .leading, spacing: 6) {
                ForEach(field.options ?? [], id: \.self) { option in
                    multiRow(option, field: field, disabled: readOnly)
                }
            }

        case "radio":
            // A vertical list of full-width buttons, not a segmented control,
            // and it cannot be deselected once picked — both as shipped.
            VStack(spacing: 6) {
                ForEach(field.options ?? [], id: \.self) { option in
                    let on = (formData[field.id] as? String) == option
                    Button {
                        guard !readOnly else { return }
                        withAnimation(AmbientMotion.snappy) { formData[field.id] = option }
                        AmbientHaptics.selection()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: on ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(on ? AnyShapeStyle(feature) : AnyShapeStyle(.secondary))
                            Text(option).font(.subheadline)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(readOnly)
                }
            }

        case "toggle":
            Toggle("", isOn: Binding(
                get: { formData[field.id] as? Bool ?? false },
                set: { formData[field.id] = $0 }))
                .labelsHidden()
                .tint(feature)
                .disabled(readOnly)

        case "date":
            // Written as a full date and read with a formatter that can parse
            // one. The live pair could not agree, so the picker snapped back to
            // today after every selection while the STORED value was correct.
            DatePicker("", selection: Binding(
                get: {
                    (formData[field.id] as? String).flatMap { Formatters.isoDate.date(from: $0) } ?? Date()
                },
                set: { formData[field.id] = Formatters.isoDate.string(from: $0) }),
                displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(readOnly)

        case "time":
            DatePicker("", selection: Binding(
                get: {
                    (formData[field.id] as? String).flatMap { Formatters.shortTime.date(from: $0) } ?? Date()
                },
                set: { formData[field.id] = Formatters.shortTime.string(from: $0) }),
                displayedComponents: .hourAndMinute)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(readOnly)

        case "file":
            filePicker

        default:
            // An UNKNOWN type falls through to a plain text field, which is how
            // "location" renders today.
            TextField(field.placeholder ?? "Enter \(field.label.lowercased())", text: text(field))
                .font(.subheadline)
                .focused($fieldFocused)
                .padding(.horizontal, 10).padding(.vertical, 9)
                // ambient-allow: an input well, not a card.
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1)))
                .disabled(readOnly)
        }
    }

    private var filePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, minHeight: 78, maxHeight: 78)
                        // ambient-allow: a photo thumbnail is content, not a card.
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(AmbientMotion.snappy) {
                                    guard selectedImages.indices.contains(index) else { return }
                                    selectedImages.remove(at: index)
                                }
                                syncPhotoFields()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.white, .black.opacity(0.55))
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove photo \(index + 1)")
                        }
                }
                Button { showImagePicker = true } label: {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.4),
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(height: 78)
                        .overlay(Image(systemName: "plus").foregroundStyle(.secondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add photo")
            }
            Text("\(selectedImages.count) photo\(selectedImages.count == 1 ? "" : "s") selected — photos are shared across every file field on a template.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func multiRow(_ option: String, field: TemplateField, disabled: Bool) -> some View {
        let selected = formData[field.id] as? [String] ?? []
        let on = selected.contains(option)
        return Button {
            guard !disabled else { return }
            var next = selected
            if on { next.removeAll { $0 == option } } else { next.append(option) }
            withAnimation(AmbientMotion.snappy) { formData[field.id] = next }
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(on ? AnyShapeStyle(feature) : AnyShapeStyle(.secondary))
                Text(option).font(.subheadline)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func readOnlyWell(_ value: String) -> some View {
        Text(value)
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 9)
            // ambient-allow: a read-only input well, not a card.
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1)))
    }

    // MARK: - Bindings

    private func text(_ field: TemplateField) -> Binding<String> {
        Binding(
            get: { formData[field.id] as? String ?? field.defaultValue ?? "" },
            set: { formData[field.id] = $0 })
    }

    /// A number field stores whatever was typed. The live version tried to store
    /// a Double when the text parsed and a String when it did not, which meant a
    /// half-typed "12." changed the stored TYPE between keystrokes.
    private func number(_ field: TemplateField) -> Binding<String> {
        Binding(
            get: {
                if let value = formData[field.id] as? Double { return String(value) }
                return formData[field.id] as? String ?? field.defaultValue ?? ""
            },
            set: { formData[field.id] = $0 })
    }

    // MARK: - Data

    private func load() {
        for field in template.fields {
            if field.smartConfig != nil {
                formData[field.id] = templateService.calculateSmartField(field, formData: formData)
            } else if let defaultValue = field.defaultValue {
                formData[field.id] = defaultValue
            }
        }
        syncPhotoFields()
        schedule.start(for: Date(), onChange: runAutoSelect)
        Task {
            await schedule.refreshReported(
                photographerFirstName: UserDefaults.standard.string(forKey: "userFirstName") ?? "",
                organizationID: storedUserOrganizationID)
            await MainActor.run { runAutoSelect() }
        }
    }

    private func runAutoSelect() {
        guard !sessionPick.isLatched,
              sessionPick.ranFor != schedule.dateKey,
              !schedule.isLoadingSessions,
              schedule.hasCheckedReported else { return }
        sessionPick.run(for: schedule.dateKey, sessions: schedule.autoSelectCandidates)
    }

    /// Photo count belongs to the fields that ask for it — the smart
    /// `photo_count` type, and every `file` field's own key, which is what a
    /// required file field validates against.
    private func syncPhotoFields() {
        for field in template.fields {
            if field.smartConfig?.calculationType == "photo_count" || field.type == "file" {
                formData[field.id] = "\(selectedImages.count)"
            }
        }
    }

    // MARK: - Submitting

    private func submit() {
        guard let userID = UserManager.shared.getCurrentUserIDUnified() else {
            failure = "User not signed in."
            return
        }
        isSubmitting = true
        failure = ""

        var payload = formData
        let session = sessionPick.selection.flatMap { id in schedule.sessions.first { $0.id == id } }
        if let session {
            payload["session_id"] = session.id
            payload["session_name"] = session.reportDisplayLabel
        }
        let images = selectedImages

        Task {
            var failedUploads = 0
            if !images.isEmpty {
                let result = await ReportPhotoUpload.upload(
                    images,
                    folder: "template-reports/\(userID.lowercased())",
                    maxDimension: 2048)
                payload["photoURLs"] = result.urls
                failedUploads = result.failed
                if result.urls.isEmpty && result.failed == images.count {
                    // Every photo failed. The live version orphaned whatever had
                    // already uploaded and filed no report at all; this files the
                    // report and says what is missing.
                    print("❌ TemplateReportView: all \(images.count) photo(s) failed to upload")
                }
            }

            do {
                _ = try await templateService.submitTemplateReport(template: template, formData: payload)
                await MainActor.run {
                    isSubmitting = false
                    if failedUploads > 0 {
                        failure = "Report submitted, but \(failedUploads) photo\(failedUploads == 1 ? "" : "s") could not be uploaded and \(failedUploads == 1 ? "is" : "are") not attached to it."
                    } else {
                        showSuccess = true
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    failure = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Session picker

/// Linking a report to a scheduled session, shared by the template form.
///
/// The standard report draws its own because the session ALSO owns the school
/// there; here the link is the whole of it.
struct ReportSessionPicker: View {
    @ObservedObject var schedule: ReportSchedule
    @Binding var pick: SessionAutoSelect
    let tint: Color

    var body: some View {
        // Only when the photographer actually has sessions today, as before.
        Group {
            if !schedule.sessions.isEmpty {
                ReportSection(title: "Session",
                              status: pick.selection == nil ? "off-schedule" : "linked",
                              statusTint: pick.selection == nil ? nil : tint) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(schedule.sessions) { session in
                            row(session.id, session.reportDisplayLabel,
                                reported: schedule.reportedSessionIDs.contains(session.id))
                        }
                        row(nil, "No scheduled session (off-schedule)", reported: false)
                    }
                }
            }
        }
    }

    private func row(_ id: String?, _ label: String, reported: Bool) -> some View {
        let on = pick.selection == id
        return Button {
            withAnimation(AmbientMotion.snappy) { pick.pick(id) }
            AmbientHaptics.selection()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
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
}
