//
//  MileageDetailView.swift
//  Iconik Employee
//
//  Created by administrator on 4/27/25.
//


import SwiftUI
import Firebase
import FirebaseFirestore

struct MileageDetailView: View {
    let record: MileageReportsViewModel.MileageRecordWrapper
    
    // Local copies of the record data for editing
    @State private var localMileage: String
    @State private var localSchoolName: String
    @State private var isEditing: Bool = false
    @State private var schoolOptions: [MileageSchoolItem] = []
    @State private var errorMessage: String = ""
    @State private var showingErrorAlert: Bool = false
    @State private var showingSuccessAlert: Bool = false
    
    // To dismiss the view when saving
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    
    // Date formatter for header
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter
    }
    
    init(record: MileageReportsViewModel.MileageRecordWrapper) {
        self.record = record
        _localMileage = State(initialValue: String(format: "%.1f", record.totalMileage))
        _localSchoolName = State(initialValue: record.schoolName)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Card with mileage details
                VStack(spacing: 16) {
                    // Date
                    Text(dateFormatter.string(from: record.date))
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    // School name
                    if isEditing {
                        if schoolOptions.isEmpty {
                            Text("Loading schools...")
                                .foregroundColor(.secondary)
                                .onAppear(perform: loadSchools)
                        } else {
                            Picker("School", selection: Binding(
                                get: {
                                    schoolOptions.first(where: { $0.name == localSchoolName }) 
                                        ?? (schoolOptions.first ?? MileageSchoolItem(id: "", name: ""))
                                },
                                set: { newSchool in
                                    localSchoolName = newSchool.name
                                }
                            )) {
                                ForEach(schoolOptions, id: \.id) { school in
                                    Text(school.name).tag(school)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .padding(.horizontal)
                            .frame(maxWidth: .infinity)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                    } else {
                        Text(localSchoolName)
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // Mileage & Reimbursement
                    HStack(spacing: 40) {
                        VStack(spacing: 5) {
                            if isEditing {
                                TextField("Miles", text: $localMileage)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 42, weight: .bold, design: .rounded))
                                    .padding(.horizontal)
                                    .frame(minWidth: 120)
                            } else {
                                Text(localMileage)
                                    .font(.system(size: 42, weight: .bold, design: .rounded))
                            }
                            Text("miles")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 5) {
                            Text("$\(calculateReimbursement(), specifier: "%.2f")")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundColor(.blue)
                            Text("reimbursement")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 5)
                }
                .padding(.vertical, 30)
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
                .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6).opacity(0.5))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // Edit button
                if isEditing {
                    HStack(spacing: 20) {
                        // Cancel Button
                        Button(action: {
                            // Reset to original values and exit edit mode
                            localMileage = String(format: "%.1f", record.totalMileage)
                            localSchoolName = record.schoolName
                            isEditing = false
                        }) {
                            Text("Cancel")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(.primary)
                                .cornerRadius(12)
                        }
                        
                        // Save Button
                        Button(action: saveChanges) {
                            Text("Save")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    Button(action: { isEditing = true }) {
                        Text("Edit Mileage")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .navigationTitle("Mileage Details")
            .navigationBarTitleDisplayMode(.inline)
            .alert(isPresented: $showingErrorAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert("Changes Saved", isPresented: $showingSuccessAlert) {
                Button("OK") {
                    presentationMode.wrappedValue.dismiss()
                }
            } message: {
                Text("Your mileage update has been saved successfully.")
            }
        }
    }
    
    // Calculate reimbursement amount (using 30 cents per mile)
    private func calculateReimbursement() -> Double {
        return (Double(localMileage) ?? 0.0) * 0.3
    }
    
    // Load school options from Firestore
    private func loadSchools() {
        let db = Firestore.firestore()
        db.collection("dropdownData")
            .whereField("type", isEqualTo: "school")
            .getDocuments { snapshot, error in
                if let error = error {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                    return
                }
                guard let docs = snapshot?.documents else { return }
                var temp: [MileageSchoolItem] = []
                for doc in docs {
                    let data = doc.data()
                    if let value = data["value"] as? String {
                        temp.append(MileageSchoolItem(id: doc.documentID, name: value))
                    }
                }
                temp.sort { $0.name.lowercased() < $1.name.lowercased() }
                schoolOptions = temp
                
                // Pre-select the matching school if possible
                if let matched = temp.first(where: { $0.name == record.schoolName }) {
                    localSchoolName = matched.name
                }
            }
    }
    
    // Save changes to Firestore
    private func saveChanges() {
        guard let mileage = Double(localMileage) else {
            errorMessage = "Invalid mileage value. Please enter a number."
            showingErrorAlert = true
            return
        }
        
        if localSchoolName.isEmpty {
            errorMessage = "Please select a school."
            showingErrorAlert = true
            return
        }
        
        let db = Firestore.firestore()
        db.collection("dailyJobReports").document(record.id).updateData([
            "totalMileage": mileage,
            "schoolOrDestination": localSchoolName
        ]) { error in
            if let error = error {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            } else {
                // Show success and dismiss
                showingSuccessAlert = true
            }
        }
    }
}

// We need this struct for the school picker
struct MileageSchoolItem: Identifiable, Hashable {
    let id: String
    let name: String
}