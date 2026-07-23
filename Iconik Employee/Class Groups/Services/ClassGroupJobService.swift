import Foundation
import Supabase
import Combine

class ClassGroupJobService: ObservableObject {
    static let shared = ClassGroupJobService()
    private let supabase = SupabaseManager.shared.client
    private let tableName = "class_group_jobs"
    private let sessionsTable = "sessions"

    @Published var classGroupJobs: [ClassGroupJob] = []
    @Published var isLoading = false
    @Published var error: Error?

    private var channel: RealtimeChannelV2?

    private init() {}

    deinit {
        Task {
            await channel?.unsubscribe()
        }
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

        Task {
            do {
                let jobs: [ClassGroupJob] = try await supabase
                    .from(tableName)
                    .select()
                    .eq("organization_id", value: orgId)
                    .order("session_date", ascending: false)
                    .execute()
                    .value

                print("Successfully fetched \(jobs.count) class group jobs")
                await MainActor.run {
                    completion(.success(jobs))
                }
            } catch {
                print("Error fetching class group jobs: \(error.localizedDescription)")
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Fetch class group job for a specific session
    func fetchClassGroupJob(forSession sessionId: String, completion: @escaping (Result<ClassGroupJob?, Error>) -> Void) {
        print("Fetching class group job for session: \(sessionId)")

        Task {
            do {
                let jobs: [ClassGroupJob] = try await supabase
                    .from(tableName)
                    .select()
                    .eq("session_id", value: sessionId)
                    .limit(1)
                    .execute()
                    .value

                await MainActor.run {
                    completion(.success(jobs.first))
                }
            } catch {
                print("Error fetching class group job: \(error.localizedDescription)")
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Get upcoming sessions (next 2 weeks) without class group jobs
    func getUpcomingSessions(organizationId: String, jobType: String = "classGroups", completion: @escaping (Result<[Session], Error>) -> Void) {
        print("📋 Fetching upcoming sessions for jobType: \(jobType)")

        let now = Date()
        let twoWeeksFromNow = Calendar.current.date(byAdding: .weekOfYear, value: 2, to: now) ?? now

        // Format dates for query
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startDateStr = dateFormatter.string(from: now)
        let endDateStr = dateFormatter.string(from: twoWeeksFromNow)

        Task {
            do {
                // First, get all sessions in the date range
                let allSessions: [Session] = try await supabase
                    .from(sessionsTable)
                    .select()
                    .eq("organization_id", value: organizationId)
                    .gte("date", value: startDateStr)
                    .lte("date", value: endDateStr)
                    .order("date")
                    .execute()
                    .value

                print("Found \(allSessions.count) total sessions in date range")

                // Filter to only include sessions with schools
                let sessionsWithSchools = allSessions.filter { $0.schoolId != nil && !$0.schoolName.isEmpty }

                if sessionsWithSchools.isEmpty {
                    print("No sessions with schools found")
                    await MainActor.run {
                        completion(.success([]))
                    }
                    return
                }

                // Get existing jobs of this type. Decode only the selected column —
                // decoding these rows as full ClassGroupJob throws (id/dates absent),
                // which errored the whole session list whenever a job already existed.
                // No server-side `in` filter: session ids are compared lowercased
                // throughout, but a Postgres IN is case-sensitive and historical id
                // casing varies — clubs have no legacy session flag to mask a missed
                // match, so fetch the org's jobs of this type and compare client-side.
                struct SessionIdRow: Decodable {
                    let session_id: String?
                }

                let existingJobs: [SessionIdRow] = try await supabase
                    .from(tableName)
                    .select("session_id")
                    .eq("organization_id", value: organizationId)
                    .eq("job_type", value: jobType)
                    .execute()
                    .value

                var sessionIdsWithJobs = Set<String>()
                existingJobs.forEach { job in
                    if let sessionId = job.session_id {
                        sessionIdsWithJobs.insert(sessionId.lowercased())
                    }
                }

                print("Sessions with existing jobs: \(sessionIdsWithJobs)")

                // Filter out sessions based on job type
                let availableSessions = sessionsWithSchools.filter { session in
                    let hasExistingJob = sessionIdsWithJobs.contains(session.id.lowercased())
                    switch jobType {
                    case ClassGroupJobType.classGroups:
                        return !hasExistingJob && !session.hasClassGroupJob
                    case ClassGroupJobType.classCandids:
                        return !hasExistingJob && !session.hasClassCandids
                    default:
                        // Clubs (and any future type) have no legacy session flag.
                        return !hasExistingJob
                    }
                }

                print("Available sessions without jobs: \(availableSessions.count)")
                await MainActor.run {
                    completion(.success(availableSessions))
                }
            } catch {
                print("Error fetching sessions: \(error.localizedDescription)")
                await MainActor.run {
                    completion(.failure(error))
                }
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
            classGroups: [],
            createdBy: UserManager.shared.getCurrentUserIDUnified() ?? "",
            lastModifiedBy: UserManager.shared.getCurrentUserIDUnified() ?? ""
        )

        Task {
            do {
                try await supabase
                    .from(tableName)
                    .insert(job)
                    .execute()

                print("Successfully created class group job: \(job.id)")

                // Update session to mark it has a job based on type
                await updateSessionHasJob(sessionId: sessionId, jobType: jobType, hasJob: true)

                await MainActor.run {
                    completion(.success(job.id))
                }
            } catch {
                print("Error creating class group job: \(error.localizedDescription)")
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Add a class group to an existing job
    func addClassGroup(toJobId jobId: String, classGroup: ClassGroup, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                // First, get the current job
                let jobs: [ClassGroupJob] = try await supabase
                    .from(tableName)
                    .select()
                    .eq("id", value: jobId)
                    .limit(1)
                    .execute()
                    .value

                guard var job = jobs.first else {
                    throw NSError(domain: "ClassGroupJobService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Job not found"])
                }

                // Add the new class group
                var updatedGroups = job.class_groups
                updatedGroups.append(classGroup)

                // Update in database
                struct UpdateData: Encodable {
                    let class_groups: [ClassGroup]
                    let updated_at: Date
                    let last_modified_by: String
                }

                try await supabase
                    .from(tableName)
                    .update(UpdateData(
                        class_groups: updatedGroups,
                        updated_at: Date(),
                        last_modified_by: UserManager.shared.getCurrentUserIDUnified() ?? ""
                    ))
                    .eq("id", value: jobId)
                    .execute()

                print("Successfully added class group to job: \(jobId)")
                await MainActor.run {
                    completion(.success(()))
                }
            } catch {
                print("Error adding class group: \(error.localizedDescription)")
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Update a specific class group in a job
    func updateClassGroup(jobId: String, classGroup: ClassGroup, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                // First, get the current job
                let jobs: [ClassGroupJob] = try await supabase
                    .from(tableName)
                    .select()
                    .eq("id", value: jobId)
                    .limit(1)
                    .execute()
                    .value

                guard let job = jobs.first else {
                    throw NSError(domain: "ClassGroupJobService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Job not found"])
                }

                // Update the class group in the array
                var updatedGroups = job.class_groups
                if let index = updatedGroups.firstIndex(where: { $0.id == classGroup.id }) {
                    updatedGroups[index] = classGroup
                }

                // Update in database
                struct UpdateData: Encodable {
                    let class_groups: [ClassGroup]
                    let updated_at: Date
                    let last_modified_by: String
                }

                try await supabase
                    .from(tableName)
                    .update(UpdateData(
                        class_groups: updatedGroups,
                        updated_at: Date(),
                        last_modified_by: UserManager.shared.getCurrentUserIDUnified() ?? ""
                    ))
                    .eq("id", value: jobId)
                    .execute()

                print("Successfully updated class group in job: \(jobId)")
                await MainActor.run {
                    completion(.success(()))
                }
            } catch {
                print("Error updating class group: \(error.localizedDescription)")
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Delete a class group from a job
    func deleteClassGroup(fromJobId jobId: String, classGroupId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                // First, get the current job
                let jobs: [ClassGroupJob] = try await supabase
                    .from(tableName)
                    .select()
                    .eq("id", value: jobId)
                    .limit(1)
                    .execute()
                    .value

                guard let job = jobs.first else {
                    throw NSError(domain: "ClassGroupJobService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Job not found"])
                }

                // Remove the class group from the array
                let updatedGroups = job.class_groups.filter { $0.id != classGroupId }

                // Update in database
                struct UpdateData: Encodable {
                    let class_groups: [ClassGroup]
                    let updated_at: Date
                    let last_modified_by: String
                }

                try await supabase
                    .from(tableName)
                    .update(UpdateData(
                        class_groups: updatedGroups,
                        updated_at: Date(),
                        last_modified_by: UserManager.shared.getCurrentUserIDUnified() ?? ""
                    ))
                    .eq("id", value: jobId)
                    .execute()

                print("Successfully deleted class group from job: \(jobId)")
                await MainActor.run {
                    completion(.success(()))
                }
            } catch {
                print("Error deleting class group: \(error.localizedDescription)")
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Delete Operations

    /// Delete a class group job
    func deleteClassGroupJob(id: String, sessionId: String, jobType: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                try await supabase
                    .from(tableName)
                    .delete()
                    .eq("id", value: id)
                    .execute()

                print("Successfully deleted class group job: \(id)")

                // Update session to mark it no longer has a job based on type
                await updateSessionHasJob(sessionId: sessionId, jobType: jobType, hasJob: false)

                await MainActor.run {
                    completion(.success(()))
                }
            } catch {
                print("Error deleting class group job: \(error.localizedDescription)")
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Real-time Listeners

    /// Set up real-time listener for organization's class group jobs
    func startListening(organizationId: String) {
        stopListening()

        isLoading = true

        // Initial fetch
        Task {
            do {
                let jobs: [ClassGroupJob] = try await supabase
                    .from(tableName)
                    .select()
                    .eq("organization_id", value: organizationId)
                    .order("session_date", ascending: false)
                    .execute()
                    .value

                await MainActor.run {
                    self.classGroupJobs = jobs
                    self.isLoading = false
                }
            } catch {
                print("Error fetching class group jobs: \(error.localizedDescription)")
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }
            }
        }

        // Set up realtime subscription using realtimeV2
        let channel = supabase.realtimeV2.channel("class_group_jobs_\(organizationId)")

        let changeStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: tableName,
            filter: "organization_id=eq.\(organizationId)"
        )

        Task {
            for await change in changeStream {
                // Refetch on any change
                do {
                    let jobs: [ClassGroupJob] = try await supabase
                        .from(tableName)
                        .select()
                        .eq("organization_id", value: organizationId)
                        .order("session_date", ascending: false)
                        .execute()
                        .value

                    await MainActor.run {
                        self.classGroupJobs = jobs
                        print("Real-time update: \(jobs.count) class group jobs")
                    }
                } catch {
                    print("Error in realtime update: \(error)")
                }
            }
        }

        Task {
            await channel.subscribe()
        }

        self.channel = channel
    }

    /// Stop listening to real-time updates
    func stopListening() {
        Task {
            await channel?.unsubscribe()
        }
        channel = nil
    }

    /// Subscribe to updates for a specific job
    func subscribeToJobUpdates(jobId: String, callback: @escaping (Result<ClassGroupJob, Error>) -> Void) -> ListenerRegistrationWrapper {
        // Initial fetch
        Task {
            do {
                let jobs: [ClassGroupJob] = try await supabase
                    .from(tableName)
                    .select()
                    .eq("id", value: jobId)
                    .limit(1)
                    .execute()
                    .value

                if let job = jobs.first {
                    callback(.success(job))
                } else {
                    callback(.failure(NSError(domain: "ClassGroupJobService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Job not found"])))
                }
            } catch {
                callback(.failure(error))
            }
        }

        // Set up realtime subscription for this specific job using realtimeV2
        let channel = supabase.realtimeV2.channel("class_group_job_\(jobId)")

        let changeStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: tableName,
            filter: "id=eq.\(jobId)"
        )

        Task {
            for await _ in changeStream {
                // Refetch on any change
                do {
                    let jobs: [ClassGroupJob] = try await supabase
                        .from(tableName)
                        .select()
                        .eq("id", value: jobId)
                        .limit(1)
                        .execute()
                        .value

                    if let job = jobs.first {
                        callback(.success(job))
                    }
                } catch {
                    print("Error in realtime update for job \(jobId): \(error)")
                }
            }
        }

        Task {
            await channel.subscribe()
        }

        return ListenerRegistrationWrapper {
            Task {
                await channel.unsubscribe()
            }
        }
    }

    // MARK: - Private Helper Methods

    private func updateSessionHasJob(sessionId: String, jobType: String, hasJob: Bool) async {
        // Clubs have no session flag — only the two legacy types write one (D3).
        let fieldName: String
        switch jobType {
        case ClassGroupJobType.classGroups: fieldName = "has_class_group_job"
        case ClassGroupJobType.classCandids: fieldName = "has_class_candids"
        default: return
        }

        do {
            try await supabase
                .from(sessionsTable)
                .update([fieldName: hasJob])
                .eq("id", value: sessionId)
                .execute()

            print("Successfully updated session \(sessionId) \(fieldName) to \(hasJob)")
        } catch {
            print("Error updating session \(fieldName): \(error.localizedDescription)")
        }
    }

    // MARK: - Export Operations

    /// Export class group jobs to CSV. Headers follow the jobs' type when uniform
    /// (clubs relabel Grade→Club Name, Teacher→Advisor); mixed lists keep the defaults.
    func exportToCSV(jobs: [ClassGroupJob]) -> String {
        let types = Set(jobs.map { ClassGroupJobType.normalize($0.jobType) })
        let headerType = types.count == 1 ? types.first : ClassGroupJobType.defaultType
        let primaryHeader = ClassGroupJobType.primaryFieldLabel(headerType)
        let secondaryHeader = ClassGroupJobType.normalize(headerType) == ClassGroupJobType.clubs ? "Advisor" : "Teacher"
        var csv = "Date,School,\(primaryHeader),\(secondaryHeader),Images,Notes\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short

        for job in jobs {
            for group in job.class_groups {
                let escapedDate = escapeCSVField(dateFormatter.string(from: job.session_date))
                let escapedSchool = escapeCSVField(job.school_name)
                let escapedGrade = escapeCSVField(group.grade)
                let escapedTeacher = escapeCSVField(group.teacher)
                let escapedImages = escapeCSVField(group.image_numbers)
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
