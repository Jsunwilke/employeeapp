//
//  SyncStatusBadge.swift
//  Iconik Employee
//
//  Updated to use SyncEngine for visual sync feedback
//

import SwiftUI

// A component to display the sync status badge for sports shoots
struct SyncStatusBadge: View {
    let shootID: UUID

    @ObservedObject private var syncEngine = SyncEngine.shared
    @State private var rotationAngle: Double = 0

    var body: some View {
        statusIcon
    }

    private var statusIcon: some View {
        Group {
            if syncEngine.isSyncing && syncEngine.pendingCount > 0 {
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
            } else if syncEngine.pendingCount > 0 {
                // Has pending changes waiting to sync
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundColor(.orange)
            } else if !syncEngine.activeConflicts.isEmpty {
                // Has unresolved conflicts
                Image(systemName: "exclamationmark.icloud")
                    .foregroundColor(.red)
            } else if syncEngine.lastSyncTime != nil {
                // Fully synced
                Image(systemName: "checkmark.icloud")
                    .foregroundColor(.green)
            } else {
                EmptyView()
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: syncEngine.isSyncing)
        .animation(.easeInOut(duration: 0.3), value: syncEngine.pendingCount)
    }
}

// MARK: - Connection Status Indicator for Header
struct ConnectionStatusIndicator: View {
    @ObservedObject private var syncEngine = SyncEngine.shared

    var body: some View {
        HStack(spacing: 4) {
            // Status icon
            Image(systemName: syncEngine.isOnline ? "wifi" : "wifi.slash")
                .foregroundColor(syncEngine.isOnline ? .green : .red)
                .font(.system(size: 12))

            // Status text - optional, can be hidden in compact views
            Text(syncEngine.isOnline ? "Online" : "Offline")
                .font(.caption)
                .foregroundColor(syncEngine.isOnline ? .green : .red)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(syncEngine.isOnline ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        )
        .animation(.easeInOut(duration: 0.3), value: syncEngine.isOnline)
    }
}

// A compact version that just shows an icon for tight spaces
struct CompactConnectionIndicator: View {
    @ObservedObject private var syncEngine = SyncEngine.shared

    var body: some View {
        Image(systemName: syncEngine.isOnline ? "wifi" : "wifi.slash")
            .foregroundColor(syncEngine.isOnline ? .green : .red)
            .font(.system(size: 12))
            .animation(.easeInOut(duration: 0.3), value: syncEngine.isOnline)
    }
}
