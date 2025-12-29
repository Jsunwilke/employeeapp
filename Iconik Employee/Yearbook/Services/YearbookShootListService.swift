import Foundation
import Supabase

class YearbookShootListService: ObservableObject {
    static let shared = YearbookShootListService()
    private let supabase = SupabaseManager.shared.client
    private let tableName = "yearbook_shoot_lists"

    // Cache for offline support
    private var cachedLists: [String: YearbookShootList] = [:]
    private let cacheQueue = DispatchQueue(label: "com.iconik.yearbook.cache")

    // Realtime channels
    private var listChannel: RealtimeChannelV2?
    private var organizationChannel: RealtimeChannelV2?

    private init() {}

    // MARK: - Fetch Operations

    /// Get yearbook shoot list for a specific school and year
    func getYearbookShootList(schoolId: String, schoolYear: String) async throws -> YearbookShootList? {
        // Check cache first
        let cacheKey = "\(schoolId)_\(schoolYear)"
        if let cached = getCachedList(key: cacheKey) {
            print("🗂️ Returning cached yearbook list for \(cacheKey)")
            return cached
        }

        let shootLists: [YearbookShootList] = try await supabase
            .from(tableName)
            .select()
            .eq("school_id", value: schoolId.lowercased())
            .eq("school_year", value: schoolYear)
            .limit(1)
            .execute()
            .value

        guard let shootList = shootLists.first else {
            print("📋 No yearbook list found for school: \(schoolId), year: \(schoolYear)")
            return nil
        }

        // Cache the result
        cacheList(shootList, key: cacheKey)

        return shootList
    }

    /// Get all yearbook lists for an organization
    func getOrganizationYearbookLists(organizationId: String) async throws -> [YearbookShootList] {
        let lists: [YearbookShootList] = try await supabase
            .from(tableName)
            .select()
            .eq("organization_id", value: organizationId.lowercased())
            .order("school_year", ascending: false)
            .execute()
            .value

        return lists
    }

    /// Get available years for a school
    func getAvailableYears(schoolId: String, organizationId: String) async throws -> [String] {
        print("🔍 YearbookShootListService.getAvailableYears")
        print("🔍 Looking for schoolId: '\(schoolId)'")
        print("🔍 With organizationId: '\(organizationId)'")

        struct YearResult: Decodable {
            let school_year: String
        }

        let results: [YearResult] = try await supabase
            .from(tableName)
            .select("school_year")
            .eq("organization_id", value: organizationId.lowercased())
            .eq("school_id", value: schoolId.lowercased())
            .execute()
            .value

        let years = results.map { $0.school_year }
        let uniqueYears = Array(Set(years)).sorted(by: >)
        print("🔍 Unique years found: \(uniqueYears)")

        return uniqueYears
    }

    /// Get active yearbook lists for current school year
    func getActiveYearbookLists(organizationId: String) async throws -> [YearbookShootList] {
        let currentYear = YearbookShootList.getCurrentSchoolYear()

        let lists: [YearbookShootList] = try await supabase
            .from(tableName)
            .select()
            .eq("organization_id", value: organizationId.lowercased())
            .eq("school_year", value: currentYear)
            .eq("is_active", value: true)
            .execute()
            .value

        return lists
    }

    // MARK: - Create Operations

