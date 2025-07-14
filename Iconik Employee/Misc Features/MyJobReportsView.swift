//
//  MyJobReportsView.swift
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// Updated JobReport struct now includes a "school" field.
struct JobReport: Identifiable {
    let id: String
    let date: Date
    let school: String
    let totalMileage: Double
}

struct MyJobReportsView: View {
    @State private var reports: [JobReport] = []
    @AppStorage("userFirstName") var storedUserFirstName: String = ""
    
    var body: some View {
        List(reports) { report in
            NavigationLink(destination: EditDailyJobReportView(report: report)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.date, style: .date)
                        .font(.headline)
                    Text(report.school)
                        .font(.subheadline)
                    Text("Mileage: \(report.totalMileage, specifier: "%.1f")")
                        .font(.footnote)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("My Daily Job Reports")
        .onAppear(perform: loadReports)
    }
    
    func loadReports() {
        guard !storedUserFirstName.isEmpty else { return }
        let db = Firestore.firestore()
        db.collection("dailyJobReports")
            .whereField("yourName", isEqualTo: storedUserFirstName)
            .order(by: "date", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching reports: \(error.localizedDescription)")
                    return
                }
                guard let documents = snapshot?.documents else { return }
                reports = documents.compactMap { doc in
                    let data = doc.data()
                    guard let timestamp = data["date"] as? Timestamp,
                          let school = data["schoolOrDestination"] as? String,
                          let totalMileage = data["totalMileage"] as? Double else { return nil }
                    return JobReport(id: doc.documentID,
                                     date: timestamp.dateValue(),
                                     school: school,
                                     totalMileage: totalMileage)
                }
            }
    }
}

