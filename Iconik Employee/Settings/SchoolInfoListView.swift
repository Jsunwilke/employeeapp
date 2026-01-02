import SwiftUI
import Supabase

struct SchoolInfoListView: View {
    @State private var schools: [School] = []
    @State private var mileageBySchool: [String: Double] = [:]
    @State private var errorMessage: String = ""
    @State private var showingAddSchool = false
    @State private var isLoading = false

    // User's organization ID
    @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""
    
    var body: some View {
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
                                Text(school.address ?? "")
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
    
    func loadSchools() {
        guard !storedUserOrganizationID.isEmpty else {
            errorMessage = "No organization ID found. Please sign in again."
            return
        }

        isLoading = true
        schools = []
        mileageBySchool = [:]

        Task {
            do {
                let loadedSchools = try await SchoolService.shared.getSchools(organizationID: storedUserOrganizationID)
                await MainActor.run {
                    self.schools = loadedSchools
                    self.isLoading = false

                    // Load mileage for each school
                    for school in loadedSchools {
                        loadMileage(for: school)
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    // Load mileage using Supabase
    func loadMileage(for school: School) {
        guard let seasonDates = currentSchoolSeasonDates() else { return }
        let seasonStart = seasonDates.start
        let seasonEnd = seasonDates.end

        Task {
            do {
                let supabase = SupabaseManager.shared.client

                struct MileageRecord: Decodable {
                    let total_mileage: Double?
                }

                let records: [MileageRecord] = try await supabase
                    .from("daily_job_reports")
                    .select("total_mileage")
                    .eq("school_or_destination", value: school.name)
                    .eq("organization_id", value: storedUserOrganizationID)
                    .gte("date", value: seasonStart.ISO8601Format())
                    .lte("date", value: seasonEnd.ISO8601Format())
                    .execute()
                    .value

                let total = records.reduce(0.0) { $0 + ($1.total_mileage ?? 0.0) }

                await MainActor.run {
                    mileageBySchool[school.id] = total
                }
            } catch {
                print("Error loading mileage for \(school.name): \(error.localizedDescription)")
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
