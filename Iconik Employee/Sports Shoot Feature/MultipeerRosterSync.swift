//
//  MultipeerRosterSync.swift
//  Iconik Employee
//
//  Multipeer Connectivity sync manager for roster entries
//  Enables real-time sync between registration kiosk iPad and photographer iPad
//  Uses Bluetooth + WiFi Direct (no internet needed)
//

import Foundation
import MultipeerConnectivity

/// Multipeer Connectivity manager for syncing roster entries between devices
/// Advertiser mode = Kiosk iPad (registration station)
/// Browser mode = Photographer iPad (connects to kiosk)
@MainActor
class MultipeerRosterSync: NSObject, ObservableObject {

    // MARK: - Constants

    private let serviceType = "iconik-roster"

    // MARK: - Published Properties

    @Published var isConnected = false
    @Published var connectedPeers: [MCPeerID] = []
    @Published var connectionStatus: String = "Not connected"

    // MARK: - Private Properties

    private let myPeerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var currentJobId: UUID?

    // MARK: - Sync Message Types

    enum SyncMessage: Codable {
        case rosterEntry(RosterEntry)
        case requestFullSync(jobId: UUID)
        case fullSyncResponse(entries: [RosterEntry])
    }

    // MARK: - Initialization

    override init() {
        let deviceName = UIDevice.current.name
        self.myPeerID = MCPeerID(displayName: deviceName)
        self.session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        super.init()
        self.session.delegate = self
        print("MultipeerRosterSync: Initialized with peer ID: \(deviceName)")
    }

    deinit {
        // Capture references to clean up on main thread
        let advertiser = self.advertiser
        let browser = self.browser

        DispatchQueue.main.async {
            advertiser?.stopAdvertisingPeer()
            browser?.stopBrowsingForPeers()
        }

        print("MultipeerRosterSync: Deinitializing")
    }

    // MARK: - Kiosk Mode (Advertiser)

    /// Start advertising as a registration station (kiosk mode)
    func startAdvertising(jobId: UUID) {
        currentJobId = jobId

        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: ["jobId": jobId.uuidString.lowercased()],
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        connectionStatus = "Advertising as registration station..."
        print("MultipeerRosterSync: Started advertising for job \(jobId)")
    }

    /// Stop advertising
    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        print("MultipeerRosterSync: Stopped advertising")
    }

    // MARK: - Photographer Mode (Browser)

    /// Start browsing for registration stations (photographer mode)
    func startBrowsing(jobId: UUID) {
        currentJobId = jobId

        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()

        connectionStatus = "Searching for registration stations..."
        print("MultipeerRosterSync: Started browsing for job \(jobId)")
    }

    /// Stop browsing
    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        print("MultipeerRosterSync: Stopped browsing")
    }

    // MARK: - Broadcasting

    /// Broadcast a roster entry to all connected peers
    func broadcastRosterEntry(_ entry: RosterEntry) {
        guard !session.connectedPeers.isEmpty else {
            print("MultipeerRosterSync: No peers connected, skipping broadcast")
            return
        }

        let message = SyncMessage.rosterEntry(entry)
        guard let data = try? JSONEncoder().encode(message) else {
            print("MultipeerRosterSync: Failed to encode roster entry")
            return
        }

        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            print("MultipeerRosterSync: Broadcasted roster entry \(entry.id) to \(session.connectedPeers.count) peer(s)")
        } catch {
            print("MultipeerRosterSync: Failed to send roster entry: \(error)")
        }
    }

    /// Request full sync of all entries for the current job
    func requestFullSync(jobId: UUID) {
        guard !session.connectedPeers.isEmpty else {
            print("MultipeerRosterSync: No peers connected, skipping full sync request")
            return
        }

        let message = SyncMessage.requestFullSync(jobId: jobId)
        guard let data = try? JSONEncoder().encode(message) else {
            print("MultipeerRosterSync: Failed to encode full sync request")
            return
        }

        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            print("MultipeerRosterSync: Requested full sync for job \(jobId)")
        } catch {
            print("MultipeerRosterSync: Failed to send full sync request: \(error)")
        }
    }

    // MARK: - Session Management

    /// Disconnect all peers
    func disconnect() {
        session.disconnect()
        stopAdvertising()
        stopBrowsing()
        isConnected = false
        connectedPeers.removeAll()
        connectionStatus = "Disconnected"
        print("MultipeerRosterSync: Disconnected all peers")
    }
}

