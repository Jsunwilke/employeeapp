import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
class YearbookShootListViewModel: ObservableObject {
    @Published var shootLists: [YearbookShootList] = []
    @Published var selectedShootList: YearbookShootList?
    @Published var availableYears: [String] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var searchText = ""
    @Published var selectedCategory: String = "All"
    @Published var showCompletedOnly = false
    @Published var showIncompleteOnly = false
    
    private let service = YearbookShootListService.shared
    private var listListener: ListenerRegistration?
    private var organizationListener: ListenerRegistration?
    
    // Session context for integration
    var sessionContext: YearbookSessionContext?
    
    // Current user info
    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    private var currentUserName: String? {
        Auth.auth().currentUser?.displayName
    }
    
    // MARK: - Computed Properties
    
    var filteredItems: [YearbookItem] {
        guard let list = selectedShootList else { return [] }
        
        var items = list.items
        
        // Filter by search text
        if !searchText.isEmpty {
            items = items.filter { item in
                item.name.localizedCaseInsensitiveContains(searchText) ||
                (item.description?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                item.category.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Filter by category
        if selectedCategory != "All" {
            items = items.filter { $0.category == selectedCategory }
        }
        
        // Filter by completion status
        if showCompletedOnly {
            items = items.filter { $0.completed }
        } else if showIncompleteOnly {
            items = items.filter { !$0.completed }
        }
        
        return items.sorted { $0.order < $1.order }
    }
    
    var categories: [String] {
        guard let list = selectedShootList else { return ["All"] }
        let uniqueCategories = Set(list.items.map { $0.category })
        return ["All"] + uniqueCategories.sorted()
    }
    
    var groupedFilteredItems: [(category: String, items: [YearbookItem])] {
        let grouped = Dictionary(grouping: filteredItems) { $0.category }
        return grouped.sorted { $0.key < $1.key }
            .map { (category: $0.key, items: $0.value.sorted { $0.order < $1.order }) }
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
    
    /// Toggle completion status of an item
    func toggleItemCompletion(_ item: YearbookItem) async {
        guard let listId = selectedShootList?.id else { return }
        
        do {
            try await service.toggleItemCompletion(
                listId: listId,
                itemId: item.id,
                sessionContext: sessionContext
            )
            
            // Optimistic update for better UX
            if var list = selectedShootList,
               let index = list.items.firstIndex(where: { $0.id == item.id }) {
                list.items[index].completed.toggle()
                list.completedCount += list.items[index].completed ? 1 : -1
                selectedShootList = list
            }
        } catch {
            self.error = error
            print("❌ Error toggling item: \(error)")
        }
    }
    
    /// Update notes for an item
    func updateItemNotes(_ item: YearbookItem, notes: String?) async {
        guard let listId = selectedShootList?.id else { return }
        
        do {
            try await service.updateItemNotes(
                listId: listId,
                itemId: item.id,
                notes: notes
            )
        } catch {
            self.error = error
        }
    }
    
    /// Update image numbers for an item
    func updateItemImageNumbers(_ item: YearbookItem, imageNumbers: [String]) async {
        guard let listId = selectedShootList?.id else { return }
        
        do {
            try await service.updateItemImageNumbers(
                listId: listId,
                itemId: item.id,
                imageNumbers: imageNumbers
            )
        } catch {
            self.error = error
        }
    }
    
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
    
    func clearFilters() {
        searchText = ""
        selectedCategory = "All"
        showCompletedOnly = false
        showIncompleteOnly = false
    }
    
    func applyQuickFilter(_ filter: QuickFilter) {
        clearFilters()
        
        switch filter {
        case .all:
            break
        case .completed:
            showCompletedOnly = true
        case .incomplete:
            showIncompleteOnly = true
        case .required:
            // Would need to add a showRequiredOnly property
            break
        }
    }
    
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

// MARK: - Supporting Types

enum QuickFilter {
    case all
    case completed
    case incomplete
    case required
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