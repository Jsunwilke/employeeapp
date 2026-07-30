import Foundation
import SwiftUI

@MainActor
class YearbookShootListViewModel: ObservableObject {
    @Published var shootLists: [YearbookShootList] = []
    @Published var selectedShootList: YearbookShootList?
    @Published var availableYears: [String] = []
    @Published var isLoading = false
    @Published var error: Error?

    /// THE FILTER IS ONE VALUE (AMB.10).
    ///
    /// It replaces `searchText` + `selectedCategory` + `showCompletedOnly` +
    /// `showIncompleteOnly`. Three independent pieces of state is what let a
    /// quick-filter tap reach over and clear the other two: every quick chip
    /// called `clearFilters()`, which reset the category to "All" and wiped the
    /// typed search, so "which football items are still open" was a question the
    /// app answered by throwing it away. The parts compose now, and the predicate
    /// itself lives in `YearbookRules` where a script runs it.
    @Published var filter = YearbookFilter()

    private let service = YearbookShootListService.shared
    private var listListener: ListenerRegistrationWrapper?
    private var organizationListener: ListenerRegistrationWrapper?
    
    // Session context for integration
    var sessionContext: YearbookSessionContext?
    
    // Current user info
    private var currentUserId: String? {
        UserManager.shared.getCurrentUserIDUnified()
    }

    private var currentUserName: String? {
        let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return fullName.isEmpty ? nil : fullName
    }
    
    // MARK: - Computed Properties
    
    /// Every item on the selected list, unfiltered — what the counts and the
    /// category chips are computed FROM, so neither can be narrowed by what the
    /// filter happens to be showing.
    var allItems: [YearbookItem] { selectedShootList?.items ?? [] }

    var filteredItems: [YearbookItem] {
        YearbookRules.items(allItems, matching: filter)
    }

    /// The categories present on the list, in the order the book is assembled in.
    /// No synthetic "All" entry: "every category" is `filter.category == nil`, and
    /// a magic string in the same list as real category names is how a category
    /// literally called "All" would have broken the screen.
    var categories: [String] { YearbookRules.categories(in: allItems) }

    /// Sections in category order, each carrying only the rows the filter left.
    /// Empty sections are dropped by the caller, not here.
    var groupedFilteredItems: [(category: String, items: [YearbookItem])] {
        let shown = filteredItems
        return categories.compactMap { category in
            let rows = shown.filter { $0.category == category }
            return rows.isEmpty ? nil : (category: category, items: rows)
        }
    }

    // MARK: - Initialization
    
    init(sessionContext: YearbookSessionContext? = nil) {
        self.sessionContext = sessionContext
    }
    
    deinit {
        listListener?.remove()
        organizationListener?.remove()
    }
    
    // MARK: - Load Operations
    
    /// Load yearbook list for a specific school and year
    func loadShootList(schoolId: String, schoolYear: String, organizationId: String) {
        isLoading = true
        error = nil
        
        // Set up real-time listener
        listListener?.remove()
        listListener = service.subscribeToShootListUpdates(
            schoolId: schoolId,
            schoolYear: schoolYear,
            organizationId: organizationId
        ) { [weak self] shootList in
            DispatchQueue.main.async {
                self?.selectedShootList = shootList
                self?.isLoading = false
            }
        }
    }
    
    /// Load yearbook list with automatic year selection
    func loadShootListForSchool(schoolId: String, schoolName: String, organizationId: String) async {
        isLoading = true
        error = nil
        
        do {
            // Get available years
            let years = try await service.getAvailableYears(schoolId: schoolId, organizationId: organizationId)
            availableYears = years
            
            // Load current year or most recent
            let currentYear = YearbookShootList.getCurrentSchoolYear()
            let yearToLoad = years.contains(currentYear) ? currentYear : years.first ?? currentYear
            
            // If no list exists for current year, offer to create one
            if !years.contains(currentYear) {
                // For now, just load the most recent year
                if let mostRecentYear = years.first {
                    loadShootList(schoolId: schoolId, schoolYear: mostRecentYear, organizationId: organizationId)
                } else {
                    // No lists exist
                    selectedShootList = nil
                    isLoading = false
                }
            } else {
                loadShootList(schoolId: schoolId, schoolYear: yearToLoad, organizationId: organizationId)
            }
        } catch {
            self.error = error
            isLoading = false
        }
    }
    
