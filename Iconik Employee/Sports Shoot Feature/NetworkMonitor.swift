//
//  NetworkMonitor.swift
//  Iconik Employee
//
//  Created by administrator on 5/18/25.
//  Updated with improved connection detection and notification

import Foundation
import Network
import SystemConfiguration

// MARK: - Network Monitoring
class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitoring")
    
    private(set) var isConnected: Bool = true
    private(set) var connectionType: ConnectionType = .unknown
    private var statusChangeHandler: ((Bool) -> Void)?
    
    // Reachability check timer
    private var reachabilityTimer: Timer?
    private let reachabilityCheckInterval: TimeInterval = 5.0 // Check every 5 seconds
    
    // Time of last successful network operation
    private var lastSuccessfulNetworkOperation = Date()
    private let networkTimeout: TimeInterval = 10.0 // Consider dead after 10 seconds
    
    // Singleton instance
    static let shared = NetworkMonitor()
    
    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case unknown
    }
    
    init() {
        // Set up the path monitor
        setupPathMonitor()
        
        // Initialize with a reachability check
        performReachabilityCheck()
    }
    
    private func setupPathMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            let newConnectionStatus = path.status == .satisfied
            let connectionType = self?.determineConnectionType(from: path) ?? .unknown
            
            DispatchQueue.main.async {
                // Update the connection type first
                self?.connectionType = connectionType
                
                // Only update and notify if there's a change in connection status
                if self?.isConnected != newConnectionStatus {
                    self?.isConnected = newConnectionStatus
                    
                    // Always perform a reachability check to confirm
                    self?.performReachabilityCheck()
                    
                    // Notify handler if set
                    if let handler = self?.statusChangeHandler {
                        handler(newConnectionStatus)
                    }
                    
                    // Post a notification for any interested observers
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NetworkStatusChanged"),
                        object: nil,
                        userInfo: ["isConnected": newConnectionStatus]
                    )
                    
                    // Also post the special notification for OfflineManager
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OfflineManagerNetworkStatusChanged"),
                        object: nil,
                        userInfo: ["isOnline": newConnectionStatus]
                    )
                }
            }
        }
        
        monitor.start(queue: queue)
    }
    
    func startMonitoring(onStatusChange: @escaping (Bool) -> Void) {
        self.statusChangeHandler = onStatusChange
        
        // Start additional reachability check timer
        startReachabilityTimer()
        
        // Immediately notify with current status
        DispatchQueue.main.async {
            onStatusChange(self.isConnected)
        }
    }
    
    func stopMonitoring() {
        statusChangeHandler = nil
        stopReachabilityTimer()
        // Don't stop the NWPathMonitor as other components might be using it
    }
    
    // Helper to check current connection status immediately
    func getCurrentConnectionStatus() -> Bool {
        performReachabilityCheck() // Update status with a fresh check
        return isConnected
    }
    
    // Record a successful network operation
    func recordSuccessfulNetworkOperation() {
        lastSuccessfulNetworkOperation = Date()
    }
    
    // MARK: - Enhanced Reachability Checking
    
    private func startReachabilityTimer() {
        // Stop any existing timer
        stopReachabilityTimer()
        
        // Create a new timer on the main thread
        DispatchQueue.main.async {
            self.reachabilityTimer = Timer.scheduledTimer(
                timeInterval: self.reachabilityCheckInterval,
                target: self,
                selector: #selector(self.reachabilityTimerFired),
                userInfo: nil,
                repeats: true
            )
        }
    }
    
    private func stopReachabilityTimer() {
        DispatchQueue.main.async {
            self.reachabilityTimer?.invalidate()
            self.reachabilityTimer = nil
        }
    }
    
    @objc private func reachabilityTimerFired() {
        performReachabilityCheck()
    }
    
    private func performReachabilityCheck() {
        // Check if we've had a successful network operation recently
        let timeSinceLastSuccess = Date().timeIntervalSince(lastSuccessfulNetworkOperation)
        
        if timeSinceLastSuccess > networkTimeout && isConnected {
            // We think we're connected, but haven't had a successful operation in a while
            // Perform a deeper check
            deepReachabilityCheck()
        }
        
        // Check if we have real internet connectivity, not just network interface status
        let reachable = isNetworkReachable()
        
        if reachable != isConnected {
            // Status has changed - update and notify
            DispatchQueue.main.async {
                self.isConnected = reachable
                
                // Notify handler if set
                if let handler = self.statusChangeHandler {
                    handler(reachable)
                }
                
                // Post a notification for any interested observers
                NotificationCenter.default.post(
                    name: NSNotification.Name("NetworkStatusChanged"),
                    object: nil,
                    userInfo: ["isConnected": reachable]
                )
                
                // Also post the special notification for OfflineManager
                NotificationCenter.default.post(
                    name: NSNotification.Name("OfflineManagerNetworkStatusChanged"),
                    object: nil,
                    userInfo: ["isOnline": reachable]
                )
            }
        }
    }
    
    private func isNetworkReachable() -> Bool {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        guard let reachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else {
            return false
        }
        
        var flags: SCNetworkReachabilityFlags = []
        if !SCNetworkReachabilityGetFlags(reachability, &flags) {
            return false
        }
        
        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)
        let canConnectAutomatically = flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic)
        let canConnectWithoutUserInteraction = canConnectAutomatically && !flags.contains(.interventionRequired)
        
        return isReachable && (!needsConnection || canConnectWithoutUserInteraction)
    }
    
    private func deepReachabilityCheck() {
        // Perform a more intensive check by attempting to connect to a reliable server
        let url = URL(string: "https://www.apple.com")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5 // Short timeout
        request.httpMethod = "HEAD" // Just fetch headers, not the entire page
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            let isReachable = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            
            if isReachable {
                self?.recordSuccessfulNetworkOperation()
            }
            
            DispatchQueue.main.async {
                if let self = self, self.isConnected != isReachable {
                    self.isConnected = isReachable
                    
                    // Notify handler if set
                    if let handler = self.statusChangeHandler {
                        handler(isReachable)
                    }
                    
                    // Post notifications
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NetworkStatusChanged"),
                        object: nil,
                        userInfo: ["isConnected": isReachable]
                    )
                    
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OfflineManagerNetworkStatusChanged"),
                        object: nil,
                        userInfo: ["isOnline": isReachable]
                    )
                }
            }
        }
        
        task.resume()
    }
    
    private func determineConnectionType(from path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else {
            return .unknown
        }
    }
}
