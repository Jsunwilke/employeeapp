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
    
    var body: some View {
        List(reports) { report in
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
        .navigationTitle("My Daily Job Reports")
        .onAppear {
            // Get current user ID
            if let currentUser = Auth.auth().currentUser {
                userId = currentUser.uid
            }
            loadReports()
        }
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
}