    /// Create a new yearbook shoot list
    func createYearbookShootList(_ list: YearbookShootList) async throws -> String {
        let newId = UUID().uuidString.lowercased()

        // Create insert data
        struct InsertData: Encodable {
            let id: String
            let organization_id: String
            let school_id: String
            let school_name: String
            let school_year: String
            let start_date: Date
            let end_date: Date
            let is_active: Bool
            let copied_from_id: String?
            let completed_count: Int
            let total_count: Int
            let items: [YearbookItem]
            let created_at: Date
            let updated_at: Date
        }

        let insertData = InsertData(
            id: newId,
            organization_id: list.organization_id.lowercased(),
            school_id: list.school_id.lowercased(),
            school_name: list.school_name,
            school_year: list.school_year,
            start_date: list.start_date,
            end_date: list.end_date,
            is_active: list.is_active,
            copied_from_id: list.copied_from_id,
            completed_count: list.completed_count,
            total_count: list.total_count,
            items: list.items,
            created_at: Date(),
            updated_at: Date()
        )

        try await supabase
            .from(tableName)
            .insert(insertData)
            .execute()

        // Cache the new list
        let cacheKey = "\(list.school_id)_\(list.school_year)"
        var newList = list
        // Note: Can't modify let property, but cache will be updated on next fetch
        cacheList(list, key: cacheKey)

        print("✅ Created yearbook list for \(list.school_name) - \(list.school_year)")
        return newId
    }

    /// Copy a yearbook list from another year or template
    func copyYearbookShootList(fromListId: String, toSchoolId: String, toSchoolYear: String, toSchoolName: String) async throws -> String {
        // Get the source list
        let sourceLists: [YearbookShootList] = try await supabase
            .from(tableName)
            .select()
            .eq("id", value: fromListId.lowercased())
            .limit(1)
            .execute()
            .value

        guard let sourceList = sourceLists.first else {
            throw YearbookError.listNotFound
        }

        // Create new list with copied items (reset completion status)
        let dates = YearbookShootList.getSchoolYearDates(schoolYear: toSchoolYear) ?? (Date(), Date())
        let newItems = sourceList.items.map { item in
            YearbookItem(
                name: item.name,
                description: item.description,
                category: item.category,
                required: item.required,
                completed: false,
                order: item.order
            )
        }

        let newList = YearbookShootList(
            id: UUID().uuidString.lowercased(),
            organization_id: sourceList.organization_id,
            school_id: toSchoolId.lowercased(),
            school_name: toSchoolName,
            school_year: toSchoolYear,
            start_date: dates.start,
            end_date: dates.end,
            is_active: toSchoolYear == YearbookShootList.getCurrentSchoolYear(),
            copied_from_id: fromListId,
            completed_count: 0,
            total_count: newItems.count,
            items: newItems,
            created_at: Date(),
            updated_at: Date()
        )

        return try await createYearbookShootList(newList)
    }

    // MARK: - Update Operations

    /// Update a specific item in the yearbook list
    func updateShootListItem(listId: String, itemId: String, updates: [String: Any]) async throws {
        // Get current list
        let lists: [YearbookShootList] = try await supabase
            .from(tableName)
            .select()
            .eq("id", value: listId.lowercased())
            .limit(1)
            .execute()
            .value

        guard var list = lists.first else {
            throw YearbookError.listNotFound
        }

        // Find item index
        guard let itemIndex = list.items.firstIndex(where: { $0.id == itemId }) else {
            throw YearbookError.itemNotFound
        }

        // Track completion status change
        let wasCompleted = list.items[itemIndex].completed

        // Apply updates to item
        var updatedItem = list.items[itemIndex]
        if let completed = updates["completed"] as? Bool {
            updatedItem.completed = completed
        }
        if let completedDate = updates["completedDate"] as? Date {
            updatedItem.completed_date = completedDate
        } else if updates["completedDate"] is NSNull {
            updatedItem.completed_date = nil
        }
        if let completedBySession = updates["completedBySession"] as? String {
            updatedItem.completed_by_session = completedBySession
        } else if updates["completedBySession"] is NSNull {
            updatedItem.completed_by_session = nil
        }
        if let photographerId = updates["photographerId"] as? String {
            updatedItem.photographer_id = photographerId
        } else if updates["photographerId"] is NSNull {
            updatedItem.photographer_id = nil
        }
        if let photographerName = updates["photographerName"] as? String {
            updatedItem.photographer_name = photographerName
        } else if updates["photographerName"] is NSNull {
            updatedItem.photographer_name = nil
        }
        if let notes = updates["notes"] as? String {
            updatedItem.notes = notes
        } else if updates["notes"] is NSNull {
            updatedItem.notes = nil
        }
        if let imageNumbers = updates["imageNumbers"] as? [String] {
            updatedItem.image_numbers = imageNumbers
        } else if updates["imageNumbers"] is NSNull {
            updatedItem.image_numbers = nil
        }

        // Update items array
        var updatedItems = list.items
        updatedItems[itemIndex] = updatedItem

        // Calculate new completed count if status changed
        var newCompletedCount = list.completed_count
        if wasCompleted != updatedItem.completed {
            newCompletedCount = updatedItem.completed ? newCompletedCount + 1 : max(0, newCompletedCount - 1)
        }

        // Update in database
        struct UpdateData: Encodable {
            let items: [YearbookItem]
            let completed_count: Int
            let updated_at: Date
        }

        try await supabase
            .from(tableName)
            .update(UpdateData(
                items: updatedItems,
                completed_count: newCompletedCount,
                updated_at: Date()
            ))
            .eq("id", value: listId.lowercased())
            .execute()

        // Invalidate cache
        let cacheKey = "\(list.school_id)_\(list.school_year)"
        invalidateCache(key: cacheKey)

        print("✅ Updated item \(itemId) in list \(listId)")
    }

