import Foundation
import Firebase
import FirebaseFirestore
import Combine
import SwiftUI

/// View model for the sports shoot list
class SportsShootListViewModel: ObservableObject {
    // MARK: - Published Properties
    
    // Main data
    @Published var sportsShoots: [SportsShoot] = []
    @Published var selectedShoot: SportsShoot? = nil
    
    // UI states
    @Published var isLoading = true
    @Published var errorMessage = ""
    @Published var showingErrorAlert = false
    
    // Network status
    @Published var isOnline = true
    
    // States for roster management
    @Published var showingAddRosterEntry = false
    @Published var showingAddGroupImage = false
    @Published var selectedRosterEntry: RosterEntry?
    @Published var selectedGroupImage: GroupImage?
    @Published var selectedTab = 0 // 0 = Athletes, 1 = Groups
    
    // Sort states
    @Published var sortField: String = "firstName" // Default to sort by Subject ID
    @Published var sortAscending: Bool = true
    
    // Import/Export state
    @Published var showingImportExport = false
    @Published var showingMultiPhotoImport = false
    
    // Field editing state
    @Published var currentlyEditingEntry: String? = nil // ID of entry being edited
    @Published var editingImageNumber: String = ""
    @Published var lockedEntries: [String: String] = [:] // [entryID: editorName]
    
    // UI state - header collapsed in landscape
    @Published var isHeaderCollapsed = false
    
    // Filter panel state
    @Published var showFilterPanel = false
    @Published var selectedFilters: Set<String> = []
    @Published var selectedSpecialFilters: Set<String> = []
    @Published var imageFilterType: ImageFilterType = .all
    
    // MARK: - Private Properties
    
    // Dependency injection
    private let repository: SportsShootRepositoryProtocol
    private let eventBus: EventBus
    
    // User info from AppStorage
    private var userOrganizationID: String = ""
    private var userFirstName: String = ""
    private var userLastName: String = ""
    
    // Track subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // Device session ID - unique to this app instance
    private let deviceSessionID = UUID().uuidString
    
    // MARK: - Initialization
    
    init(
        repository: SportsShootRepositoryProtocol = SportsShootRepository(),
        eventBus: EventBus = EventBus.shared,
        userOrganizationID: String = "",
        userFirstName: String = "",
        userLastName: String = ""
    ) {
        self.repository = repository
        self.eventBus = eventBus
        self.userOrganizationID = userOrganizationID
        self.userFirstName = userFirstName
        self.userLastName = userLastName
        
        // Setup event subscriptions
        setupSubscriptions()
    }
    
    // MARK: - Subscriptions
    
