//
//  ManagerEmployeeDetailView.swift
//  Iconik_EmployeeApp
//
//  Shows the employee's name in a large font within the content area,
//  leaving the navigation bar title empty. The system back button remains
//  in the nav bar, but no text is shown in the nav bar itself.
//

import SwiftUI
import Firebase
import FirebaseFirestore
import FirebaseAuth

struct ManagerDailyRecord: Identifiable {
    let id: String
    let date: Date
    let schoolName: String
    let totalMileage: Double
    let photoURLs: [String]
}

class ManagerEmployeeDetailViewModel: ObservableObject {
    @Published var records: [ManagerDailyRecord] = []
    @Published var totalPeriodMileage: Double = 0.0
    @Published var errorMessage: String? = nil
    
    let employeeName: String
    let periodStart: Date
    let periodEnd: Date
    
    private let calendar = Calendar.current
    
    init(employeeName: String, periodStart: Date) {
        self.employeeName = employeeName
        self.periodStart  = periodStart
        // A 14-day window
        self.periodEnd    = calendar.date(byAdding: .day, value: 13, to: periodStart) ?? periodStart
    }
    
    func loadRecords() {
        // Get current user's organization ID
        guard let currentUser = Auth.auth().currentUser else {
            self.errorMessage = "Not authenticated"
            return
        }
        
        let db = Firestore.firestore()
        
        // First get the user's organization ID
        db.collection("users").document(currentUser.uid).getDocument { [weak self] userDoc, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Error getting user data: \(error.localizedDescription)"
                }
                return
            }
            
            guard let userData = userDoc?.data(),
                  let organizationID = userData["organizationID"] as? String else {
                DispatchQueue.main.async {
                    self?.errorMessage = "User organization not found"
                }
                return
            }
            
            // Now query with organization ID
            db.collection("dailyJobReports")
                .whereField("organizationID", isEqualTo: organizationID)
                .whereField("yourName", isEqualTo: self?.employeeName ?? "")
                .whereField("date", isGreaterThanOrEqualTo: self?.periodStart ?? Date())
                .whereField("date", isLessThanOrEqualTo: self?.periodEnd ?? Date())
                .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Error loading records: \(error.localizedDescription)"
                    }
                    return
                }
                guard let docs = snapshot?.documents, let self = self else { return }
                
                var tempRecords: [ManagerDailyRecord] = []
                var totalMiles: Double = 0.0
                
                for doc in docs {
                    let data = doc.data()
                    guard let ts = data["date"] as? Timestamp else { continue }
                    
                    let dateVal = ts.dateValue()
                    let school  = data["schoolOrDestination"] as? String ?? "Unknown"
                    let miles   = data["totalMileage"] as? Double ?? 0.0
                    let photoURLs = data["photoURLs"] as? [String] ?? []
                    totalMiles += miles
                    
                    tempRecords.append(
                        ManagerDailyRecord(
                            id: doc.documentID,
                            date: dateVal,
                            schoolName: school,
                            totalMileage: miles,
                            photoURLs: photoURLs
                        )
                    )
                }
                
                // Sort descending by date
                tempRecords.sort { $0.date > $1.date }
                
                DispatchQueue.main.async {
                    self.records = tempRecords
                    self.totalPeriodMileage = totalMiles
                }
            }
        }
    }
    
    var periodRangeText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return "\(f.string(from: periodStart)) - \(f.string(from: periodEnd))"
    }
}

struct ManagerEmployeeDetailView: View {
    @StateObject private var viewModel: ManagerEmployeeDetailViewModel
    
    init(employeeName: String, periodStart: Date) {
        let vm = ManagerEmployeeDetailViewModel(employeeName: employeeName, periodStart: periodStart)
        _viewModel = StateObject(wrappedValue: vm)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 1) Big name text at the top
            Text(viewModel.employeeName)
                .font(.system(size: 40, weight: .bold))
                .padding(.top, 16)
                .padding(.horizontal)
            
            // 2) Period date range
            Text("Period: \(viewModel.periodRangeText)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 4)
                .padding(.horizontal)
            
            // 3) Total miles in this period
            HStack {
                Text("Total Miles This Period:")
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.1f", viewModel.totalPeriodMileage))
                    .font(.headline)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // 4) List of daily records
            List(viewModel.records) { record in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dateFormatter.string(from: record.date))
                                .font(.headline)
                            Text(record.schoolName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f miles", record.totalMileage))
                                .font(.footnote)
                        }
                        
                        Spacer()
                        
                        if !record.photoURLs.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "photo.fill")
                                    .font(.caption)
                                Text("\(record.photoURLs.count)")
                                    .font(.caption)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    
                    // Show photo thumbnails if available
                    if !record.photoURLs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(record.photoURLs.prefix(5), id: \.self) { photoURL in
                                    FirebaseImageThumbnail(imageURL: photoURL, size: 60)
                                }
                                if record.photoURLs.count > 5 {
                                    ZStack {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 60, height: 60)
                                            .cornerRadius(8)
                                        Text("+\(record.photoURLs.count - 5)")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        // 5) Remove any text from the nav bar title
        .navigationBarTitle("", displayMode: .inline)
        // Let the system show the single back button (arrow + default text)
        .navigationBarBackButtonHidden(false)
        // If you want only the arrow, you can do the custom approach:
        // .navigationBarBackButtonHidden(true)
        // .toolbar { ... custom arrow ... }
        .alert(item: Binding(
            get: { viewModel.errorMessage.map { ManagerDetailError(message: $0) } },
            set: { _ in viewModel.errorMessage = nil }
        )) { err in
            Alert(title: Text("Error"), message: Text(err.message), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            viewModel.loadRecords()
        }
    }
    
    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }
}

fileprivate struct ManagerDetailError: Identifiable {
    let id = UUID()
    let message: String
}

