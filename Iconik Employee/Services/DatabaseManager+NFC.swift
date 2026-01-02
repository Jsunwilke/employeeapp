import Foundation
import Supabase
import Combine

// MARK: - NFC SD Tracker Manager
// Uses Supabase for data persistence

// Singleton manager for NFC functionality
class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    private var supabase: SupabaseClient { SupabaseManager.shared.client }

    private init() {}

    // Published properties for UI updates
    @Published var isLoading = false
    @Published var loadingMessage = ""

    // Cache for schools data to prevent unnecessary updates
    private var lastSchoolsData: [SchoolItem]?
    private let schoolsDataQueue = DispatchQueue(label: "com.iconik.schoolsdata", attributes: .concurrent)

    // Store realtime channels for cleanup
    private var photographersChannel: RealtimeChannelV2?
    private var schoolsChannel: RealtimeChannelV2?
    
    // MARK: - Save Record (SD Card)
    func saveRecord(timestamp: Date,
                   photographer: String,
                   cardNumber: String,
                   school: String,
                   status: String,
                   uploadedFromJasonsHouse: String?,
                   uploadedFromAndysHouse: String?,
                   organizationID: String,
                   userId: String,
                   completion: @escaping (Result<String, Error>) -> Void) {

        // Check if we're online
        if OfflineDataManager.shared.isOnline {
            Task {
                do {
                    // Create record data with snake_case field names
                    // Note: photographer name is derived from user_id via join, not stored directly
                    var recordData: [String: AnyJSON] = [
                        "id": .string(UUID().uuidString.lowercased()),
                        "card_number": .string(cardNumber),
                        "school": .string(school),
                        "status": .string(status),
                        "user_id": .string(userId),
                        "organization_id": .string(organizationID),
                        "updated_at": .string(timestamp.ISO8601Format())
                    ]

                    // Add upload location fields if status is "Uploaded"
                    if status.lowercased() == "uploaded" {
                        if let jasonHouse = uploadedFromJasonsHouse, !jasonHouse.isEmpty {
                            recordData["uploaded_from_jasons_house"] = .string(jasonHouse)
                        }
                        if let andyHouse = uploadedFromAndysHouse, !andyHouse.isEmpty {
                            recordData["uploaded_from_andys_house"] = .string(andyHouse)
                        }
                    }

                    try await supabase
                        .from("records")
                        .insert(recordData)
                        .execute()

                    await MainActor.run {
                        completion(.success("SD card scan saved successfully"))
                    }
                } catch {
                    await MainActor.run {
                        completion(.failure(error))
                    }
                }
            }
        } else {
            // Handle offline saving
            let record = NFCRecord(
                timestamp: timestamp,
                photographer: photographer,
                cardNumber: cardNumber,
                school: school,
                status: status,
                uploadedFromJasonsHouse: uploadedFromJasonsHouse,
                uploadedFromAndysHouse: uploadedFromAndysHouse,
                organizationID: organizationID,
                userId: userId
            )
            OfflineDataManager.shared.addOfflineRecord(record: record)
            completion(.success("SD card scan saved offline. Will sync when connection is restored."))
        }
    }
    
    // MARK: - Fetch Records (SD Card)
    func fetchRecords(field: String,
                     value: String,
                     organizationID: String,
                     completion: @escaping (Result<[NFCRecord], Error>) -> Void) {

        // Check if we're online
        print("DEBUG fetchRecords: Starting fetch for org \(organizationID), field: \(field), value: \(value)")
        print("DEBUG fetchRecords: Online status: \(OfflineDataManager.shared.isOnline)")

        if OfflineDataManager.shared.isOnline {
            Task {
                do {
                    // Decodable struct for Supabase response
                    // Note: photographer name is not stored directly - use user_id to join with users table
                    struct RecordDTO: Decodable {
                        let id: String
                        let card_number: String?
                        let school: String?
                        let status: String?
                        let user_id: String?
                        let organization_id: String?
                        let timestamp: Date?
                        let uploaded_from_jasons_house: Bool?  // Database stores as Bool
                        let uploaded_from_andys_house: Bool?   // Database stores as Bool
                    }

                    print("DEBUG fetchRecords: Querying records table...")
                    var query = supabase
                        .from("records")
                        .select()
                        .eq("organization_id", value: organizationID)

                    // Add field filter if not "all"
                    if field.lowercased() != "all" {
                        let snakeField = self.toSnakeCase(field)
                        query = query.eq(snakeField, value: value)
                    }

                    let recordDTOs: [RecordDTO] = try await query.execute().value
                    print("DEBUG fetchRecords: Query returned \(recordDTOs.count) records")

                    // Convert DTOs to NFCRecord
                    // Note: photographer name will need to be looked up via user_id join
                    let records = recordDTOs.map { dto -> NFCRecord in
                        NFCRecord(
                            id: dto.id,
                            timestamp: dto.timestamp ?? Date(),
                            photographer: "", // Name looked up via user_id
                            cardNumber: dto.card_number ?? "",
                            school: dto.school ?? "",
                            status: dto.status ?? "",
                            uploadedFromJasonsHouse: dto.uploaded_from_jasons_house == true ? "Yes" : nil,
                            uploadedFromAndysHouse: dto.uploaded_from_andys_house == true ? "Yes" : nil,
                            organizationID: dto.organization_id ?? "",
                            userId: dto.user_id ?? ""
                        )
                    }

                    // Cache records for offline use
                    OfflineDataManager.shared.cacheRecords(records: records)

                    await MainActor.run {
                        completion(.success(records))
                    }
                } catch {
                    // Try to get cached data if there's an error
                    print("DEBUG fetchRecords: ERROR - \(error)")
                    print("DEBUG fetchRecords: Error details - \(String(describing: error))")
                    await MainActor.run {
                        if let cachedRecords = OfflineDataManager.shared.getCachedRecords() {
                            print("DEBUG fetchRecords: Using \(cachedRecords.count) cached records")
                            let filteredRecords = self.filterCachedRecords(
                                records: cachedRecords,
                                field: field,
                                value: value,
                                organizationID: organizationID
                            )
                            completion(.success(filteredRecords))
                        } else {
                            print("DEBUG fetchRecords: No cached records available")
                            completion(.failure(error))
                        }
                    }
                }
            }
        } else {
            // Offline mode - use cached data
            if let cachedRecords = OfflineDataManager.shared.getCachedRecords() {
                let filteredRecords = filterCachedRecords(
                    records: cachedRecords,
                    field: field,
                    value: value,
                    organizationID: organizationID
                )
                completion(.success(filteredRecords))
            } else {
                let error = NSError(domain: "com.iconikstudio.sdtracker", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "No cached SD card data available while offline"
                ])
                completion(.failure(error))
            }
        }
    }

    // Helper to convert camelCase to snake_case
    private func toSnakeCase(_ input: String) -> String {
        let pattern = "([a-z])([A-Z])"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: input.count)
        return regex?.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: "$1_$2").lowercased() ?? input.lowercased()
    }
    
    // Helper method to filter cached records
    private func filterCachedRecords(records: [NFCRecord],
                                   field: String,
                                   value: String,
                                   organizationID: String) -> [NFCRecord] {
        let orgRecords = records.filter { $0.organizationID == organizationID }
        
        if field.lowercased() == "all" {
            return orgRecords
        } else {
            return orgRecords.filter { record in
                switch field.lowercased() {
                case "cardnumber":
                    return record.cardNumber == value
                case "photographer":
                    return record.photographer == value
                case "school":
                    return record.school == value
                case "status":
                    return record.status.lowercased() == value.lowercased()
                default:
                    return false
                }
            }
        }
    }
    
    // MARK: - Save Job Box Record
    func saveJobBoxRecord(timestamp: Date,
                        photographer: String,
                        boxNumber: String,
                        school: String,
                        schoolId: String? = nil,
                        status: String,
                        organizationID: String,
                        userId: String,
                        shiftUid: String? = nil,
                        completion: @escaping (Result<String, Error>) -> Void) {

        // Check if we're online
        if OfflineDataManager.shared.isOnline {
            Task {
                do {
                    let jobBoxId = UUID().uuidString.lowercased()

                    // Create job box data with snake_case field names
                    // Note: photographer name is derived from user_id via join, not stored directly
                    var jobBoxData: [String: AnyJSON] = [
                        "id": .string(jobBoxId),
                        "box_number": .string(boxNumber),
                        "school": .string(school),
                        "status": .string(status),
                        "user_id": .string(userId),
                        "organization_id": .string(organizationID),
                        "updated_at": .string(timestamp.ISO8601Format())
                    ]

                    // Add optional fields if present
                    if let schoolId = schoolId {
                        jobBoxData["school_id"] = .string(schoolId)
                    }
                    if let shiftUid = shiftUid {
                        jobBoxData["shift_uid"] = .string(shiftUid)
                    }

                    try await supabase
                        .from("job_boxes")
                        .insert(jobBoxData)
                        .execute()

                    // Update the session to mark it as assigned
                    if let shiftUid = shiftUid {
                        do {
                            let sessionUpdate: [String: AnyJSON] = [
                                "has_job_box_assigned": .bool(true),
                                "job_box_record_id": .string(jobBoxId)
                            ]
                            try await supabase
                                .from("sessions")
                                .update(sessionUpdate)
                                .eq("id", value: shiftUid)
                                .execute()
                            print("✅ Successfully updated session \(shiftUid) with job box assignment")
                        } catch {
                            print("⚠️ Warning: Failed to update session assignment status: \(error)")
                            // Still consider the job box save successful
                        }
                    }

                    await MainActor.run {
                        completion(.success("Job box record saved successfully"))
                    }
                } catch {
                    await MainActor.run {
                        completion(.failure(error))
                    }
                }
            }
        } else {
            // Handle offline saving
            let recordData: [String: Any] = [
                "boxNumber": boxNumber,
                "school": school,
                "status": status,
                "photographer": photographer,
                "userId": userId,
                "organizationID": organizationID,
                "timestamp": timestamp,
                "schoolId": schoolId as Any,
                "shiftUid": shiftUid as Any
            ]
            OfflineDataManager.shared.addPendingOperation(
                type: .add,
                collectionPath: "jobBoxes",
                data: recordData
            )
            completion(.success("Job box record saved offline. Will sync when connection is restored."))
        }
    }
    
    // MARK: - Fetch Job Box Records
    func fetchJobBoxRecords(field: String,
                          value: String,
                          organizationID: String,
                          completion: @escaping (Result<[JobBox], Error>) -> Void) {

        // Check if we're online
        if OfflineDataManager.shared.isOnline {
            Task {
                do {
                    // Decodable struct for Supabase response
                    // Note: photographer name is not stored directly - use user_id to join with users table
                    struct JobBoxDTO: Decodable {
                        let id: String
                        let box_number: String?
                        let school: String?
                        let school_id: String?
                        let status: String?
                        let user_id: String?
                        let organization_id: String?
                        let updated_at: Date?
                        let shift_uid: String?
                    }

                    var query = supabase
                        .from("job_boxes")
                        .select()
                        .eq("organization_id", value: organizationID)

                    if field.lowercased() != "all" {
                        let snakeField = self.toSnakeCase(field)
                        query = query.eq(snakeField, value: value)
                    }

                    let jobBoxDTOs: [JobBoxDTO] = try await query.execute().value

                    // Convert DTOs to JobBox
                    // Note: photographer name will need to be looked up via user_id join
                    let records = jobBoxDTOs.map { dto -> JobBox in
                        JobBox(
                            id: dto.id,
                            shift_uid: dto.shift_uid ?? "",
                            status: dto.status ?? "",
                            photographer: "", // Name looked up via user_id
                            updated_at: dto.updated_at,
                            box_number: dto.box_number,
                            organization_id: dto.organization_id ?? "",
                            school: dto.school,
                            school_id: dto.school_id,
                            user_id: dto.user_id
                        )
                    }

                    await MainActor.run {
                        completion(.success(records))
                    }
                } catch {
                    await MainActor.run {
                        completion(.failure(error))
                    }
                }
            }
        } else {
            // Offline mode - return empty array for now
            let error = NSError(domain: "com.iconikstudio.sdtracker", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Job box data not available offline"
            ])
            completion(.failure(error))
        }
    }
    
    // MARK: - Listen for Photographers
    func listenForPhotographers(inOrgID orgID: String, completion: @escaping ([String]) -> Void) {
        Task {
            // First, fetch initial data
            await fetchAndNotifyPhotographers(orgID: orgID, completion: completion)

            // Then set up realtime subscription
            let channelKey = "photographers_\(orgID)"

            // Unsubscribe from existing channel if any
            if let existingChannel = photographersChannel {
                await existingChannel.unsubscribe()
            }

            let channel = supabase.channel(channelKey)

            // Listen for changes to users for this organization
            let changeStream = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "users",
                filter: "organization_id=eq.\(orgID)"
            )

            // Start listening for changes
            Task {
                for await _ in changeStream {
                    // Refetch all photographers when any change occurs
                    await self.fetchAndNotifyPhotographers(orgID: orgID, completion: completion)
                }
            }

            await channel.subscribe()
            photographersChannel = channel
        }
    }

    // Helper method to fetch photographers and notify
    private func fetchAndNotifyPhotographers(orgID: String, completion: @escaping ([String]) -> Void) async {
        do {
            struct UserDTO: Decodable {
                let first_name: String?
                let is_active: Bool?
            }

            let users: [UserDTO] = try await supabase
                .from("users")
                .select("first_name, is_active")
                .eq("organization_id", value: orgID)
                .eq("is_active", value: true)
                .execute()
                .value

            let photographers = users.compactMap { $0.first_name }.sorted()

            // Cache the photographer names
            if let encoded = try? JSONEncoder().encode(photographers) {
                UserDefaults.standard.set(encoded, forKey: "photographerNames")
            }

            await MainActor.run {
                completion(photographers)
            }
        } catch {
            print("Error fetching photographers: \(error)")
            await MainActor.run {
                completion([])
            }
        }
    }
    
    // MARK: - Listen for Schools Data

    // Force refresh schools from server (for pull-to-refresh)
    func refreshSchoolsFromServer(forOrgID orgID: String, completion: @escaping ([SchoolItem]) -> Void) {
        Task {
            await fetchAndProcessSchools(orgID: orgID, completion: completion)
            print("Schools refreshed from server")
        }
    }

    func listenForSchoolsData(forOrgID orgID: String, completion: @escaping ([SchoolItem]) -> Void) {
        Task {
            // First, fetch initial data
            await fetchAndProcessSchools(orgID: orgID, completion: completion)

            // Then set up realtime subscription
            let channelKey = "schools_\(orgID)"

            // Unsubscribe from existing channel if any
            if let existingChannel = schoolsChannel {
                await existingChannel.unsubscribe()
            }

            let channel = supabase.channel(channelKey)

            // Listen for changes to schools for this organization
            let changeStream = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "schools",
                filter: "organization_id=eq.\(orgID)"
            )

            // Start listening for changes
            Task {
                for await _ in changeStream {
                    // Refetch all schools when any change occurs
                    await self.fetchAndProcessSchools(orgID: orgID, completion: completion)
                }
            }

            await channel.subscribe()
            schoolsChannel = channel
        }
    }

    // Helper method to fetch and process schools
    private func fetchAndProcessSchools(orgID: String, completion: @escaping ([SchoolItem]) -> Void) async {
        do {
            // SchoolDTO with flexible coordinates decoding (can be string OR object)
            struct SchoolDTO: Decodable {
                let id: String
                let name: String?
                let street: String?
                let city: String?
                let state: String?
                let zip: String?
                let coordinates: String?

                enum CodingKeys: String, CodingKey {
                    case id, name, street, city, state, zip, coordinates
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    id = try container.decode(String.self, forKey: .id)
                    name = try container.decodeIfPresent(String.self, forKey: .name)
                    street = try container.decodeIfPresent(String.self, forKey: .street)
                    city = try container.decodeIfPresent(String.self, forKey: .city)
                    state = try container.decodeIfPresent(String.self, forKey: .state)
                    zip = try container.decodeIfPresent(String.self, forKey: .zip)

                    // Handle coordinates as either String or Object
                    if let coordString = try? container.decodeIfPresent(String.self, forKey: .coordinates) {
                        coordinates = coordString
                    } else if let coordObject = try? container.decodeIfPresent([String: Double].self, forKey: .coordinates) {
                        // Convert {lat: x, lng: y} to "lat,lng" string
                        if let lat = coordObject["lat"], let lng = coordObject["lng"] {
                            coordinates = "\(lat),\(lng)"
                        } else {
                            coordinates = nil
                        }
                    } else {
                        coordinates = nil
                    }
                }
            }

            let schoolDTOs: [SchoolDTO] = try await supabase
                .from("schools")
                .select("id, name, street, city, state, zip, coordinates")
                .eq("organization_id", value: orgID)
                .order("name")
                .execute()
                .value

            let schools = schoolDTOs.compactMap { dto -> SchoolItem? in
                guard let name = dto.name else { return nil }

                // Build address from available fields
                var addressComponents: [String] = []
                if let street = dto.street, !street.isEmpty {
                    addressComponents.append(street)
                }
                if let city = dto.city, !city.isEmpty {
                    addressComponents.append(city)
                }
                if let state = dto.state, !state.isEmpty {
                    addressComponents.append(state)
                }
                if let zipCode = dto.zip, !zipCode.isEmpty {
                    addressComponents.append(zipCode)
                }

                let address = addressComponents.isEmpty ? name : addressComponents.joined(separator: ", ")

                return SchoolItem(
                    id: dto.id,
                    name: name,
                    address: address,
                    coordinates: dto.coordinates
                )
            }

            // Thread-safe check if data has changed
            schoolsDataQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                let oldSchools = self.lastSchoolsData
                let schoolsChanged = self.hasSchoolsDataChanged(oldSchools: oldSchools, newSchools: schools)

                if schoolsChanged {
                    // Update the cached data
                    self.lastSchoolsData = schools

                    // Cache the school records to UserDefaults
                    if let encoded = try? JSONEncoder().encode(schools) {
                        UserDefaults.standard.set(encoded, forKey: "nfcSchools")
                    }

                    // Only call completion if data actually changed
                    DispatchQueue.main.async {
                        completion(schools)
                    }
                    print("Schools data updated - \(schools.count) schools")
                } else {
                    // Data hasn't changed, don't trigger an update
                    print("Schools data unchanged, skipping update")
                }
            }
        } catch {
            print("Error fetching schools: \(error)")
            await MainActor.run {
                completion([])
            }
        }
    }
    
    private func hasSchoolsDataChanged(oldSchools: [SchoolItem]?, newSchools: [SchoolItem]) -> Bool {
        guard let oldSchools = oldSchools else {
            // First load, always update
            return true
        }
        
        // Check if count is different
        if oldSchools.count != newSchools.count {
            return true
        }
        
        // Check if any school has changed by comparing sorted arrays
        let sortedOld = oldSchools.sorted { $0.id < $1.id }
        let sortedNew = newSchools.sorted { $0.id < $1.id }
        
        for (index, newSchool) in sortedNew.enumerated() {
            if index >= sortedOld.count {
                return true
            }
            
            let oldSchool = sortedOld[index]
            if oldSchool.id != newSchool.id ||
               oldSchool.name != newSchool.name ||
               oldSchool.address != newSchool.address ||
               oldSchool.coordinates != newSchool.coordinates {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Delete Operations

    func deleteRecord(recordID: String, completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                try await supabase
                    .from("records")
                    .delete()
                    .eq("id", value: recordID)
                    .execute()

                await MainActor.run {
                    completion(.success("Record deleted successfully"))
                }
            } catch {
                // Also mark for offline deletion if needed
                if !OfflineDataManager.shared.isOnline {
                    OfflineDataManager.shared.addPendingOperation(
                        type: .delete,
                        collectionPath: "records",
                        data: [:],
                        id: recordID
                    )
                    await MainActor.run {
                        completion(.success("Record marked for deletion when online"))
                    }
                } else {
                    await MainActor.run {
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    func deleteJobBoxRecord(recordID: String, completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                try await supabase
                    .from("job_boxes")
                    .delete()
                    .eq("id", value: recordID)
                    .execute()

                await MainActor.run {
                    completion(.success("Job box record deleted successfully"))
                }
            } catch {
                // Also mark for offline deletion if needed
                if !OfflineDataManager.shared.isOnline {
                    OfflineDataManager.shared.addPendingOperation(
                        type: .delete,
                        collectionPath: "jobBoxes",
                        data: [:],
                        id: recordID
                    )
                    await MainActor.run {
                        completion(.success("Job box record marked for deletion when online"))
                    }
                } else {
                    await MainActor.run {
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    // Debug helper to print job box document structure
    func debugPrintJobBoxDocuments(organizationID: String) {
        Task {
            do {
                struct JobBoxDebug: Decodable {
                    let id: String
                    let box_number: String?
                    let school: String?
                    let status: String?
                    let photographer: String?
                    let timestamp: Date?
                }

                let jobBoxes: [JobBoxDebug] = try await supabase
                    .from("job_boxes")
                    .select()
                    .eq("organization_id", value: organizationID)
                    .limit(1)
                    .execute()
                    .value

                guard let jobBox = jobBoxes.first else {
                    print("❌ DEBUG: No job box documents found")
                    return
                }

                print("📦 DEBUG: Job Box Document Structure:")
                print("Document ID: \(jobBox.id)")
                print("  box_number: \(jobBox.box_number ?? "nil")")
                print("  school: \(jobBox.school ?? "nil")")
                print("  status: \(jobBox.status ?? "nil")")
                print("  photographer: \(jobBox.photographer ?? "nil")")
                print("  timestamp: \(String(describing: jobBox.timestamp))")
            } catch {
                print("❌ DEBUG: Error fetching job box documents: \(error)")
            }
        }
    }

    // MARK: - Get Highest Box Number
    func getHighestBoxNumber(organizationID: String, completion: @escaping (Result<Int, Error>) -> Void) {
        Task {
            do {
                struct BoxNumberDTO: Decodable {
                    let box_number: String?
                }

                let jobBoxes: [BoxNumberDTO] = try await supabase
                    .from("job_boxes")
                    .select("box_number")
                    .eq("organization_id", value: organizationID)
                    .execute()
                    .value

                let boxNumbers = jobBoxes.compactMap { dto -> Int? in
                    guard let boxNumberStr = dto.box_number else { return nil }
                    return Int(boxNumberStr)
                }

                if let maxNumber = boxNumbers.max() {
                    await MainActor.run {
                        completion(.success(maxNumber))
                    }
                } else {
                    await MainActor.run {
                        completion(.success(3000)) // Default if no boxes found
                    }
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Cleanup

    func stopListening() {
        Task {
            if let channel = photographersChannel {
                await channel.unsubscribe()
                photographersChannel = nil
            }
            if let channel = schoolsChannel {
                await channel.unsubscribe()
                schoolsChannel = nil
            }
        }
    }
}