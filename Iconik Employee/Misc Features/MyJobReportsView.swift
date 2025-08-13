//
//  MyJobReportsView.swift
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// Updated JobReport struct now includes a "school" field and photo count.
struct JobReport: Identifiable {
    let id: String
    let date: Date
    let school: String
    let totalMileage: Double
    let photoCount: Int
    let photoURLs: [String]
}

struct MyJobReportsView: View {
    @State private var reports: [JobReport] = []
    @AppStorage("userFirstName") var storedUserFirstName: String = ""
    @State private var userId: String? = nil
    @State private var showDeleteAlert = false
    @State private var reportToDelete: JobReport?
    @State private var isDeleting = false
    
    var body: some View {
        List {
            ForEach(reports) { report in
                NavigationLink(destination: EditDailyJobReportView(report: report)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(report.date, style: .date)
                                .font(.headline)
                            Text(report.school)
                                .font(.subheadline)
                            HStack {
                                Text("Mileage: \(report.totalMileage, specifier: "%.1f")")
                                    .font(.footnote)
                                if report.photoCount > 0 {
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Image(systemName: "photo.fill")
                                            .font(.caption)
                                        Text("\(report.photoCount)")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(10)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete(perform: deleteReports)
        }
        .navigationTitle("My Daily Job Reports")
        .onAppear {
            // Get current user ID
            if let currentUser = Auth.auth().currentUser {
                userId = currentUser.uid
            }
            loadReports()
        }
        .alert("Delete Report", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {
                reportToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let report = reportToDelete {
                    deleteReport(report)
                }
            }
        } message: {
            if let report = reportToDelete {
                Text("Are you sure you want to delete the report from \(report.date, style: .date)?")
            }
        }
        .disabled(isDeleting)
    }
    
    func loadReports() {
        let db = Firestore.firestore()
        
        // Build query - prefer userId if available, fallback to yourName
        let baseCollection = db.collection("dailyJobReports")
        let query: Query
        
        if let userId = userId {
            print("Querying reports by userId: \(userId)")
            query = baseCollection.whereField("userId", isEqualTo: userId)
                .order(by: "date", descending: true)
        } else if !storedUserFirstName.isEmpty {
            print("Querying reports by yourName: \(storedUserFirstName)")
            query = baseCollection.whereField("yourName", isEqualTo: storedUserFirstName)
                .order(by: "date", descending: true)
        } else {
            print("No user ID or name available")
            return
        }
        
        query.getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching reports: \(error.localizedDescription)")
                    
                    // More detailed error logging
                    if (error as NSError).code == 7 { // Permission denied
                        print("Permission denied. User ID: \(self.userId ?? "nil"), UserName: \(self.storedUserFirstName)")
                    }
                    return
                }
                guard let documents = snapshot?.documents else { return }
                reports = documents.compactMap { doc in
                    let data = doc.data()
                    guard let timestamp = data["date"] as? Timestamp,
                          let school = data["schoolOrDestination"] as? String,
                          let totalMileage = data["totalMileage"] as? Double else { return nil }
                    
                    // Get photo URLs from the report
                    let photoURLs = data["photoURLs"] as? [String] ?? []
                    
                    return JobReport(id: doc.documentID,
                                     date: timestamp.dateValue(),
                                     school: school,
                                     totalMileage: totalMileage,
                                     photoCount: photoURLs.count,
                                     photoURLs: photoURLs)
                }
            }
    }
    
    // Handle swipe-to-delete
    func deleteReports(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        reportToDelete = reports[index]
        showDeleteAlert = true
    }
    
    // Delete a report from Firestore
    func deleteReport(_ report: JobReport) {
        isDeleting = true
        
        let db = Firestore.firestore()
        db.collection("dailyJobReports").document(report.id).delete { error in
            DispatchQueue.main.async {
                isDeleting = false
                
                if let error = error {
                    print("Error deleting report: \(error.localizedDescription)")
                    // Could show an error alert here if needed
                } else {
                    // Remove from local array
                    reports.removeAll { $0.id == report.id }
                    reportToDelete = nil
                    print("Report deleted successfully")
                }
            }
        }
    }
}

