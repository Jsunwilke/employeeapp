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
    var batteryLevel: Int?      // 0-100
    var batteryCharging: Bool?
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

// MARK: - Capture Info (for subject captures list)

struct FPCaptureInfo: Identifiable {
    let id = UUID()
    let filename: String
    let poseNumber: Int?
    let size: Int
    let timestamp: String
}

// MARK: - Full Image Result

struct FPFullImage {
    let image: UIImage
    let filename: String
    let size: Int
}

// MARK: - Sync Errors

enum FPSyncError: LocalizedError {
    case notConnected
    case timeout
    case invalidId
    case invalidImageData
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to Production"
        case .timeout: return "Request timed out"
        case .invalidId: return "Invalid ID format"
        case .invalidImageData: return "Could not decode image data"
        case .serverError(let msg): return msg
        }
    }
}

// MARK: - RemoteGroupRow

/// Full group_images row received over the LAN WebSocket. Used by the
/// onGroupUpdated callback so the receiver can apply the row directly to
/// local PowerSync without a cloud round-trip — required for offline
/// shoots. Fields are non-optional with safe defaults so missing wire
/// fields (older sender) still produce a usable row.
struct RemoteGroupRow {
    let id: String
    let galleryId: String
    let organizationId: String
    let description: String
    let imageNumbers: String
    let notes: String
    let sport: String
    let gender: String
    let teamLevel: String
    let sortOrder: Int
    let version: Int
    let updatedAt: String      // ISO 8601
    let updatedBy: String?
    let lockedBy: String?
    let lockedByName: String?
    let lockedAt: String?
    let createdAt: String      // ISO 8601
    let photographerId: String?
    let memberField: String?
    let memberValue: String?
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
    var onSubjectUpdated: ((String, String?, String, String, String, String) -> Void)?  // rosterEntryId, subjectId?, firstName, lastName, rosterId, senderDeviceId
    /// Same event, but carries every field present on the wire. Receivers
    /// that want to apply non-name edits (organization, custom1-20, etc.)
    /// instantly should bind this callback. Fired alongside onSubjectUpdated.
    /// Args: (rosterEntryId, subjectId?, fields, senderDeviceId)
    var onSubjectUpdatedFields: ((String, String?, SubjectSyncFields, String) -> Void)?
    /// Mirror of onSubjectCreated that carries every field on the wire so a
    /// remote add includes organization / custom / address / etc. without
    /// waiting for cloud round-trip. Fired alongside onSubjectCreated.
    /// Args: (rosterEntryId, fields, senderDeviceId)
    var onSubjectCreatedFields: ((String, SubjectSyncFields, String) -> Void)?
    var onQueueReorder: (([String]) -> Void)?                      // ordered subject_ids
    var onGroupPhotoReady: ((String, [String], Int) -> Void)?      // groupName, presentSubjectIds, total
    var onGroupCaptureCompleted: ((String, Int, String) -> Void)?  // groupId, imageNumber, filename — auto-fill image_numbers on group
    /// A device on the network created or edited a group row. Carries the FULL
    /// row payload so the receiver can apply it directly to local PowerSync —
    /// required for offline shoots where the LAN is the only path between
    /// iPad and Surface. The receiver should INSERT OR REPLACE on local
    /// SQLite; PowerSync's CRDT handles dedup once cloud sync resumes.
    /// Args: (groupId, senderDeviceId, fullRow as RemoteGroupRow)
    var onGroupUpdated: ((String, String, RemoteGroupRow) -> Void)?
    /// A device on the network hard-deleted a group row. Receiver should
    /// DELETE from local PowerSync; the same delete will propagate via
    /// cloud sync once both sides are online. Args: (groupId)
    var onGroupDeleted: ((String) -> Void)?
    var onSubjectLinked: ((String, String) -> Void)?               // rosterEntryId, subjectId — Production created a subject for this roster entry
    var onSubjectsDeleted: (([String]) -> Void)?                   // subject_ids deleted on Production
    var onSubjectCreated: ((String, String, String, String, String, String) -> Void)?  // rosterEntryId, firstName, lastName, rosterId, grade, groupName
    var onCaptureReassigned: ((Int, String, String) -> Void)?      // imageNumber, oldRosterEntryId, newRosterEntryId
    var onVerificationWarning: ((String, String, String, String, String?) -> Void)?  // subjectId, subjectName, status, message, qrData
    var onGalleryChanged: ((String, String) -> Void)?                               // oldGalleryId, newGalleryId
    /// Reconciliation snapshot from Surface — Surface periodically advertises
    /// its current view of the gallery's subjects so we can detect drift
    /// without waiting for cloud sync. Args: (galleryId, subjectCount, nameHash).
    var onSubjectStateSummary: ((String, Int, String) -> Void)?
    /// Fires when any other device on the same WebSocket bus drops its
    /// connection. UI can show a blocking alert so the photographer
    /// notices a kiosk/iPad going offline during a live shoot. Args:
    /// (deviceId, deviceName-at-time-of-disconnect).
    var onDeviceDisconnected: ((String, String) -> Void)?

    // Internal state
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var heartbeatTimer: Timer?
    // Sync rewrite — handshake watchdog. Set when sendHello fires; cleared
    // either on first inbound message or when this fires noteHandshakeTimeout.
    private var handshakeTimer: Timer?
    private let handshakeTimeoutSeconds: TimeInterval = 10.0
    private var pingTimer: Timer?
    private var missedPongs: Int = 0
    private let maxMissedPongs: Int = 2  // 2 missed pongs (20s) = dead
    private var reconnectTimer: Timer?
    private var reconnectDelay: TimeInterval = 2.0
    private(set) var intentionalClose = false
    private var galleryId: String?
    private var authToken: String = ""

    // Image request state
    private var requestIdCounter = 0
    private var pendingImageRequests: [String: CheckedContinuation<FPFullImage, Error>] = [:]
    private var pendingCaptureListRequests: [String: CheckedContinuation<[FPCaptureInfo], Error>] = [:]
    private var pendingImageHeader: [String: Any]? = nil
    private let imageRequestTimeout: TimeInterval = 30.0

    // Pending message queue (queued while disconnected, flushed on reconnect)
    private var pendingMessages: [[String: Any]] = []
    private let pendingQueueMax = 500
    private let staleMessageTypes: Set<String> = ["heartbeat", "log_report", "device_hello"]

    // Dedup for capture_completed events (prevents double-processing on retransmit)
    private var seenCaptureIds: Set<String> = []
    private let maxSeenCaptures = 1000

