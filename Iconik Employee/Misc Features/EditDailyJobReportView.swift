//
//  EditDailyJobReportView.swift
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct EditDailyJobReportView: View {
    let report: JobReport
    
    // Form fields – note that "jobDescriptionText" is now represented as "jobNotes"
    @State private var reportDate: Date = Date()
    @State private var totalMileage: String = ""
    @State private var jobNotes: String = ""
    @State private var photoshootNoteText: String = ""  // New field for photoshoot notes
    @State private var jobDescriptions: [String] = []
    @State private var extraItems: [String] = []
    @State private var cardsScannedChoice: String = "Yes"
    @State private var jobBoxAndCameraCards: String = "NA"
    @State private var sportsBackgroundShot: String = "NA"
    @State private var schoolOrDestination: String = ""
    // (Photo attachments and photoshoot note selection logic are omitted for brevity.)
    
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String = ""
    @Environment(\.presentationMode) var presentationMode
    
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
    
    // The list of school options loaded from Firestore
    @State private var schoolOptions: [SchoolItem] = []
    
    var body: some View {
        Form {
            Section(header: Text("Report Details")) {
                DatePicker("Date", selection: $reportDate, displayedComponents: .date)
                TextField("Total Mileage", text: $totalMileage)
                    .keyboardType(.decimalPad)
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
        }
        .navigationTitle("Edit Job Report")
        .onAppear(perform: loadReportData)
    }
    
    func loadReportData() {
        let db = Firestore.firestore()
        db.collection("dailyJobReports").document(report.id).getDocument { snapshot, error in
            if let error = error {
                errorMessage = error.localizedDescription
                return
            }
            guard let data = snapshot?.data() else { return }
            if let timestamp = data["date"] as? Timestamp {
                reportDate = timestamp.dateValue()
            }
            if let mileage = data["totalMileage"] as? Double {
                totalMileage = String(format: "%.1f", mileage)
            }
            if let notes = data["jobDescriptionText"] as? String {
                jobNotes = notes
            }
            // Load the photoshoot note text if present.
            if let noteText = data["photoshootNoteText"] as? String {
                photoshootNoteText = noteText
            }
            if let jobDescs = data["jobDescriptions"] as? [String] {
                jobDescriptions = jobDescs
            }
            if let extras = data["extraItems"] as? [String] {
                extraItems = extras
            }
            if let cardsScanned = data["cardsScannedChoice"] as? String {
                cardsScannedChoice = cardsScanned
            }
            if let boxCards = data["jobBoxAndCameraCards"] as? String {
                jobBoxAndCameraCards = boxCards
            }
            if let sportsShot = data["sportsBackgroundShot"] as? String {
                sportsBackgroundShot = sportsShot
            }
            if let school = data["schoolOrDestination"] as? String {
                schoolOrDestination = school
            }
        }
        
        loadSchools()
    }
    
    func loadSchools() {
        let db = Firestore.firestore()
        db.collection("dropdownData")
            .whereField("type", isEqualTo: "school")
            .getDocuments { snapshot, error in
                if let error = error {
                    errorMessage = error.localizedDescription
                    return
                }
                guard let docs = snapshot?.documents else { return }
                var temp: [SchoolItem] = []
                for doc in docs {
                    let data = doc.data()
                    if let value = data["value"] as? String,
                       let address = data["schoolAddress"] as? String {
                        temp.append(SchoolItem(id: doc.documentID, name: value, address: address))
                    }
                }
                temp.sort { $0.name.lowercased() < $1.name.lowercased() }
                schoolOptions = temp
            }
    }
    
    func submitUpdate() {
        guard let _ = Auth.auth().currentUser else {
            errorMessage = "User not signed in."
            return
        }
        isSubmitting = true
        let mileageValue = Double(totalMileage) ?? 0.0
        let updatedData: [String: Any] = [
            "date": reportDate,
            "totalMileage": mileageValue,
            "jobDescriptionText": jobNotes,
            "photoshootNoteText": photoshootNoteText, // Update photoshoot note info.
            "jobDescriptions": jobDescriptions,
            "extraItems": extraItems,
            "cardsScannedChoice": cardsScannedChoice,
            "jobBoxAndCameraCards": jobBoxAndCameraCards,
            "sportsBackgroundShot": sportsBackgroundShot,
            "schoolOrDestination": schoolOrDestination,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        let db = Firestore.firestore()
        db.collection("dailyJobReports").document(report.id).updateData(updatedData) { error in
            isSubmitting = false
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                presentationMode.wrappedValue.dismiss()
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
