//
//  to.swift
//  Iconik Employee
//
//  Created by administrator on 5/19/25.
//


import Foundation
import Network
import Combine

/// A class to monitor network connectivity
class ConnectivityMonitor {
    static let shared = ConnectivityMonitor()
    
    // Network path monitor
    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "ConnectivityMonitor")
    
    // Subject for publishing connectivity changes
    private let connectivitySubject = CurrentValueSubject<Bool, Never>(true)
    
    /// A publisher for connectivity status
    var connectivityPublisher: AnyPublisher<Bool, Never> {
        return connectivitySubject.eraseToAnyPublisher()
    }
    
    /// Current connectivity status
    var isConnected: Bool {
        return connectivitySubject.value
    }
    
    private init() {
        monitor = NWPathMonitor()
        
        // Set up the monitoring
        monitor.pathUpdateHandler = { [weak self] path in
            let newConnectionStatus = path.status == .satisfied
            
            // Only send updates when status changes
            if self?.connectivitySubject.value != newConnectionStatus {
                // Update on main thread to safely update UI
                DispatchQueue.main.async {
                    self?.connectivitySubject.send(newConnectionStatus)
                }
            }
        }
        
        // Start monitoring
        monitor.start(queue: monitorQueue)
    }
    
    deinit {
        monitor.cancel()
    }
}