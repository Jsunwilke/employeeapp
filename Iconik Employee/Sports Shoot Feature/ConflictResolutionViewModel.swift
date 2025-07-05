import Foundation
import Combine

/// ViewModel for conflict resolution
class ConflictResolutionViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var entryConflicts: [ConflictEntry] = []
    @Published var groupConflicts: [ConflictGroup] = []
    @Published var localShoot: SportsShoot
    @Published var remoteShoot: SportsShoot
    
    @Published var useLocalEntries: Set<String> = []
    @Published var useRemoteEntries: Set<String> = []
    @Published var useLocalGroups: Set<String> = []
    @Published var useRemoteGroups: Set<String> = []
    
    @Published var isResolving = false
    @Published var resolutionComplete = false
    @Published var error: Error?
    
    // MARK: - Private Properties
    
    private let shootID: String
    private let repository: SportsShootRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(
        shootID: String,
        entryConflicts: [ConflictEntry],
        groupConflicts: [ConflictGroup],
        localShoot: SportsShoot,
        remoteShoot: SportsShoot,
        repository: SportsShootRepositoryProtocol = SportsShootRepository()
    ) {
        self.shootID = shootID
        self.entryConflicts = entryConflicts
        self.groupConflicts = groupConflicts
        self.localShoot = localShoot
        self.remoteShoot = remoteShoot
        self.repository = repository
    }
    
    // MARK: - Public Methods
    
    /// Toggle selection of local entry
    func toggleLocalEntry(_ id: String) {
        // If selecting local, deselect remote
        if useRemoteEntries.contains(id) {
            useRemoteEntries.remove(id)
        }
        
        // Toggle local
        if useLocalEntries.contains(id) {
            useLocalEntries.remove(id)
        } else {
            useLocalEntries.insert(id)
        }
    }
    
    /// Toggle selection of remote entry
    func toggleRemoteEntry(_ id: String) {
        // If selecting remote, deselect local
        if useLocalEntries.contains(id) {
            useLocalEntries.remove(id)
        }
        
        // Toggle remote
        if useRemoteEntries.contains(id) {
            useRemoteEntries.remove(id)
        } else {
            useRemoteEntries.insert(id)
        }
    }
    
    /// Toggle selection of local group
    func toggleLocalGroup(_ id: String) {
        // If selecting local, deselect remote
        if useRemoteGroups.contains(id) {
            useRemoteGroups.remove(id)
        }
        
        // Toggle local
        if useLocalGroups.contains(id) {
            useLocalGroups.remove(id)
        } else {
            useLocalGroups.insert(id)
        }
    }
    
    /// Toggle selection of remote group
    func toggleRemoteGroup(_ id: String) {
        // If selecting remote, deselect local
        if useLocalGroups.contains(id) {
            useLocalGroups.remove(id)
        }
        
        // Toggle remote
        if useRemoteGroups.contains(id) {
            useRemoteGroups.remove(id)
        } else {
            useRemoteGroups.insert(id)
        }
    }
    
    /// Use local version for all conflicts
    func useLocalForAll() {
        // Clear existing selections
        useRemoteEntries.removeAll()
        useRemoteGroups.removeAll()
        
        // Select all local entries
        for conflict in entryConflicts {
            useLocalEntries.insert(conflict.localEntry.id)
        }
        
        // Select all local groups
        for conflict in groupConflicts {
            useLocalGroups.insert(conflict.localGroup.id)
        }
    }
    
    /// Use remote version for all conflicts
    func useRemoteForAll() {
        // Clear existing selections
        useLocalEntries.removeAll()
        useLocalGroups.removeAll()
        
        // Select all remote entries
        for conflict in entryConflicts {
            useRemoteEntries.insert(conflict.remoteEntry.id)
        }
        
        // Select all remote groups
        for conflict in groupConflicts {
            useRemoteGroups.insert(conflict.remoteGroup.id)
        }
    }
    
    /// Check if all conflicts have been resolved
    func allConflictsResolved() -> Bool {
        // All entry conflicts resolved
        let entriesResolved = entryConflicts.allSatisfy { conflict in
            useLocalEntries.contains(conflict.localEntry.id) || useRemoteEntries.contains(conflict.remoteEntry.id)
        }
        
        // All group conflicts resolved
        let groupsResolved = groupConflicts.allSatisfy { conflict in
            useLocalGroups.contains(conflict.localGroup.id) || useRemoteGroups.contains(conflict.remoteGroup.id)
        }
        
        return entriesResolved && groupsResolved
    }
    
    /// Resolve conflicts and save
    func resolveConflicts(completion: @escaping (Bool) -> Void) {
        // Cannot resolve if not all conflicts have been addressed
        guard allConflictsResolved() else {
            completion(false)
            return
        }
        
        isResolving = true
        
        let offlineManager = OfflineManager.shared
        
        offlineManager.resolveConflicts(
            shootID: shootID,
            useLocalEntries: Array(useLocalEntries),
            useRemoteEntries: Array(useRemoteEntries),
            useLocalGroups: Array(useLocalGroups),
            useRemoteGroups: Array(useRemoteGroups)
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completionResult in
                self?.isResolving = false
                
                switch completionResult {
                case .failure(let error):
                    self?.error = error
                    completion(false)
                case .finished:
                    break
                }
            },
            receiveValue: { [weak self] success in
                self?.isResolving = false
                
                if success {
                    self?.resolutionComplete = true
                    completion(true)
                } else {
                    completion(false)
                }
            }
        )
        .store(in: &cancellables)
    }
}