    /// Load all yearbook lists for an organization
    func loadOrganizationLists(organizationId: String) {
        isLoading = true
        error = nil
        
        organizationListener?.remove()
        organizationListener = service.subscribeToOrganizationLists(
            organizationId: organizationId
        ) { [weak self] lists in
            DispatchQueue.main.async {
                self?.shootLists = lists
                self?.isLoading = false
            }
        }
    }
    
    /// Re-read the organization's lists and WAIT for the answer.
    ///
    /// `.refreshable` on the root screen used to call `loadOrganizationLists`,
    /// which only re-subscribes: it returns immediately, so the spinner vanished
    /// before any data arrived and a pull-to-refresh proved nothing. This awaits
    /// the same fetch the subscription performs internally
    /// (`getOrganizationYearbookLists`) — no new service surface — and, unlike
    /// the subscription (which since AMB.10 publishes nothing at all on a failed
    /// fetch), it can REPORT the failure.
    func refreshOrganizationLists(organizationId: String) async {
        do {
            let lists = try await service.getOrganizationYearbookLists(organizationId: organizationId)
            shootLists = lists
            error = nil
        } catch {
            self.error = error
        }
        isLoading = false
    }

    /// Load active lists for current school year
    func loadActiveListsForOrganization(organizationId: String) async {
        isLoading = true
        error = nil
        
        do {
            let lists = try await service.getActiveYearbookLists(organizationId: organizationId)
            shootLists = lists
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }
    
    // MARK: - Item Operations
    
    /// One toggle in flight per item. A second tap while the round trip is out
    /// is IGNORED rather than queued: the row gives no feedback until the write
    /// returns, so the second tap is almost always the same intent repeated —
    /// and letting it race produced a stale read that both dropped the tap's
    /// meaning and over-counted the mirror.
    private var togglesInFlight: Set<String> = []

    /// Toggle completion status of an item.
    ///
    /// RETURNS THE FAILURE, OR NIL ON SUCCESS. Nothing on these screens used to be
    /// able to tell: the failure went into `error`, which no view on the checklist
    /// or the detail sheet ever read, so a check-off that did not save was
    /// completely silent — and since the 2026-07-30 hardening the service can also
    /// fail LOUDLY when its filter matches no row, which is the case that used to
    /// report success and persist nothing. Returning the error itself (rather than
    /// a Bool) lets the item sheet report THIS call's failure without reading the
    /// shared `error` — which may carry someone else's.
    ///
    /// `publishError: false` is for a caller that reports the returned failure
    /// itself (the item sheet's inline card) — publishing it too would raise a
    /// SECOND banner on the checklist behind the sheet for the same failure.
    @discardableResult
    func toggleItemCompletion(_ item: YearbookItem, publishError: Bool = true) async -> Error? {
        guard let listId = selectedShootList?.id else { return YearbookError.itemNotFound }
        guard !togglesInFlight.contains(item.id) else { return nil }
        togglesInFlight.insert(item.id)
        defer { togglesInFlight.remove(item.id) }

        do {
            // THE SERVER'S ANSWER, not a local guess. The service computes the
            // flip from the row it just read and returns what it WROTE — the
            // flag AND the stored count the write left behind. This screen never
            // subscribes, so its copy can be stale: a local `!completed` could
            // mirror the OPPOSITE of what saved while stamping a photographer
            // onto an item the server just un-completed, and a local `±1` could
            // move a counter the server did not.
            let written = try await service.toggleItemCompletion(
                listId: listId,
                itemId: item.id,
                sessionContext: sessionContext
            )
            let nowCompleted = written.completed

            // Local update, so the row reflects the write without waiting for a
            // refetch this screen never makes. It mirrors EVERYTHING the service
            // stamped, not just the flag: the sheet stays open after a toggle to
            // show the write landed, and a local copy that says "Photographer:
            // Unknown / Date: —" over a row the server just attributed is the
            // sheet stating two falsehoods in the one place built to show the
            // truth. Same source of values as the service: the session context,
            // else the signed-in user.
            // `before` answers only "does a local row exist" — a missed id (list
            // swapped across the await) must not touch the progress bar.
            let before = self.item(id: item.id)?.completed
            updateLocalItem(id: item.id) { local in
                local.completed = nowCompleted
                if nowCompleted {
                    local.completedDate = Date()
                    if let context = self.sessionContext {
                        local.completedBySession = context.sessionId
                        local.photographerId = context.photographerId
                        local.photographerName = context.photographerName
                    } else if let currentUserId = UserManager.shared.getCurrentUserIDUnified() {
                        let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
                        let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
                        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                        local.photographerId = currentUserId
                        local.photographerName = fullName.isEmpty ? "Unknown" : fullName
                    }
                } else {
                    local.completedDate = nil
                    local.completedBySession = nil
                    local.photographerId = nil
                    local.photographerName = nil
                }
            }
            // ASSIGNED from the write's own answer, never inferred with ±1 —
            // the server counter moves only when the service's read saw the
            // flag change, so arithmetic here over-counts under races. Guarded
            // on the list still being the one the write was for.
            if before != nil, var list = selectedShootList, list.id == listId {
                list.completedCount = written.completedCount
                selectedShootList = list
            }
            return nil
        } catch {
            if publishError { self.error = error }
            print("❌ Error toggling item: \(error)")
            return error
        }
    }

    /// Update notes for an item.
    ///
    /// The local copy is updated ON SUCCESS (AMB.10). Before, neither this nor the
    /// image-number write touched local state at all, so a saved note did not
    /// appear on its row until the whole screen was rebuilt — and the note badge,
    /// which is computed from that value, stayed wrong with it.
    @discardableResult
    func updateItemNotes(_ item: YearbookItem, notes: String?, publishError: Bool = true) async -> Error? {
        guard let listId = selectedShootList?.id else { return YearbookError.itemNotFound }

        do {
            try await service.updateItemNotes(
                listId: listId,
                itemId: item.id,
                notes: notes
            )
            updateLocalItem(id: item.id) { $0.notes = notes }
            return nil
        } catch {
            if publishError { self.error = error }
            return error
        }
    }

    /// Update image numbers for an item.
    @discardableResult
    func updateItemImageNumbers(_ item: YearbookItem, imageNumbers: [String], publishError: Bool = true) async -> Error? {
        guard let listId = selectedShootList?.id else { return YearbookError.itemNotFound }

        do {
            try await service.updateItemImageNumbers(
                listId: listId,
                itemId: item.id,
                imageNumbers: imageNumbers
            )
            // The service stores NULL for an empty array, so the local copy has to
            // agree or the row's image line and the database disagree.
            updateLocalItem(id: item.id) { $0.imageNumbers = imageNumbers.isEmpty ? nil : imageNumbers }
            return nil
        } catch {
            if publishError { self.error = error }
            return error
        }
    }

    /// The one place local item state is edited, so a "keep the screen in step"
    /// fix cannot be applied to one writer and forgotten on the next.
    private func updateLocalItem(id: String, _ apply: (inout YearbookItem) -> Void) {
        guard var list = selectedShootList,
              let index = list.items.firstIndex(where: { $0.id == id }) else { return }
        apply(&list.items[index])
        selectedShootList = list
    }

    /// The current server-side truth for one item, so a sheet holding a snapshot
    /// taken when it opened can redraw from what actually saved.
    func item(id: String) -> YearbookItem? {
        selectedShootList?.items.first { $0.id == id }
    }

    func dismissError() { error = nil }

    // MARK: - List Operations
    
    /// Create a new yearbook list
    func createYearbookList(
        organizationId: String,
        schoolId: String,
        schoolName: String,
        schoolYear: String,
        items: [YearbookItem]
    ) async throws {
        let dates = YearbookShootList.getSchoolYearDates(schoolYear: schoolYear) ?? (Date(), Date())
        
        let newList = YearbookShootList(
            organizationId: organizationId,
            schoolId: schoolId,
            schoolName: schoolName,
            schoolYear: schoolYear,
            startDate: dates.start,
            endDate: dates.end,
            isActive: schoolYear == YearbookShootList.getCurrentSchoolYear(),
            copiedFromId: nil,
            completedCount: 0,
            totalCount: items.count,
            items: items,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        _ = try await service.createYearbookShootList(newList)
    }
    
    /// Copy a yearbook list
    func copyYearbookList(
        fromListId: String,
        toSchoolId: String,
        toSchoolYear: String,
        toSchoolName: String
    ) async throws {
        _ = try await service.copyYearbookShootList(
            fromListId: fromListId,
            toSchoolId: toSchoolId,
            toSchoolYear: toSchoolYear,
            toSchoolName: toSchoolName
        )
    }
    
    /// Delete a yearbook list
    func deleteYearbookList(_ listId: String) async throws {
        try await service.deleteYearbookShootList(listId: listId)
        
        // Remove from local array
        shootLists.removeAll { $0.id == listId }
        
        // Clear selection if deleted
        if selectedShootList?.id == listId {
            selectedShootList = nil
        }
    }
    
    // MARK: - Filter Operations
    //
    // `clearFilters()` and `applyQuickFilter(_:)` are GONE, with the `QuickFilter`
    // enum whose `.required` case fell through to `break`. A quick filter now sets
    // `filter.quick` and nothing else; "Clear Filters" is `filter = .clear` and is
    // reachable only from the no-matches state, where clearing everything is what
    // the button says it does.

    // MARK: - Export Operations
    
    /// Export completed items as text
    func exportCompletedItems() -> String {
        guard let list = selectedShootList else { return "" }
        
        var export = "Yearbook Checklist Export\n"
        export += "\(list.schoolName) - \(list.schoolYear)\n"
        export += "Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))\n"
        export += "Completion: \(list.completedCount)/\(list.totalCount) (\(Int(list.completionPercentage))%)\n\n"
        
        let groupedItems = list.itemsByCategory()
        
        for (category, items) in groupedItems {
            export += "\n\(category):\n"
            for item in items {
                let status = item.completed ? "✓" : "○"
                export += "  \(status) \(item.name)"
                
                if item.completed,
                   let photographer = item.photographerName,
                   let date = item.completedDate {
                    let dateStr = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
                    export += " (by \(photographer) on \(dateStr))"
                }
                
                if let notes = item.notes, !notes.isEmpty {
                    export += "\n     Notes: \(notes)"
                }
                
                if let imageNumbers = item.imageNumbers, !imageNumbers.isEmpty {
                    export += "\n     Images: \(imageNumbers.joined(separator: ", "))"
                }
                
                export += "\n"
            }
        }
        
        return export
    }
}

// MARK: - Preview Support

extension YearbookShootListViewModel {
    static var preview: YearbookShootListViewModel {
        let vm = YearbookShootListViewModel()
        
        // Create sample data
        let sampleItems = [
            YearbookItem(name: "Team Photo", category: "Sports", order: 1),
            YearbookItem(name: "Individual Player Photos", category: "Sports", order: 2),
            YearbookItem(name: "Action Shots", category: "Sports", completed: true, order: 3),
            YearbookItem(name: "Class Group Photo", category: "Academics", order: 1),
            YearbookItem(name: "Teacher Portraits", category: "Academics", order: 2),
            YearbookItem(name: "Classroom Activities", category: "Academics", completed: true, order: 3)
        ]
        
        vm.selectedShootList = YearbookShootList(
            id: "preview",
            organizationId: "org123",
            schoolId: "school123",
            schoolName: "Lincoln High School",
            schoolYear: "2024-2025",
            startDate: Date(),
            endDate: Date(),
            isActive: true,
            copiedFromId: nil,
            completedCount: 2,
            totalCount: 6,
            items: sampleItems,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        return vm
    }
}