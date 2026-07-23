import SwiftUI

struct ClassGroupJobsListView: View {
    @StateObject private var service = ClassGroupJobService.shared
    @State private var showingCreateJob = false
    @State private var selectedJobId: String?
    @State private var organizationId: String?
    @State private var selectedTab = "classGroups"
    @State private var showingDeleteConfirmation = false
    @State private var jobToDelete: IndexSet?
    
    // Access TabBarManager to check for selected job
    @ObservedObject private var tabBarManager = TabBarManager.shared
    
    var filteredJobs: [ClassGroupJob] {
        service.classGroupJobs.filter { ClassGroupJobType.normalize($0.jobType) == selectedTab }
    }

    var body: some View {
        VStack {
            // Tab Picker
            Picker("", selection: $selectedTab) {
                ForEach(ClassGroupJobType.all, id: \.self) { jobType in
                    Text(ClassGroupJobType.displayName(jobType)).tag(jobType)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            if service.isLoading && service.classGroupJobs.isEmpty {
                ProgressView("Loading jobs...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredJobs.isEmpty {
                EmptyStateView(showingCreateJob: $showingCreateJob, jobType: selectedTab)
            } else {
                List {
                    ForEach(filteredJobs) { job in
                        NavigationLink(
                            destination: ClassGroupJobDetailView(jobId: job.id),
                            tag: job.id,
                            selection: $selectedJobId
                        ) {
                            ClassGroupJobRowView(job: job)
                        }
                    }
                    .onDelete(perform: deleteJobs)
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
        .navigationTitle(ClassGroupJobType.displayName(selectedTab))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingCreateJob = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateJob) {
            CreateClassGroupJobView(initialJobType: selectedTab) { jobId in
                // Navigate to the newly created job
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    selectedJobId = jobId
                }
            }
        }
        .onAppear {
            loadData()
        }
        .onDisappear {
            service.stopListening()
        }
        .alert("Delete Job?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let offsets = jobToDelete {
                    performDelete(at: offsets)
                }
            }
        } message: {
            Text("This will delete the entire job and all its \(ClassGroupJobType.rowNounPlural(selectedTab)). This action cannot be undone.")
        }
    }
    
    private func loadData() {
        UserManager.shared.getCurrentUserOrganizationID { orgId in
            guard let organizationId = orgId else {
                print("Failed to get organization ID")
                return
            }
            
            self.organizationId = organizationId
            service.startListening(organizationId: organizationId)
            
            // Check if we have a selected job from the widget
            checkForSelectedJob()
        }
    }
    
    private func deleteJobs(at offsets: IndexSet) {
        jobToDelete = offsets
        showingDeleteConfirmation = true
    }
    
    private func performDelete(at offsets: IndexSet) {
        for index in offsets {
            let job = filteredJobs[index]
            service.deleteClassGroupJob(id: job.id, sessionId: job.sessionId, jobType: job.jobType) { result in
                switch result {
                case .success:
                    print("Successfully deleted job")
                case .failure(let error):
                    print("Error deleting job: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func checkForSelectedJob() {
        // Check if we have a selected job ID from the widget
        guard let selectedId = tabBarManager.selectedClassGroupJobId else { return }

        // Clear the selected job after using it
        defer {
            tabBarManager.selectedClassGroupJobId = nil
            tabBarManager.selectedClassGroupJobType = nil
        }

        // Switch to the job's segment first — the NavigationLink for the job only
        // exists in its own tab's list, so navigating from the widget to a candids
        // or clubs job dead-ends without this.
        if let jobType = tabBarManager.selectedClassGroupJobType {
            selectedTab = ClassGroupJobType.normalize(jobType)
        }

        // Navigate to the selected job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.selectedJobId = selectedId
        }
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    @Binding var showingCreateJob: Bool
    let jobType: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: ClassGroupJobType.listEmptyIcon(jobType))
                .font(.system(size: 80))
                .foregroundColor(.gray)

            Text("No \(ClassGroupJobType.singularTitle(jobType)) Jobs")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a job for an upcoming session to start tracking \(ClassGroupJobType.rowNounPlural(jobType))")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: {
                showingCreateJob = true
            }) {
                Label("Create Job", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Job Row View
struct ClassGroupJobRowView: View {
    let job: ClassGroupJob
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Date
            Text(formattedDate)
                .font(.headline)
            
            // School name
            Text(job.schoolName)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Group count
            HStack {
                if job.classGroupCount > 0 {
                    Label("\(job.classGroupCount) \(job.classGroupCount == 1 ? ClassGroupJobType.countNoun(job.jobType) : ClassGroupJobType.countNounPlural(job.jobType))",
                          systemImage: "person.3")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else {
                    Text("No \(ClassGroupJobType.countNounPlural(job.jobType)) added")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                if job.totalImageCount > 0 {
                    Spacer()
                    Label("\(job.totalImageCount) images", systemImage: "photo")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: job.sessionDate)
    }
}

// MARK: - Preview
struct ClassGroupJobsListView_Previews: PreviewProvider {
    static var previews: some View {
        ClassGroupJobsListView()
    }
}