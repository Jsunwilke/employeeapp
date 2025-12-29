import Foundation
import Supabase

// Model for roster entry (individual subject)
struct RosterEntry: Identifiable, Codable, Hashable {
    var id: String
    var lastName: String     // Maps to "Name" in Captura
    var firstName: String    // Maps to "Subject ID" in Captura
    var teacher: String      // Maps to "Special" in Captura
    var group: String        // Maps to "Sport/Team" in Captura
    var email: String
    var phone: String
    var imageNumbers: String
    var notes: String
    var wasBlank: Bool       // Track if entry was created as blank
    var isFilledBlank: Bool // Track if blank entry was filled with a name
    
    init(id: String = UUID().uuidString,
         lastName: String = "",
         firstName: String = "",
         teacher: String = "",
         group: String = "",
         email: String = "",
         phone: String = "",
         imageNumbers: String = "",
         notes: String = "",
         wasBlank: Bool = true,
         isFilledBlank: Bool = false) {
        self.id = id
        self.lastName = lastName
        self.firstName = firstName
        self.teacher = teacher
        self.group = group
        self.email = email
        self.phone = phone
        self.imageNumbers = imageNumbers
        self.notes = notes
        self.wasBlank = wasBlank
        // If creating with a lastName, mark as filled
        self.isFilledBlank = isFilledBlank || !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // Create from a dictionary - handle field mapping
    init?(from dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String else {
            return nil
        }
        
        self.id = id
        self.lastName = dictionary["lastName"] as? String ?? ""      // Maps to "Name" in Captura
        self.firstName = dictionary["firstName"] as? String ?? ""    // Maps to "Subject ID" in Captura
        self.teacher = dictionary["teacher"] as? String ?? ""        // Maps to "Special" in Captura
        self.group = dictionary["group"] as? String ?? ""            // Maps to "Sport/Team" in Captura
        self.email = dictionary["email"] as? String ?? ""
        self.phone = dictionary["phone"] as? String ?? ""
        self.imageNumbers = dictionary["imageNumbers"] as? String ?? ""
        self.notes = dictionary["notes"] as? String ?? ""
        self.wasBlank = dictionary["wasBlank"] as? Bool ?? true
        self.isFilledBlank = dictionary["isFilledBlank"] as? Bool ?? false
    }
    
    // Convert to dictionary for database storage
    func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "lastName": lastName,          // Maps to "Name" in Captura
            "firstName": firstName,        // Maps to "Subject ID" in Captura
            "teacher": teacher,            // Maps to "Special" in Captura
            "group": group,                // Maps to "Sport/Team" in Captura
            "email": email,
            "phone": phone,
            "imageNumbers": imageNumbers,
            "notes": notes,
            "wasBlank": wasBlank,
            "isFilledBlank": isFilledBlank
        ]
    }
}

// Model for group image tracking
struct GroupImage: Identifiable, Codable, Hashable {
    var id: String
    var description: String
    var imageNumbers: String
    var notes: String
    var sport: String?  // Selected sport from roster
    var gender: String?  // Gender (Boys, Girls, Co-ed)
    var teamLevel: String?  // Team level (Varsity, JV, etc.)
    
    init(id: String = UUID().uuidString,
         description: String = "",
         imageNumbers: String = "",
         notes: String = "",
         sport: String? = nil,
         gender: String? = nil,
         teamLevel: String? = nil) {
        self.id = id
        self.description = description
        self.imageNumbers = imageNumbers
        self.notes = notes
        self.sport = sport
        self.gender = gender
        self.teamLevel = teamLevel
    }
    
    // Create from a dictionary
    init?(from dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String else {
            return nil
        }
        
        self.id = id
        self.description = dictionary["description"] as? String ?? ""
        self.imageNumbers = dictionary["imageNumbers"] as? String ?? ""
        self.notes = dictionary["notes"] as? String ?? ""
        self.sport = dictionary["sport"] as? String
        self.gender = dictionary["gender"] as? String
        self.teamLevel = dictionary["teamLevel"] as? String
    }
    