// MARK: - MCSessionDelegate

extension MultipeerRosterSync: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            let oldConnected = self.isConnected
            self.connectedPeers = session.connectedPeers
            self.isConnected = !session.connectedPeers.isEmpty

            switch state {
            case .notConnected:
                self.connectionStatus = self.isConnected ? "Connected to \(session.connectedPeers.count) peer(s)" : "Not connected"
                print("MultipeerRosterSync: Peer \(peerID.displayName) disconnected")

            case .connecting:
                self.connectionStatus = "Connecting to \(peerID.displayName)..."
                print("MultipeerRosterSync: Connecting to peer \(peerID.displayName)")

            case .connected:
                self.connectionStatus = "Connected to \(peerID.displayName)"
                print("MultipeerRosterSync: Connected to peer \(peerID.displayName)")

                // CRITICAL FIX: Request full sync when reconnecting
                if !oldConnected && self.isConnected, let jobId = self.currentJobId {
                    print("MultipeerRosterSync: Connection established, requesting full sync for job \(jobId)")
                    self.requestFullSync(jobId: jobId)
                }

            @unknown default:
                print("MultipeerRosterSync: Unknown session state: \(state)")
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(SyncMessage.self, from: data) else {
            print("MultipeerRosterSync: Failed to decode message from \(peerID.displayName)")
            return
        }

        switch message {
        case .rosterEntry(let entry):
            print("MultipeerRosterSync: Received roster entry \(entry.id) from \(peerID.displayName)")
            // Save to PowerSync with SAME UUID (prevents duplicates on both devices)
            Task { @MainActor in
                do {
                    try await PowerSyncManager.shared.saveRosterEntry(entry)
                    print("MultipeerRosterSync: Saved received roster entry \(entry.id)")
                } catch {
                    print("MultipeerRosterSync: Failed to save roster entry: \(error)")
                }
            }

        case .requestFullSync(let jobId):
            print("MultipeerRosterSync: Received full sync request for job \(jobId) from \(peerID.displayName)")
            // Send all entries for this job
            Task { @MainActor in
                do {
                    let entries = try await PowerSyncManager.shared.getRosterEntries(forJob: jobId)
                    let response = SyncMessage.fullSyncResponse(entries: entries)
                    guard let responseData = try? JSONEncoder().encode(response) else {
                        print("MultipeerRosterSync: Failed to encode full sync response")
                        return
                    }
                    try session.send(responseData, toPeers: [peerID], with: .reliable)
                    print("MultipeerRosterSync: Sent full sync response with \(entries.count) entries")
                } catch {
                    print("MultipeerRosterSync: Failed to handle full sync request: \(error)")
                }
            }

        case .fullSyncResponse(let entries):
            print("MultipeerRosterSync: Received full sync response with \(entries.count) entries from \(peerID.displayName)")
            // Save all received entries
            Task { @MainActor in
                for entry in entries {
                    do {
                        try await PowerSyncManager.shared.saveRosterEntry(entry)
                        print("MultipeerRosterSync: Saved sync entry \(entry.id)")
                    } catch {
                        print("MultipeerRosterSync: Failed to save sync entry \(entry.id): \(error)")
                    }
                }
                print("MultipeerRosterSync: Full sync complete")
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used for roster sync
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used for roster sync
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used for roster sync
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerRosterSync: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("MultipeerRosterSync: Received invitation from \(peerID.displayName)")
        // Auto-accept invitations (trust local network)
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            self.connectionStatus = "Failed to advertise: \(error.localizedDescription)"
        }
        print("MultipeerRosterSync: Failed to start advertising: \(error)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerRosterSync: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("MultipeerRosterSync: Found peer \(peerID.displayName) with info: \(info ?? [:])")

        // Verify this peer is for the same job
        if let jobIdString = info?["jobId"],
           let currentJobIdString = currentJobId?.uuidString.lowercased(),
           jobIdString == currentJobIdString {
            // Auto-invite found peers for the same job
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
            print("MultipeerRosterSync: Invited peer \(peerID.displayName)")
        } else {
            print("MultipeerRosterSync: Skipping peer \(peerID.displayName) - job ID mismatch")
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("MultipeerRosterSync: Lost peer \(peerID.displayName)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.connectionStatus = "Failed to browse: \(error.localizedDescription)"
        }
        print("MultipeerRosterSync: Failed to start browsing: \(error)")
    }
}
