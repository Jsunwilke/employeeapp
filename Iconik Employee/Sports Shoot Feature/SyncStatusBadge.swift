//
//  SyncStatusBadge.swift
//  Iconik Employee
//
//  Created by administrator on 5/18/25.
//  Updated to fix UI flashing issues and improve performance

import SwiftUI

// A component to display the sync status badge for sports shoots
struct SyncStatusBadge: View {
    let shootID: String
    
    // Use state instead of observed object to reduce unnecessary refreshes
    @State private var status: OfflineManager.CacheStatus = .notCached
    @State private var isOnline: Bool = true
    
    // Timer to control refresh frequency
    @State private var timer: Timer? = nil
    
    var body: some View {
        statusIcon
            .onAppear {
                // Initial status update
                updateStatus()
                
                // Set up a less aggressive timer (5 seconds instead of 2)
                setupTimer()
            }
            .onDisappear {
                // Clean up timer when view disappears
                timer?.invalidate()
                timer = nil
            }
    }
    
    private var statusIcon: some View {
        Group {
            switch status {
            case .notCached:
                if isOnline {
                    EmptyView()  // No badge for uncached shoots when online
                } else {
                    // When offline, show that this shoot is not available
                    Image(systemName: "icloud.slash")
                        .foregroundColor(.red)
                        .transition(.opacity) // Smooth transition to prevent harsh flashing
                }
            case .cached:
                Image(systemName: "icloud.and.arrow.down.fill")
                    .foregroundColor(.blue)
                    .transition(.opacity)
            case .modified:
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundColor(.orange)
                    .transition(.opacity)
            case .syncing:
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.green)
                    .transition(.opacity)
            case .error:
                Image(systemName: "exclamationmark.icloud")
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: status) // Add animation to smooth transitions
    }
    
    private func setupTimer() {
        // Use a longer interval to reduce flashing (5 seconds)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            // Only update if the view is visible (parent is responsible for removing when not visible)
            updateStatus()
        }
    }
    
    private func updateStatus() {
        // Get status from the offline manager - using a method that doesn't trigger UI updates
        let newStatus = OfflineManager.shared.cacheStatusForShoot(id: shootID)
        let isCurrentlyOnline = OfflineManager.shared.isDeviceOnline()
        
        // Only update if something actually changed to avoid unnecessary UI refreshes
        if status != newStatus || isOnline != isCurrentlyOnline {
            // Update status with animation to prevent flashing
            withAnimation {
                status = newStatus
                isOnline = isCurrentlyOnline
            }
        }
    }
}

// MARK: - Connection Status Indicator for Header
struct ConnectionStatusIndicator: View {
    // Use state to avoid excessive refreshes
    @State private var isOnline: Bool = true
    @State private var timer: Timer? = nil
    
    var body: some View {
        HStack(spacing: 4) {
            // Status icon
            Image(systemName: isOnline ? "wifi" : "wifi.slash")
                .foregroundColor(isOnline ? .green : .red)
                .font(.system(size: 12))
            
            // Status text - optional, can be hidden in compact views
            Text(isOnline ? "Online" : "Offline")
                .font(.caption)
                .foregroundColor(isOnline ? .green : .red)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isOnline ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        )
        .onAppear {
            // Get initial status
            updateConnectionStatus()
            
            // Set up a timer with reasonable frequency
            setupTimer()
            
            // Listen for network status changes
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("NetworkStatusChanged"),
                object: nil,
                queue: .main
            ) { notification in
                if let isConnected = notification.userInfo?["isConnected"] as? Bool {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.isOnline = isConnected
                    }
                }
            }
            
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("OfflineManagerNetworkStatusChanged"),
                object: nil,
                queue: .main
            ) { notification in
                if let isConnected = notification.userInfo?["isOnline"] as? Bool {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.isOnline = isConnected
                    }
                }
            }
        }
        .onDisappear {
            // Clean up
            timer?.invalidate()
            timer = nil
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    private func setupTimer() {
        timer?.invalidate()
        // Less frequent updates (5 seconds) to reduce visual distraction
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            updateConnectionStatus()
        }
    }
    
    private func updateConnectionStatus() {
        let newStatus = OfflineManager.shared.isDeviceOnline()
        
        // Only update if status actually changed
        if isOnline != newStatus {
            withAnimation(.easeInOut(duration: 0.3)) {
                isOnline = newStatus
            }
        }
    }
}

// A compact version that just shows an icon for tight spaces
struct CompactConnectionIndicator: View {
    @State private var isOnline: Bool = true
    
    var body: some View {
        Image(systemName: isOnline ? "wifi" : "wifi.slash")
            .foregroundColor(isOnline ? .green : .red)
            .font(.system(size: 12))
            .onAppear {
                updateStatus()
                
                // Listen for network status changes
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("NetworkStatusChanged"),
                    object: nil,
                    queue: .main
                ) { notification in
                    if let isConnected = notification.userInfo?["isConnected"] as? Bool {
                        withAnimation {
                            self.isOnline = isConnected
                        }
                    }
                }
            }
            .onDisappear {
                NotificationCenter.default.removeObserver(self)
            }
    }
    
    private func updateStatus() {
        let newStatus = OfflineManager.shared.isDeviceOnline()
        if isOnline != newStatus {
            withAnimation {
                isOnline = newStatus
            }
        }
    }
}
