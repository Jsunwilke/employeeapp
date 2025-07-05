//
//  ConflictResolver.swift
//  Iconik Employee
//
//  Created by administrator on 5/19/25.
//


import SwiftUI
import Combine

/// A wrapper around the ConflictResolutionView that handles presenting the conflict UI
struct ConflictResolver: ViewModifier {
    // MARK: - Published Properties
    
    @Binding var isPresented: Bool
    
    // Conflict data
    let eventData: ConflictEvent?
    
    // Completion handler
    let onComplete: (Bool) -> Void
    
    // MARK: - Body
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                if let event = eventData {
                    ConflictResolutionView(
                        shootID: event.shootID,
                        entryConflicts: event.entryConflicts,
                        groupConflicts: event.groupConflicts,
                        localShoot: event.localShoot,
                        remoteShoot: event.remoteShoot,
                        onComplete: { success in
                            isPresented = false
                            onComplete(success)
                        }
                    )
                } else {
                    // Fallback if event data is not available
                    Text("No conflict data available")
                        .padding()
                }
            }
    }
}

/// A coordinator for handling conflict events and presenting the conflict UI
class ConflictCoordinator: ObservableObject {
    // MARK: - Published Properties
    
    @Published var showConflictUI = false
    @Published var currentConflict: ConflictEvent?
    
    // MARK: - Private Properties
    
    private let eventBus: EventBus
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(eventBus: EventBus = EventBus.shared) {
        self.eventBus = eventBus
        
        // Subscribe to conflict events
        subscribeToConflictEvents()
    }
    
    // MARK: - Private Methods
    
    private func subscribeToConflictEvents() {
        eventBus.subscribe("ConflictCoordinator", eventType: ConflictEvent.self) { [weak self] event in
            DispatchQueue.main.async {
                // Store the conflict data
                self?.currentConflict = event
                
                // Show the conflict UI
                self?.showConflictUI = true
            }
        }
        .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Handle conflict resolution completion
    func handleResolutionComplete(success: Bool) {
        // Reset conflict data
        currentConflict = nil
    }
    
    deinit {
        // Clean up subscriptions
        eventBus.unsubscribe("ConflictCoordinator")
        cancellables.forEach { $0.cancel() }
    }
}

// MARK: - View Extension

extension View {
    /// Add conflict resolution handling to a view
    func withConflictResolution(coordinator: ConflictCoordinator) -> some View {
        self.modifier(ConflictResolver(
            isPresented: $coordinator.showConflictUI,
            eventData: coordinator.currentConflict,
            onComplete: { success in
                coordinator.handleResolutionComplete(success: success)
            }
        ))
    }
}