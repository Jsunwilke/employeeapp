import SwiftUI

struct ClassGroupJobsListView: View {
    @StateObject private var service = ClassGroupJobService.shared
    @State private var showingCreateJob = false
    @State private var selectedJobId: String?
    @State private var organizationId: String?
    @State private var selectedTab = "classGroups"
    @State private var showingDeleteConfirmation = false
    @State private var jobToDelete: IndexSet?
    
    var filteredJobs: [ClassGroupJob] {
        service.classGroupJobs.filter { $0.jobType == selectedTab }
    }
    
    var body: some View {
        VStack {
            // Tab Picker
            Picker("", selection: $selectedTab) {
                Text("Class Groups").tag("classGroups")
                Text("Class Candids").tag("classCandids")
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
        .navigationTitle(selectedTab == "classGroups" ? "Class Groups" : "Class Candids")
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
            Text("This will delete the entire job and all its \(selectedTab == "classGroups" ? "class groups" : "class candids"). This action cannot be undone.")
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
}

// MARK: - Empty State View
struct EmptyStateView: View {
    @Binding var showingCreateJob: Bool
    let jobType: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: jobType == "classGroups" ? "person.3" : "camera")
                .font(.system(size: 80))
                .foregroundColor(.gray)
            
            Text("No \(jobType == "classGroups" ? "Class Group" : "Class Candid") Jobs")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create a job for an upcoming session to start tracking \(jobType == "classGroups" ? "class groups" : "class candids")")
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
                    Label("\(job.classGroupCount) group\(job.classGroupCount == 1 ? "" : "s")", 
                          systemImage: "person.3")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else {
                    Text("No groups added")
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