    // Convert to dictionary for database storage
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "description": description,
            "imageNumbers": imageNumbers,
            "notes": notes
        ]
        
        if let sport = sport {
            dict["sport"] = sport
        }
        if let gender = gender {
            dict["gender"] = gender
        }
        if let teamLevel = teamLevel {
            dict["teamLevel"] = teamLevel
        }
        
        return dict
    }
}

// Main sports shoot model
struct SportsShoot: Identifiable, Codable {
    var id: String
    var schoolName: String
    var schoolId: String?
    var sportName: String
    var seasonType: String?
    var shootDate: Date
    var location: String
    var photographer: String
    var roster: [RosterEntry]
    var groupImages: [GroupImage]
    var additionalNotes: String
    var organizationID: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    
    init(id: String = UUID().uuidString,
         schoolName: String = "",
         schoolId: String? = nil,
         sportName: String = "",
         seasonType: String? = nil,
         shootDate: Date = Date(),
         location: String = "",
         photographer: String = "",
         roster: [RosterEntry] = [],
         groupImages: [GroupImage] = [],
         additionalNotes: String = "",
         organizationID: String = "",
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         isArchived: Bool = false) {
        self.id = id
        self.schoolName = schoolName
        self.schoolId = schoolId
        self.sportName = sportName
        self.seasonType = seasonType
        self.shootDate = shootDate
        self.location = location
        self.photographer = photographer
        self.roster = roster
        self.groupImages = groupImages
        self.additionalNotes = additionalNotes
        self.organizationID = organizationID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }
    
    // Adding a custom Codable implementation to handle optional fields and field mapping
    enum CodingKeys: String, CodingKey {
        case id, schoolName, schoolId, sportName, seasonType, shootDate, location, photographer
        case roster, groupImages, additionalNotes, organizationID
        case createdAt, updatedAt, isArchived
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        schoolName = try container.decodeIfPresent(String.self, forKey: .schoolName) ?? ""
        schoolId = try container.decodeIfPresent(String.self, forKey: .schoolId)
        sportName = try container.decodeIfPresent(String.self, forKey: .sportName) ?? ""
        seasonType = try container.decodeIfPresent(String.self, forKey: .seasonType)
        shootDate = try container.decodeIfPresent(Date.self, forKey: .shootDate) ?? Date()
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        photographer = try container.decodeIfPresent(String.self, forKey: .photographer) ?? ""
        roster = try container.decodeIfPresent([RosterEntry].self, forKey: .roster) ?? []
        groupImages = try container.decodeIfPresent([GroupImage].self, forKey: .groupImages) ?? []
        additionalNotes = try container.decodeIfPresent(String.self, forKey: .additionalNotes) ?? ""
        organizationID = try container.decodeIfPresent(String.self, forKey: .organizationID) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
    
}

// Supabase-compatible model for sports shoots
struct SupabaseSportsShoot: Codable {
    let id: String
    let school_name: String?
    let school_id: String?
    let sport_name: String?
    let season_type: String?
    let shoot_date: Date?
    let location: String?
    let photographer: String?
    let roster: [RosterEntry]?
    let group_images: [GroupImage]?
    let additional_notes: String?
    let organization_id: String
    let created_at: Date?
    let updated_at: Date?
    let is_archived: Bool?

    func toSportsShoot() -> SportsShoot {
        SportsShoot(
            id: id,
            schoolName: school_name ?? "Unknown School",
            schoolId: school_id,
            sportName: sport_name ?? "Unknown Sport",
            seasonType: season_type,
            shootDate: shoot_date ?? Date(),
            location: location ?? "",
            photographer: photographer ?? "",
            roster: roster ?? [],
            groupImages: group_images ?? [],
            additionalNotes: additional_notes ?? "",
            organizationID: organization_id,
            createdAt: created_at ?? Date(),
            updatedAt: updated_at ?? Date(),
            isArchived: is_archived ?? false
        )
    }
}

// MARK: - Supabase Update Payloads
// These structs are used for type-safe Supabase updates

private struct RosterUpdatePayload: Encodable {
    let roster: [RosterEntry]
    let updated_at: String

