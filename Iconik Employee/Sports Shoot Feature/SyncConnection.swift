//
//  SyncConnection.swift
//  Iconik Employee
//
//  Connection state machine for the iPad ↔ Surface WebSocket. Mirror of
//  src/data/sync/sync-connection.ts on the Mac side. Replaces boolean
//  `isConnected` checks that historically caused mis-routing of writes
//  during transient connection flips (the 2026-04-23 modal-revert bug).
//
//  This module is transport-agnostic. The actual WebSocket lifecycle is
//  driven by FocalPointSyncClient; this state machine observes events and
//  exposes a clean read API. The routing decision (`canDeliverEventually`)
//  is the single source of truth for "should this write go via WebSocket?".
//
//  See IPAD_SURFACE_SYNC_REWRITE.md §6.
//

import Foundation
import Combine

enum SyncConnectionState: String {
    case disconnected
    case connecting
    case authenticating
    case connected
    case degraded
    case reconnecting
    case failed
}

@MainActor
final class SyncConnection: ObservableObject {
    static let shared = SyncConnection()

    @Published private(set) var state: SyncConnectionState = .disconnected
    @Published private(set) var lastAckAt: Date? = nil
    @Published private(set) var lastHeartbeatAt: Date? = nil
    @Published private(set) var lastStateChangeAt: Date = Date()

    private static let activeStates: Set<SyncConnectionState> = [.connected, .degraded, .reconnecting]
    private static let terminalStates: Set<SyncConnectionState> = [.disconnected, .failed]

    private static let heartbeatDegradeSeconds: TimeInterval = 30
    private static let ackDegradeSeconds: TimeInterval = 30

    private init() {}

    // MARK: - Public API

    /// Routing decision: should writes go through the WebSocket pathway?
    /// True for active states (including `reconnecting` — caller persists into
    /// the send queue and we flush when the socket reopens). False ONLY for
    /// terminal states (disconnected, failed); in those states the caller MUST
    /// surface an offline UI rather than dual-write.
    var canDeliverEventually: Bool {
        SyncConnection.activeStates.contains(state)
    }

    var isTerminallyOffline: Bool {
        SyncConnection.terminalStates.contains(state)
    }

    // MARK: - Transitions (called by FocalPointSyncClient lifecycle)

    func noteConnectStarted() {
        if state == .disconnected || state == .failed || state == .reconnecting {
            transition(to: .connecting, reason: "connect_started")
        }
    }

    func noteSocketOpenHelloSent() {
        if state == .connecting || state == .reconnecting {
            transition(to: .authenticating, reason: "socket_open")
        }
    }

    func noteHandshakeComplete() {
        transition(to: .connected, reason: "handshake_complete")
        lastHeartbeatAt = Date()
    }

    func noteMessageReceived() {
        lastHeartbeatAt = Date()
        if state == .degraded {
            transition(to: .connected, reason: "message_received")
        }
    }

    func noteAckReceived() {
        lastAckAt = Date()
        noteMessageReceived()
    }

    func noteSocketClosed(intentional: Bool) {
        if intentional {
            transition(to: .disconnected, reason: "intentional_close")
        } else if state != .failed {
            transition(to: .reconnecting, reason: "socket_closed_unexpected")
        }
    }

    func noteHandshakeTimeout() {
        transition(to: .failed, reason: "handshake_timeout")
    }

    func noteReconnectAttemptsExhausted() {
        transition(to: .failed, reason: "reconnect_exhausted")
    }

    func noteUserInitiatedReconnect() {
        if state == .failed || state == .disconnected {
            transition(to: .connecting, reason: "user_reconnect")
        }
    }

    // MARK: - Heartbeat watchdog

    /// Promote `connected` to `degraded` when no heartbeat in 30s. Call
    /// periodically from a Timer (e.g., every 5s) on the main actor.
    func watchdogTick() {
        guard state == .connected, let last = lastHeartbeatAt else { return }
        if Date().timeIntervalSince(last) > SyncConnection.heartbeatDegradeSeconds {
            transition(to: .degraded, reason: "heartbeat_silence")
        }
    }

    // MARK: - Test seam

    func _testReset() {
        state = .disconnected
        lastAckAt = nil
        lastHeartbeatAt = nil
        lastStateChangeAt = Date()
    }

    // MARK: - Internals

    private func transition(to next: SyncConnectionState, reason: String) {
        guard next != state else { return }
        let prev = state
        state = next
        lastStateChangeAt = Date()
        print("[SyncConnection] \(prev.rawValue) → \(next.rawValue) (\(reason))")
    }
}
