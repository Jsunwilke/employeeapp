//
//  EditDailyJobReportView.swift
//

import SwiftUI

struct EditDailyJobReportView: View {
    let report: JobReport
    
    // Form fields – note that "jobDescriptionText" is now represented as "jobNotes"
    @State private var reportDate: Date = Date()
    @State private var totalMileage: String = ""
    @State private var vehicleType: String = "personal"  // "personal" or "company"
    @State private var jobNotes: String = ""
    @State private var photoshootNoteText: String = ""  // New field for photoshoot notes
    @State private var jobDescriptions: [String] = []
    @State private var extraItems: [String] = []
    @State private var cardsScannedChoice: String = "Yes"
    @State private var jobBoxAndCameraCards: String = "NA"
    @State private var sportsBackgroundShot: String = "NA"
    @State private var schoolOrDestination: String = ""
    // Session link is preserved across edits (not re-selectable here); carried
    // forward verbatim so editing a report never wipes its session link (SR1.7).
    @State private var sessionId: String? = nil
    @State private var sessionName: String? = nil
    @State private var existingPhotoURLs: [String] = []
    @State private var showPhotoDetail: Bool = false
    @State private var selectedPhotoURL: String = ""
    
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String = ""
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.dismiss) private var dismiss
    
    // Options arrays (same as in DailyJobReportView)
    let yesNoNaOptions = ["Yes", "No", "NA"]
    let yesNoOptions   = ["Yes", "No"]
    let jobDescriptionOptions = [
        "Fall Original Day",
        "Fall Makeup Day",
        "Classroom Groups",
        "Fall Sports",
        "Winter Sports",
        "Spring Sports",
        "Spring Photos",
        "Homecoming",
        "Prom",
        "Graduation",
        "Yearbook Candid's",
        "Yearbook Groups and Clubs",
        "Sports League",
        "District Office Photos",
        "Banner Photos",
        "In Studio Photos",
        "School Board Photos",
        "Dr. Office Head Shots",
        "Dr. Office Cards",
        "Dr. Office Candid's",
        "Deliveries",
        "NONE"
    ]
    let extraItemsOptions = [
        "Underclass Makeup",
        "Staff Makeup",
        "ID card Images",
        "Sports Makeup",
        "Class Groups",
        "Yearbook Groups and Clubs",
        "Class Candids",
        "Students from other schools",
        "Siblings",
        "Office Staff Photos",
        "Deliveries",
        "NONE"
    ]
    let columns = [
        GridItem(.flexible(minimum: 100), spacing: 10),
        GridItem(.flexible(minimum: 100), spacing: 10)
    ]
    
    // The list of school options loaded from Supabase
    @State private var schoolOptions: [SchoolItem] = []
    
    var body: some View {
        Form {
            Section(header: Text("Report Details")) {
                DatePicker("Date", selection: $reportDate, displayedComponents: .date)
                TextField("Total Mileage", text: $totalMileage)
                    .keyboardType(.decimalPad)
                Picker("Vehicle", selection: $vehicleType) {
                    Text("Personal").tag("personal")
                    Text("Company").tag("company")
                }
                .pickerStyle(.segmented)
                TextField("School / Destination", text: $schoolOrDestination)
            }
            
            // Renamed section header from "Job Description" to "Job Notes"
            Section(header: Text("Job Notes")) {
                TextEditor(text: $jobNotes)
                    .frame(height: 80)
            }
            
            // New section to display/edit photoshoot notes
            Section(header: Text("Photoshoot Note Info:")) {
                TextEditor(text: $photoshootNoteText)
                    .frame(height: 80)
            }
            
            Section(header: Text("Job Descriptions (Select applicable)")) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(jobDescriptionOptions, id: \.self) { option in
                        Toggle(isOn: Binding(
                            get: { jobDescriptions.contains(option) },
                            set: { newValue in
                                if newValue {
                                    jobDescriptions.append(option)
                                } else {
                                    jobDescriptions.removeAll { $0 == option }
                                }
                            }
                        )) {
                            Text(option)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .toggleStyle(CheckboxStyle())
                    }
                }
            }
            
            Section(header: Text("Extra Items Added")) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(extraItemsOptions, id: \.self) { option in
                        Toggle(isOn: Binding(
                            get: { extraItems.contains(option) },
                            set: { newValue in
                                if newValue {
                                    extraItems.append(option)
                                } else {
                                    extraItems.removeAll { $0 == option }
                                }
                            }
                        )) {
                            Text(option)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .toggleStyle(CheckboxStyle())
                    }
                }
            }
            
            Section(header: Text("Cards Scanned")) {
                ForEach(yesNoOptions, id: \.self) { option in
                    RadioRow(label: option, isSelected: (cardsScannedChoice == option)) {
                        cardsScannedChoice = option
                    }
                }
            }
            
            Section(header: Text("Job Box and Camera Cards Turned In")) {
                ForEach(yesNoNaOptions, id: \.self) { option in
                    RadioRow(label: option, isSelected: (jobBoxAndCameraCards == option)) {
                        jobBoxAndCameraCards = option
                    }
                }
            }
            
            Section(header: Text("Sports Background Shot")) {
                ForEach(yesNoNaOptions, id: \.self) { option in
                    RadioRow(label: option, isSelected: (sportsBackgroundShot == option)) {
                        sportsBackgroundShot = option
                    }
                }
            }
            
            Button(action: submitUpdate) {
                if isSubmitting {
                    ProgressView()
                } else {
                    Text("Update Report")
                }
            }
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
            }
            
            // Photos section
            if !existingPhotoURLs.isEmpty {
                Section(header: Text("Attached Photos")) {
                    StoragePhotoGallery(photoURLs: existingPhotoURLs, columns: 3)
                        .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Edit Job Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .disabled(isDeleting)
            }
        }
        .alert("Delete Report", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteReport()
            }
        } message: {
            Text("Are you sure you want to delete this report? This action cannot be undone.")
        }
        .onAppear(perform: loadReportData)
        .disabled(isDeleting)
    }
    
    func loadReportData() {
        Task {
            do {
                // Load report from Supabase
                if let supabaseReport = try await DailyJobReportService.shared.getReport(reportId: report.id) {
                    await MainActor.run {
                        reportDate = supabaseReport.date
                        totalMileage = String(format: "%.1f", supabaseReport.total_mileage)
                        vehicleType = supabaseReport.vehicle_type ?? "personal"
                        jobNotes = supabaseReport.job_description_text ?? ""
                        photoshootNoteText = supabaseReport.photoshoot_note_text ?? ""
                        jobDescriptions = supabaseReport.job_descriptions ?? []
                        extraItems = supabaseReport.extra_items ?? []
                        cardsScannedChoice = supabaseReport.cards_scanned_choice ?? "Yes"
                        jobBoxAndCameraCards = supabaseReport.job_box_and_camera_cards ?? "NA"
                        sportsBackgroundShot = supabaseReport.sports_background_shot ?? "NA"
                        schoolOrDestination = supabaseReport.school_or_destination ?? ""
                        sessionId = supabaseReport.session_id
                        sessionName = supabaseReport.session_name
                        existingPhotoURLs = supabaseReport.photo_urls ?? []
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }

        loadSchools()
    }

    func loadSchools() {
        let organizationID = UserDefaults.standard.string(forKey: "userOrganizationID") ?? ""

        guard !organizationID.isEmpty else {
            errorMessage = "User organization not found"
            return
        }

        Task {
            do {
                let schools = try await SchoolService.shared.getSchools(organizationID: organizationID)

                await MainActor.run {
                    // Convert School models to SchoolItem
                    var temp: [SchoolItem] = []
                    for school in schools {
                        var addressComponents: [String] = []
                        if let street = school.street, !street.isEmpty {
                            addressComponents.append(street)
                        }
                        if let city = school.city, !city.isEmpty {
                            addressComponents.append(city)
                        }
                        if let state = school.state, !state.isEmpty {
                            addressComponents.append(state)
                        }
                        if let zip = school.zip, !zip.isEmpty {
                            addressComponents.append(zip)
                        }
                        let address = addressComponents.isEmpty ? school.value : addressComponents.joined(separator: ", ")

                        temp.append(SchoolItem(
                            id: school.id,
                            name: school.value,
                            address: address,
                            coordinates: school.coordinates
                        ))
                    }
                    temp.sort { $0.name.lowercased() < $1.name.lowercased() }
                    self.schoolOptions = temp
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func submitUpdate() {
        guard let currentUserId = UserManager.shared.getCurrentUserIDUnified() else {
            errorMessage = "User not signed in."
            return
        }
        isSubmitting = true

        let organizationID = UserDefaults.standard.string(forKey: "userOrganizationID") ?? ""
        let yourName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let mileageValue = Double(totalMileage) ?? 0.0

        // Create updated report
        let updatedReport = DailyJobReport(
            id: report.id,
            organizationID: organizationID,
            userId: currentUserId,
            date: reportDate,
            yourName: yourName,
            schoolOrDestination: schoolOrDestination.isEmpty ? nil : schoolOrDestination,
            sessionId: sessionId,
            sessionName: sessionName,
            totalMileage: mileageValue,
            vehicleType: vehicleType,
            jobDescriptions: jobDescriptions.isEmpty ? nil : jobDescriptions,
            extraItems: extraItems.isEmpty ? nil : extraItems,
            cardsScannedChoice: cardsScannedChoice.isEmpty ? nil : cardsScannedChoice,
            jobBoxAndCameraCards: jobBoxAndCameraCards.isEmpty ? nil : jobBoxAndCameraCards,
            sportsBackgroundShot: sportsBackgroundShot.isEmpty ? nil : sportsBackgroundShot,
            jobDescriptionText: jobNotes.isEmpty ? nil : jobNotes,
            photoshootNoteText: photoshootNoteText.isEmpty ? nil : photoshootNoteText,
            photoURLs: existingPhotoURLs.isEmpty ? nil : existingPhotoURLs
        )

        Task {
            do {
                try await DailyJobReportService.shared.updateReport(updatedReport)

                await MainActor.run {
                    isSubmitting = false
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func deleteReport() {
        isDeleting = true

        Task {
            do {
                try await DailyJobReportService.shared.deleteReport(reportId: report.id)

                await MainActor.run {
                    isDeleting = false
                    print("Report deleted successfully")
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    print("Error deleting report: \(error.localizedDescription)")
                    errorMessage = "Failed to delete report: \(error.localizedDescription)"
                }
            }
        }
    }
}

// ------------------------------------------------------------------
// CheckboxStyle
// ------------------------------------------------------------------
struct CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square" : "square")
                .resizable()
                .frame(width: 20, height: 20)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
            configuration.label
        }
    }
}

// ------------------------------------------------------------------
// RadioRow
// ------------------------------------------------------------------
struct RadioRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundColor(.blue)
            Text(label)
        }
        .onTapGesture {
            action()
        }
    }
}
