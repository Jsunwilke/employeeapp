import SwiftUI

struct FormView: View {
    let cardNumber: String
    @Binding var selectedSchool: String
    @Binding var selectedStatus: String
    let localStatuses: [String]
    let lastRecord: FirestoreRecord?
    
    var onSubmit: (String, String, String, String, @escaping (Bool) -> Void) -> Void
    var onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var userManager = UserManager.shared
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""
    
    @State private var uploadedFromJasonsHouse: Bool = false
    @State private var uploadedFromAndysHouse: Bool = false
    @State private var localPhotographer: String = ""
    
    @State private var isSubmitting = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    // For photographers & schools
    @State private var photographerNames: [String] = []
    @State private var schools: [SchoolItem] = []
    
    var body: some View {
        formContent
    }
    
    private var formContent: some View {
        Form {
                Section(header: Text("Card Information")) {
                    Text("Card Number: \(cardNumber)")
                }
                
                Section(header: Text("Additional Information")) {
                    // Photographer Picker (data from users)
                    Picker("Photographer", selection: $localPhotographer) {
                        ForEach(photographerNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    
                    // School Picker (data from dropdownData)
                    Picker("School", selection: $selectedSchool) {
                        ForEach(schools.sorted { $0.name < $1.name }) { school in
                            Text(school.name).tag(school.name)
                        }
                    }
                    
                    // Status Picker
                    Picker("Status", selection: $selectedStatus) {
                        ForEach(localStatuses, id: \.self) { status in
                            Text(status).tag(status)
                        }
                    }
                    // If "Cleared" is picked, default the school to "Iconik"
                    .onChange(of: selectedStatus) { newVal in
                        if newVal.lowercased() == "cleared" {
                            selectedSchool = "Iconik"
                        }
                    }
                    
                    // Conditionally show toggles if status is "uploaded"
                    if selectedStatus.lowercased() == "uploaded",
                       userManager.currentUserOrganizationID == "T6XeeaUNoOp8VJqq36wi" {
                        Toggle("Uploaded from Jason's house", isOn: $uploadedFromJasonsHouse)
                            .onChange(of: uploadedFromJasonsHouse) { newValue in
                                if newValue { uploadedFromAndysHouse = false }
                            }
                        
                        Toggle("Uploaded from Andy's house", isOn: $uploadedFromAndysHouse)
                            .onChange(of: uploadedFromAndysHouse) { newValue in
                                if newValue { uploadedFromJasonsHouse = false }
                            }
                    }
                }
                
                // Action buttons at the bottom
                Section {
                HStack(spacing: 16) {
                    Button(action: {
                        print("FormView - Cancel button pressed")
                        onCancel()
                    }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Button("Submit") {
                        guard !isSubmitting else { return }
                        isSubmitting = true
                        let jasonValue = uploadedFromJasonsHouse ? "Yes" : ""
                        let andyValue = uploadedFromAndysHouse ? "Yes" : ""
                        
                        onSubmit(cardNumber, localPhotographer, jasonValue, andyValue) { success in
                            DispatchQueue.main.async {
                                isSubmitting = false
                                if success {
                                    dismiss()
                                } else {
                                    if alertMessage.isEmpty {
                                        alertMessage = "Submission failed. Please try again."
                                    }
                                    showAlert = true
                                }
                            }
                        }
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(isSubmitting ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(isSubmitting)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle("Enter Info")
            .onAppear {
                // Set default photographer from session
                localPhotographer = storedUserFirstName
                updateDefaults()
                
                // Load photographers from cached data and listen for live updates
                if let data = UserDefaults.standard.data(forKey: "photographerNames"),
                   let cachedNames = try? JSONDecoder().decode([String].self, from: data) {
                    self.photographerNames = cachedNames
                }
                let orgID = userManager.currentUserOrganizationID
                if !orgID.isEmpty {
                    FirestoreManager.shared.listenForPhotographers(inOrgID: orgID) { names in
                        DispatchQueue.main.async {
                            self.photographerNames = names
                        }
                    }
                }
                
                // Load schools from cached data and listen for live updates
                if let data = UserDefaults.standard.data(forKey: "nfcSchools"),
                   let cachedSchools = try? JSONDecoder().decode([SchoolItem].self, from: data) {
                    self.schools = cachedSchools
                }
                let schoolOrgID = userManager.currentUserOrganizationID
                if !schoolOrgID.isEmpty {
                    FirestoreManager.shared.listenForSchoolsData(forOrgID: schoolOrgID) { records in
                        DispatchQueue.main.async {
                            self.schools = records
                            // Ensure a default school is selected if none exists.
                            if selectedSchool.isEmpty {
                                if let firstSchool = schools.sorted(by: { $0.name < $1.name }).first?.name {
                                    selectedSchool = firstSchool
                                }
                            }
                        }
                    }
                }
            }
            .alert(isPresented: $showAlert) {
                if alertMessage == "Scan saved" {
                    return Alert(title: Text(""), message: Text(alertMessage))
                } else {
                    return Alert(title: Text(""), message: Text(alertMessage), dismissButton: .default(Text("OK"), action: {
                        isSubmitting = false
                    }))
                }
            }
    }
    
    private func updateDefaults() {
        if let last = lastRecord {
            // If the last record was "cleared", default the school to "Iconik"
            if last.status.lowercased() == "cleared" {
                selectedSchool = "Iconik"
            } else {
                selectedSchool = last.school
            }
            
            let lastStatus = last.status.lowercased()
            if lastStatus == "camera bag" {
                selectedStatus = "Camera"
                return
            }
            if lastStatus == "personal" {
                selectedStatus = "Cleared"
                return
            }
            
            let defaultStatuses = localStatuses.filter {
                let s = $0.lowercased()
                return s != "camera bag" && s != "personal"
            }
            if let index = defaultStatuses.firstIndex(where: { $0.lowercased() == lastStatus }) {
                let nextIndex = (index + 1) % defaultStatuses.count
                selectedStatus = defaultStatuses[nextIndex]
            } else {
                selectedStatus = defaultStatuses.first ?? ""
            }
        } else {
            // If no last record exists, and no school has been selected, set the default to the first available school.
            if selectedSchool.isEmpty {
                if let firstSchool = schools.sorted(by: { $0.name < $1.name }).first?.name {
                    selectedSchool = firstSchool
                }
            }
        }
    }
}