    private func setupSubscriptions() {
        // Network status subscription
        eventBus.subscribe("SportsShootListViewModel", eventType: NetworkStatusEvent.self) { [weak self] event in
            self?.isOnline = event.isOnline
        }
        .store(in: &cancellables)
        
        // Lock updates subscription
        eventBus.subscribe("SportsShootListViewModel", eventType: LockUpdateEvent.self) { [weak self] event in
            guard let selectedShoot = self?.selectedShoot, selectedShoot.id == event.shootID else { return }
            self?.lockedEntries = event.locks
        }
        .store(in: &cancellables)
        
        // Entry update subscription
        eventBus.subscribe("SportsShootListViewModel", eventType: EntryUpdateEvent.self) { [weak self] event in
            guard let selectedShoot = self?.selectedShoot, selectedShoot.id == event.shootID else { return }
            self?.refreshSelectedShoot()
        }
        .store(in: &cancellables)
        
        // Conflict detection subscription
        eventBus.subscribe("SportsShootListViewModel", eventType: ConflictEvent.self) { [weak self] event in
            self?.handleConflictDetected(event)
        }
        .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Load all sports shoots for the current organization
    func loadSportsShoots() {
        guard !userOrganizationID.isEmpty else {
            errorMessage = "No organization ID found. Please sign in again."
            showingErrorAlert = true
            return
        }
        
        isLoading = true
        print("Fetching sports shoots with organization ID: \(userOrganizationID)")
        
        repository.fetchAllSportsShoots(forOrganization: userOrganizationID)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    
                    if case let .failure(error) = completion {
                        print("Error loading sports shoots: \(error.localizedDescription)")
                        self?.errorMessage = "Failed to load sports shoots: \(error.localizedDescription)"
                        self?.showingErrorAlert = true
                    }
                },
                receiveValue: { [weak self] shoots in
                    print("Successfully fetched \(shoots.count) sports shoots")
                    self?.sportsShoots = shoots
                }
            )
            .store(in: &cancellables)
    }
    
    /// Refresh the currently selected shoot
    func refreshSelectedShoot() {
        guard let currentShoot = selectedShoot else { return }
        
        repository.fetchSportsShoot(id: currentShoot.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case let .failure(error) = completion {
                        self?.errorMessage = "Failed to refresh: \(error.localizedDescription)"
                        self?.showingErrorAlert = true
                    }
                },
                receiveValue: { [weak self] updatedShoot in
                    // Update the selected shoot
                    self?.selectedShoot = updatedShoot
                    
                    // Also update this shoot in the list
                    if let index = self?.sportsShoots.firstIndex(where: { $0.id == updatedShoot.id }) {
                        self?.sportsShoots[index] = updatedShoot
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    /// Cache a shoot for offline use
    func cacheShootForOffline(id: String) {
        repository.cacheShootForOffline(id: id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case let .failure(error) = completion {
                        self?.errorMessage = "Failed to save for offline use: \(error.localizedDescription)"
                        self?.showingErrorAlert = true
                    }
                },
                receiveValue: { [weak self] success in
                    if success {
                        // Show success message
                        self?.errorMessage = "This shoot is now available offline"
                        self?.showingErrorAlert = true
                    } else {
                        // Show error message
                        self?.errorMessage = "Failed to save for offline use. Please try again."
                        self?.showingErrorAlert = true
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Roster Entry Operations
    
    /// Add a new roster entry
    func addRosterEntry(shootID: String, entry: RosterEntry) {
        repository.addRosterEntry(shootID: shootID, entry: entry)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case let .failure(error) = completion {
                        self?.errorMessage = "Failed to add roster entry: \(error.localizedDescription)"
                        self?.showingErrorAlert = true
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.refreshSelectedShoot()
                }
            )
            .store(in: &cancellables)
    }
    
    /// Update an existing roster entry
    func updateRosterEntry(shootID: String, entry: RosterEntry) {
        repository.updateRosterEntry(shootID: shootID, entry: entry)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case let .failure(error) = completion {
                        self?.errorMessage = "Failed to update roster entry: \(error.localizedDescription)"
                        self?.showingErrorAlert = true
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.refreshSelectedShoot()
                }
            )
            .store(in: &cancellables)
    }
    
    /// Delete a roster entry
    func deleteRosterEntry(shootID: String, entryID: String) {
        repository.deleteRosterEntry(shootID: shootID, entryID: entryID)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case let .failure(error) = completion {
                        self?.errorMessage = "Failed to delete roster entry: \(error.localizedDescription)"
                        self?.showingErrorAlert = true
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.refreshSelectedShoot()
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Group Image Operations
    
    /// Add a new group image
    func addGroupImage(shootID: String, groupImage: GroupImage) {
        repository.addGroupImage(shootID: shootID, groupImage: groupImage)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case let .failure(error) = completion {
                        self?.errorMessage = "Failed to add group image: \(error.localizedDescription)"
                        self?.showingErrorAlert = true
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.refreshSelectedShoot()
                }
            )
            .store(in: &cancellables)
    }
    
    /// Update an existing group image
    func updateGroupImage(shootID: String, groupImage: GroupImage) {
        repository.updateGroupImage(shootID: shootID, groupImage: groupImage)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case let .failure(error) = completion {
                        self?.errorMessage = "Failed to update group image: \(error.localizedDescription)"
                        self?.showingErrorAlert = true
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.refreshSelectedShoot()
                }
            )
            .store(in: &cancellables)
    }
    
    /// Delete a group image
    func deleteGroupImage(shootID: String, groupID: String) {
        repository.deleteGroupImage(shootID: shootID, groupID: groupID)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case let .failure(error) = completion {
                        self?.errorMessage = "Failed to delete group image: \(error.localizedDescription)"
                        self?.showingErrorAlert = true
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.refreshSelectedShoot()
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Lock Management
    
    /// Acquire a lock for an entry
    func acquireLock(shootID: String, entryID: String) -> AnyPublisher<Bool, Error> {
        let editorID = Auth.auth().currentUser?.uid ?? UUID().uuidString
        let editorName = "\(userFirstName) \(userLastName) (\(deviceSessionID.prefix(8)))"
        
        return repository.acquireLock(shootID: shootID, entryID: entryID, editorID: editorID, editorName: editorName)
            .handleEvents(receiveOutput: { [weak self] success in
                if success {
                    self?.currentlyEditingEntry = entryID
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Release a lock for an entry
    func releaseLock(shootID: String, entryID: String) -> AnyPublisher<Bool, Error> {
        let editorID = Auth.auth().currentUser?.uid ?? UUID().uuidString
        
        return repository.releaseLock(shootID: shootID, entryID: entryID, editorID: editorID)
            .handleEvents(receiveOutput: { [weak self] success in
                if success && self?.currentlyEditingEntry == entryID {
                    self?.currentlyEditingEntry = nil
                    self?.editingImageNumber = ""
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Observe locks for a shoot
    func observeLocks(shootID: String) {
        repository.observeLocks(shootID: shootID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] locks in
                self?.lockedEntries = locks
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Helper Methods
    
    /// Determine if device is currently online
    func isDeviceOnline() -> Bool {
        return repository.isDeviceOnline()
    }
    
    /// Current user identifier combines name and device
    var currentEditorIdentifier: String {
        return "\(userFirstName) \(userLastName) (\(deviceSessionID.prefix(8)))"
    }
    
    /// Check if a lock is owned by the current device
    func isOwnLock(_ lockId: String) -> Bool {
        return lockedEntries[lockId] == currentEditorIdentifier
    }
    
    /// Start editing an entry - acquires lock and sets up editing state
    func startEditing(shootID: String, entry: RosterEntry) {
        // Check if anyone else is editing this entry
        if let editor = lockedEntries[entry.id], !isOwnLock(entry.id) {
            // Entry is locked by someone else - show an alert
            errorMessage = "This entry is currently being edited by \(editor)"
            showingErrorAlert = true
            return
        }
        
        // Check if we already have a lock on this entry
        if isOwnLock(entry.id) {
            // We already have the lock, just start editing without acquiring a new lock
            currentlyEditingEntry = entry.id
            editingImageNumber = entry.imageNumbers
            return
        }
        
        // Release any previous lock
        if let previousEntryID = currentlyEditingEntry {
            _ = releaseLock(shootID: shootID, entryID: previousEntryID)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { _ in }
                )
                .store(in: &cancellables)
        }
        
        // Set up editing state
        editingImageNumber = entry.imageNumbers
        
        // Acquire lock for this entry
        acquireLock(shootID: shootID, entryID: entry.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case let .failure(error) = completion {
                        self?.errorMessage = "Failed to acquire lock: \(error.localizedDescription)"
                        self?.showingErrorAlert = true
                    }
                },
                receiveValue: { [weak self] success in
                    if !success {
                        self?.errorMessage = "This entry is currently being edited by someone else"
                        self?.showingErrorAlert = true
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    /// Save current editing state for an entry
    func saveEditingEntry(shootID: String) {
        guard let entryID = currentlyEditingEntry,
              let selectedShoot = selectedShoot,
              let entry = selectedShoot.roster.first(where: { $0.id == entryID }) else {
            return
        }
        
        // Create updated entry with new image number
        var updatedEntry = entry
        updatedEntry.imageNumbers = editingImageNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Update in repository
        updateRosterEntry(shootID: shootID, entry: updatedEntry)
        
        // Release the lock
        _ = releaseLock(shootID: shootID, entryID: entryID)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }
    
    /// Cancel editing an entry
    func cancelEditing(shootID: String) {
        if let entryID = currentlyEditingEntry {
            _ = releaseLock(shootID: shootID, entryID: entryID)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { _ in }
                )
                .store(in: &cancellables)
        }
    }
    
    // MARK: - Conflict Handling
    
    /// Handle conflict detected event
    private func handleConflictDetected(_ event: ConflictEvent) {
        // This method would show the conflict resolution UI
        // In a real implementation, it would present a modal view controller
        print("Conflict detected for shoot: \(event.shootID)")
        print("Entry conflicts: \(event.entryConflicts.count)")
        print("Group conflicts: \(event.groupConflicts.count)")
        
        // This would be replaced with actual UI display code
        // The conflict resolution UI is implemented separately
    }
    
    // MARK: - Data Manipulation
    
    /// Filter roster based on selected filters
    func filterRoster(_ roster: [RosterEntry]) -> [RosterEntry] {
        // Apply filters in sequence
        
        // First, filter by group and special categories
        var filteredRoster = roster
        
        // If group or special filters are selected
        if !selectedFilters.isEmpty || !selectedSpecialFilters.isEmpty {
            filteredRoster = roster.filter { entry in
                // Check if entry matches any selected group filter
                let matchesGroup = selectedFilters.contains(entry.group)
                
                // Check if entry matches any selected special filter
                let matchesSpecial = (selectedSpecialFilters.contains("Seniors") && entry.teacher.lowercased() == "s") ||
                                    (selectedSpecialFilters.contains("8th Graders") && entry.teacher.lowercased() == "8") ||
                                    (selectedSpecialFilters.contains("Coaches") && entry.teacher.lowercased() == "c")
                
                // If both filter types are applied, match entries that satisfy BOTH conditions
                if !selectedFilters.isEmpty && !selectedSpecialFilters.isEmpty {
                    return matchesGroup && matchesSpecial
                }
                // If only group filters are applied
                else if !selectedFilters.isEmpty {
                    return matchesGroup
                }
                // If only special filters are applied
                else {
                    return matchesSpecial
                }
            }
        }
        
        // Then, apply image filter if set
        switch imageFilterType {
        case .all:
            // No additional filtering needed
            return filteredRoster
        case .hasImages:
            // Filter for entries with image numbers
            return filteredRoster.filter { !$0.imageNumbers.isEmpty }
        case .noImages:
            // Filter for entries without image numbers
            return filteredRoster.filter { $0.imageNumbers.isEmpty }
        }
    }
    
    /// Sort roster entries based on current sort field and direction
    func sortRoster(_ roster: [RosterEntry]) -> [RosterEntry] {
        return roster.sorted { (a, b) -> Bool in
            let result: Bool
            
            switch sortField {
            case "lastName":
                result = a.lastName.lowercased() < b.lastName.lowercased()
            case "firstName":
                result = a.firstName.lowercased() < b.firstName.lowercased()
            case "teacher":
                result = a.teacher.lowercased() < b.teacher.lowercased()
            case "group":
                result = a.group.lowercased() < b.group.lowercased()
            default:
                result = a.lastName.lowercased() < b.lastName.lowercased()
            }
            
            return sortAscending ? result : !result
        }
    }
    
    /// Get all unique group names from the current roster
    func allGroupNames() -> [String] {
        guard let shoot = selectedShoot else { return [] }
        
        let allGroups = Set(shoot.roster.map { $0.group })
        return Array(allGroups).filter { !$0.isEmpty }.sorted()
    }
    
    /// Helper function to translate special codes
    func specialTranslation(_ special: String) -> String {
        switch special.lowercased() {
        case "c": return "Coach"
        case "s": return "Senior"
        case "8": return "8th Grader"
        default: return special // Return as is if not one of the special codes
        }
    }
    
    /// Clean up resources when view model is no longer needed
    func cleanup() {
        // Cancel all subscriptions
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        
        // Release any active locks
        if let shootID = selectedShoot?.id, let entryID = currentlyEditingEntry {
            _ = releaseLock(shootID: shootID, entryID: entryID)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { _ in }
                )
                .store(in: &cancellables)
        }
        
        // Unsubscribe from event bus
        eventBus.unsubscribe("SportsShootListViewModel")
    }
    
    deinit {
        cleanup()
    }
}

// MARK: - Enums

enum ImageFilterType {
    case all
    case hasImages
    case noImages
}