    /// Set the auth token (PIN) for manual connection
    func setAuthToken(_ token: String) {
        authToken = token
    }

    /// Set the gallery ID for manual connection
    func setGalleryId(_ id: String) {
        if galleryId != id {
            seenCaptureIds.removeAll()
            if !pendingMessages.isEmpty {
                print("[FPSync] Cleared \(pendingMessages.count) pending message(s) on gallery switch")
                pendingMessages.removeAll()
            }
        }
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
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 10

    // Auth retry (re-discover mDNS to get fresh token when server restarts)
    private var authRetryCount: Int = 0
    private let maxAuthRetries: Int = 3

    var isConnected: Bool {
        connectionStatus == .connected
    }

    // MARK: - Discovery

    func startDiscovery(galleryId: String, authToken: String? = nil) {
        if self.galleryId != galleryId {
            seenCaptureIds.removeAll()
            if !pendingMessages.isEmpty {
                print("[FPSync] Cleared \(pendingMessages.count) pending message(s) on gallery switch (discovery)")
                pendingMessages.removeAll()
            }
        }
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
        // Sync rewrite — tell the connection state machine we're attempting
        // a socket. SubjectSyncService.canDeliverEventually reads this state
        // to decide whether to write locally vs broadcast-only.
        SyncConnection.shared.noteConnectStarted()
        lastHost = host
        lastPort = port

        let url = URL(string: "ws://\(host):\(port)")!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        urlSession = URLSession(configuration: config)
        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()

        startReceiving()

        // Verify connection with a real ping before marking connected
        webSocket?.sendPing { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    print("[FPSync] Connection verification failed: \(error)")
                    self.handleDisconnect()
                    return
                }
                guard self.webSocket?.state == .running else {
                    self.handleDisconnect()
                    return
                }
                self.sendHello()
                SyncConnection.shared.noteSocketOpenHelloSent()
                self.connectionStatus = .connected
                // Treat connectionStatus=.connected as the handshake-complete
                // signal. The server's device_list response confirms shortly
                // after but the existing client doesn't gate on it.
                SyncConnection.shared.noteHandshakeComplete()
                // Start handshake watchdog — fires noteHandshakeTimeout if
                // no inbound message arrives within the window. The server
                // could be stuck at the application layer even with a live
                // TCP socket; without this the state machine sits in a
                // never-arriving state.
                self.handshakeTimer?.invalidate()
                self.handshakeTimer = Timer.scheduledTimer(withTimeInterval: self.handshakeTimeoutSeconds, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        guard let self = self else { return }
                        // If we've received any message since arming, lastHeartbeatAt
                        // will have moved forward — bail. Otherwise treat as failed.
                        if SyncConnection.shared.lastHeartbeatAt == nil {
                            print("[FPSync] Handshake timeout (\(self.handshakeTimeoutSeconds)s) — no inbound message")
                            SyncConnection.shared.noteHandshakeTimeout()
                            self.handleDisconnect()
                        }
                    }
                }
                self.reconnectDelay = 2.0
                self.reconnectAttempts = 0
                self.authRetryCount = 0
                self.stopDiscovery()
                self.startHeartbeat()

                // Flush pending messages queued while disconnected
                if !self.pendingMessages.isEmpty {
                    let queued = self.pendingMessages
                    self.pendingMessages.removeAll()
                    print("[FPSync] Flushing \(queued.count) pending messages")
                    for msg in queued {
                        self.send(msg)
                    }
                }

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
        handshakeTimer?.invalidate()
        handshakeTimer = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        urlSession = nil
        connectionStatus = .disconnected
        SyncConnection.shared.noteSocketClosed(intentional: true)
        devices = []
        pairedCameraId = nil
        seenCaptureIds.removeAll()
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

    /// Send subject selection to the paired camera station (requires pairing)
    func selectSubject(subjectId: String, rosterEntryId: String?, subjectName: String) {
        guard isConnected else {
            print("[FPSync] Cannot select subject — not connected")
            return
        }
        guard let galleryId = galleryId else {
            print("[FPSync] Cannot select subject — no gallery linked")
            return
        }
        guard let pairedId = pairedCameraId else {
            print("[FPSync] Cannot select subject — not paired to a camera station")
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
            "target_device_id": pairedId,
            "station_name": "iPad - \(deviceName)",
        ]
        send(msg)
    }

    /// Broadcast that a subject was checked in (for poser station queue sync)
    func broadcastCheckIn(galleryId: String, subjectId: String, subjectName: String) {
        let msg: [String: Any] = [
            "type": "subject_checked_in",
            "device_id": deviceId,
            "gallery_id": galleryId,
            "subject_id": subjectId,
            "subject_name": subjectName,
            "checked_in_at": ISO8601DateFormatter().string(from: Date()),
        ]
        send(msg)
    }

    /// Mark a subject as absent/present and notify Production
    func markSubjectAbsent(subjectId: String, rosterEntryId: String?, isAbsent: Bool) {
        guard let galleryId = galleryId else { return }
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
        guard let galleryId = galleryId else { return }
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

    /// Send name/field update for a subject (when blank placeholder gets a name on iPad)
    func sendSubjectUpdated(subjectId: String?, rosterEntryId: String, firstName: String, lastName: String, rosterId: String, imageNumbers: String? = nil) {
        guard let galleryId = galleryId else { return }
        var msg: [String: Any] = [
            "type": "subject_updated",
            "device_id": deviceId,
            "gallery_id": galleryId,
            "subject_id": subjectId ?? NSNull(),
            "roster_entry_id": rosterEntryId,
            "first_name": String(firstName.prefix(200)),
            "last_name": String(lastName.prefix(200)),
            "roster_id": String(rosterId.prefix(50)),
            "station_name": "iPad - \(deviceName)",
        ]
        if let nums = imageNumbers {
            msg["image_numbers"] = String(nums.prefix(500))
        }
        send(msg)
    }

    /// Send a full subject field update — carries every iPad-editable field.
    /// Used when the iPad skips its own PowerSync write (Surface is connected)
    /// so the Surface can write all the edits to Supabase authoritatively.
    func sendSubjectFullUpdate(_ subject: FPSubject) {
        guard let galleryId = galleryId else { return }
        let sid = subject.id.uuidString.lowercased()
        var msg: [String: Any] = [
            "type": "subject_updated",
            "device_id": deviceId,
            "gallery_id": galleryId,
            "subject_id": sid,
            "roster_entry_id": sid,
            "first_name": String(subject.firstName.prefix(200)),
            "last_name": String(subject.lastName.prefix(200)),
            "grade": String(subject.grade.prefix(50)),
            "teacher": String(subject.teacher.prefix(200)),
            "homeroom": String(subject.homeroom.prefix(200)),
            "student_id": String(subject.studentId.prefix(50)),
            "roster_id": String(subject.rosterId.prefix(50)),
            "online_code": String(subject.onlineCode.prefix(100)),
            "jersey_number": String(subject.jerseyNumber.prefix(50)),
            "sport": String(subject.sport.prefix(100)),
            "position": String(subject.position.prefix(100)),
            "organization_name": String(subject.organizationName.prefix(200)),
            "year": String(subject.year.prefix(50)),
            "subject_type": String(subject.subjectType.prefix(50)),
            "title": String(subject.title.prefix(200)),
            "reference_number": String(subject.referenceNumber.prefix(100)),
            "photographer": String(subject.photographer.prefix(200)),
            "photo_session_date": subject.photoSessionDate,
            "expiration_date": subject.expirationDate,
            "email": String(subject.email.prefix(200)),
            "phone": String(subject.phone.prefix(50)),
            "phone2": String(subject.phone2.prefix(50)),
            "address1": String(subject.address1.prefix(200)),
            "address2": String(subject.address2.prefix(200)),
            "city": String(subject.city.prefix(100)),
            "state": String(subject.state.prefix(100)),
            "zip": String(subject.zip.prefix(50)),
            "country": String(subject.country.prefix(100)),
            "mother": String(subject.mother.prefix(200)),
            "father": String(subject.father.prefix(200)),
            "personalization": String(subject.personalization.prefix(200)),
            "discount_code": String(subject.discountCode.prefix(100)),
            "custom1": String(subject.custom1.prefix(500)),
            "custom2": String(subject.custom2.prefix(500)),
            "custom3": String(subject.custom3.prefix(500)),
            "custom4": String(subject.custom4.prefix(500)),
            "custom5": String(subject.custom5.prefix(500)),
            "custom6": String(subject.custom6.prefix(500)),
            "custom7": String(subject.custom7.prefix(500)),
            "custom8": String(subject.custom8.prefix(500)),
            "custom9": String(subject.custom9.prefix(500)),
            "custom10": String(subject.custom10.prefix(500)),
            "custom11": String(subject.custom11.prefix(500)),
            "custom12": String(subject.custom12.prefix(500)),
            "custom13": String(subject.custom13.prefix(500)),
            "custom14": String(subject.custom14.prefix(500)),
            "custom15": String(subject.custom15.prefix(500)),
            "custom16": String(subject.custom16.prefix(500)),
            "custom17": String(subject.custom17.prefix(500)),
            "custom18": String(subject.custom18.prefix(500)),
            "custom19": String(subject.custom19.prefix(500)),
            "custom20": String(subject.custom20.prefix(500)),
            "notes": String(subject.notes.prefix(1000)),
            "image_numbers": String(subject.imageNumbers.prefix(500)),
            "is_absent": subject.isAbsent,
            "needs_retake": subject.needsRetake,
            "station_name": "iPad - \(deviceName)",
        ]
        if let checkedIn = subject.checkedInAt {
            msg["checked_in_at"] = checkedIn
        }
        send(msg)
    }

    /// Send a full group-row edit — broadcasts after an iPad save so the
    /// Surface and other iPads on the network refresh their in-memory
    /// groups list instantly instead of waiting for PowerSync cloud
    /// round-trip. Mirrors the sendSubjectFullUpdate fast-path pattern
    /// for individual subjects.
    func sendGroupFullUpdate(_ group: GroupImage) {
        guard let galleryId = galleryId else { return }
        let gid = group.id.uuidString.lowercased()
        let isoFormatter = ISO8601DateFormatter()
        // Send the FULL row so the receiver can INSERT OR REPLACE on
        // local PowerSync without a cloud round-trip — required for
        // offline shoots. Field caps stay in place to bound message
        // size on the LAN.
        var msg: [String: Any] = [
            "type": "group_updated",
            "device_id": deviceId,
            "gallery_id": galleryId,
            "group_id": gid,
            "organization_id": group.organizationId,
            "description": String(group.description.prefix(500)),
            "image_numbers": String(group.imageNumbers.prefix(500)),
            "notes": String(group.notes.prefix(1000)),
            "sport": String(group.sport.prefix(100)),
            "gender": String(group.gender.prefix(50)),
            "team_level": String(group.teamLevel.prefix(100)),
            "sort_order": group.sortOrder,
            "version": group.version,
            "updated_at": isoFormatter.string(from: group.updatedAt),
            "created_at": isoFormatter.string(from: group.createdAt),
            "station_name": "iPad - \(deviceName)",
        ]
        if let updatedBy = group.updatedBy { msg["updated_by"] = updatedBy.uuidString.lowercased() }
        if let lockedBy = group.lockedBy { msg["locked_by"] = lockedBy.uuidString.lowercased() }
        if let lockedByName = group.lockedByName { msg["locked_by_name"] = lockedByName }
        if let lockedAt = group.lockedAt { msg["locked_at"] = isoFormatter.string(from: lockedAt) }
        if let photographerId = group.photographerId { msg["photographer_id"] = photographerId }
        if let memberField = group.memberField { msg["member_field"] = memberField }
        if let memberValue = group.memberValue { msg["member_value"] = memberValue }
        send(msg)
    }

    /// Broadcast that a group row was hard-deleted on this iPad. Receivers
    /// remove the row from local PowerSync immediately so the delete is
    /// visible across the LAN even when offline.
    func sendGroupDeleted(groupId: UUID) {
        guard let galleryId = galleryId else { return }
        let msg: [String: Any] = [
            "type": "group_deleted",
            "device_id": deviceId,
            "gallery_id": galleryId,
            "group_id": groupId.uuidString.lowercased(),
            "station_name": "iPad - \(deviceName)",
        ]
        send(msg)
    }

    /// Broadcast that a new subject/athlete was created on iPad
    /// Optional `email` and `custom10`–`custom20` carry extended fields
    /// for the dance kiosk (couple/group entry). Receiver (FP Production
    /// CapturePage subject_created handler) forwards every present extra
    /// into the subject row, so callers can pass empty strings when they
    /// don't apply (existing sports-kiosk callers are unaffected).
    func broadcastSubjectCreated(
        rosterEntryId: String,
        firstName: String,
        lastName: String,
        rosterId: String,
        grade: String,
        groupName: String,
        email: String = "",
        custom10: String = "",
        custom11: String = "",
        custom12: String = "",
        custom13: String = "",
        custom14: String = "",
        custom15: String = "",
        custom16: String = "",
        custom17: String = "",
        custom18: String = "",
        custom19: String = "",
        custom20: String = ""
    ) {
        guard let galleryId = galleryId else { return }
        var msg: [String: Any] = [
            "type": "subject_created",
            "device_id": deviceId,
            "gallery_id": galleryId,
            "roster_entry_id": rosterEntryId,
            "first_name": String(firstName.prefix(200)),
            "last_name": String(lastName.prefix(200)),
            "roster_id": String(rosterId.prefix(50)),
            "grade": String(grade.prefix(50)),
            "group_name": String(groupName.prefix(200)),
            "station_name": "iPad - \(deviceName)",
        ]
        // Email cap matches customN (500). Joined dance emails can run
        // 250–400+ chars (10 emails with ", " separators); 200 truncates.
        if !email.isEmpty { msg["email"] = String(email.prefix(500)) }
        if !custom10.isEmpty { msg["custom10"] = String(custom10.prefix(500)) }
        if !custom11.isEmpty { msg["custom11"] = String(custom11.prefix(500)) }
        if !custom12.isEmpty { msg["custom12"] = String(custom12.prefix(500)) }
        if !custom13.isEmpty { msg["custom13"] = String(custom13.prefix(500)) }
        if !custom14.isEmpty { msg["custom14"] = String(custom14.prefix(500)) }
        if !custom15.isEmpty { msg["custom15"] = String(custom15.prefix(500)) }
        if !custom16.isEmpty { msg["custom16"] = String(custom16.prefix(500)) }
        if !custom17.isEmpty { msg["custom17"] = String(custom17.prefix(500)) }
        if !custom18.isEmpty { msg["custom18"] = String(custom18.prefix(500)) }
        if !custom19.isEmpty { msg["custom19"] = String(custom19.prefix(500)) }
        if !custom20.isEmpty { msg["custom20"] = String(custom20.prefix(500)) }
        send(msg)
    }

    /// Respond to verification warning — dismiss (unresolved mismatch) or confirm same subject
    func sendVerificationResponse(subjectId: String, confirmed: Bool) {
        let msg: [String: Any] = [
            "type": "verification_response",
            "device_id": deviceId,
            "subject_id": subjectId,
            "confirmed": confirmed, // true = same subject, false = dismissed (mismatch)
            "station_name": "iPad - \(deviceName)",
        ]
        send(msg)
    }

    /// Broadcast that roster entries were batch-deleted on iPad
    func broadcastEntriesDeleted(rosterEntryIds: [String]) {
        guard let galleryId = galleryId else { return }
        let capped = Array(rosterEntryIds.prefix(500))
        let msg: [String: Any] = [
            "type": "roster_entries_deleted",
            "device_id": deviceId,
            "gallery_id": galleryId,
            "roster_entry_ids": capped,
            "station_name": "iPad - \(deviceName)",
        ]
        send(msg)
    }

    /// Request Production to move a capture from one subject to another
    func sendMoveCapture(imageNumber: Int, fromSubjectId: String, toSubjectId: String, fromRosterEntryId: String, toRosterEntryId: String) {
        guard let galleryId = galleryId else { return }
        let msg: [String: Any] = [
            "type": "move_capture",
            "device_id": deviceId,
            "gallery_id": galleryId,
            "subject_id": fromSubjectId,
            "target_subject_id": toSubjectId,
            "image_number": imageNumber,
            "roster_entry_id": fromRosterEntryId,
            "target_roster_entry_id": toRosterEntryId,
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

    // MARK: - Image Requests

    /// Request a full-resolution image from Production via WebSocket binary frame.
    func requestImage(filename: String) async throws -> FPFullImage {
        guard isConnected else { throw FPSyncError.notConnected }

        requestIdCounter += 1
        let requestId = "r\(requestIdCounter)"

        let msg: [String: Any] = [
            "type": "request_image",
            "filename": filename,
            "request_id": requestId,
            "device_id": deviceId,
            "gallery_id": galleryId ?? "",
        ]
        send(msg)

        return try await withCheckedThrowingContinuation { continuation in
            pendingImageRequests[requestId] = continuation

            // Timeout
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(self?.imageRequestTimeout ?? 30) * 1_000_000_000)
                guard let self = self else { return }
                if let cont = self.pendingImageRequests.removeValue(forKey: requestId) {
                    cont.resume(throwing: FPSyncError.timeout)
                }
            }
        }
    }

    /// Request the list of captures for a subject from Production.
    func requestSubjectCaptures(subjectId: String) async throws -> [FPCaptureInfo] {
        guard isConnected else {
            print("[FPSync] requestSubjectCaptures — not connected")
            throw FPSyncError.notConnected
        }
        // Allow empty subjectId — server returns all hot folder files anyway
        if !subjectId.isEmpty, UUID(uuidString: subjectId) == nil {
            print("[FPSync] requestSubjectCaptures — invalid UUID: \(subjectId)")
            throw FPSyncError.invalidId
        }

        requestIdCounter += 1
        let requestId = "r\(requestIdCounter)"

        let msg: [String: Any] = [
            "type": "request_subject_captures",
            "subject_id": subjectId,
            "request_id": requestId,
            "device_id": deviceId,
            "gallery_id": galleryId ?? "",
        ]
        print("[FPSync] Sending request_subject_captures requestId=\(requestId) subjectId=\(subjectId)")
        send(msg)

        return try await withCheckedThrowingContinuation { continuation in
            pendingCaptureListRequests[requestId] = continuation

            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(self?.imageRequestTimeout ?? 30) * 1_000_000_000)
                guard let self = self else { return }
                if let cont = self.pendingCaptureListRequests.removeValue(forKey: requestId) {
                    cont.resume(throwing: FPSyncError.timeout)
                }
            }
        }
    }

