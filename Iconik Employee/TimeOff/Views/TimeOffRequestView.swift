//  TimeOffRequestView.swift
//  Iconik Employee — create AND edit, one form, converted to Ambient in AMB.8
//
//  THE ONE REAL REDESIGN IN THIS PHASE IS THE PTO BLOCK. It used to be four
//  separate rows the user had to assemble in their head: a current balance
//  (omitted entirely when nil), a projected balance that turned orange when
//  insufficient, an hours field, and two inline validation messages. It is now one
//  block that states the sum — available now, this request, left afterwards.
//
//  EVERY DATE AND TIME RULE RUNS THROUGH `TimeOffRules.swift`, which is compiled
//  and RUN by scripts/test_timeoff_rules.sh. They were previously spread across
//  five `.onChange` handlers where they could only be verified by reading them:
//    - switching to partial forces end date = start date
//    - moving the start past the end drags the end with it
//    - an end time at or before the start is REPAIRED to start + 1 hour, not
//      rejected — a deliberate kindness on a phone form
//    - a partial day has a 30-minute minimum, and it is the ONLY thing that
//      disables Submit
//
//  TWO DELIBERATE OMISSIONS, both named rather than slipped past:
//
//  1. THE "SCHEDULE CONFLICTS" SECTION IS GONE. `TimeOffService.checkForConflicts`
//     declares an empty array, loops the date range doing nothing, and returns it —
//     so the header, the conflict rows and the line "Your manager will need to
//     reassign these sessions if your request is approved" could never render.
//     Drawing it would be mocking a feature that does not exist; BUILDING it is a
//     feature, not a restyle. Recorded in AUDIT_ROADMAP.md.
//
//  2. A PTO SHORTFALL STILL DOES NOT BLOCK SUBMISSION. The form says plainly that
//     you are short, then lets you submit — because that is what the app does
//     today, and changing it is a payroll change. `reservePTOHours` throws
//     "Insufficient PTO balance", `createTimeOffRequest` catches it and only
//     prints a warning, and the row is already inserted by then. The lab mockup
//     draws the blocked state and marks it PROPOSED for exactly this reason.
//     TOF.1 owns it.

import SwiftUI

struct TimeOffRequestView: View {
    @ObservedObject var timeOffService: TimeOffService
    @Environment(\.presentationMode) private var presentationMode

    let editingRequest: TimeOffRequest?

    // Form state
    @State private var isPartialDay = false
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var selectedReason = TimeOffReason.vacation
    @State private var notes = ""

    // PTO state
    @State private var isPaidTimeOff = true
    @State private var ptoHours = PTOHoursField()
    @State private var currentPTOBalance: PTOBalance?
    @State private var ptoSettings: PTOSettings?
    @State private var projectedPTOBalance = 0.0

    // UI state
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isSubmitting = false
    @State private var didSucceed = false
    @FocusState private var hoursFocused: Bool

    private let ptoService = PTOService.shared
    private var tint: Color { TimeOffStyle.requests }

    init(timeOffService: TimeOffService, editingRequest: TimeOffRequest? = nil) {
        self.timeOffService = timeOffService
        self.editingRequest = editingRequest

        guard let request = editingRequest else { return }
        _isPartialDay = State(initialValue: request.isPartialDay)
        _startDate = State(initialValue: request.startDate)
        _endDate = State(initialValue: request.endDate)
        _selectedReason = State(initialValue: request.reasonEnum)
        _notes = State(initialValue: request.notes ?? "")
        _isPaidTimeOff = State(initialValue: request.isPaidTimeOff)
        // Seeded as ALREADY user-edited: a saved request's hours are a decision
        // somebody made, and re-deriving them from the dates on open would quietly
        // overwrite a figure payroll may have agreed.
        _ptoHours = State(initialValue: PTOHoursField(value: request.ptoHoursRequested ?? 0,
                                                      isUserEdited: request.ptoHoursRequested != nil))

        // Times parse through TimeOfDay, which pins a POSIX locale. The old init
        // used a bare `DateFormatter` with dateFormat "HH:mm" and no locale, which
        // can return nil on a 12-hour device — and a nil there silently skipped
        // the seed, so an edited partial day reopened at the wrong time.
        if request.isPartialDay {
            if let parsed = request.startTime.flatMap(TimeOfDay.init),
               let seeded = Self.date(from: parsed) {
                _startTime = State(initialValue: seeded)
            }
            if let parsed = request.endTime.flatMap(TimeOfDay.init),
               let seeded = Self.date(from: parsed) {
                _endTime = State(initialValue: seeded)
            }
        }
    }

    // MARK: - Derived, all through the tested rule types