    init(roster: [RosterEntry]) {
        self.roster = roster
        self.updated_at = Date().ISO8601Format()
    }
}

private struct GroupImagesUpdatePayload: Encodable {
    let group_images: [GroupImage]
    let updated_at: String

    init(groupImages: [GroupImage]) {
        self.group_images = groupImages
        self.updated_at = Date().ISO8601Format()
    }
}

private struct ArchiveUpdatePayload: Encodable {
    let is_archived: Bool
    let updated_at: String

    init(isArchived: Bool) {
        self.is_archived = isArchived
        self.updated_at = Date().ISO8601Format()
    }
}

// Service class for managing Sports Shoots
class SportsShootService {
    static let shared = SportsShootService()
    private var supabase: SupabaseClient { SupabaseManager.shared.client }
    private let sportsShootsCollection = "sports_jobs"

    // Network monitor for connectivity tracking
    private let networkMonitor = NetworkMonitor()
    private var isOnline = true

    // Initialize the service
    private init() {
        // Start monitoring network status
        networkMonitor.startMonitoring { [weak self] isConnected in
            self?.isOnline = isConnected

            // If we just came online, sync modified shoots
            if isConnected {
                OfflineManager.shared.syncModifiedShoots()
            }

            // Notify listeners about network status change
            NotificationCenter.default.post(
                name: NSNotification.Name("SportsShootServiceNetworkStatusChanged"),
                object: nil,
                userInfo: ["isOnline": isConnected]
            )
        }

        // Initialize the isOnline property with the current status
        isOnline = networkMonitor.getCurrentConnectionStatus()

        // Also listen for network status changes from OfflineManager
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(networkStatusChanged(_:)),
            name: NSNotification.Name("OfflineManagerNetworkStatusChanged"),
            object: nil
        )
    }

    @objc private func networkStatusChanged(_ notification: Notification) {
        if let isOnline = notification.userInfo?["isOnline"] as? Bool {
            self.isOnline = isOnline
        }
    }

    // Public method to check if device is online
    func isDeviceOnline() -> Bool {
        return isOnline
    }
    
    // MARK: - Fetch

    func fetchSportsShoot(id: String, completion: @escaping (Result<SportsShoot, Error>) -> Void) {
        print("Fetching sports shoot with ID: \(id)")

        // Check if we are offline
        if !isOnline {
            print("Device is offline, using cached data...")

            if let cachedShoot = OfflineManager.shared.loadCachedShoot(id: id) {
                completion(.success(cachedShoot))
                return
            } else {
                let userInfo = [NSLocalizedDescriptionKey: "Shoot not found in cache and device is offline"]
                let error = NSError(domain: "SportsShootService", code: -1, userInfo: userInfo)
                completion(.failure(error))
                return
            }
        }

        // We're online, fetch from Supabase
        Task {
            do {
                let shoots: [SupabaseSportsShoot] = try await supabase
                    .from(sportsShootsCollection)
                    .select()
                    .eq("id", value: id.lowercased())
                    .limit(1)
                    .execute()
                    .value

                guard let supabaseShoot = shoots.first else {
                    // Try cache as fallback
                    if let cachedShoot = OfflineManager.shared.loadCachedShoot(id: id) {
                        await MainActor.run { completion(.success(cachedShoot)) }
                    } else {
                        let userInfo = [NSLocalizedDescriptionKey: "Sports shoot not found"]
                        let error = NSError(domain: "SportsShootService", code: -1, userInfo: userInfo)
                        await MainActor.run { completion(.failure(error)) }
                    }
                    return
                }

                let sportsShoot = supabaseShoot.toSportsShoot()

                // Cache the shoot for offline use
                OfflineManager.shared.cacheShoot(sportsShoot) { _ in
                    print("Cached shoot \(id) for offline use")
                }

                await MainActor.run {
                    completion(.success(sportsShoot))
                }
            } catch {
                print("Error fetching document: \(error.localizedDescription)")
                // Try to load from cache as fallback
                if let cachedShoot = OfflineManager.shared.loadCachedShoot(id: id) {
                    await MainActor.run { completion(.success(cachedShoot)) }
                } else {
                    await MainActor.run { completion(.failure(error)) }
                }
            }
        }
    }
    
