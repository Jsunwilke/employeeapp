//
//  AppEvent.swift
//  Iconik Employee
//
//  Created by administrator on 5/19/25.
//


import Foundation
import Combine

/// Enum for all possible events in the app
enum AppEvent {
    // Network events
    case networkStatusChanged(isOnline: Bool)
    
    // Sync events
    case syncStatusChanged(shootID: String, status: CacheStatus)
    case shootCached(shootID: String)
    
    // Lock events
    case locksUpdated(shootID: String, locks: [String: String])
    case lockAcquired(shootID: String, entryID: String, editorName: String)
    case lockReleased(shootID: String, entryID: String, editorName: String)
    case lockStaleRemoved(shootID: String, entryID: String, editorName: String)
    
    // Data events
    case rosterEntryUpdated(shootID: String, entryID: String)
    case rosterEntryUpdateFailed(shootID: String, entryID: String)
    case rosterEntryDeleted(shootID: String, entryID: String)
    case groupImageUpdated(shootID: String, groupID: String)
    case groupImageUpdateFailed(shootID: String, groupID: String)
    case groupImageDeleted(shootID: String, groupID: String)
    
    // Conflict events
    case conflictsDetected(
        shootID: String,
        entryConflicts: [ConflictEntry],
        groupConflicts: [ConflictGroup],
        localShoot: SportsShoot,
        remoteShoot: SportsShoot
    )
}

/// Central event bus for app-wide event handling
class EventBus {
    static let shared = EventBus()
    
    // Subject to publish events
    private let eventSubject = PassthroughSubject<AppEvent, Never>()
    
    // Dictionary to hold subscribers to specific event types
    private var subscribers = [String: [AnyCancellable]]()
    
    /// Publisher for all events
    var publisher: AnyPublisher<AppEvent, Never> {
        return eventSubject.eraseToAnyPublisher()
    }
    
    private init() {}
    
    /// Publish an event to the bus
    func publish(_ event: AppEvent) {
        // Dispatch to main thread for UI safety
        DispatchQueue.main.async { [weak self] in
            self?.eventSubject.send(event)
        }
    }
    
    /// Subscribe to all events
    func subscribe(_ subscriber: String, handler: @escaping (AppEvent) -> Void) -> AnyCancellable {
        let cancellable = eventSubject.sink { event in
            handler(event)
        }
        
        // Store the subscription
        if subscribers[subscriber] == nil {
            subscribers[subscriber] = []
        }
        subscribers[subscriber]?.append(cancellable)
        
        return cancellable
    }
    
    /// Subscribe to specific event types
    func subscribe<T>(_ subscriber: String, eventType: T.Type, handler: @escaping (T) -> Void) -> AnyCancellable where T: AppEventConvertible {
        let cancellable = eventSubject
            .compactMap { event -> T? in
                return T.convert(from: event)
            }
            .sink { typedEvent in
                handler(typedEvent)
            }
        
        // Store the subscription
        if subscribers[subscriber] == nil {
            subscribers[subscriber] = []
        }
        subscribers[subscriber]?.append(cancellable)
        
        return cancellable
    }
    
    /// Unsubscribe a specific subscriber from all events
    func unsubscribe(_ subscriber: String) {
        subscribers[subscriber]?.forEach { $0.cancel() }
        subscribers.removeValue(forKey: subscriber)
    }
}

/// Protocol for converting AppEvent to specific event types
protocol AppEventConvertible {
    static func convert(from event: AppEvent) -> Self?
}

// MARK: - Event Type Wrappers

/// Network events
struct NetworkStatusEvent: AppEventConvertible {
    let isOnline: Bool
    
    static func convert(from event: AppEvent) -> NetworkStatusEvent? {
        if case .networkStatusChanged(let isOnline) = event {
            return NetworkStatusEvent(isOnline: isOnline)
        }
        return nil
    }
}

/// Sync events
struct SyncStatusEvent: AppEventConvertible {
    let shootID: String
    let status: CacheStatus
    
    static func convert(from event: AppEvent) -> SyncStatusEvent? {
        if case .syncStatusChanged(let shootID, let status) = event {
            return SyncStatusEvent(shootID: shootID, status: status)
        }
        return nil
    }
}

/// Lock events
struct LockUpdateEvent: AppEventConvertible {
    let shootID: String
    let locks: [String: String]
    
    static func convert(from event: AppEvent) -> LockUpdateEvent? {
        if case .locksUpdated(let shootID, let locks) = event {
            return LockUpdateEvent(shootID: shootID, locks: locks)
        }
        return nil
    }
}

/// Data update events
struct EntryUpdateEvent: AppEventConvertible {
    let shootID: String
    let entryID: String
    
    static func convert(from event: AppEvent) -> EntryUpdateEvent? {
        if case .rosterEntryUpdated(let shootID, let entryID) = event {
            return EntryUpdateEvent(shootID: shootID, entryID: entryID)
        }
        return nil
    }
}

/// Conflict events
struct ConflictEvent: AppEventConvertible {
    let shootID: String
    let entryConflicts: [ConflictEntry]
    let groupConflicts: [ConflictGroup]
    let localShoot: SportsShoot
    let remoteShoot: SportsShoot
    
    static func convert(from event: AppEvent) -> ConflictEvent? {
        if case .conflictsDetected(let shootID, let entryConflicts, let groupConflicts, let localShoot, let remoteShoot) = event {
            return ConflictEvent(
                shootID: shootID,
                entryConflicts: entryConflicts,
                groupConflicts: groupConflicts,
                localShoot: localShoot,
                remoteShoot: remoteShoot
            )
        }
        return nil
    }
}