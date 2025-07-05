import SwiftUI

// A component to display the sync status badge for sports shoots
struct SyncStatusBadge: View {
    let shootID: String
    
    // Use observed object so it updates automatically
    @ObservedObject private var statusMonitor = SyncStatusMonitor()
    
    init(shootID: String) {
        self.shootID = shootID
        self.statusMonitor.shootID = shootID
    }
    
    var body: some View {
        switch statusMonitor.status {
        case .notCached:
            EmptyView()  // No badge for uncached shoots
        case .cached:
            Image(systemName: "icloud.and.arrow.down.fill")
                .foregroundColor(.blue)
        case .modified:
            Image(systemName: "icloud.and.arrow.up")
                .foregroundColor(.orange)
        case .syncing:
            Image(systemName: "arrow.clockwise")
                .foregroundColor(.green)
        case .error:
            Image(systemName: "exclamationmark.icloud")
                .foregroundColor(.red)
        }
    }
}

// A helper class to monitor status changes
class SyncStatusMonitor: ObservableObject {
    @Published var shootID: String = "" {
        didSet {
            updateStatus()
        }
    }
    
    @Published var status: OfflineManager.CacheStatus = .notCached
    
    private var timer: Timer?
    
    init() {
        // Update status periodically
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
        
        // Listen for network status changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(networkStatusChanged),
            name: NSNotification.Name("NetworkStatusChanged"),
            object: nil
        )
    }
    
    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func networkStatusChanged(_ notification: Notification) {
        updateStatus()
    }
    
    private func updateStatus() {
        guard !shootID.isEmpty else { return }
        
        // Get status from the offline manager
        let newStatus = OfflineManager.shared.cacheStatusForShoot(id: shootID)
        
        // Only update if status has changed (to avoid unnecessary UI updates)
        DispatchQueue.main.async {
            if self.status != newStatus {
                self.status = newStatus
            }
        }
    }
}