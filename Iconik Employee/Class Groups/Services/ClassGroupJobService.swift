import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

class ClassGroupJobService: ObservableObject {
    static let shared = ClassGroupJobService()
    private let db = Firestore.firestore()
    private let collectionName = "classGroupJobs"
    private let sessionsCollection = "sessions"
    
    @Published var classGroupJobs: [ClassGroupJob] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private var listener: ListenerRegistration?
    
    private init() {}
    
    deinit {
        listener?.remove()
    }
    
    // MARK: - Fetch Operations
    
    /// Fetch all class group jobs for an organization
    func fetchAllClassGroupJobs(forOrganization orgId: String, completion: @escaping (Result<[ClassGroupJob], Error>) -> Void) {
        print("Fetching all class group jobs for organization: \(orgId)")
        
        guard !orgId.isEmpty else {
            let error = NSError(domain: "ClassGroupJobService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Organization ID is required"])
            completion(.failure(error))
            return
        }
        
        db.collection(collectionName)
            .whereField("organizationId", isEqualTo: orgId)
            .order(by: "sessionDate", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching class group jobs: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("No class group jobs found")
                    completion(.success([]))
                    return
                }
                
                let jobs = documents.compactMap { ClassGroupJob(from: $0) }
                print("Successfully fetched \(jobs.count) class group jobs")
                completion(.success(jobs))
            }
    }
    
    /// Fetch class group job for a specific session
    func fetchClassGroupJob(forSession sessionId: String, completion: @escaping (Result<ClassGroupJob?, Error>) -> Void) {
        print("Fetching class group job for session: \(sessionId)")
        
        db.collection(collectionName)
            .whereField("sessionId", isEqualTo: sessionId)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching class group job: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let document = snapshot?.documents.first else {
                    completion(.success(nil))
                    return
                }
                
                let job = ClassGroupJob(from: document)
                completion(.success(job))
            }
    }
    
    /// Get upcoming sessions (next 2 weeks) without class group jobs
    func getUpcomingSessions(organizationId: String, jobType: String = "classGroups", completion: @escaping (Result<[Session], Error>) -> Void) {
        print("📋 Fetching upcoming sessions for jobType: \(jobType)")
        
        let now = Date()
        let twoWeeksFromNow = Calendar.current.date(byAdding: .weekOfYear, value: 2, to: now) ?? now
        
        // Format dates for Firestore query
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startDateStr = dateFormatter.string(from: now)
        let endDateStr = dateFormatter.string(from: twoWeeksFromNow)
        
        // First, get all sessions in the date range (without hasClassGroupJob filter)
        db.collection(sessionsCollection)
            .whereField("organizationID", isEqualTo: organizationId)
            .whereField("date", isGreaterThanOrEqualTo: startDateStr)
            .whereField("date", isLessThanOrEqualTo: endDateStr)
            .order(by: "date")
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("Error fetching sessions: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                print("Found \(documents.count) total sessions in date range")
                let allSessions = documents.map { doc -> Session in
                    Session(id: doc.documentID, data: doc.data())
                }
                
                // Filter to only include sessions with schools
                let sessionsWithSchools = allSessions.filter { $0.schoolId != nil && !$0.schoolName.isEmpty }
                
                // Handle empty sessions case
                if sessionsWithSchools.isEmpty {
                    print("No sessions with schools found")
                    completion(.success([]))
                    return
                }
                
                // Now check which sessions already have class group jobs of this type
                let sessionIds = sessionsWithSchools.map { $0.id }
                
                // Firestore 'in' query has a limit of 10 items, so we need to batch
                var sessionIdsWithJobs = Set<String>()
                let batchSize = 10
                let batches = stride(from: 0, to: sessionIds.count, by: batchSize).map {
                    Array(sessionIds[$0..<min($0 + batchSize, sessionIds.count)])
                }
                
                let group = DispatchGroup()
                
                for batch in batches {
                    group.enter()
                    self?.db.collection(self?.collectionName ?? "")
                        .whereField("organizationId", isEqualTo: organizationId)
                        .whereField("sessionId", in: batch)
                        .whereField("jobType", isEqualTo: jobType)
                        .getDocuments { jobSnapshot, jobError in
                            if let jobError = jobError {
                                print("Error fetching existing jobs: \(jobError.localizedDescription)")
                            } else {
                                // Add session IDs that have jobs
                                jobSnapshot?.documents.forEach { doc in
                                    if let sessionId = doc.data()["sessionId"] as? String {
                                        sessionIdsWithJobs.insert(sessionId)
                                    }
                                }
                            }
                            group.leave()
                        }
                }
                
                group.notify(queue: .main) {
                    print("Sessions with existing jobs: \(sessionIdsWithJobs)")
                    
                    // Filter out sessions based on job type
                    let availableSessions = sessionsWithSchools.filter { session in
                        let hasExistingJob = sessionIdsWithJobs.contains(session.id)
                        if jobType == "classGroups" {
                            print("📋 Checking session \(session.id): hasExistingJob=\(hasExistingJob), hasClassGroupJob=\(session.hasClassGroupJob)")
                            return !hasExistingJob && !session.hasClassGroupJob
                        } else {
                            print("📋 Checking session \(session.id): hasExistingJob=\(hasExistingJob), hasClassCandids=\(session.hasClassCandids)")
                            return !hasExistingJob && !session.hasClassCandids
                        }
                    }
                    
                    print("Available sessions without jobs: \(availableSessions.count)")
                    completion(.success(availableSessions))
                }
            }
    }
    
    // MARK: - Create/Update Operations
    
    /// Create a new class group job
    func createClassGroupJob(sessionId: String, sessionDate: Date, schoolId: String, schoolName: String, organizationId: String, jobType: String, completion: @escaping (Result<String, Error>) -> Void) {
        let job = ClassGroupJob(
            sessionId: sessionId,
            sessionDate: sessionDate,
            schoolId: schoolId,
            schoolName: schoolName,
            organizationId: organizationId,
            jobType: jobType,
            classGroups: [], // Start with empty array
            createdBy: Auth.auth().currentUser?.uid ?? "",
            lastModifiedBy: Auth.auth().currentUser?.uid ?? ""
        )
        
        db.collection(collectionName).document(job.id).setData(job.toFirestoreData()) { [weak self] error in
            if let error = error {
                print("Error creating class group job: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                print("Successfully created class group job: \(job.id)")
                // Update session to mark it has a job based on type
                self?.updateSessionHasJob(sessionId: sessionId, jobType: jobType, hasJob: true) { _ in
                    completion(.success(job.id))
                }
            }
        }
    }
    
    /// Add a class group to an existing job
    func addClassGroup(toJobId jobId: String, classGroup: ClassGroup, completion: @escaping (Result<Void, Error>) -> Void) {
        let docRef = db.collection(collectionName).document(jobId)
        
        docRef.updateData([
            "classGroups": FieldValue.arrayUnion([classGroup.toFirestoreData()]),
            "updatedAt": FieldValue.serverTimestamp(),
            "lastModifiedBy": Auth.auth().currentUser?.uid ?? ""
        ]) { error in
            if let error = error {
                print("Error adding class group: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                print("Successfully added class group to job: \(jobId)")
                completion(.success(()))
            }
        }
    }
    
    /// Update a specific class group in a job
    func updateClassGroup(jobId: String, classGroup: ClassGroup, completion: @escaping (Result<Void, Error>) -> Void) {
        // First, get the current job
        db.collection(collectionName).document(jobId).getDocument { [weak self] snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let snapshot = snapshot,
                  let job = ClassGroupJob(from: snapshot) else {
                completion(.failure(NSError(domain: "ClassGroupJobService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Job not found"])))
                return
            }
            
            // Update the class group in the array
            var updatedGroups = job.classGroups
            if let index = updatedGroups.firstIndex(where: { $0.id == classGroup.id }) {
                updatedGroups[index] = classGroup
            }
            
            // Update the document
            self?.db.collection(self?.collectionName ?? "").document(jobId).updateData([
                "classGroups": updatedGroups.map { $0.toFirestoreData() },
                "updatedAt": FieldValue.serverTimestamp(),
                "lastModifiedBy": Auth.auth().currentUser?.uid ?? ""
            ]) { error in
                if let error = error {
                    print("Error updating class group: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    print("Successfully updated class group in job: \(jobId)")
                    completion(.success(()))
                }
            }
        }
    }
    
    /// Delete a class group from a job
    func deleteClassGroup(fromJobId jobId: String, classGroupId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // First, get the current job
        db.collection(collectionName).document(jobId).getDocument { [weak self] snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let snapshot = snapshot,
                  let job = ClassGroupJob(from: snapshot) else {
                completion(.failure(NSError(domain: "ClassGroupJobService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Job not found"])))
                return
            }
            
            // Remove the class group from the array
            let updatedGroups = job.classGroups.filter { $0.id != classGroupId }
            
            // Update the document
            self?.db.collection(self?.collectionName ?? "").document(jobId).updateData([
                "classGroups": updatedGroups.map { $0.toFirestoreData() },
                "updatedAt": FieldValue.serverTimestamp(),
                "lastModifiedBy": Auth.auth().currentUser?.uid ?? ""
            ]) { error in
                if let error = error {
                    print("Error deleting class group: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    print("Successfully deleted class group from job: \(jobId)")
                    completion(.success(()))
                }
            }
        }
    }
    
    // MARK: - Delete Operations
    
    /// Delete a class group job
    func deleteClassGroupJob(id: String, sessionId: String, jobType: String, completion: @escaping (Result<Void, Error>) -> Void) {
        db.collection(collectionName).document(id).delete { [weak self] error in
            if let error = error {
                print("Error deleting class group job: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                print("Successfully deleted class group job: \(id)")
                // Update session to mark it no longer has a job based on type
                self?.updateSessionHasJob(sessionId: sessionId, jobType: jobType, hasJob: false) { _ in
                    completion(.success(()))
                }
            }
        }
    }
    
    // MARK: - Real-time Listeners
    
    /// Set up real-time listener for organization's class group jobs
    func startListening(organizationId: String) {
        stopListening()
        
        isLoading = true
        
        listener = db.collection(collectionName)
            .whereField("organizationId", isEqualTo: organizationId)
            .order(by: "sessionDate", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                self.isLoading = false
                
                if let error = error {
                    print("Error listening to class group jobs: \(error.localizedDescription)")
                    self.error = error
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.classGroupJobs = []
                    return
                }
                
                self.classGroupJobs = documents.compactMap { ClassGroupJob(from: $0) }
                print("Real-time update: \(self.classGroupJobs.count) class group jobs")
            }
    }
    
    /// Stop listening to real-time updates
    func stopListening() {
        listener?.remove()
        listener = nil
    }
    
    // MARK: - Private Helper Methods
    
    private func updateSessionHasJob(sessionId: String, jobType: String, hasJob: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        let fieldName = jobType == "classGroups" ? "hasClassGroupJob" : "hasClassCandids"
        
        db.collection(sessionsCollection).document(sessionId).updateData([
            fieldName: hasJob
        ]) { error in
            if let error = error {
                print("Error updating session \(fieldName): \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                print("Successfully updated session \(sessionId) \(fieldName) to \(hasJob)")
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Export Operations
    
    /// Export class group jobs to CSV
    func exportToCSV(jobs: [ClassGroupJob]) -> String {
        var csv = "Date,School,Grade,Teacher,Images,Notes\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        
        for job in jobs {
            for group in job.classGroups {
                let escapedDate = escapeCSVField(dateFormatter.string(from: job.sessionDate))
                let escapedSchool = escapeCSVField(job.schoolName)
                let escapedGrade = escapeCSVField(group.grade)
                let escapedTeacher = escapeCSVField(group.teacher)
                let escapedImages = escapeCSVField(group.imageNumbers)
                let escapedNotes = escapeCSVField(group.notes)
                
                csv += "\(escapedDate),\(escapedSchool),\(escapedGrade),\(escapedTeacher),\(escapedImages),\(escapedNotes)\n"
            }
        }
        
        return csv
    }
    
    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
}