import SwiftUI

struct SessionFormView: View {
    @Binding var formData: SessionFormData
    let schools: [School]
    let teamMembers: [TeamMember]
    let sessionTypes: [SessionType]
    let isEditing: Bool
    
    @State private var showDatePicker = false
    @State private var showStartTimePicker = false
    @State private var showEndTimePicker = false
    @State private var selectedDate = Date()
    @State private var selectedStartTime = Date()
    @State private var selectedEndTime = Date()
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    
    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    private let displayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        Form {
            // School Selection
            Section(header: Text("School")) {
                Picker("Select School", selection: $formData.schoolId) {
                    Text("Select a school").tag("")
                    ForEach(schools) { school in
                        Text(school.value).tag(school.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
            
            // Date and Time
            Section(header: Text("Date & Time")) {
                // Date
                HStack {
                    Text("Date")
                    Spacer()
                    Button(action: { showDatePicker.toggle() }) {
                        Text(formData.date.isEmpty ? "Select Date" : displayDateFormatter.string(from: dateFromString(formData.date) ?? Date()))
                            .foregroundColor(formData.date.isEmpty ? .gray : .primary)
                    }
                }
                
                // Start Time
                HStack {
                    Text("Start Time")
                    Spacer()
                    Button(action: { showStartTimePicker.toggle() }) {
                        Text(formData.startTime.isEmpty ? "Select Time" : displayTimeFormatter.string(from: timeFromString(formData.startTime) ?? Date()))
                            .foregroundColor(formData.startTime.isEmpty ? .gray : .primary)
                    }
                }
                
                // End Time
                HStack {
                    Text("End Time")
                    Spacer()
                    Button(action: { showEndTimePicker.toggle() }) {
                        Text(formData.endTime.isEmpty ? "Select Time" : displayTimeFormatter.string(from: timeFromString(formData.endTime) ?? Date()))
                            .foregroundColor(formData.endTime.isEmpty ? .gray : .primary)
                    }
                }
            }
            
            // Session Types
            Section(header: Text("Session Types")) {
                ForEach(sessionTypes) { type in
                    HStack {
                        Image(systemName: formData.sessionTypes.contains(type.id) ? "checkmark.square.fill" : "square")
                            .foregroundColor(formData.sessionTypes.contains(type.id) ? .blue : .gray)
                        
                        Circle()
                            .fill(Color(hex: type.color))
                            .frame(width: 16, height: 16)
                        
                        Text(type.name)
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleSessionType(type.id)
                    }
                }
                
                // Custom session type input if "other" is selected
                if formData.sessionTypes.contains("other") {
                    TextField("Specify custom type", text: $formData.customSessionType)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
            
            // Photographers
            Section(header: Text("Photographers")) {
                ForEach(teamMembers.filter { $0.isActive }) { member in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: formData.photographerIds.contains(member.id) ? "checkmark.square.fill" : "square")
                                .foregroundColor(formData.photographerIds.contains(member.id) ? .blue : .gray)
                            
                            Text(member.fullName)
                            
                            Spacer()
                            
                            if !member.isActive {
                                Text("Inactive")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            togglePhotographer(member.id)
                        }
                        
                        // Notes field for selected photographers
                        if formData.photographerIds.contains(member.id) {
                            TextField("Notes for \(member.firstName)", text: bindingForPhotographerNote(member.id))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.caption)
                        }
                    }
                }
                
                if teamMembers.filter({ $0.isActive }).isEmpty {
                    Text("No active photographers available")
                        .foregroundColor(.gray)
                }
            }
            
            // General Notes
            Section(header: Text("Notes")) {
                TextEditor(text: $formData.notes)
                    .frame(minHeight: 100)
            }
            
            // Status (for editing only)
            if isEditing {
                Section(header: Text("Status")) {
                    Picker("Status", selection: $formData.status) {
                        Text("Scheduled").tag("scheduled")
                        Text("Completed").tag("completed")
                        Text("Cancelled").tag("cancelled")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(
                date: $selectedDate,
                onSave: {
                    formData.date = dateFormatter.string(from: selectedDate)
                },
                mode: .date
            )
        }
        .sheet(isPresented: $showStartTimePicker) {
            DatePickerSheet(
                date: $selectedStartTime,
                onSave: {
                    formData.startTime = timeFormatter.string(from: selectedStartTime)
                },
                mode: .time
            )
        }
        .sheet(isPresented: $showEndTimePicker) {
            DatePickerSheet(
                date: $selectedEndTime,
                onSave: {
                    formData.endTime = timeFormatter.string(from: selectedEndTime)
                },
                mode: .time
            )
        }
        .onAppear {
            // Initialize date/time pickers with existing values or defaults
            if !formData.date.isEmpty, let date = dateFromString(formData.date) {
                selectedDate = date
            }
            if !formData.startTime.isEmpty, let time = timeFromString(formData.startTime) {
                selectedStartTime = time
            }
            if !formData.endTime.isEmpty, let time = timeFromString(formData.endTime) {
                selectedEndTime = time
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func toggleSessionType(_ typeId: String) {
        if formData.sessionTypes.contains(typeId) {
            formData.sessionTypes.removeAll { $0 == typeId }
        } else {
            formData.sessionTypes.append(typeId)
        }
    }
    
    private func togglePhotographer(_ photographerId: String) {
        if formData.photographerIds.contains(photographerId) {
            formData.photographerIds.remove(photographerId)
            formData.photographerNotes.removeValue(forKey: photographerId)
        } else {
            formData.photographerIds.insert(photographerId)
        }
    }
    
    private func bindingForPhotographerNote(_ photographerId: String) -> Binding<String> {
        Binding(
            get: { formData.photographerNotes[photographerId] ?? "" },
            set: { formData.photographerNotes[photographerId] = $0 }
        )
    }
    
    private func dateFromString(_ dateString: String) -> Date? {
        dateFormatter.date(from: dateString)
    }
    
    private func timeFromString(_ timeString: String) -> Date? {
        timeFormatter.date(from: timeString)
    }
}

// MARK: - Date Picker Sheet
struct DatePickerSheet: View {
    @Binding var date: Date
    let onSave: () -> Void
    let mode: UIDatePicker.Mode
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                DatePicker(
                    "",
                    selection: $date,
                    displayedComponents: mode == .date ? .date : .hourAndMinute
                )
                .datePickerStyle(WheelDatePickerStyle())
                .labelsHidden()
                
                Spacer()
            }
            .navigationTitle(mode == .date ? "Select Date" : "Select Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

