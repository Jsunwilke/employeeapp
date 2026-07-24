//
//  MileageDetailView.swift
//  Iconik Employee
//
//  Created by administrator on 4/27/25.
//


import SwiftUI
import Supabase

struct MileageDetailView: View {
    let record: MileageReportsViewModel.MileageRecordWrapper
    let personalRate: Double
    let companyRate: Double

    // Local copies of the record data for editing
    @State private var localMileage: String
    @State private var localSchoolName: String
    @State private var localVehicleType: String
    @State private var isEditing: Bool = false
    @State private var schoolOptions: [MileageSchoolItem] = []
    @State private var errorMessage: String = ""
    @State private var showingErrorAlert: Bool = false
    @State private var showingSuccessAlert: Bool = false
    
    // To dismiss the view when saving
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    
    // User organization for filtering schools
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    
    // Date formatter for header
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter
    }
    
    init(record: MileageReportsViewModel.MileageRecordWrapper, personalRate: Double, companyRate: Double) {
        self.record = record
        self.personalRate = personalRate
        self.companyRate = companyRate
        _localMileage = State(initialValue: String(format: "%.1f", record.totalMileage))
        _localSchoolName = State(initialValue: record.schoolName)
        _localVehicleType = State(initialValue: record.vehicleType)
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
                            SearchableMileageSchoolPicker(
                                selectedSchoolName: $localSchoolName,
                                schools: schoolOptions,
                                title: "School"
                            )
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

                    // Vehicle type
                    if isEditing {
                        Picker("Vehicle", selection: $localVehicleType) {
                            Text("Personal").tag("personal")
                            Text("Company").tag("company")
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    } else if VehicleRates.isCompany(localVehicleType) {
                        Text("Company car")
                            .font(.subheadline)
                            .foregroundColor(.orange)
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
                            localVehicleType = record.vehicleType
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
    
    // Calculate reimbursement amount at the vehicle-appropriate rate.
    private func calculateReimbursement() -> Double {
        let miles = Double(localMileage) ?? 0.0
        let rate = VehicleRates.rate(forVehicleType: localVehicleType, personalRate: personalRate, companyCarRate: companyRate)
        return miles * rate
    }
    
    // Load school options from Supabase
    private func loadSchools() {
        Task {
            do {
                let supabase = SupabaseManager.shared.client

                struct SchoolRecord: Decodable {
                    let id: String
                    let name: String?
                }

                let schools: [SchoolRecord] = try await supabase
                    .from("schools")
                    .select("id, name")
                    .eq("organization_id", value: storedUserOrganizationID)
                    .execute()
                    .value

                await MainActor.run {
                    var temp: [MileageSchoolItem] = []
                    for school in schools {
                        if let name = school.name {
                            temp.append(MileageSchoolItem(id: school.id, name: name))
                        }
                    }
                    temp.sort { $0.name.lowercased() < $1.name.lowercased() }
                    schoolOptions = temp

                    // Pre-select the matching school if possible
                    if let matched = temp.first(where: { $0.name == record.schoolName }) {
                        localSchoolName = matched.name
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                }
            }
        }
    }
    
    // Save changes to Supabase
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

        Task {
            do {
                let supabase = SupabaseManager.shared.client

                print("📝 Saving mileage - ID: \(record.id), Mileage: \(mileage), School: \(localSchoolName)")

                let updateData: [String: AnyJSON] = [
                    "total_mileage": .double(mileage),
                    "school_or_destination": .string(localSchoolName),
                    "vehicle_type": .string(localVehicleType)
                ]
                try await supabase
                    .from("daily_job_reports")
                    .update(updateData)
                    .eq("id", value: record.id)
                    .execute()

                print("✅ Mileage saved successfully")

                await MainActor.run {
                    showingSuccessAlert = true
                }
            } catch {
                print("❌ Mileage save error: \(error)")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                }
            }
        }
    }
}

// We need this struct for the school picker
struct MileageSchoolItem: Identifiable, Hashable {
    let id: String
    let name: String
}