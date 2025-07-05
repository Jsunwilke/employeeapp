import SwiftUI
import FirebaseFirestore

struct SchoolInfoListView: View {
    @State private var schools: [SchoolItem] = []
    @State private var mileageBySchool: [String: Double] = [:]
    @State private var errorMessage: String = ""
    @State private var showingAddSchool = false
    @State private var isLoading = false
    
    // User's organization ID
    @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading schools...")
                        .padding()
                } else if schools.isEmpty {
                    VStack(spacing: 20) {
                        Text("No schools found")
                            .font(.headline)
                        
                        Button(action: {
                            showingAddSchool = true
                        }) {
                            Label("Add Your First School", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                } else {
                    List(schools) { school in
                        NavigationLink(destination: SchoolDetailView(schoolId: school.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(school.name)
                                    .font(.headline)
                                Text(school.address)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                if let mileage = mileageBySchool[school.id] {
                                    Text("Mileage: \(mileage, specifier: "%.1f") miles")
                                        .font(.footnote)
                                        .foregroundColor(.blue)
                                } else {
                                    Text("Mileage: --")
                                        .font(.footnote)
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .refreshable {
                        loadSchools()
                    }
                }
            }
            .navigationTitle("School Info")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddSchool = true
                    }) {
                        Label("Add School", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSchool) {
                AddSchoolView()
                    .onDisappear {
                        // Reload the school list when the Add School view disappears
                        loadSchools()
                    }
            }
            .onAppear(perform: loadSchools)
            .alert(isPresented: .constant(!errorMessage.isEmpty)) {
                Alert(title: Text("Error"),
                      message: Text(errorMessage),
                      dismissButton: .default(Text("OK")) {
                          errorMessage = ""
                      })
            }
        }
    }
    
    func loadSchools() {
        guard !storedUserOrganizationID.isEmpty else {
            errorMessage = "No organization ID found. Please sign in again."
            return
        }
        
        isLoading = true
        schools = []
        mileageBySchool = [:]
        
        let db = Firestore.firestore()
        db.collection("dropdownData")
            .whereField("type", isEqualTo: "school")
            .whereField("organizationID", isEqualTo: storedUserOrganizationID) // Filter by organization ID
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false
                    
                    if let error = error {
                        errorMessage = error.localizedDescription
                        return
                    }
                    
                    guard let docs = snapshot?.documents else { return }
                    
                    if docs.isEmpty {
                        // No schools found for this organization
                        return
                    }
                    
                    var temp: [SchoolItem] = []
                    for doc in docs {
                        let data = doc.data()
                        if let value = data["value"] as? String,
                           let address = data["schoolAddress"] as? String {
                            let school = SchoolItem(id: doc.documentID, name: value, address: address)
                            temp.append(school)
                            loadMileage(for: school)
                        }
                    }
                    temp.sort { $0.name.lowercased() < $1.name.lowercased() }
                    schools = temp
                }
            }
    }
    
    func loadMileage(for school: SchoolItem) {
        guard let seasonDates = currentSchoolSeasonDates() else { return }
        let seasonStart = seasonDates.start
        let seasonEnd = seasonDates.end
        let db = Firestore.firestore()
        
        db.collection("dailyJobReports")
            .whereField("schoolOrDestination", isEqualTo: school.name)
            .whereField("organizationID", isEqualTo: storedUserOrganizationID) // Filter by organization ID
            .whereField("date", isGreaterThanOrEqualTo: seasonStart)
            .whereField("date", isLessThanOrEqualTo: seasonEnd)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error loading mileage for \(school.name): \(error.localizedDescription)")
                    return
                }
                guard let docs = snapshot?.documents else { return }
                var total: Double = 0.0
                for doc in docs {
                    let data = doc.data()
                    let mileage = data["totalMileage"] as? Double ?? 0.0
                    total += mileage
                }
                DispatchQueue.main.async {
                    mileageBySchool[school.id] = total
                }
            }
    }
    
    func currentSchoolSeasonDates() -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        let today = Date()
        let year = calendar.component(.year, from: today)
        guard let july15ThisYear = calendar.date(from: DateComponents(year: year, month: 7, day: 15)),
              let june1ThisYear = calendar.date(from: DateComponents(year: year, month: 6, day: 1)) else {
            return nil
        }
        if today >= july15ThisYear {
            // Season runs from July 15 this year to June 1 next year.
            let seasonStart = july15ThisYear
            let seasonEnd = calendar.date(from: DateComponents(year: year + 1, month: 6, day: 1))!
            return (seasonStart, seasonEnd)
        } else {
            // Season runs from July 15 last year to June 1 this year.
            let seasonStart = calendar.date(from: DateComponents(year: year - 1, month: 7, day: 15))!
            let seasonEnd = june1ThisYear
            return (seasonStart, seasonEnd)
        }
    }
}