    /// Toggle item completion status
    func toggleItemCompletion(listId: String, itemId: String, sessionContext: YearbookSessionContext?) async throws {
        // Get current list
        let lists: [YearbookShootList] = try await supabase
            .from(tableName)
            .select()
            .eq("id", value: listId.lowercased())
            .limit(1)
            .execute()
            .value

        guard let list = lists.first,
              let item = list.items.first(where: { $0.id == itemId }) else {
            throw YearbookError.itemNotFound
        }

        // Prepare updates
        var updates: [String: Any] = [
            "completed": !item.completed
        ]

        if !item.completed {
            // Marking as complete
            updates["completedDate"] = Date()

            if let context = sessionContext {
                updates["completedBySession"] = context.sessionId
                updates["photographerId"] = context.photographerId
                updates["photographerName"] = context.photographerName
            } else if let currentUserId = UserManager.shared.getCurrentUserIDUnified() {
                let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
                let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
                let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                updates["photographerId"] = currentUserId
                updates["photographerName"] = fullName.isEmpty ? "Unknown" : fullName
            }
        } else {
            // Marking as incomplete
            updates["completedDate"] = NSNull()
            updates["completedBySession"] = NSNull()
            updates["photographerId"] = NSNull()
            updates["photographerName"] = NSNull()
        }

        try await updateShootListItem(listId: listId, itemId: itemId, updates: updates)
    }

    /// Update item notes
    func updateItemNotes(listId: String, itemId: String, notes: String?) async throws {
        let updates: [String: Any] = notes != nil ? ["notes": notes!] : ["notes": NSNull()]
        try await updateShootListItem(listId: listId, itemId: itemId, updates: updates)
    }

    /// Update item image numbers
    func updateItemImageNumbers(listId: String, itemId: String, imageNumbers: [String]) async throws {
        let updates: [String: Any] = !imageNumbers.isEmpty ? ["imageNumbers": imageNumbers] : ["imageNumbers": NSNull()]
        try await updateShootListItem(listId: listId, itemId: itemId, updates: updates)
    }

    // MARK: - Real-time Listeners

    /// Subscribe to updates for a specific yearbook list
    func subscribeToShootListUpdates(schoolId: String, schoolYear: String, organizationId: String,
                                    completion: @escaping (YearbookShootList?) -> Void) -> ListenerRegistrationWrapper {
        // Stop existing channel if any
        Task {
            await listChannel?.unsubscribe()
        }

        // Initial fetch
        Task {
            do {
                let list = try await getYearbookShootList(schoolId: schoolId, schoolYear: schoolYear)
                await MainActor.run {
                    completion(list)
                }
            } catch {
                print("❌ Error fetching yearbook list: \(error)")
                await MainActor.run {
                    completion(nil)
                }
            }
        }

        // Set up realtime subscription
        let channel = supabase.channel("yearbook_list_\(schoolId)_\(schoolYear)")

        let changeStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: tableName,
            filter: "school_id=eq.\(schoolId.lowercased())"
        )

