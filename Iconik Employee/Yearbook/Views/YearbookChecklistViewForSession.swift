import SwiftUI

/// Wrapper view that loads the yearbook checklist for a specific school based on session date
struct YearbookChecklistViewForSession: View {
    let schoolId: String
    let schoolName: String
    let sessionContext: YearbookSessionContext
    
    @StateObject private var viewModel = YearbookShootListViewModel()
    @State private var isLoading = true
    @State private var selectedYear: String?
    @State private var noListsFound = false
    @State private var organizationId: String?
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading yearbook checklist...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if noListsFound {
                noListsFoundView
            } else if let year = selectedYear {
                if let shootList = viewModel.selectedShootList {
                    YearbookChecklistView(
                        shootList: shootList,
                        sessionContext: sessionContext
                    )
                } else {
                    // Still loading the selected shoot list
                    ProgressView("Loading yearbook checklist...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                yearSelectionView
            }
        }
        .navigationTitle("Yearbook Checklist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .onAppear {
            loadYearbookList()
        }
    }
    
    private var noListsFoundView: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Yearbook List Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("No yearbook checklist exists for \(schoolName)")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Close") {
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    private var yearSelectionView: some View {
        VStack(spacing: 20) {
            Text("Select School Year")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Multiple yearbook lists found for \(schoolName)")
                .font(.body)
                .foregroundColor(.secondary)
            
            ForEach(viewModel.availableYears, id: \.self) { year in
                Button(action: {
                    selectedYear = year
                    if let orgId = organizationId {
                        viewModel.loadShootList(schoolId: schoolId, schoolYear: year, organizationId: orgId)
                    }
                }) {
                    HStack {
                        Text(year)
                            .font(.headline)
                        
                        if year == YearbookShootList.getCurrentSchoolYear(date: sessionContext.sessionDate) {
                            Text("(Current)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
        }
    }
    
    private func loadYearbookList() {
        Task {
            do {
                print("📋 YearbookChecklistViewForSession - Loading yearbook list")
                print("📋 School ID: '\(schoolId)'")
                print("📋 School Name: '\(schoolName)'")
                print("📋 Session Date: \(sessionContext.sessionDate)")
                
                // Get organization ID first
                let organizationId = await withCheckedContinuation { continuation in
                    UserManager.shared.getCurrentUserOrganizationID { orgId in
                        continuation.resume(returning: orgId)
                    }
                }
                
                guard let orgId = organizationId else {
                    print("📋 No organization ID found")
                    noListsFound = true
                    isLoading = false
                    return
                }
                
                // Store organizationId for use in year selection
                self.organizationId = orgId

                // Get available years for this school
                let years = try await YearbookShootListService.shared.getAvailableYears(schoolId: schoolId, organizationId: orgId)
                
                print("📋 Available years found: \(years)")
                
                if years.isEmpty {
                    print("📋 No yearbook lists found for school ID: '\(schoolId)'")
                    noListsFound = true
                    isLoading = false
                    return
                }
                
                viewModel.availableYears = years
                
                // Calculate which school year the session falls into
                let sessionYear = YearbookShootList.getCurrentSchoolYear(date: sessionContext.sessionDate)
                print("📋 Calculated session year: \(sessionYear)")
                
                if years.contains(sessionYear) {
                    // Load the matching year
                    print("📋 Loading yearbook list for year: \(sessionYear)")
                    selectedYear = sessionYear
                    viewModel.loadShootList(schoolId: schoolId, schoolYear: sessionYear, organizationId: orgId)
                } else if years.count == 1, let firstYear = years.first {
                    // Only one year available, load it
                    print("📋 Loading only available year: \(firstYear)")
                    selectedYear = firstYear
                    viewModel.loadShootList(schoolId: schoolId, schoolYear: firstYear, organizationId: orgId)
                } else {
                    // Multiple years available, let user choose
                    print("📋 Multiple years available, showing selection")
                    // The yearSelectionView will be shown
                }
                
                isLoading = false
            } catch {
                print("📋 Error loading yearbook list: \(error)")
                noListsFound = true
                isLoading = false
            }
        }
    }
}

// MARK: - Preview
struct YearbookChecklistViewForSession_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            YearbookChecklistViewForSession(
                schoolId: "school123",
                schoolName: "Lincoln High School",
                sessionContext: YearbookSessionContext(
                    sessionId: "session123",
                    photographerId: "user123",
                    photographerName: "John Doe",
                    sessionDate: Date()
                )
            )
        }
    }
}