//
//  FocalPointSyncClient.swift
//  Iconik Employee
//
//  WebSocket client for iPad ↔ Surface Pro (Focal Point Production) real-time sync.
//  Discovers Production's WebSocket server via mDNS, connects, and enables:
//    - Tap athlete on iPad → auto-select subject on Surface Pro
//    - Surface Pro captures → auto-fill image numbers on iPad
//    - Device pairing for multi-camera setups
//

import Foundation
import Network
import Combine
import UIKit

// MARK: - Connection Status

enum FPSyncConnectionStatus: Equatable {
    case disconnected
    case discovering
    case connecting
    case connected
    case authFailed
}

// MARK: - Device Info

struct FPSyncDevice: Identifiable, Equatable {
    let id: String  // device_id
    let name: String
    let stationMode: String
    var captureCount: Int
}

// MARK: - Capture Completed Event

struct FPCaptureEvent {
    let subjectId: String
    let rosterEntryId: String?
    let imageNumber: Int?
    let captureFilename: String?
    let stationName: String
    let fromDeviceId: String
}

// MARK: - FocalPointSyncClient

@MainActor
class FocalPointSyncClient: ObservableObject {
    static let shared = FocalPointSyncClient()

    // Published state
    @Published var connectionStatus: FPSyncConnectionStatus = .disconnected
    @Published var devices: [FPSyncDevice] = []
    @Published var pairedCameraId: String? = nil

    // Callbacks
    var onCaptureCompleted: ((FPCaptureEvent) -> Void)?
    var onSubjectPhotographed: ((String, String?, Int?) -> Void)?  // subjectId, thumbnail, poseNumber
    var onActiveSubjectChanged: ((String) -> Void)?                // subjectId — Production selected a subject
    var onQCFlagChanged: ((String, Bool) -> Void)?                 // subjectId, flagged
    var onSubjectAbsentChanged: ((String, Bool) -> Void)?          // subjectId, isAbsent
    var onNotesChanged: ((String, String?, String) -> Void)?       // subjectId, rosterEntryId, notes
    var onQueueReorder: (([String]) -> Void)?                      // ordered subject_ids
    var onGroupPhotoReady: ((String, [String], Int) -> Void)?      // groupName, presentSubjectIds, total

    // Internal state
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var heartbeatTimer: Timer?
    private var reconnectTimer: Timer?
    private var reconnectDelay: TimeInterval = 2.0
    private var intentionalClose = false
    private var galleryId: String?
    private var authToken: String = ""

    /// Set the auth token (PIN) for manual connection
    func setAuthToken(_ token: String) {
        authToken = token
    }

    /// Set the gallery ID for manual connection
    func setGalleryId(_ id: String) {
        galleryId = id
    }

    // mDNS discovery
    private var browser: NWBrowser?
    private var discoveredServers: [(host: String, port: Int, token: String)] = []

