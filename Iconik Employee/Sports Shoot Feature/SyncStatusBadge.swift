//
//  SyncStatusBadge.swift
//  Iconik Employee
//
//  Updated to use PowerSync for visual sync feedback
//

import SwiftUI

// A component to display the sync status badge for sports shoots
struct SyncStatusBadge: View {
    let shootID: UUID

    @ObservedObject private var powerSync = PowerSyncManager.shared
    @State private var rotationAngle: Double = 0

    var body: some View {
        statusIcon
    }

    private var statusIcon: some View {
        Group {
            if powerSync.isSyncing {
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
            } else if powerSync.lastSyncTime != nil {
                // Fully synced
                Image(systemName: "checkmark.icloud")
                    .foregroundColor(.green)
            } else {
                EmptyView()
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: powerSync.isSyncing)
    }
}

// MARK: - Connection Status Indicator for Header
struct ConnectionStatusIndicator: View {
    @ObservedObject private var powerSync = PowerSyncManager.shared

    var body: some View {
        HStack(spacing: 4) {
            // Status icon
            Image(systemName: powerSync.isConnected ? "wifi" : "wifi.slash")
                .foregroundColor(powerSync.isConnected ? .green : .red)
                .font(.system(size: 12))

            // Status text - optional, can be hidden in compact views
            Text(powerSync.isConnected ? "Online" : "Offline")
                .font(.caption)
                .foregroundColor(powerSync.isConnected ? .green : .red)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(powerSync.isConnected ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        )
        .animation(.easeInOut(duration: 0.3), value: powerSync.isConnected)
    }
}

// A compact version that just shows an icon for tight spaces
struct CompactConnectionIndicator: View {
    @ObservedObject private var powerSync = PowerSyncManager.shared

    var body: some View {
        Image(systemName: powerSync.isConnected ? "wifi" : "wifi.slash")
            .foregroundColor(powerSync.isConnected ? .green : .red)
            .font(.system(size: 12))
            .animation(.easeInOut(duration: 0.3), value: powerSync.isConnected)
    }
}