        Task {
            for await change in changeStream {
                // Refetch on any change
                do {
                    let list = try await getYearbookShootList(schoolId: schoolId, schoolYear: schoolYear)
                    await MainActor.run {
                        completion(list)
                    }
                } catch {
                    print("❌ Error in realtime update: \(error)")
                }
            }
        }

        Task {
            await channel.subscribe()
        }

        self.listChannel = channel

        return ListenerRegistrationWrapper {
            Task {
                await channel.unsubscribe()
            }
        }
    }

    /// Subscribe to all lists for an organization
    func subscribeToOrganizationLists(organizationId: String,
                                     completion: @escaping ([YearbookShootList]) -> Void) -> ListenerRegistrationWrapper {
        // Stop existing channel if any
        Task {
            await organizationChannel?.unsubscribe()
        }

        // Initial fetch
        Task {
            do {
                let lists = try await getOrganizationYearbookLists(organizationId: organizationId)
                await MainActor.run {
                    completion(lists)
                }
            } catch {
                print("❌ Error fetching organization yearbook lists: \(error)")
                await MainActor.run {
                    completion([])
                }
            }
        }

        // Set up realtime subscription
        let channel = supabase.channel("yearbook_org_\(organizationId)")

        let changeStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: tableName,
            filter: "organization_id=eq.\(organizationId.lowercased())"
        )

        Task {
            for await change in changeStream {
                // Refetch on any change
                do {
                    let lists = try await getOrganizationYearbookLists(organizationId: organizationId)
                    await MainActor.run {
                        completion(lists)
                    }
                } catch {
                    print("❌ Error in realtime update: \(error)")
                }
            }
        }

        Task {
            await channel.subscribe()
        }

        self.organizationChannel = channel

        return ListenerRegistrationWrapper {
            Task {
                await channel.unsubscribe()
            }
        }
    }

    // MARK: - Delete Operations

    /// Delete a yearbook shoot list
    func deleteYearbookShootList(listId: String) async throws {
        try await supabase
            .from(tableName)
            .delete()
            .eq("id", value: listId.lowercased())
            .execute()

        print("🗑️ Deleted yearbook list: \(listId)")
    }

    // MARK: - Cache Management

    private func cacheList(_ list: YearbookShootList, key: String) {
        cacheQueue.async {
            self.cachedLists[key] = list

            // Save to UserDefaults for persistence
            if let encoded = try? JSONEncoder().encode(list) {
                UserDefaults.standard.set(encoded, forKey: "yearbook_cache_\(key)")
            }
        }
    }

    private func getCachedList(key: String) -> YearbookShootList? {
        // Check memory cache first
        if let cached = cacheQueue.sync(execute: { cachedLists[key] }) {
            return cached
        }

        // Check UserDefaults
        if let data = UserDefaults.standard.data(forKey: "yearbook_cache_\(key)"),
           let list = try? JSONDecoder().decode(YearbookShootList.self, from: data) {
            // Restore to memory cache
            cacheQueue.async {
                self.cachedLists[key] = list
            }
            return list
        }

        return nil
    }

    private func invalidateCache(key: String) {
        cacheQueue.async {
            self.cachedLists.removeValue(forKey: key)
            UserDefaults.standard.removeObject(forKey: "yearbook_cache_\(key)")
        }
    }

    func clearAllCache() {
        cacheQueue.async {
            self.cachedLists.removeAll()

            // Clear UserDefaults cache
            let defaults = UserDefaults.standard
            let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("yearbook_cache_") }
            keys.forEach { defaults.removeObject(forKey: $0) }
        }
    }
}