    // Device identity (persistent across sessions)
    private var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: "fp_sync_device_id") {
            return id
        }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "fp_sync_device_id")
        return id
    }

    private var deviceName: String {
        return UIDevice.current.name
    }

    // Connection info for reconnection
    private var lastHost: String?
    private var lastPort: Int?

    private let maxReconnectDelay: TimeInterval = 15.0

    var isConnected: Bool {
        connectionStatus == .connected
    }

    // MARK: - Discovery

    func startDiscovery(galleryId: String, authToken: String? = nil) {
        self.galleryId = galleryId
        // Only override authToken if explicitly provided (preserve token set via setAuthToken)
        if let token = authToken {
            self.authToken = token
        }
        connectionStatus = .discovering
        discoveredServers = []

        // Try last known server first
        if let lastServer = UserDefaults.standard.dictionary(forKey: "fp_last_server"),
           let ip = lastServer["ip"] as? String,
           let port = lastServer["port"] as? Int {
            print("[FPSync] Trying last known server \(ip):\(port)")
            connect(host: ip, port: port)

            // Give it 3 seconds, then fall back to mDNS if not connected
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self, self.connectionStatus != .connected else { return }
                self.browseMDNS()
            }
            return
        }

        browseMDNS()
    }

    private func browseMDNS() {
        browser?.cancel()

        let params = NWParameters()
        params.includePeerToPeer = true
        browser = NWBrowser(for: .bonjour(type: "_focal-point._tcp", domain: nil), using: params)

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            for result in results {
                if case .service(let name, let type, let domain, _) = result.endpoint {
                    print("[FPSync] Discovered: \(name) (\(type) in \(domain))")
                    self.resolveService(result: result)
                }
            }
        }

        browser?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[FPSync] mDNS browser ready")
            case .failed(let error):
                print("[FPSync] mDNS browser failed: \(error)")
            default:
                break
            }
        }

        browser?.start(queue: .main)

        // Timeout: stop browsing after 10 seconds if not connected
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self else { return }
            if self.connectionStatus == .discovering {
                self.connectionStatus = .disconnected
                self.browser?.cancel()
                self.browser = nil
                print("[FPSync] mDNS discovery timed out")
            }
        }
    }

    private nonisolated func resolveService(result: NWBrowser.Result) {
        // Extract auth token from mDNS TXT record
        var discoveredToken: String?
        if case .bonjour(let txtRecord) = result.metadata {
            if let entry = txtRecord.getEntry(for: "token") {
                switch entry {
                case .string(let token):
                    discoveredToken = token
                    print("[FPSync] Found token in TXT record")
                default:
                    print("[FPSync] TXT 'token' entry exists but not a string")
                }
            } else {
                print("[FPSync] No 'token' key in TXT record")
            }
        } else {
            print("[FPSync] No Bonjour metadata in mDNS result")
        }

        let connection = NWConnection(to: result.endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .ready = state {
                if let endpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = endpoint {
                    let hostStr = "\(host)"
                        .replacingOccurrences(of: "%.*", with: "", options: .regularExpression)
                    let portInt = Int(port.rawValue)
                    connection.cancel()
                    Task { @MainActor in
                        if self.connectionStatus != .connected {
                            // Set auth token from TXT record before connecting
                            if let token = discoveredToken {
                                self.authToken = token
                            }
                            self.connect(host: hostStr, port: portInt)
                        }
                    }
                }
            }
        }
        connection.start(queue: .main)
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
    }

    // MARK: - Connection

    func connect(host: String, port: Int) {
        guard connectionStatus != .connected else { return }

        intentionalClose = false
        connectionStatus = .connecting
        lastHost = host
        lastPort = port

        let url = URL(string: "ws://\(host):\(port)")!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        urlSession = URLSession(configuration: config)
        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()

        startReceiving()
        startHeartbeat()

        // Wait for WebSocket to open before sending hello
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if self.webSocket?.state == .running {
                self.sendHello()
                self.connectionStatus = .connected
                self.reconnectDelay = 2.0
                self.stopDiscovery()

                // Remember server for fast reconnect
                UserDefaults.standard.set(["ip": host, "port": port], forKey: "fp_last_server")

                print("[FPSync] Connected to \(host):\(port)")
            }
        }
    }

    func disconnect() {
        intentionalClose = true
        stopHeartbeat()
        stopReconnect()
        stopDiscovery()
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        urlSession = nil
        connectionStatus = .disconnected
        devices = []
        pairedCameraId = nil
        UserDefaults.standard.removeObject(forKey: "fp_last_server")
        print("[FPSync] Disconnected")
    }

    // MARK: - Device Pairing

    func pairWithCamera(deviceId: String) {
        pairedCameraId = deviceId
        print("[FPSync] Paired with camera: \(deviceId)")
    }

    func unpairCamera() {
        pairedCameraId = nil
    }

    /// Camera station devices from the device list
    var cameraDevices: [FPSyncDevice] {
        devices.filter { $0.stationMode == "camera" && $0.id != deviceId }
    }

    // MARK: - Actions

    /// Send subject selection to the paired camera station
    func selectSubject(subjectId: String, rosterEntryId: String?, subjectName: String) {
        guard isConnected else {
            print("[FPSync] Cannot select subject — not connected")
            return
        }
        guard let galleryId = galleryId else {
            print("[FPSync] Cannot select subject — no gallery linked")
            return
        }

        // Validate subject_id is a valid UUID format
        guard UUID(uuidString: subjectId) != nil else {
            print("[FPSync] Invalid subject_id: \(subjectId)")
            return
        }

        let msg: [String: Any] = [
            "type": "select_subject_request",
            "device_id": deviceId,
            "gallery_id": galleryId,
            "subject_id": subjectId,
            "roster_entry_id": rosterEntryId ?? NSNull(),
            "subject_name": subjectName,
            "target_device_id": pairedCameraId ?? NSNull(),
            "station_name": "iPad - \(deviceName)",
        ]
        send(msg)
    }

    /// Mark a subject as absent/present and notify Production
    func markSubjectAbsent(subjectId: String, rosterEntryId: String?, isAbsent: Bool) {
        guard isConnected, let galleryId = galleryId else { return }
        let msg: [String: Any] = [
            "type": "subject_absent_changed",
            "device_id": deviceId,
            "gallery_id": galleryId,
            "subject_id": subjectId,
            "roster_entry_id": rosterEntryId ?? NSNull(),
            "is_absent": isAbsent,
            "station_name": "iPad - \(deviceName)",
        ]
        send(msg)
    }

    /// Send notes update for a subject
    func sendNotes(subjectId: String, rosterEntryId: String?, notes: String) {
        guard isConnected, let galleryId = galleryId else { return }
        // Cap notes length
        let trimmed = String(notes.prefix(1000))
        let msg: [String: Any] = [
            "type": "subject_notes_changed",
            "device_id": deviceId,
            "gallery_id": galleryId,
            "subject_id": subjectId,
            "roster_entry_id": rosterEntryId ?? NSNull(),
            "notes": trimmed,
            "station_name": "iPad - \(deviceName)",
        ]
        send(msg)
    }

    /// Send queue reorder to Production
    func sendQueueReorder(orderedSubjectIds: [String]) {
        guard isConnected, let galleryId = galleryId else { return }
        // Cap at 2000 entries
        let capped = Array(orderedSubjectIds.prefix(2000))
        let msg: [String: Any] = [
            "type": "queue_reorder",
            "device_id": deviceId,
            "gallery_id": galleryId,
            "ordered_subject_ids": capped,
            "station_name": "iPad - \(deviceName)",
        ]
        send(msg)
    }

    /// Signal that a group is ready for their team photo
    func sendGroupPhotoReady(groupName: String, presentSubjectIds: [String], totalInGroup: Int) {
        guard isConnected, let galleryId = galleryId else { return }
        let msg: [String: Any] = [
            "type": "group_photo_ready",
            "device_id": deviceId,
            "gallery_id": galleryId,
            "group_name": groupName,
            "present_subject_ids": presentSubjectIds,
            "total_in_group": totalInGroup,
            "station_name": "iPad - \(deviceName)",
        ]
        send(msg)
    }

    // MARK: - Sending

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(str)) { error in
            if let error = error {
                print("[FPSync] Send error: \(error)")
            }
        }
    }

    private func sendHello() {
        let msg: [String: Any] = [
            "type": "device_hello",
            "device_id": deviceId,
            "device_name": "iPad - \(deviceName)",
            "station_mode": "ios_roster",
            "gallery_id": galleryId ?? "",
            "auth_token": authToken,
        ]
        send(msg)
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let msg: [String: Any] = [
                    "type": "heartbeat",
                    "device_id": self.deviceId,
                    "gallery_id": self.galleryId ?? "",
                    "station_mode": "ios_roster",
                    "active_subject_id": "",
                    "capture_count": 0,
                    "queue_length": 0,
                ]
                self.send(msg)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Receiving

    private func startReceiving() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        if let data = text.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            self.handleMessage(json)
                        }
                    default:
                        break
                    }
                    // Continue receiving
                    self.startReceiving()

                case .failure(let error):
                    print("[FPSync] Receive error: \(error)")
                    self.handleDisconnect()
                }
            }
        }
    }

    private func handleMessage(_ msg: [String: Any]) {
        guard let type = msg["type"] as? String else { return }

        // Skip messages from ourselves
        if let senderId = msg["device_id"] as? String, senderId == deviceId { return }

        // Skip messages for a different gallery
        if let msgGalleryId = msg["gallery_id"] as? String,
           let ourGalleryId = galleryId,
           !msgGalleryId.isEmpty && !ourGalleryId.isEmpty && msgGalleryId != ourGalleryId {
            return
        }

        switch type {
        case "device_list":
            if let deviceList = msg["devices"] as? [[String: Any]] {
                devices = deviceList.compactMap { d in
                    guard let id = d["device_id"] as? String,
                          let name = d["device_name"] as? String else { return nil }
                    return FPSyncDevice(
                        id: id,
                        name: name,
                        stationMode: d["station_mode"] as? String ?? "unknown",
                        captureCount: d["capture_count"] as? Int ?? 0
                    )
                }.filter { $0.id != deviceId }

                // Auto-pair if exactly one camera and no pairing yet
                if pairedCameraId == nil {
                    let cameras = cameraDevices
                    if cameras.count == 1 {
                        pairWithCamera(deviceId: cameras[0].id)
                    }
                }
            }

        case "capture_completed":
            // Validate required fields
            guard let subjectId = msg["subject_id"] as? String, !subjectId.isEmpty,
                  UUID(uuidString: subjectId) != nil else { break }
            let event = FPCaptureEvent(
                subjectId: subjectId,
                rosterEntryId: msg["roster_entry_id"] as? String,
                imageNumber: msg["image_number"] as? Int,
                captureFilename: msg["capture_filename"] as? String,
                stationName: msg["station_name"] as? String ?? "Unknown",
                fromDeviceId: msg["device_id"] as? String ?? ""
            )
            // Only process from our paired camera (or any if not paired)
            if pairedCameraId == nil || event.fromDeviceId == pairedCameraId {
                onCaptureCompleted?(event)
            }

        case "subject_photographed":
            guard let subjectId = msg["subject_id"] as? String, !subjectId.isEmpty,
                  UUID(uuidString: subjectId) != nil else { break }
            var thumbnail = msg["thumbnail"] as? String
            // Cap thumbnail size at 500KB to prevent memory abuse
            if let thumb = thumbnail, thumb.count > 500_000 {
                thumbnail = nil
            }
            let poseNumber = msg["pose_number"] as? Int
            if let fromDevice = msg["device_id"] as? String,
               pairedCameraId == nil || fromDevice == pairedCameraId {
                onSubjectPhotographed?(subjectId, thumbnail, poseNumber)
            }

        case "auth_error":
            connectionStatus = .authFailed
            disconnect()

        case "active_subject_changed":
            guard let subjectId = msg["subject_id"] as? String, !subjectId.isEmpty,
                  UUID(uuidString: subjectId) != nil else { break }
            if let fromDevice = msg["device_id"] as? String,
               pairedCameraId == nil || fromDevice == pairedCameraId {
                onActiveSubjectChanged?(subjectId)
            }

        case "qc_flag_changed":
            guard let subjectId = msg["subject_id"] as? String, !subjectId.isEmpty,
                  UUID(uuidString: subjectId) != nil else { break }
            let flagged = msg["flagged"] as? Bool ?? false
            if let fromDevice = msg["device_id"] as? String,
               pairedCameraId == nil || fromDevice == pairedCameraId {
                onQCFlagChanged?(subjectId, flagged)
            }

        case "subject_absent_changed":
            guard let subjectId = msg["subject_id"] as? String,
                  UUID(uuidString: subjectId) != nil else { break }
            let isAbsent = msg["is_absent"] as? Bool ?? false
            onSubjectAbsentChanged?(subjectId, isAbsent)

        case "subject_notes_changed":
            guard let subjectId = msg["subject_id"] as? String,
                  UUID(uuidString: subjectId) != nil else { break }
            let notes = String((msg["notes"] as? String ?? "").prefix(1000))
            let rosterEntryId = msg["roster_entry_id"] as? String
            onNotesChanged?(subjectId, rosterEntryId, notes)

        case "queue_reorder":
            if let orderedIds = msg["ordered_subject_ids"] as? [String],
               orderedIds.count <= 2000 {
                onQueueReorder?(orderedIds)
            }

        case "group_photo_ready":
            if let groupName = msg["group_name"] as? String,
               let presentIds = msg["present_subject_ids"] as? [String],
               let total = msg["total_in_group"] as? Int,
               presentIds.count <= 2000 {
                onGroupPhotoReady?(groupName, presentIds, total)
            }

        case "device_disconnected":
            if let disconnectedId = msg["device_id"] as? String {
                devices.removeAll { $0.id == disconnectedId }
                // Warn if paired camera disconnected
                if disconnectedId == pairedCameraId {
                    pairedCameraId = nil
                }
            }

        default:
            break
        }
    }

    // MARK: - Reconnection

    private func handleDisconnect() {
        connectionStatus = .disconnected
        stopHeartbeat()

        guard !intentionalClose, let host = lastHost, let port = lastPort else { return }
        scheduleReconnect(host: host, port: port)
    }

    private func scheduleReconnect(host: String, port: Int) {
        stopReconnect()
        print("[FPSync] Reconnecting in \(reconnectDelay)s")
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.reconnectDelay = min(self.reconnectDelay * 1.5, self.maxReconnectDelay)
                self.connect(host: host, port: port)
            }
        }
    }

    private func stopReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
}
