import SwiftUI
import FirebaseAuth

struct CreateClassGroupJobView: View {
    @Environment(\.presentationMode) var presentationMode
    
    let onComplete: (String) -> Void // Pass back the job ID
    let initialJobType: String
    
    @State private var availableSessions: [Session] = []
    @State private var selectedSession: Session?
    @State private var selectedJobType: String
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    
    private let service = ClassGroupJobService.shared
    
    init(initialJobType: String = "classGroups", onComplete: @escaping (String) -> Void) {
        self.initialJobType = initialJobType
        self.onComplete = onComplete
        self._selectedJobType = State(initialValue: initialJobType)
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading && availableSessions.isEmpty {
                    ProgressView("Loading available sessions...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if availableSessions.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Available Sessions")
                            .font(.headline)
                        
                        Text("There are no upcoming sessions without \(selectedJobType == "classGroups" ? "class group" : "class candid") jobs in the next 2 weeks.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Sessions List
                    List(availableSessions) { session in
                        ClassGroupSessionRowView(session: session, isSelected: selectedSession?.id == session.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSession = session
                            }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle("Create \(selectedJobType == "classGroups" ? "Class Group" : "Class Candid") Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create Job") {
                        createJob()
                    }
                    .disabled(selectedSession == nil || isLoading)
                }
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                // Make sure we're using the correct job type when loading
                selectedJobType = initialJobType
                loadAvailableSessions()
            }
        }
    }
    
    private func loadAvailableSessions() {
        isLoading = true
        
        print("🔍 Loading sessions for jobType: \(selectedJobType)")
        
        UserManager.shared.getCurrentUserOrganizationID { organizationId in
            guard let orgId = organizationId else {
                self.errorMessage = "Unable to determine organization"
                self.showingErrorAlert = true
                self.isLoading = false
                return
            }
            
            print("🔍 Calling getUpcomingSessions with jobType: \(selectedJobType)")
            service.getUpcomingSessions(organizationId: orgId, jobType: selectedJobType) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    switch result {
                    case .success(let sessions):
                        self.availableSessions = sessions
                    case .failure(let error):
                        self.errorMessage = "Failed to load sessions: \(error.localizedDescription)"
                        self.showingErrorAlert = true
                    }
                }
            }
        }
    }
    
    private func createJob() {
        guard let session = selectedSession,
              let schoolId = session.schoolId else { return }
        
        isLoading = true
        
        UserManager.shared.getCurrentUserOrganizationID { organizationId in
            guard let orgId = organizationId else {
                self.errorMessage = "Unable to determine organization"
                self.showingErrorAlert = true
                self.isLoading = false
                return
            }
            
            service.createClassGroupJob(
                sessionId: session.id,
                sessionDate: session.startDate ?? Date(),
                schoolId: schoolId,
                schoolName: session.schoolName,
                organizationId: orgId,
                jobType: selectedJobType
            ) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    switch result {
                    case .success(let jobId):
                        self.onComplete(jobId)
                        self.presentationMode.wrappedValue.dismiss()
                    case .failure(let error):
                        self.errorMessage = "Failed to create job: \(error.localizedDescription)"
                        self.showingErrorAlert = true
                    }
                }
            }
        }
    }
}

// MARK: - Session Row View
struct ClassGroupSessionRowView: View {
    let session: Session
    let isSelected: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                // Date and time
                Text(formattedDateTime)
                    .font(.headline)
                
                // School name
                Text(session.schoolName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Session type
                if let sessionTypes = session.sessionType, !sessionTypes.isEmpty {
                    Text(sessionTypes.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
            }
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
    
    private var formattedDateTime: String {
        guard let startDate = session.startDate else {
            return "Date not available"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        return formatter.string(from: startDate)
    }
}

// MARK: - Preview
struct CreateClassGroupJobView_Previews: PreviewProvider {
    static var previews: some View {
        CreateClassGroupJobView(initialJobType: "classGroups") { _ in }
    }
}