    private var span: TimeOffSpan {
        TimeOffSpan(startDay: startDate,
                    endDay: endDate,
                    isPartialDay: isPartialDay,
                    start: TimeOfDay(from: startTime),
                    end: TimeOfDay(from: endTime))
    }

    private var calculatedHours: Double { PTOMath.calculatedHours(for: span) ?? 0 }

    private var remaining: Double {
        PTOMath.remaining(available: currentPTOBalance?.availableBalance ?? 0,
                          requested: ptoHours.value)
    }

    private var standing: PTOStanding {
        PTOStanding.evaluate(availableNow: currentPTOBalance?.availableBalance ?? 0,
                             projectedByRequestDate: projectedPTOBalance,
                             requested: ptoHours.value)
    }

    private var submitGate: SubmitGate { SubmitGate.evaluate(span: span) }

    private var durationLabel: String {
        if isPartialDay {
            guard let hours = span.partialHours else { return "Time not set" }
            if hours == 1 { return "1 hour" }
            if hours.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(hours)) hours" }
            return String(format: "%.1f hours", hours)
        }
        return span.dayCount == 1 ? "1 day" : "\(span.dayCount) days"
    }

    private var dateRangeLabel: String {
        if isPartialDay || Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            return Formatters.mediumDate.string(from: startDate)
        }
        return "\(Formatters.mediumDate.string(from: startDate)) – \(Formatters.mediumDate.string(from: endDate))"
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: tint, intensity: 0.7)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        typeSection
                        datesSection
                        reasonSection
                        ptoSection
                        notesSection
                        summarySection
                        submitButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .ambientNoBounceWhenShort()
            }
            .navigationTitle(editingRequest != nil ? "Edit Request" : "Request Time Off")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hoursFocused = false }
                }
            }
            .alert("Time Off Request", isPresented: $showingAlert) {
                Button("OK", role: .cancel) {
                    // Dismiss on SUCCESS only. The old form tested
                    // `alertMessage.contains("successfully")` — a string match
                    // against a message that can also carry server error text.
                    if didSucceed { presentationMode.wrappedValue.dismiss() }
                }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                loadPTOData()
                updatePTOCalculations()
            }
        }
    }

    // MARK: - Type

    private var typeSection: some View {
        AmbientFormSection(title: "Type",
                           status: isPartialDay ? "Partial day" : "Full day",
                           statusTint: tint) {
            VStack(alignment: .leading, spacing: 8) {
                AmbientChoiceRow(title: "How long are you away?",
                                 options: ["Full Day", "Partial Day"],
                                 selection: Binding(
                                    get: { isPartialDay ? "Partial Day" : "Full Day" },
                                    set: { newValue in
                                        let partial = (newValue == "Partial Day")
                                        guard partial != isPartialDay else { return }
                                        withAnimation(AmbientMotion.snappy) {
                                            isPartialDay = partial
                                            // Switching to partial FORCES end = start.
                                            if partial { endDate = startDate }
                                        }
                                        updatePTOCalculations()
                                    }),
                                 tint: tint)
                if isPartialDay {
                    Text("A partial day is a single date. Minimum 30 minutes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Dates

    private var datesSection: some View {
        AmbientFormSection(title: isPartialDay ? "Date and time" : "Dates",
                           status: durationLabel,
                           statusTint: tint) {
            VStack(alignment: .leading, spacing: 0) {
                if isPartialDay {
                    datePickerRow("Date", $startDate, range: Date()...) { newValue in
                        endDate = newValue
                        updatePTOCalculations()
                    }
                    Divider()
                    timePickerRow("Start Time", $startTime)
                    Divider()
                    timePickerRow("End Time", $endTime)
                } else {
                    datePickerRow("Start Date", $startDate, range: Date()...) { newValue in
                        // Moving the start past the end drags the end with it.
                        if newValue > endDate { endDate = newValue }
                        updatePTOCalculations()
                    }
                    Divider()
                    datePickerRow("End Date", $endDate, range: startDate...) { _ in
                        updatePTOCalculations()
                    }
                }
                Divider()
                TimeOffDetailRow(label: "Duration", value: durationLabel, emphasised: true)

                if isPartialDay {
                    Text("If the end time lands before the start, it is corrected to start + 1 hour rather than rejected.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
            }
        }
    }

    private func datePickerRow(_ label: String,
                               _ value: Binding<Date>,
                               range: PartialRangeFrom<Date>,
                               onChange: @escaping (Date) -> Void) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            DatePicker("", selection: value, in: range, displayedComponents: .date)
                .labelsHidden()
                .onChange(of: value.wrappedValue) { newValue in onChange(newValue) }
        }
        .padding(.vertical, 5)
    }

    private func timePickerRow(_ label: String, _ value: Binding<Date>) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            DatePicker("", selection: value, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .onChange(of: value.wrappedValue) { _ in
                    repairTimes()
                    updatePTOCalculations()
                }
        }
        .padding(.vertical, 5)
    }

    // MARK: - Reason

    private var reasonSection: some View {
        AmbientFormSection(title: "Reason",
                           status: selectedReason.displayName,
                           statusTint: tint) {
            // Six reasons, each with its own icon and colour — the same identity
            // the card uses, so the choice made here is the mark seen on the list
            // afterwards. Everything visible; nothing behind a picker.
            AmbientFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(TimeOffReason.allReasons, id: \.self) { option in
                    let display = TimeOffReasonDisplay.from(raw: option.rawValue)
                    let on = selectedReason == option
                    Button {
                        withAnimation(AmbientMotion.snappy) { selectedReason = option }
                        AmbientHaptics.selection()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: display.symbol).font(.system(size: 11, weight: .semibold))
                            Text(option.displayName).font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(on ? .white : display.color)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        // ambient-allow: a selection chip is a control.
                        .background(Capsule().fill(on
                                                   ? AnyShapeStyle(display.color)
                                                   : AnyShapeStyle(display.color.opacity(0.13))))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - PTO

    private var ptoSection: some View {
        AmbientFormSection(title: "Paid time off",
                           status: isPaidTimeOff ? String(format: "%.1f hours", ptoHours.value) : "Unpaid",
                           statusTint: isPaidTimeOff ? tint : nil) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $isPaidTimeOff) {
                    Text("Use PTO Balance").font(.subheadline.weight(.semibold))
                }
                .tint(tint)

                if isPaidTimeOff {
                    Divider()
                    HStack {
                        Text("PTO Hours Requested").font(.subheadline)
                        Spacer(minLength: 8)
                        TextField("Hours", value: Binding(
                            get: { ptoHours.value },
                            set: { ptoHours.userTyped($0, calculated: calculatedHours) }
                        ), format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($hoursFocused)
                            .frame(width: 80)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                    Text("Filled from the dates. Type over it if payroll agreed something else.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    // The balance rows are OMITTED when the balance could not be
                    // loaded — as today. What is new is that the arithmetic is
                    // stated rather than left for the user to assemble.
                    if let balance = currentPTOBalance {
                        Divider()
                        VStack(spacing: 6) {
                            mathRow("Available now", balance.availableBalance, .secondary)
                            mathRow("This request", -ptoHours.value, .secondary)
                            Divider()
                            mathRow("Left afterwards", remaining,
                                    remaining < 0 ? .orange : .green, emphasised: true)
                        }
                    }
                }
            }
        }
    }

    private func mathRow(_ label: String, _ value: Double, _ rowTint: Color, emphasised: Bool = false) -> some View {
        HStack {
            Text(label).font(emphasised ? .subheadline.weight(.semibold) : .subheadline)
            Spacer(minLength: 8)
            Text("\(value >= 0 ? "" : "−")\(abs(value), specifier: "%.1f") h")
                .font(.system(size: emphasised ? 17 : 15,
                              weight: emphasised ? .bold : .medium,
                              design: .rounded))
                .foregroundStyle(rowTint)
                .contentTransition(.numericText())
        }
    }

    /// The two inline messages the old form had, driven by the tested
    /// `PTOStanding` rather than by two hand-written comparisons that disagreed
    /// about which balance they measured against.
    @ViewBuilder
    private var ptoMessage: some View {
        if isPaidTimeOff, currentPTOBalance != nil {
            switch standing {
            case .sufficient:
                EmptyView()
            case .coveredByFutureAccrual:
                TimeOffInlineNote(text: "This uses PTO you haven't accrued yet — you'll have enough by the request date.",
                                  icon: "clock.arrow.circlepath",
                                  tint: .blue)
            case .short(let by):
                TimeOffInlineNote(text: String(format: "You will not have sufficient PTO by the request date — you are %.1f hours short. Reduce the request, or turn off \"Use PTO Balance\" to request it unpaid.", by),
                                  icon: "exclamationmark.triangle.fill",
                                  tint: .orange)
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        AmbientFormSection(title: "Notes",
                           status: notes.isEmpty ? "optional" : "\(notes.count) characters",
                           statusTint: notes.isEmpty ? nil : tint) {
            TextEditor(text: $notes)
                .frame(minHeight: 80)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        AmbientFormSection(title: "Summary", status: "", statusTint: nil) {
            VStack(spacing: 0) {
                TimeOffDetailRow(label: "Type", value: isPartialDay ? "Partial Day" : "Full Day")
                Divider()
                TimeOffDetailRow(label: "Dates", value: dateRangeLabel)
                Divider()
                TimeOffDetailRow(label: "Duration", value: durationLabel)
                Divider()
                TimeOffDetailRow(label: "Reason", value: selectedReason.displayName)
            }
        }
    }

    // MARK: - Submit

    private var submitButton: some View {
        VStack(spacing: 8) {
            ptoMessage

            TimeOffPrimaryButton(
                title: isSubmitting
                    ? "Submitting…"
                    : (editingRequest != nil ? "Update Request" : "Submit Request"),
                tint: tint,
                enabled: submitGate.isAllowed && !isSubmitting) {
                    submitRequest()
                }

            // The real rule, said out loud: a full-day request is never blocked,
            // and the ONLY thing that disables Submit is the partial-day minimum.
            if isPartialDay && !submitGate.isAllowed {
                Text("A partial day must be at least 30 minutes.")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Rules applied to state

    /// end <= start becomes start + 1 hour, through `PartialDayRange`, so the
    /// repair the tests cover is the repair that actually runs.
    private func repairTimes() {
        guard let start = TimeOfDay(from: startTime), let end = TimeOfDay(from: endTime) else { return }
        let range = PartialDayRange(start: start, end: end)
        if range.end != end, let repaired = Self.date(from: range.end) {
            endTime = repaired
        }
    }

    // MARK: - Data

    private func loadPTOData() {
        guard let userId = UserManager.shared.getCurrentUserIDUnified(), !userId.isEmpty,
              let orgId = UserDefaults.standard.string(forKey: "userOrganizationID"), !orgId.isEmpty
        else { return }

        Task {
            do {
                let balance = try await ptoService.getPTOBalance(userId: userId, organizationID: orgId)
                let settings = try await ptoService.getPTOSettings(organizationID: orgId)
                await MainActor.run {
                    self.currentPTOBalance = balance
                    self.ptoSettings = settings
                    self.updatePTOCalculations()
                }
            } catch {
                // The balance rows are omitted when this fails, exactly as before.
                // Left as a print because surfacing it properly means deciding what
                // a form should DO about an unknown balance, and that is a
                // behaviour question this phase is not authorised to answer.
                print("Error loading PTO data: \(error.localizedDescription)")
            }
        }
    }

    private func updatePTOCalculations() {
        ptoHours.autoFill(calculated: calculatedHours)
        if let balance = currentPTOBalance, let settings = ptoSettings {
            projectedPTOBalance = ptoService.calculateProjectedBalance(
                currentBalance: balance,
                settings: settings,
                targetDate: startDate)
        }
    }

    private func submitRequest() {
        isSubmitting = true

        // Written through TimeOfDay.storageString, which is always "HH:mm". The old
        // form used a locale-less DateFormatter here — the same hazard on the
        // WRITE path, where it would store a string the reader cannot parse back.
        let startTimeString = isPartialDay ? TimeOfDay(from: startTime)?.storageString : nil
        let endTimeString = isPartialDay ? TimeOfDay(from: endTime)?.storageString : nil
        let hours = isPaidTimeOff ? ptoHours.value : nil
        let projected = isPaidTimeOff ? projectedPTOBalance : nil

        Task {
            do {
                if let editingRequest {
                    try await timeOffService.updateTimeOffRequest(
                        requestId: editingRequest.id,
                        startDate: startDate,
                        endDate: endDate,
                        reason: selectedReason,
                        notes: notes,
                        isPartialDay: isPartialDay,
                        startTime: startTimeString,
                        endTime: endTimeString,
                        isPaidTimeOff: isPaidTimeOff,
                        ptoHoursRequested: hours,
                        projectedPTOBalance: projected)
                    await MainActor.run {
                        didSucceed = true
                        alertMessage = "Time off request updated successfully!"
                    }
                } else {
                    try await timeOffService.createTimeOffRequest(
                        startDate: startDate,
                        endDate: endDate,
                        reason: selectedReason,
                        notes: notes,
                        isPartialDay: isPartialDay,
                        startTime: startTimeString,
                        endTime: endTimeString,
                        isPaidTimeOff: isPaidTimeOff,
                        ptoHoursRequested: hours,
                        projectedPTOBalance: projected)
                    await MainActor.run {
                        didSucceed = true
                        alertMessage = "Time off request submitted successfully!"
                    }
                }
            } catch {
                await MainActor.run {
                    didSucceed = false
                    alertMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isSubmitting = false
                showingAlert = true
            }
        }
    }

    // MARK: - Date <-> TimeOfDay

    private static func date(from time: TimeOfDay) -> Date? {
        Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date())
    }
}

extension TimeOfDay {
    /// A `DatePicker` speaks `Date`; the database and the rules speak `TimeOfDay`.
    init?(from date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        self.init(hour: hour, minute: minute)
    }
}
