import SwiftUI
import FirebaseFirestore

struct ClassGroupJobDetailView: View {
    let jobId: String
    
    @State private var job: ClassGroupJob?
    @State private var isLoading = true
    @State private var showingAddGroup = false
    @State private var selectedGroup: ClassGroup?
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var showingDeleteConfirmation = false
    @State private var groupToDelete: IndexSet?
    
    private let service = ClassGroupJobService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading job details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let job = job {
                // School name header
                VStack(spacing: 6) {
                    Text(job.schoolName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text(job.jobType == "classGroups" ? "Class Groups" : "Class Candids")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                if job.classGroups.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(job.classGroups) { group in
                            ClassGroupDetailRowView(
                                classGroup: group,
                                schoolName: job.schoolName,
                                onEdit: {
                                    selectedGroup = group
                                },
                                onSlate: {
                                    // Slate is handled within the row view
                                }
                            )
                        }
                        .onDelete(perform: deleteGroups)
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            } else {
                Text("Job not found")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingAddGroup = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddGroup) {
            AddClassGroupView(jobId: jobId, jobType: job?.jobType ?? "classGroups") { success in
                if success {
                    refreshJob()
                }
            }
        }
        .sheet(item: $selectedGroup) { group in
            EditClassGroupView(jobId: jobId, classGroup: group, jobType: job?.jobType ?? "classGroups") { success in
                if success {
                    refreshJob()
                }
            }
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Delete \(job?.jobType == "classGroups" ? "Class Group" : "Class Candid")?", 
               isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let offsets = groupToDelete {
                    performDelete(at: offsets)
                }
            }
        } message: {
            Text("Are you sure you want to delete this \(job?.jobType == "classGroups" ? "class group" : "class candid")?")
        }
        .onAppear {
            loadJob()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: job?.jobType == "classGroups" ? "camera.viewfinder" : "camera")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No \(job?.jobType == "classGroups" ? "Class Groups" : "Class Candids") Added")
                .font(.headline)
            
            Text("Tap the + button to add \(job?.jobType == "classGroups" ? "class groups" : "class candids") as you photograph them")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: {
                showingAddGroup = true
            }) {
                Label("Add \(job?.jobType == "classGroups" ? "Class Group" : "Class Candid")", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func loadJob() {
        isLoading = true
        
        // Listen for real-time updates to this specific job
        let db = Firestore.firestore()
        db.collection("classGroupJobs").document(jobId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    self.errorMessage = "Failed to load job: \(error.localizedDescription)"
                    self.showingErrorAlert = true
                    self.isLoading = false
                    return
                }
                
                guard let snapshot = snapshot, snapshot.exists else {
                    self.job = nil
                    self.isLoading = false
                    return
                }
                
                self.job = ClassGroupJob(from: snapshot)
                self.isLoading = false
            }
    }
    
    private func refreshJob() {
        // The real-time listener will automatically update
    }
    
    private func deleteGroups(at offsets: IndexSet) {
        groupToDelete = offsets
        showingDeleteConfirmation = true
    }
    
    private func performDelete(at offsets: IndexSet) {
        guard let job = job else { return }
        
        for index in offsets {
            let group = job.classGroups[index]
            
            service.deleteClassGroup(fromJobId: jobId, classGroupId: group.id) { result in
                switch result {
                case .success:
                    print("Successfully deleted class group")
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to delete: \(error.localizedDescription)"
                        self.showingErrorAlert = true
                    }
                }
            }
        }
    }
}

// MARK: - Class Group Detail Row
struct ClassGroupDetailRowView: View {
    let classGroup: ClassGroup
    let schoolName: String
    let onEdit: () -> Void
    let onSlate: () -> Void
    
    @State private var showingSlate = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Main content with background
            VStack(alignment: .leading, spacing: 6) {
                // Grade and Teacher on same line
                Text("\(classGroup.grade) - \(classGroup.teacher)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Image numbers or status
                if classGroup.hasImages {
                    Text("Images: \(classGroup.imageNumbers)")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(nil)
                } else {
                    Text("No images")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
                
                // Notes indicator (only if has notes)
                if !classGroup.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        Text("Has notes")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            // Action buttons
            HStack(spacing: 8) {
                // Edit button
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.title3)
                        .foregroundColor(.blue)
                        .frame(width: 36, height: 36)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(BorderlessButtonStyle())
                
                // Slate button
                Button(action: {
                    showingSlate = true
                    onSlate()
                }) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title3)
                        .foregroundColor(.green)
                        .frame(width: 36, height: 36)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .fullScreenCover(isPresented: $showingSlate) {
            ClassGroupSlateView(
                grade: classGroup.grade,
                teacher: classGroup.teacher,
                schoolName: schoolName
            )
        }
    }
}

// MARK: - Preview
struct ClassGroupJobDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ClassGroupJobDetailView(jobId: "preview123")
        }
    }
}