    func fetchAllSportsShoots(forOrganization orgID: String, completion: @escaping (Result<[SportsShoot], Error>) -> Void) {
        print("Fetching all sports shoots for organization: \(orgID)")

        guard !orgID.isEmpty else {
            let userInfo = [NSLocalizedDescriptionKey: "Organization ID is required"]
            let error = NSError(domain: "SportsShootService", code: -2, userInfo: userInfo)
            completion(.failure(error))
            return
        }

        // Check if we are offline - if so, use cached data
        if !isOnline {
            print("Device is offline, using cached data...")
            var cachedShoots: [SportsShoot] = []

            let fileManager = FileManager.default
            let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("sportsShootCache")

            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: nil)

                for fileURL in fileURLs {
                    if fileURL.pathExtension == "json" && fileURL.lastPathComponent != "cachedShoots.json" && fileURL.lastPathComponent != "modifiedShoots.json" {
                        let shootID = fileURL.deletingPathExtension().lastPathComponent

                        if let shoot = OfflineManager.shared.loadCachedShoot(id: shootID),
                           shoot.organizationID == orgID {
                            cachedShoots.append(shoot)
                        }
                    }
                }

                cachedShoots.sort { $0.shootDate > $1.shootDate }
                completion(.success(cachedShoots))
            } catch {
                print("Error reading cached shoots: \(error.localizedDescription)")
                completion(.failure(error))
            }

