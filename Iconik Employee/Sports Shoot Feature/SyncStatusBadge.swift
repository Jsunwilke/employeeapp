//
//  SyncStatusBadge.swift
//  Iconik Employee
//
//  Created by administrator on 5/18/25.
//  Updated to use BackgroundSyncService for visual sync feedback

import SwiftUI

// A component to display the sync status badge for sports shoots
struct SyncStatusBadge: View {
    let shootID: String

    @ObservedObject private var syncService = BackgroundSyncService.shared
    @State private var pendingCount: Int = 0
    @State private var isCached: Bool = false
    @State private var rotationAngle: Double = 0

    // Timer to control refresh frequency
    @State private var timer: Timer? = nil

    var body: some View {
        statusIcon
            .onAppear {
                updateStatus()
                setupTimer()
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }

    private var statusIcon: some View {
        Group {
            if syncService.isSyncing && pendingCount > 0 {
                // Actively syncing - use rotation animation
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.green)
                    .rotationEffect(.degrees(rotationAngle))
                    .onAppear {
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            rotationAngle = 360
                        }
                    }
                    .onDisappear {
                        rotationAngle = 0
                    }
            } else if pendingCount > 0 {
                // Has pending changes waiting to sync
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundColor(.orange)
            } else if !syncService.lastSyncSuccess {
                // Last sync had errors
                Image(systemName: "exclamationmark.icloud")
                    .foregroundColor(.red)
            } else if isCached {
                // Fully synced and cached
                Image(systemName: "icloud.and.arrow.down.fill")
                    .foregroundColor(.blue)
            } else {
                EmptyView()
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: syncService.isSyncing)
        .animation(.easeInOut(duration: 0.3), value: pendingCount)
    }

    private func setupTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            updateStatus()
        }
    }

    private func updateStatus() {
        let newPendingCount = PendingSyncManager.shared.pendingChangeCount(for: shootID)
        let newIsCached = LocalSportsShootRepository.shared.isFullyCached(shootId: shootID)

        if pendingCount != newPendingCount || isCached != newIsCached {
            withAnimation {
                pendingCount = newPendingCount
                isCached = newIsCached
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
