import SwiftUI
import FirebaseAuth

struct TimeOffRequestView: View {
    @ObservedObject var timeOffService: TimeOffService
    @Environment(\.presentationMode) var presentationMode
    
    // Form state
    @State private var isPartialDay = false
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var selectedReason = TimeOffReason.vacation
    @State private var notes = ""
    
    // Partial day specific
    @State private var startTime = Date()
    @State private var endTime = Date()
    
    // PTO state
    @State private var isPaidTimeOff = true
    @State private var ptoHoursRequested = 0.0
    @State private var currentPTOBalance: PTOBalance?
    @State private var projectedPTOBalance = 0.0
    @State private var ptoSettings: PTOSettings?
    
    // UI state
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isSubmitting = false
    @State private var conflicts: [String] = []
    
    // PTO Service
    private let ptoService = PTOService.shared
    
    // Editing mode
    let editingRequest: TimeOffRequest?
    
    // Date formatters
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    private var timeStringFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }
    
    private var shortDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }
    
    init(timeOffService: TimeOffService, editingRequest: TimeOffRequest? = nil) {
        self.timeOffService = timeOffService
        self.editingRequest = editingRequest
        
        // Initialize form with existing data if editing
        if let request = editingRequest {
            _isPartialDay = State(initialValue: request.isPartialDay)
            _startDate = State(initialValue: request.startDate)
            _endDate = State(initialValue: request.endDate)
            _selectedReason = State(initialValue: request.reason)
            _notes = State(initialValue: request.notes)
            _isPaidTimeOff = State(initialValue: request.isPaidTimeOff)
            _ptoHoursRequested = State(initialValue: request.ptoHoursRequested ?? 0)
            
            // Set times for partial day
            if request.isPartialDay,
               let startTimeString = request.startTime,
               let endTimeString = request.endTime {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                
                if let startTime = formatter.date(from: startTimeString) {
                    _startTime = State(initialValue: startTime)
                }
                if let endTime = formatter.date(from: endTimeString) {
                    _endTime = State(initialValue: endTime)
                }
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Type Selection Section
                Section(header: Text("Request Type")) {
                    Picker("Type", selection: $isPartialDay) {
                        Text("Full Day").tag(false)
                        Text("Partial Day").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: isPartialDay) { newValue in
                        if newValue {
                            // Switch to partial day - set same date
                            endDate = startDate
                        }
                        checkForConflicts()
                    }
                }
                
                // Date Selection Section
                Section(header: Text(isPartialDay ? "Date" : "Dates")) {
                    if isPartialDay {
                        // Partial day - single date
                        DatePicker("Date", selection: $startDate, in: Date()..., displayedComponents: .date)
                            .onChange(of: startDate) { newValue in
                                endDate = newValue
                                checkForConflicts()
                            }
                    } else {
                        // Full day - date range
                        DatePicker("Start Date", selection: $startDate, in: Date()..., displayedComponents: .date)
                            .onChange(of: startDate) { newValue in
                                if newValue > endDate {
                                    endDate = newValue
                                }
                                checkForConflicts()
                            }
                        
                        DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: .date)
                            .onChange(of: endDate) { _ in
                                checkForConflicts()
                            }
                    }
                }
                
                // Time Selection Section (only for partial days)
                if isPartialDay {
                    Section(header: Text("Time Range")) {
                        DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                            .onChange(of: startTime) { _ in
                                validateTimes()
                                checkForConflicts()
                            }
                        
                        DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                            .onChange(of: endTime) { _ in
                                validateTimes()
                                checkForConflicts()
                            }
                        
                        // Show duration
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(formattedDuration)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Reason Selection Section
                Section(header: Text("Reason")) {
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(TimeOffReason.allCases, id: \.self) { reason in
                            HStack {
                                Image(systemName: reason.systemImageName)
                                    .foregroundColor(Color(reason.colorName))
                                Text(reason.displayName)
                            }.tag(reason)
                        }
                    }
                }
                
                // Notes Section
                Section(header: Text("Notes (Optional)")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
                
                // PTO Section
                Section(header: Text("Paid Time Off")) {
                    Toggle("Use PTO Balance", isOn: $isPaidTimeOff)
                        .onChange(of: isPaidTimeOff) { _ in
                            updatePTOCalculations()
                        }
                    
                    if isPaidTimeOff {
                        // Current balance
                        if let balance = currentPTOBalance {
                            HStack {
                                Text("Current Balance:")
                                Spacer()
                                Text(ptoService.formatPTOHours(balance.availableBalance))
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Projected balance
                        HStack {
                            Text("Projected Balance by \(startDate, formatter: shortDateFormatter):")
                            Spacer()
                            Text(ptoService.formatPTOHours(projectedPTOBalance))
                                .fontWeight(.medium)
                                .foregroundColor(projectedPTOBalance >= ptoHoursRequested ? .green : .orange)
                        }
                        
                        // PTO hours input
                        HStack {
                            Text("PTO Hours Requested:")
                            Spacer()
                            TextField("Hours", value: $ptoHoursRequested, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        // Validation message
                        if ptoHoursRequested > projectedPTOBalance {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("You will not have sufficient PTO by the request date")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        } else if ptoHoursRequested > 0 && projectedPTOBalance > currentPTOBalance?.availableBalance ?? 0 {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                Text("This uses future PTO accrual")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                
                // Conflicts Section (if any)
                if !conflicts.isEmpty {
                    Section(header: 
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Schedule Conflicts")
                        }
                    ) {
                        ForEach(conflicts, id: \.self) { conflict in
                            Text(conflict)
                                .foregroundColor(.orange)
                        }
                        
                        Text("Your manager will need to reassign these sessions if your request is approved.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Summary Section
                Section(header: Text("Summary")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Type:")
                            Spacer()
                            Text(isPartialDay ? "Partial Day" : "Full Day")
                                .fontWeight(.medium)
                        }
                        
                        HStack {
                            Text("Dates:")
                            Spacer()
                            Text(formattedDateRange)
                                .fontWeight(.medium)
                        }
                        
                        HStack {
                            Text("Duration:")
                            Spacer()
                            Text(formattedDuration)
                                .fontWeight(.medium)
                        }
                        
                        HStack {
                            Text("Reason:")
                            Spacer()
                            HStack {
                                Image(systemName: selectedReason.systemImageName)
                                    .foregroundColor(Color(selectedReason.colorName))
                                Text(selectedReason.displayName)
                            }
                            .fontWeight(.medium)
                        }
                    }
                }
            }
            .navigationTitle(editingRequest != nil ? "Edit Request" : "Request Time Off")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button(editingRequest != nil ? "Update" : "Submit") {
                    submitRequest()
                }
                .disabled(isSubmitting || !isFormValid)
            )
        }
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text("Time Off Request"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK")) {
                    if alertMessage.contains("successfully") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            )
        }
        .onAppear {
            checkForConflicts()
            loadPTOData()
            updatePTOCalculations()
        }
        .onChange(of: startDate) { _ in
            updatePTOCalculations()
        }
        .onChange(of: endDate) { _ in
            updatePTOCalculations()
        }
        .onChange(of: isPartialDay) { _ in
            updatePTOCalculations()
        }
        .onChange(of: startTime) { _ in
            updatePTOCalculations()
        }
        .onChange(of: endTime) { _ in
            updatePTOCalculations()
        }
    }
    
    // MARK: - Computed Properties
    
    private var isFormValid: Bool {
        if isPartialDay {
            // For partial days, ensure times are valid
            let timeInterval = endTime.timeIntervalSince(startTime)
            return timeInterval >= 1800 // At least 30 minutes
        } else {
            // For full days, dates should be valid (handled by date picker constraints)
            return true
        }
    }
    
    private var formattedDateRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        
        if isPartialDay {
            return formatter.string(from: startDate)
        } else {
            if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
                return formatter.string(from: startDate)
            } else {
                return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
            }
        }
    }
    
    private var formattedDuration: String {
        if isPartialDay {
            let timeInterval = endTime.timeIntervalSince(startTime)
            let hours = timeInterval / 3600
            
            if hours == 1 {
                return "1 hour"
            } else if hours.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(hours)) hours"
            } else {
                return String(format: "%.1f hours", hours)
            }
        } else {
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
            let totalDays = days + 1
            return totalDays == 1 ? "1 day" : "\(totalDays) days"
        }
    }
    
    // MARK: - Helper Methods
    
    private func validateTimes() {
        if endTime <= startTime {
            // Automatically adjust end time if it's not after start time
            let adjustedEndTime = Calendar.current.date(byAdding: .hour, value: 1, to: startTime) ?? startTime
            endTime = adjustedEndTime
        }
    }
    
    private func checkForConflicts() {
        let startTimeString = isPartialDay ? timeStringFormatter.string(from: startTime) : nil
        let endTimeString = isPartialDay ? timeStringFormatter.string(from: endTime) : nil
        
        timeOffService.checkForConflicts(
            startDate: startDate,
            endDate: endDate,
            isPartialDay: isPartialDay,
            startTime: startTimeString,
            endTime: endTimeString,
            excludeRequestId: editingRequest?.id
        ) { foundConflicts in
            DispatchQueue.main.async {
                self.conflicts = foundConflicts
            }
        }
    }
    
    // MARK: - PTO Methods
    
    private func loadPTOData() {
        guard let userId = Auth.auth().currentUser?.uid,
              let orgId = UserDefaults.standard.string(forKey: "userOrganizationID") else { return }
        
        // Load PTO balance
        ptoService.getPTOBalance(userId: userId, organizationID: orgId) { balance in
            DispatchQueue.main.async {
                self.currentPTOBalance = balance
            }
        }
        
        // Load PTO settings
        ptoService.getPTOSettings(organizationID: orgId) { settings in
            DispatchQueue.main.async {
                self.ptoSettings = settings
            }
        }
    }
    
    private func updatePTOCalculations() {
        // Calculate PTO hours based on request duration
        let calculatedHours = ptoService.calculatePTOHours(
            startDate: startDate,
            endDate: endDate,
            isPartialDay: isPartialDay,
            startTime: isPartialDay ? timeStringFormatter.string(from: startTime) : nil,
            endTime: isPartialDay ? timeStringFormatter.string(from: endTime) : nil
        )
        
        // Only update if user hasn't manually changed it
        if ptoHoursRequested == 0 || ptoHoursRequested == calculatedHours {
            ptoHoursRequested = calculatedHours
        }
        
        // Calculate projected balance
        if let balance = currentPTOBalance, let settings = ptoSettings {
            projectedPTOBalance = ptoService.calculateProjectedBalance(
                currentBalance: balance,
                settings: settings,
                targetDate: startDate
            )
        }
    }
    
    private func submitRequest() {
        isSubmitting = true
        
        let startTimeString = isPartialDay ? timeStringFormatter.string(from: startTime) : nil
        let endTimeString = isPartialDay ? timeStringFormatter.string(from: endTime) : nil
        
        if let editingRequest = editingRequest {
            // Update existing request
            timeOffService.updateTimeOffRequest(
                requestId: editingRequest.id,
                startDate: startDate,
                endDate: endDate,
                reason: selectedReason,
                notes: notes,
                isPartialDay: isPartialDay,
                startTime: startTimeString,
                endTime: endTimeString,
                isPaidTimeOff: isPaidTimeOff,
                ptoHoursRequested: isPaidTimeOff ? ptoHoursRequested : nil,
                projectedPTOBalance: isPaidTimeOff ? projectedPTOBalance : nil
            ) { success, error in
                DispatchQueue.main.async {
                    isSubmitting = false
                    
                    if success {
                        alertMessage = "Time off request updated successfully!"
                    } else {
                        alertMessage = error ?? "Failed to update request"
                    }
                    showingAlert = true
                }
            }
        } else {
            // Create new request
            timeOffService.createTimeOffRequest(
                startDate: startDate,
                endDate: endDate,
                reason: selectedReason,
                notes: notes,
                isPartialDay: isPartialDay,
                startTime: startTimeString,
                endTime: endTimeString,
                isPaidTimeOff: isPaidTimeOff,
                ptoHoursRequested: isPaidTimeOff ? ptoHoursRequested : nil,
                projectedPTOBalance: isPaidTimeOff ? projectedPTOBalance : nil
            ) { success, error in
                DispatchQueue.main.async {
                    isSubmitting = false
                    
                    if success {
                        alertMessage = "Time off request submitted successfully!"
                    } else {
                        alertMessage = error ?? "Failed to submit request"
                    }
                    showingAlert = true
                }
            }
        }
    }
}