            return
        }

        // We're online, fetch from Supabase
        Task {
            do {
                let shoots: [SupabaseSportsShoot] = try await supabase
                    .from(sportsShootsCollection)
                    .select()
                    .eq("organization_id", value: orgID.lowercased())
                    .order("shoot_date", ascending: false)
                    .execute()
                    .value

                print("Found \(shoots.count) documents")

                let sportsShoots = shoots.map { $0.toSportsShoot() }

                print("Successfully processed \(sportsShoots.count) sports shoots")
                await MainActor.run {
                    completion(.success(sportsShoots))
                }
            } catch {
                print("Error fetching documents: \(error.localizedDescription)")
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Update

    // Update roster entry with field mapping
    func updateRosterEntry(shootID: String, entry: RosterEntry, completion: @escaping (Result<Void, Error>) -> Void) {
        // Check if we are offline
        if !isOnline {
            print("Device is offline, updating cached shoot...")
            OfflineManager.shared.updateRosterEntryOffline(shootID: shootID, entry: entry, completion: completion)
            return
        }

        // We're online, fetch current shoot, update roster, and save
        Task {
            do {
                // Fetch current shoot
                let shoots: [SupabaseSportsShoot] = try await supabase
                    .from(sportsShootsCollection)
                    .select()
                    .eq("id", value: shootID.lowercased())
                    .limit(1)
                    .execute()
                    .value

                guard let currentShoot = shoots.first else {
                    let userInfo = [NSLocalizedDescriptionKey: "Sports shoot not found"]
                    let error = NSError(domain: "SportsShootService", code: -1, userInfo: userInfo)
                    await MainActor.run { completion(.failure(error)) }
                    return
                }

                // Update the roster
                var updatedRoster = currentShoot.roster ?? []
                if let idx = updatedRoster.firstIndex(where: { $0.id == entry.id }) {
                    updatedRoster[idx] = entry
                } else {
                    updatedRoster.append(entry)
                }

                // Save updated roster to Supabase
                try await supabase
                    .from(sportsShootsCollection)
                    .update(RosterUpdatePayload(roster: updatedRoster))
                    .eq("id", value: shootID.lowercased())
                    .execute()

                // Cache the updated shoot
                var sportsShoot = currentShoot.toSportsShoot()
                sportsShoot.roster = updatedRoster
                sportsShoot.updatedAt = Date()
                OfflineManager.shared.cacheShoot(sportsShoot) { _ in }

                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }
    
    // Update group image
    func updateGroupImage(shootID: String, groupImage: GroupImage, completion: @escaping (Result<Void, Error>) -> Void) {
        if !isOnline {
            print("Device is offline, updating cached shoot...")
            OfflineManager.shared.updateGroupImageOffline(shootID: shootID, group: groupImage, completion: completion)
            return
        }

        Task {
            do {
                let shoots: [SupabaseSportsShoot] = try await supabase
                    .from(sportsShootsCollection)
                    .select()
                    .eq("id", value: shootID.lowercased())
                    .limit(1)
                    .execute()
                    .value

                guard let currentShoot = shoots.first else {
                    let userInfo = [NSLocalizedDescriptionKey: "Sports shoot not found"]
                    let error = NSError(domain: "SportsShootService", code: -1, userInfo: userInfo)
                    await MainActor.run { completion(.failure(error)) }
                    return
                }

                var updatedGroupImages = currentShoot.group_images ?? []
                if let idx = updatedGroupImages.firstIndex(where: { $0.id == groupImage.id }) {
                    updatedGroupImages[idx] = groupImage
                } else {
                    updatedGroupImages.append(groupImage)
                }

                try await supabase
                    .from(sportsShootsCollection)
                    .update(GroupImagesUpdatePayload(groupImages: updatedGroupImages))
                    .eq("id", value: shootID.lowercased())
                    .execute()

                var sportsShoot = currentShoot.toSportsShoot()
                sportsShoot.groupImages = updatedGroupImages
                sportsShoot.updatedAt = Date()
                OfflineManager.shared.cacheShoot(sportsShoot) { _ in }

                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    // Add a new roster entry with field mapping
    func addRosterEntry(shootID: String, entry: RosterEntry, completion: @escaping (Result<Void, Error>) -> Void) {
        if !isOnline {
            print("Device is offline, updating cached shoot...")
            OfflineManager.shared.addRosterEntryOffline(shootID: shootID, entry: entry, completion: completion)
            return
        }

        Task {
            do {
                let shoots: [SupabaseSportsShoot] = try await supabase
                    .from(sportsShootsCollection)
                    .select()
                    .eq("id", value: shootID.lowercased())
                    .limit(1)
                    .execute()
                    .value

                guard let currentShoot = shoots.first else {
                    let error = NSError(domain: "SportsShootService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sports shoot not found"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }

                var updatedRoster = currentShoot.roster ?? []
                updatedRoster.append(entry)

                try await supabase
                    .from(sportsShootsCollection)
                    .update(RosterUpdatePayload(roster: updatedRoster))
                    .eq("id", value: shootID.lowercased())
                    .execute()

                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    // Batch add multiple roster entries
    func batchAddRosterEntries(shootID: String, entries: [RosterEntry], completion: @escaping (Bool, Error?) -> Void) {
        if !isOnline {
            print("Device is offline, cannot batch add entries")
            let error = NSError(domain: "SportsShootService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot batch add entries while offline"])
            completion(false, error)
            return
        }

        Task {
            do {
                let shoots: [SupabaseSportsShoot] = try await supabase
                    .from(sportsShootsCollection)
                    .select()
                    .eq("id", value: shootID.lowercased())
                    .limit(1)
                    .execute()
                    .value

                guard let currentShoot = shoots.first else {
                    let error = NSError(domain: "SportsShootService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sports shoot not found"])
                    await MainActor.run { completion(false, error) }
                    return
                }

                var updatedRoster = currentShoot.roster ?? []
                updatedRoster.append(contentsOf: entries)

                try await supabase
                    .from(sportsShootsCollection)
                    .update(RosterUpdatePayload(roster: updatedRoster))
                    .eq("id", value: shootID.lowercased())
                    .execute()

                await MainActor.run { completion(true, nil) }
            } catch {
                await MainActor.run { completion(false, error) }
            }
        }
    }

    // Add a new group image
    func addGroupImage(shootID: String, groupImage: GroupImage, completion: @escaping (Result<Void, Error>) -> Void) {
        if !isOnline {
            print("Device is offline, updating cached shoot...")
            OfflineManager.shared.addGroupImageOffline(shootID: shootID, group: groupImage, completion: completion)
            return
        }

        Task {
            do {
                let shoots: [SupabaseSportsShoot] = try await supabase
                    .from(sportsShootsCollection)
                    .select()
                    .eq("id", value: shootID.lowercased())
                    .limit(1)
                    .execute()
                    .value

                guard let currentShoot = shoots.first else {
                    let error = NSError(domain: "SportsShootService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sports shoot not found"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }

                var updatedGroupImages = currentShoot.group_images ?? []
                updatedGroupImages.append(groupImage)

                try await supabase
                    .from(sportsShootsCollection)
                    .update(GroupImagesUpdatePayload(groupImages: updatedGroupImages))
                    .eq("id", value: shootID.lowercased())
                    .execute()

                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    // Delete roster entry
    func deleteRosterEntry(shootID: String, entryID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        if !isOnline {
            print("Device is offline, updating cached shoot...")
            OfflineManager.shared.deleteRosterEntryOffline(shootID: shootID, entryID: entryID, completion: completion)
            return
        }

        Task {
            do {
                let shoots: [SupabaseSportsShoot] = try await supabase
                    .from(sportsShootsCollection)
                    .select()
                    .eq("id", value: shootID.lowercased())
                    .limit(1)
                    .execute()
                    .value

                guard let currentShoot = shoots.first else {
                    let error = NSError(domain: "SportsShootService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sports shoot not found"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }

                var updatedRoster = currentShoot.roster ?? []
                updatedRoster.removeAll(where: { $0.id == entryID })

                try await supabase
                    .from(sportsShootsCollection)
                    .update(RosterUpdatePayload(roster: updatedRoster))
                    .eq("id", value: shootID.lowercased())
                    .execute()

                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    // Delete group image
    func deleteGroupImage(shootID: String, groupID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        if !isOnline {
            print("Device is offline, updating cached shoot...")
            OfflineManager.shared.deleteGroupImageOffline(shootID: shootID, groupID: groupID, completion: completion)
            return
        }

        Task {
            do {
                let shoots: [SupabaseSportsShoot] = try await supabase
                    .from(sportsShootsCollection)
                    .select()
                    .eq("id", value: shootID.lowercased())
                    .limit(1)
                    .execute()
                    .value

                guard let currentShoot = shoots.first else {
                    let error = NSError(domain: "SportsShootService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sports shoot not found"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }

                var updatedGroupImages = currentShoot.group_images ?? []
                updatedGroupImages.removeAll(where: { $0.id == groupID })

                try await supabase
                    .from(sportsShootsCollection)
                    .update(GroupImagesUpdatePayload(groupImages: updatedGroupImages))
                    .eq("id", value: shootID.lowercased())
                    .execute()

                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Offline Helpers
    
    // Check sync status for a shoot
    func syncStatusForShoot(id: String) -> OfflineManager.CacheStatus {
        return OfflineManager.shared.cacheStatusForShoot(id: id)
    }
    
    // Cache a shoot for offline use
    func cacheShootForOffline(id: String, completion: @escaping (Bool) -> Void) {
        // Fetch the shoot and cache it
        fetchSportsShoot(id: id) { result in
            switch result {
            case .success(let shoot):
                OfflineManager.shared.cacheShoot(shoot, completion: completion)
            case .failure:
                completion(false)
            }
        }
    }
    
    // Helper to handle conflict resolution
    func handleSyncConflicts() {
        // Listen for sync conflict notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SyncConflictsDetected"),
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let shootID = userInfo["shootID"] as? String,
                  let entryConflicts = userInfo["entryConflicts"] as? [OfflineManager.EntryConflict],
                  let groupConflicts = userInfo["groupConflicts"] as? [OfflineManager.GroupConflict],
                  let localShoot = userInfo["localShoot"] as? SportsShoot,
                  let remoteShoot = userInfo["remoteShoot"] as? SportsShoot else {
                return
            }
            
            // Post a notification to show the conflict resolution UI
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowConflictResolution"),
                object: nil,
                userInfo: [
                    "shootID": shootID,
                    "entryConflicts": entryConflicts,
                    "groupConflicts": groupConflicts,
                    "localShoot": localShoot,
                    "remoteShoot": remoteShoot
                ]
            )
        }
    }
    
    // MARK: - Session Integration

    // Fetch upcoming sessions for sports job creation
    func fetchUpcomingSessions(forOrganization orgID: String, completion: @escaping (Result<[Session], Error>) -> Void) {
        print("Fetching upcoming sessions for sports job creation")

        let now = Date()
        let twoWeeksFromNow = Calendar.current.date(byAdding: .weekOfYear, value: 2, to: now) ?? now

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startDateStr = dateFormatter.string(from: now)
        let endDateStr = dateFormatter.string(from: twoWeeksFromNow)

        Task {
            do {
                // Use SessionService to fetch sessions
                let sessions = try await SessionService.shared.fetchSessions(organizationID: orgID.lowercased())

                // Filter for upcoming sessions that don't have sports jobs
                let availableSessions = sessions.filter { session in
                    guard let sessionDate = session.startDate else { return false }
                    return sessionDate >= now && sessionDate <= twoWeeksFromNow && !session.hasSportsJob
                }.sorted { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) }

                print("Found \(availableSessions.count) available sessions for sports jobs")
                await MainActor.run { completion(.success(availableSessions)) }
            } catch {
                print("Error fetching sessions: \(error.localizedDescription)")
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Archive Management

    // Archive a sports shoot
    func archiveSportsShoot(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                try await supabase
                    .from(sportsShootsCollection)
                    .update(ArchiveUpdatePayload(isArchived: true))
                    .eq("id", value: id.lowercased())
                    .execute()

                // Update cached version if exists
                if let cachedShoot = OfflineManager.shared.loadCachedShoot(id: id) {
                    var updatedShoot = cachedShoot
                    updatedShoot.isArchived = true
                    updatedShoot.updatedAt = Date()
                    OfflineManager.shared.cacheShoot(updatedShoot) { _ in }
                }

                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    // Unarchive a sports shoot
    func unarchiveSportsShoot(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                try await supabase
                    .from(sportsShootsCollection)
                    .update(ArchiveUpdatePayload(isArchived: false))
                    .eq("id", value: id.lowercased())
                    .execute()

                // Update cached version if exists
                if let cachedShoot = OfflineManager.shared.loadCachedShoot(id: id) {
                    var updatedShoot = cachedShoot
                    updatedShoot.isArchived = false
                    updatedShoot.updatedAt = Date()
                    OfflineManager.shared.cacheShoot(updatedShoot) { _ in }
                }

                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }
    
    // MARK: - CSV Import/Export
    
    // Import roster from CSV with updated display names
    func importRosterFromCSV(csvString: String) -> [RosterEntry] {
        var roster: [RosterEntry] = []
        
        // Split into lines
        let lines = csvString.components(separatedBy: .newlines)
        
        // Need at least a header row and one data row
        guard lines.count >= 2 else { return [] }
        
        // Get headers
        let headers = lines[0].components(separatedBy: ",")
        
        // Find column indices based on headers (case-insensitive)
        let normalizedHeaders = headers.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // Support both old column names and new display names
        let nameIndex = normalizedHeaders.firstIndex {
            $0.contains("last name") || $0.contains("name") && !$0.contains("first")
        } ?? -1
        
        let subjectIDIndex = normalizedHeaders.firstIndex {
            $0.contains("first name") || $0.contains("subject id")
        } ?? -1
        
        let specialIndex = normalizedHeaders.firstIndex {
            $0.contains("teacher") || $0.contains("special")
        } ?? -1
        
        let sportTeamIndex = normalizedHeaders.firstIndex {
            $0.contains("group") || $0.contains("sport") || $0.contains("team")
        } ?? -1
        
        let emailIndex = normalizedHeaders.firstIndex(where: { $0.contains("email") }) ?? -1
        let phoneIndex = normalizedHeaders.firstIndex(where: { $0.contains("phone") }) ?? -1
        let imagesIndex = normalizedHeaders.firstIndex(where: { $0.contains("image") }) ?? -1
        
        // Process data rows
        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty { continue }
            
            // Parse CSV line (handling quotes properly)
            var fields: [String] = []
            var currentField = ""
            var insideQuotes = false
            
            for char in line {
                if char == "\"" {
                    insideQuotes = !insideQuotes
                } else if char == "," && !insideQuotes {
                    fields.append(currentField)
                    currentField = ""
                } else {
                    currentField.append(char)
                }
            }
            fields.append(currentField) // Add the last field
            
            // Create entry with mapped fields
            let lastName = nameIndex >= 0 && nameIndex < fields.count ? fields[nameIndex] : ""
            let entry = RosterEntry(
                id: UUID().uuidString,
                lastName: lastName,
                firstName: subjectIDIndex >= 0 && subjectIDIndex < fields.count ? fields[subjectIDIndex] : "",
                teacher: specialIndex >= 0 && specialIndex < fields.count ? fields[specialIndex] : "",
                group: sportTeamIndex >= 0 && sportTeamIndex < fields.count ? fields[sportTeamIndex] : "",
                email: emailIndex >= 0 && emailIndex < fields.count ? fields[emailIndex] : "",
                phone: phoneIndex >= 0 && phoneIndex < fields.count ? fields[phoneIndex] : "",
                imageNumbers: imagesIndex >= 0 && imagesIndex < fields.count ? fields[imagesIndex] : "",
                notes: "",
                wasBlank: true,  // All imported entries are considered new/blank
                isFilledBlank: !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty  // Filled if has lastName
            )
            
            roster.append(entry)
        }
        
        return roster
    }
    
    // Export roster to CSV with updated display names
    func exportRosterToCSV(roster: [RosterEntry]) -> String {
        // Create header row with mapped fields (display names)
        var csv = "Name,Subject ID,Special,Sport/Team,Email,Phone,Images\n"
        
        // Add entries
        for entry in roster {
            let escapedLastName = escapeCSVField(entry.lastName)
            let escapedFirstName = escapeCSVField(entry.firstName)
            let escapedTeacher = escapeCSVField(entry.teacher)
            let escapedGroup = escapeCSVField(entry.group)
            let escapedEmail = escapeCSVField(entry.email)
            let escapedPhone = escapeCSVField(entry.phone)
            let escapedImageNumbers = escapeCSVField(entry.imageNumbers)
            
            csv += "\(escapedLastName),\(escapedFirstName),\(escapedTeacher),\(escapedGroup),\(escapedEmail),\(escapedPhone),\(escapedImageNumbers)\n"
        }
        
        return csv
    }
    
    // Helper to escape CSV fields
    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
}