    // MARK: - Sending

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            print("[FPSync] Send failed: could not serialize message")
            return
        }
        let msgType = dict["type"] as? String ?? "?"
        guard let ws = webSocket else {
            // Queue non-stale messages for later delivery
            if !staleMessageTypes.contains(msgType) {
                pendingMessages.append(dict)
                if pendingMessages.count > pendingQueueMax {
                    pendingMessages.removeFirst()
                }
                print("[FPSync] Queued \(msgType) (pending: \(pendingMessages.count))")
            }
            return
        }
        ws.send(.string(str)) { error in
            if let error = error {
                print("[FPSync] Send error (\(msgType)): \(error)")
            } else {
                print("[FPSync] Sent \(msgType) (\(str.count) bytes)")
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
        UIDevice.current.isBatteryMonitoringEnabled = true
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let batteryLevel = Int(UIDevice.current.batteryLevel * 100)
                let batteryCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
                let msg: [String: Any] = [
                    "type": "heartbeat",
                    "device_id": self.deviceId,
                    "gallery_id": self.galleryId ?? "",
                    "station_mode": "ios_roster",
                    "active_subject_id": "",
                    "capture_count": 0,
                    "queue_length": 0,
                    "battery_level": batteryLevel,
                    "battery_charging": batteryCharging,
                ]
                self.send(msg)
                // Sync rewrite — promote `connected` to `degraded` if no
                // inbound message arrived in the heartbeat-silence window.
                SyncConnection.shared.watchdogTick()
            }
        }
        // Ping/pong every 10s to detect dead connections fast
        startPingPong()
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        stopPingPong()
    }

    private func startPingPong() {
        stopPingPong()
        missedPongs = 0
        pingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.missedPongs += 1
                if self.missedPongs > self.maxMissedPongs {
                    print("[FPSync] Server unresponsive (\(self.missedPongs) missed pongs), disconnecting")
                    self.webSocket?.cancel(with: .abnormalClosure, reason: nil)
                    self.webSocket = nil
                    self.handleDisconnect()
                    return
                }
                self.webSocket?.sendPing { [weak self] error in
                    Task { @MainActor in
                        guard let self = self else { return }
                        if let error = error {
                            print("[FPSync] Ping failed: \(error)")
                            // Don't disconnect here — missedPongs will catch it
                        } else {
                            self.missedPongs = 0
                        }
                    }
                }
            }
        }
    }

    private func stopPingPong() {
        pingTimer?.invalidate()
        pingTimer = nil
        missedPongs = 0
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
                    case .data(let binaryData):
                        self.handleBinaryFrame(binaryData)
                    @unknown default:
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
        // Sync rewrite — any inbound message is evidence the socket is alive.
        // The state machine recovers from `degraded` on this signal. Also
        // clear the handshake watchdog — we're past the handshake window.
        if handshakeTimer != nil {
            handshakeTimer?.invalidate()
            handshakeTimer = nil
        }
        SyncConnection.shared.noteMessageReceived()
        guard let type = msg["type"] as? String else {
            print("[FPSync] Received message with no type field")
            return
        }
        print("[FPSync] Received: \(type)")

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
                        captureCount: d["capture_count"] as? Int ?? 0,
                        batteryLevel: d["battery_level"] as? Int,
                        batteryCharging: d["battery_charging"] as? Bool
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
            // Parse image_number — handle both Int and String from JSON
            let imageNumber: Int? = (msg["image_number"] as? Int) ?? (msg["image_number"] as? String).flatMap { Int($0) }
            // Dedup using capture_id (unique per capture) with fallback to subject+image
            let dedupKey = (msg["capture_id"] as? String) ?? "\(subjectId)_\(imageNumber ?? 0)_\(msg["capture_filename"] as? String ?? "")"
            if seenCaptureIds.contains(dedupKey) {
                print("[FPSync] Duplicate capture_completed, skipping: \(dedupKey)")
                break
            }
            seenCaptureIds.insert(dedupKey)
            // Trim seen set when it gets too large (keep ~half)
            if seenCaptureIds.count > maxSeenCaptures {
                let excess = seenCaptureIds.count - maxSeenCaptures / 2
                for _ in 0..<excess {
                    seenCaptureIds.removeFirst()
                }
            }
            let event = FPCaptureEvent(
                subjectId: subjectId,
                rosterEntryId: msg["roster_entry_id"] as? String,
                imageNumber: imageNumber,
                captureFilename: msg["capture_filename"] as? String,
                stationName: msg["station_name"] as? String ?? "Unknown",
                fromDeviceId: msg["device_id"] as? String ?? ""
            )
            // Only process from our paired camera (or any if not paired)
            if pairedCameraId == nil || event.fromDeviceId == pairedCameraId {
                onCaptureCompleted?(event)
            }

            // Send ack back to Production so it knows we received this capture event
            if let captureId = msg["capture_id"] as? String, !captureId.isEmpty {
                send([
                    "type": "capture_completed_ack",
                    "capture_id": captureId,
                    "device_id": deviceId,
                    "gallery_id": galleryId ?? "",
                ])
            }

        case "subject_photographed":
            guard let subjectId = msg["subject_id"] as? String, !subjectId.isEmpty,
                  UUID(uuidString: subjectId) != nil else { break }
            var thumbnail = msg["thumbnail"] as? String
            // Cap thumbnail size at 2MB to allow 1200px preview images
            if let thumb = thumbnail, thumb.count > 2_000_000 {
                thumbnail = nil
            }
            let poseNumber = msg["pose_number"] as? Int
            if let fromDevice = msg["device_id"] as? String,
               pairedCameraId == nil || fromDevice == pairedCameraId {
                onSubjectPhotographed?(subjectId, thumbnail, poseNumber)
            }

        case "auth_error":
            authRetryCount += 1
            if authRetryCount <= maxAuthRetries, let gid = galleryId {
                print("[FPSync] Auth failed, re-discovering to get fresh token (attempt \(authRetryCount)/\(maxAuthRetries))")
                // Close current socket without clearing last server (intentional != full disconnect)
                stopHeartbeat()
                webSocket?.cancel(with: .normalClosure, reason: nil)
                webSocket = nil
                urlSession = nil
                connectionStatus = .discovering
                // Clear stale cached server so mDNS discovers fresh TXT record
                UserDefaults.standard.removeObject(forKey: "fp_last_server")
                startDiscovery(galleryId: gid)
            } else {
                print("[FPSync] Auth failed, max retries reached — giving up")
                connectionStatus = .authFailed
                disconnect()
            }

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

        case "subject_updated":
            guard let rosterEntryId = msg["roster_entry_id"] as? String,
                  UUID(uuidString: rosterEntryId) != nil else { break }
            let subjectId = msg["subject_id"] as? String
            let firstName = String((msg["first_name"] as? String ?? "").prefix(200))
            let lastName = String((msg["last_name"] as? String ?? "").prefix(200))
            let rosterId = String((msg["roster_id"] as? String ?? "").prefix(50))
            let senderId = (msg["device_id"] as? String) ?? "unknown"
            let galleryId = msg["gallery_id"] as? String

            // Build a SubjectSyncFields from every field present on the wire
            // so receivers can apply non-name edits (organization, custom1-20,
            // address, etc.) instantly without waiting for the cloud round-trip.
            var fields = SubjectSyncFields()
            func _str(_ key: String, _ cap: Int) -> String? {
                guard let raw = msg[key] as? String else { return nil }
                return String(raw.prefix(cap))
            }
            if let v = _str("first_name", 200)         { fields.firstName = v }
            if let v = _str("last_name", 200)          { fields.lastName = v }
            if let v = _str("grade", 50)               { fields.grade = v }
            if let v = _str("teacher", 200)            { fields.teacher = v }
            if let v = _str("homeroom", 200)           { fields.homeroom = v }
            if let v = _str("student_id", 50)          { fields.studentId = v }
            if let v = _str("roster_id", 50)           { fields.rosterId = v }
            if let v = _str("online_code", 100)        { fields.onlineCode = v }
            if let v = _str("jersey_number", 50)       { fields.jerseyNumber = v }
            if let v = _str("sport", 100)              { fields.sport = v }
            if let v = _str("position", 100)           { fields.position = v }
            if let v = _str("organization_name", 200)  { fields.organizationName = v }
            if let v = _str("year", 50)                { fields.year = v }
            if let v = _str("subject_type", 50)        { fields.subjectType = v }
            if let v = _str("title", 200)              { fields.title = v }
            if let v = _str("reference_number", 100)   { fields.referenceNumber = v }
            if let v = _str("photographer", 200)       { fields.photographer = v }
            if let v = _str("photo_session_date", 50)  { fields.photoSessionDate = v }
            if let v = _str("expiration_date", 50)     { fields.expirationDate = v }
            if let v = _str("email", 200)              { fields.email = v }
            if let v = _str("phone", 50)               { fields.phone = v }
            if let v = _str("phone2", 50)              { fields.phone2 = v }
            if let v = _str("address1", 200)           { fields.address1 = v }
            if let v = _str("address2", 200)           { fields.address2 = v }
            if let v = _str("city", 100)               { fields.city = v }
            if let v = _str("state", 100)              { fields.state = v }
            if let v = _str("zip", 50)                 { fields.zip = v }
            if let v = _str("country", 100)            { fields.country = v }
            if let v = _str("mother", 200)             { fields.mother = v }
            if let v = _str("father", 200)             { fields.father = v }
            if let v = _str("personalization", 200)    { fields.personalization = v }
            if let v = _str("discount_code", 100)      { fields.discountCode = v }
            if let v = _str("custom1", 500)            { fields.custom1 = v }
            if let v = _str("custom2", 500)            { fields.custom2 = v }
            if let v = _str("custom3", 500)            { fields.custom3 = v }
            if let v = _str("custom4", 500)            { fields.custom4 = v }
            if let v = _str("custom5", 500)            { fields.custom5 = v }
            if let v = _str("custom6", 500)            { fields.custom6 = v }
            if let v = _str("custom7", 500)            { fields.custom7 = v }
            if let v = _str("custom8", 500)            { fields.custom8 = v }
            if let v = _str("custom9", 500)            { fields.custom9 = v }
            if let v = _str("custom10", 500)           { fields.custom10 = v }
            if let v = _str("custom11", 500)           { fields.custom11 = v }
            if let v = _str("custom12", 500)           { fields.custom12 = v }
            if let v = _str("custom13", 500)           { fields.custom13 = v }
            if let v = _str("custom14", 500)           { fields.custom14 = v }
            if let v = _str("custom15", 500)           { fields.custom15 = v }
            if let v = _str("custom16", 500)           { fields.custom16 = v }
            if let v = _str("custom17", 500)           { fields.custom17 = v }
            if let v = _str("custom18", 500)           { fields.custom18 = v }
            if let v = _str("custom19", 500)           { fields.custom19 = v }
            if let v = _str("custom20", 500)           { fields.custom20 = v }
            if let v = _str("notes", 1000)             { fields.notes = v }
            if let v = _str("image_numbers", 500)      { fields.imageNumbers = v }
            if let v = _str("checked_in_at", 50)       { fields.checkedInAt = v }
            if let v = msg["is_absent"] as? Bool       { fields.isAbsent = v }
            if let v = msg["needs_retake"] as? Bool    { fields.needsRetake = v }

            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: senderId,
                deviceRole: "Surface",
                operation: .update,
                outcome: .received,
                sourcePath: "FocalPointSyncClient.subject_updated",
                subjectId: subjectId,
                galleryId: galleryId,
                fieldsTouched: fields.fieldsTouched
            ))
            onSubjectUpdated?(rosterEntryId, subjectId, firstName, lastName, rosterId, senderId)
            onSubjectUpdatedFields?(rosterEntryId, subjectId, fields, senderId)

        case "subject_state_summary":
            // Reconciliation snapshot from Surface — compare to local view to
            // detect drift without waiting for cloud sync.
            guard let galleryId = msg["gallery_id"] as? String,
                  let count = msg["subject_count"] as? Int else { break }
            let nameHash = (msg["name_hash"] as? String) ?? ""
            onSubjectStateSummary?(galleryId, count, nameHash)

        case "subject_created":
            guard let rosterEntryId = msg["roster_entry_id"] as? String,
                  UUID(uuidString: rosterEntryId) != nil else { break }
            // Skip if this device sent it
            if let senderId = msg["device_id"] as? String, senderId == deviceId { break }
            let firstName = String((msg["first_name"] as? String ?? "").prefix(200))
            let lastName = String((msg["last_name"] as? String ?? "").prefix(200))
            let rosterId = String((msg["roster_id"] as? String ?? "").prefix(50))
            let grade = String((msg["grade"] as? String ?? "").prefix(50))
            let groupName = String((msg["group_name"] as? String ?? "").prefix(200))
            onSubjectCreated?(rosterEntryId, firstName, lastName, rosterId, grade, groupName)

            // Build a fields payload from every column on the wire so remote
            // adds carry organization / custom / address / etc. instantly.
            var createFields = SubjectSyncFields()
            func _cstr(_ key: String, _ cap: Int) -> String? {
                guard let raw = msg[key] as? String else { return nil }
                return String(raw.prefix(cap))
            }
            if let v = _cstr("first_name", 200)         { createFields.firstName = v }
            if let v = _cstr("last_name", 200)          { createFields.lastName = v }
            if let v = _cstr("grade", 50)               { createFields.grade = v }
            if let v = _cstr("teacher", 200)            { createFields.teacher = v }
            if let v = _cstr("homeroom", 200)           { createFields.homeroom = v }
            if let v = _cstr("student_id", 50)          { createFields.studentId = v }
            if let v = _cstr("roster_id", 50)           { createFields.rosterId = v }
            if let v = _cstr("online_code", 100)        { createFields.onlineCode = v }
            if let v = _cstr("jersey_number", 50)       { createFields.jerseyNumber = v }
            if let v = _cstr("sport", 100)              { createFields.sport = v }
            if let v = _cstr("position", 100)           { createFields.position = v }
            if let v = _cstr("organization_name", 200)  { createFields.organizationName = v }
            if let v = _cstr("year", 50)                { createFields.year = v }
            if let v = _cstr("subject_type", 50)        { createFields.subjectType = v }
            if let v = _cstr("title", 200)              { createFields.title = v }
            if let v = _cstr("reference_number", 100)   { createFields.referenceNumber = v }
            if let v = _cstr("photographer", 200)       { createFields.photographer = v }
            if let v = _cstr("photo_session_date", 50)  { createFields.photoSessionDate = v }
            if let v = _cstr("expiration_date", 50)     { createFields.expirationDate = v }
            if let v = _cstr("email", 200)              { createFields.email = v }
            if let v = _cstr("phone", 50)               { createFields.phone = v }
            if let v = _cstr("phone2", 50)              { createFields.phone2 = v }
            if let v = _cstr("address1", 200)           { createFields.address1 = v }
            if let v = _cstr("address2", 200)           { createFields.address2 = v }
            if let v = _cstr("city", 100)               { createFields.city = v }
            if let v = _cstr("state", 100)              { createFields.state = v }
            if let v = _cstr("zip", 50)                 { createFields.zip = v }
            if let v = _cstr("country", 100)            { createFields.country = v }
            if let v = _cstr("mother", 200)             { createFields.mother = v }
            if let v = _cstr("father", 200)             { createFields.father = v }
            if let v = _cstr("personalization", 200)    { createFields.personalization = v }
            if let v = _cstr("discount_code", 100)      { createFields.discountCode = v }
            if let v = _cstr("custom1", 500)            { createFields.custom1 = v }
            if let v = _cstr("custom2", 500)            { createFields.custom2 = v }
            if let v = _cstr("custom3", 500)            { createFields.custom3 = v }
            if let v = _cstr("custom4", 500)            { createFields.custom4 = v }
            if let v = _cstr("custom5", 500)            { createFields.custom5 = v }
            if let v = _cstr("custom6", 500)            { createFields.custom6 = v }
            if let v = _cstr("custom7", 500)            { createFields.custom7 = v }
            if let v = _cstr("custom8", 500)            { createFields.custom8 = v }
            if let v = _cstr("custom9", 500)            { createFields.custom9 = v }
            if let v = _cstr("custom10", 500)           { createFields.custom10 = v }
            if let v = _cstr("custom11", 500)           { createFields.custom11 = v }
            if let v = _cstr("custom12", 500)           { createFields.custom12 = v }
            if let v = _cstr("custom13", 500)           { createFields.custom13 = v }
            if let v = _cstr("custom14", 500)           { createFields.custom14 = v }
            if let v = _cstr("custom15", 500)           { createFields.custom15 = v }
            if let v = _cstr("custom16", 500)           { createFields.custom16 = v }
            if let v = _cstr("custom17", 500)           { createFields.custom17 = v }
            if let v = _cstr("custom18", 500)           { createFields.custom18 = v }
            if let v = _cstr("custom19", 500)           { createFields.custom19 = v }
            if let v = _cstr("custom20", 500)           { createFields.custom20 = v }
            if let v = _cstr("notes", 1000)             { createFields.notes = v }
            if let v = _cstr("image_numbers", 500)      { createFields.imageNumbers = v }
            if let v = _cstr("checked_in_at", 50)       { createFields.checkedInAt = v }
            let createSenderId = (msg["device_id"] as? String) ?? "unknown"
            onSubjectCreatedFields?(rosterEntryId, createFields, createSenderId)

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

        case "group_capture_completed":
            if let groupId = msg["group_id"] as? String, !groupId.isEmpty,
               UUID(uuidString: groupId) != nil {
                let imageNumber = (msg["image_number"] as? Int) ?? (msg["image_number"] as? String).flatMap { Int($0) } ?? 0
                let filename = msg["capture_filename"] as? String ?? ""
                onGroupCaptureCompleted?(groupId, imageNumber, filename)
            }

        case "group_updated":
            // Fast-path: Surface (or another iPad) just created or edited
            // a group row. Carries the FULL row so we can apply it
            // directly to local PowerSync without a cloud round-trip —
            // required for offline shoots where the LAN is the only
            // path between devices. PowerSync's CRDT dedups when both
            // sides eventually reach the cloud (LWW by updated_at).
            if let groupId = msg["group_id"] as? String, !groupId.isEmpty,
               UUID(uuidString: groupId) != nil,
               let galleryId = msg["gallery_id"] as? String, !galleryId.isEmpty,
               UUID(uuidString: galleryId) != nil {
                let senderDeviceId = msg["device_id"] as? String ?? ""
                let nowISO = ISO8601DateFormatter().string(from: Date())
                let row = RemoteGroupRow(
                    id: groupId,
                    galleryId: galleryId,
                    organizationId: (msg["organization_id"] as? String) ?? "",
                    description: (msg["description"] as? String) ?? "",
                    imageNumbers: (msg["image_numbers"] as? String) ?? "",
                    notes: (msg["notes"] as? String) ?? "",
                    sport: (msg["sport"] as? String) ?? "",
                    gender: (msg["gender"] as? String) ?? "",
                    teamLevel: (msg["team_level"] as? String) ?? "",
                    sortOrder: (msg["sort_order"] as? Int) ?? 0,
                    version: (msg["version"] as? Int) ?? 1,
                    updatedAt: (msg["updated_at"] as? String) ?? nowISO,
                    updatedBy: msg["updated_by"] as? String,
                    lockedBy: msg["locked_by"] as? String,
                    lockedByName: msg["locked_by_name"] as? String,
                    lockedAt: msg["locked_at"] as? String,
                    createdAt: (msg["created_at"] as? String) ?? nowISO,
                    photographerId: msg["photographer_id"] as? String,
                    memberField: msg["member_field"] as? String,
                    memberValue: msg["member_value"] as? String
                )
                onGroupUpdated?(groupId, senderDeviceId, row)
            }

        case "group_deleted":
            // Fast-path: a device deleted a group. Receiver should DELETE
            // from local PowerSync immediately; the same delete will
            // propagate via cloud sync once both sides are online.
            if let groupId = msg["group_id"] as? String, !groupId.isEmpty,
               UUID(uuidString: groupId) != nil {
                onGroupDeleted?(groupId)
            }

        case "device_disconnected":
            if let disconnectedId = msg["device_id"] as? String {
                // Capture the device's friendly name BEFORE removing it
                // so the UI alert can identify which iPad/Surface dropped.
                let disconnectedName = devices.first { $0.id == disconnectedId }?.name ?? "Device"
                devices.removeAll { $0.id == disconnectedId }
                // Warn if paired camera disconnected
                if disconnectedId == pairedCameraId {
                    pairedCameraId = nil
                }
                onDeviceDisconnected?(disconnectedId, disconnectedName)
            }

        case "image_header":
            // Store header — next binary frame will be the image data
            pendingImageHeader = msg

        case "image_error":
            if let requestId = msg["request_id"] as? String {
                let errorMsg = msg["error"] as? String ?? "Unknown error"
                if let cont = pendingImageRequests.removeValue(forKey: requestId) {
                    cont.resume(throwing: FPSyncError.serverError(errorMsg))
                }
            }

        case "subject_captures":
            print("[FPSync] Received subject_captures response: request_id=\(msg["request_id"] ?? "nil") captures_count=\((msg["captures"] as? [Any])?.count ?? -1)")
            if let requestId = msg["request_id"] as? String,
               let captures = msg["captures"] as? [[String: Any]] {
                let infos = captures.map { c in
                    FPCaptureInfo(
                        filename: c["filename"] as? String ?? "",
                        poseNumber: c["pose_number"] as? Int,
                        size: c["size"] as? Int ?? 0,
                        timestamp: c["timestamp"] as? String ?? ""
                    )
                }
                if let cont = pendingCaptureListRequests.removeValue(forKey: requestId) {
                    cont.resume(returning: infos)
                }
            }

        case "subject_linked":
            guard let rosterEntryId = msg["roster_entry_id"] as? String, !rosterEntryId.isEmpty,
                  UUID(uuidString: rosterEntryId) != nil,
                  let subjectId = msg["subject_id"] as? String, !subjectId.isEmpty,
                  UUID(uuidString: subjectId) != nil else { break }
            print("[FPSync] Subject linked: roster_entry=\(rosterEntryId) -> subject=\(subjectId), callback=\(onSubjectLinked != nil ? "SET" : "NIL")")
            onSubjectLinked?(rosterEntryId, subjectId)

        case "subjects_deleted":
            guard let subjectIds = msg["subject_ids"] as? [String], !subjectIds.isEmpty else { break }
            // Validate all are UUIDs
            let validIds = subjectIds.filter { UUID(uuidString: $0) != nil }
            guard !validIds.isEmpty else { break }
            print("[FPSync] Subjects deleted from Production: \(validIds.count) subjects")
            onSubjectsDeleted?(validIds)

        case "capture_reassigned":
            guard let imageNumber = msg["image_number"] as? Int,
                  let oldRosterEntryId = msg["old_roster_entry_id"] as? String, !oldRosterEntryId.isEmpty,
                  let newRosterEntryId = msg["new_roster_entry_id"] as? String, !newRosterEntryId.isEmpty else { break }
            print("[FPSync] Capture reassigned: image #\(imageNumber) from \(oldRosterEntryId) to \(newRosterEntryId)")
            onCaptureReassigned?(imageNumber, oldRosterEntryId, newRosterEntryId)

        case "verification_warning":
            if let subjectId = msg["subject_id"] as? String,
               let subjectName = msg["subject_name"] as? String,
               let status = msg["status"] as? String,
               let message = msg["message"] as? String,
               let fromDevice = msg["device_id"] as? String,
               pairedCameraId == nil || fromDevice == pairedCameraId {
                let qrData = msg["qr_data"] as? String
                print("[FPSync] Verification warning: \(status) for \(subjectName) — \(message)")
                onVerificationWarning?(subjectId, subjectName, status, message, qrData)
            }

        case "gallery_changed":
            let oldGalleryId = msg["old_gallery_id"] as? String ?? ""
            let newGalleryId = msg["new_gallery_id"] as? String ?? ""
            if !oldGalleryId.isEmpty && oldGalleryId == galleryId {
                // Production switched away from our gallery
                print("[FPSync] Production switched gallery: \(oldGalleryId) -> \(newGalleryId)")
                onGalleryChanged?(oldGalleryId, newGalleryId)
            }

        default:
            break
        }
    }

    // MARK: - Binary Frame Handling

    private func handleBinaryFrame(_ data: Data) {
        guard let header = pendingImageHeader else {
            print("[FPSync] Received binary frame with no pending header — ignoring")
            return
        }
        pendingImageHeader = nil

        guard let requestId = header["request_id"] as? String else { return }

        guard let image = UIImage(data: data) else {
            if let cont = pendingImageRequests.removeValue(forKey: requestId) {
                cont.resume(throwing: FPSyncError.invalidImageData)
            }
            return
        }

        let filename = header["filename"] as? String ?? ""
        let size = header["size"] as? Int ?? data.count

        if let cont = pendingImageRequests.removeValue(forKey: requestId) {
            cont.resume(returning: FPFullImage(image: image, filename: filename, size: size))
        }
    }

    // MARK: - Reconnection

    private func handleDisconnect() {
        connectionStatus = .disconnected
        // Sync rewrite — this is the unintentional-disconnect path. The
        // intentional close path goes through disconnect() which already
        // notes its own state transition. Pass intentional=false here so
        // the state machine moves to `reconnecting` and SubjectSyncService
        // keeps queueing rather than falling back to standalone PowerSync.
        SyncConnection.shared.noteSocketClosed(intentional: false)
        stopHeartbeat()

        // Cancel all pending image/capture requests
        for (_, cont) in pendingImageRequests {
            cont.resume(throwing: FPSyncError.notConnected)
        }
        pendingImageRequests.removeAll()
        for (_, cont) in pendingCaptureListRequests {
            cont.resume(throwing: FPSyncError.notConnected)
        }
        pendingCaptureListRequests.removeAll()
        pendingImageHeader = nil
        pendingMessages.removeAll()

        guard !intentionalClose, let host = lastHost, let port = lastPort else { return }
        scheduleReconnect(host: host, port: port)
    }

    private func scheduleReconnect(host: String, port: Int) {
        stopReconnect()
        reconnectAttempts += 1
        if reconnectAttempts > maxReconnectAttempts {
            print("[FPSync] Max reconnect attempts (\(maxReconnectAttempts)) reached, giving up")
            connectionStatus = .disconnected
            return
        }
        print("[FPSync] Reconnecting in \(reconnectDelay)s (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")
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
