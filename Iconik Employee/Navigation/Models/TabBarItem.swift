import SwiftUI
import UIKit

// MARK: - Tab Bar Item Model
struct TabBarItem: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let description: String
    var isQuickAccess: Bool
    let order: Int
    
    // Badge configuration
    var badgeType: BadgeType = .none
    
    // Equatable implementation
    static func == (lhs: TabBarItem, rhs: TabBarItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.systemImage == rhs.systemImage &&
        lhs.description == rhs.description &&
        lhs.isQuickAccess == rhs.isQuickAccess &&
        lhs.order == rhs.order &&
        lhs.badgeType == rhs.badgeType
    }
    
    enum BadgeType: Codable, Equatable {
        case none
        case count(Int)
        case active
        case dot
    }
    
    // Computed property for badge display
    var badgeValue: String? {
        switch badgeType {
        case .count(let value) where value > 0:
            return value > 99 ? "99+" : String(value)
        default:
            return nil
        }
    }
    
    var showDot: Bool {
        switch badgeType {
        case .dot, .active:
            return true
        default:
            return false
        }
    }
    
    // Create from FeatureItem
    init(from feature: FeatureItem, order: Int, isQuickAccess: Bool = false) {
        self.id = feature.id
        self.title = Self.shortTitle(for: feature.id) ?? feature.title
        self.systemImage = feature.systemImage
        self.description = feature.description
        self.order = order
        self.isQuickAccess = isQuickAccess
        self.badgeType = .none
    }
    
    // Mapping of feature IDs to short tab bar titles
    static func shortTitle(for featureId: String) -> String? {
        let shortTitles: [String: String] = [
            "timeTracking": "Time",
            "chat": "Chat",
            "scan": "Scan",
            "photoshootNotes": "Notes",
            "dailyJobReport": "Reports",
            "customDailyReports": "Custom",
            "myDailyJobReports": "My Reports",
            "mileageReports": "Mileage",
            "schedule": "Schedule",
            "locationPhotos": "Photos",
            "sportsShoot": "Sports",
            "timeOffRequests": "Time Off",
            "equipment": "Equipment",
            "classGroups": "Groups"
        ]
        return shortTitles[featureId]
    }
    
    // Direct initializer
    init(id: String, title: String, systemImage: String, description: String, order: Int, isQuickAccess: Bool = false) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.order = order
        self.isQuickAccess = isQuickAccess
        self.badgeType = .none
    }
}

// MARK: - Tab Bar Configuration
struct TabBarConfiguration: Codable {
    var items: [TabBarItem]
    var showLabels: Bool = true
    // `animateSelection` lived here and was persisted, and nothing ever read it —
    // removed in AMB.4. Decoding an older saved configuration still works: an
    // unknown key is ignored, and every remaining property has a default.
    
    static let defaultConfiguration = TabBarConfiguration(
        items: [
            TabBarItem(id: "timeTracking", title: "Time", systemImage: "clock.fill", description: "Clock in/out and track your hours", order: 0, isQuickAccess: true),
            TabBarItem(id: "chat", title: "Chat", systemImage: "bubble.left.and.bubble.right.fill", description: "Message your team", order: 1, isQuickAccess: true),
            TabBarItem(id: "scan", title: "Scan", systemImage: "wave.3.right.circle.fill", description: "Scan SD cards and job boxes", order: 999, isQuickAccess: true), // High order to always be in middle
            TabBarItem(id: "photoshootNotes", title: "Notes", systemImage: "note.text", description: "Create and manage notes for your photoshoots", order: 3, isQuickAccess: true),
            TabBarItem(id: "dailyJobReport", title: "Reports", systemImage: "doc.text", description: "Submit your daily job report", order: 4, isQuickAccess: false),
            TabBarItem(id: "sportsShoot", title: "Sports", systemImage: "sportscourt", description: "Manage sports shoot rosters and images", order: 5, isQuickAccess: false)
        ]
    )
}

// MARK: - Tab Bar Manager
class TabBarManager: ObservableObject {
    static let shared = TabBarManager()

    @Published var configuration: TabBarConfiguration
    // Canonical Home identity. Home is a permanent destination reachable from
    // the fixed Home button in the bottom bar; there is no "" vs "home" split.
    @Published var selectedTab: String = "home"

    // Full-screen overlay state (hides tab bar when photo viewer etc. is active)
    @Published var isFullScreenOverlayActive: Bool = false

    /// Whether the software keyboard is up.
    ///
    /// The floating bar gets out of the way while you type, and the space it was
    /// reserving is released. Two reasons, and the second is the one that was
    /// reported: typing wants every row it can get, and on iPad the TUCKED bar's
    /// handle sits in the bottom-right corner — exactly where the keyboard puts its
    /// own dismiss key. Two controls fighting for one corner, one of them the way
    /// out of the keyboard.
    @Published var isKeyboardVisible: Bool = false

    // Navigation data for passing between features
    @Published var selectedSportsSession: Session? = nil
    @Published var selectedSportsShoot: SportsShoot? = nil
    @Published var selectedClassGroupJobId: String? = nil
    @Published var selectedClassGroupJobType: String? = nil
    
    private let configurationKey = "TabBarConfiguration"
    
    private var keyboardObservers: [NSObjectProtocol] = []

    private init() {
        // Load saved configuration or use default
        if let savedData = UserDefaults.standard.data(forKey: configurationKey),
           let savedConfig = try? JSONDecoder().decode(TabBarConfiguration.self, from: savedData) {
            self.configuration = savedConfig
            ensureScanIsAlwaysQuickAccess()
            updateTitlesToShortVersions() // Update existing titles to short versions
        } else {
            self.configuration = TabBarConfiguration.defaultConfiguration
        }

        observeKeyboard()
    }

    /// NotificationCenter rather than an environment value, because SwiftUI has no
    /// keyboard-visibility environment key at this app's iOS 16.6 floor.
    private func observeKeyboard() {
        let center = NotificationCenter.default
        keyboardObservers = [
            center.addObserver(forName: UIResponder.keyboardWillShowNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.isKeyboardVisible = true
            },
            center.addObserver(forName: UIResponder.keyboardWillHideNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.isKeyboardVisible = false
            },
        ]
    }
    
    private func updateTitlesToShortVersions() {
        // Update all existing items to use short titles
        configuration.items = configuration.items.map { item in
            if let shortTitle = TabBarItem.shortTitle(for: item.id) {
                return TabBarItem(
                    id: item.id,
                    title: shortTitle,
                    systemImage: item.systemImage,
                    description: item.description,
                    order: item.order,
                    isQuickAccess: item.isQuickAccess
                )
            }
            return item
        }
    }
    
    private func ensureScanIsAlwaysQuickAccess() {
        // Find scan item and ensure it's always quick access
        if let scanIndex = configuration.items.firstIndex(where: { $0.id == "scan" }) {
            configuration.items[scanIndex].isQuickAccess = true
        } else {
            // If scan is missing, add it
            let scanItem = TabBarItem(
                id: "scan",
                title: "Scan",
                systemImage: "wave.3.right.circle.fill",
                description: "Scan SD cards and job boxes",
                order: 999,
                isQuickAccess: true
            )
            configuration.items.append(scanItem)
        }
    }
    
    func saveConfiguration() {
        if let encoded = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(encoded, forKey: configurationKey)
        }
    }
    
    func updateTabBarItems(_ items: [TabBarItem]) {
        configuration.items = items
        ensureScanIsAlwaysQuickAccess()
        saveConfiguration()
    }
    
    func updateBadge(for tabId: String, badge: TabBarItem.BadgeType) {
        if let index = configuration.items.firstIndex(where: { $0.id == tabId }) {
            configuration.items[index].badgeType = badge
        }
    }
    
    
    func getQuickAccessItemsExcludingScan() -> [TabBarItem] {
        let maxItems = getMaxItemsForDevice()
        return configuration.items
            .filter { $0.isQuickAccess && $0.id != "scan" }
            .sorted { $0.order < $1.order }
            .prefix(maxItems)
            .map { $0 }
    }
    
    
    func getMaxItemsForDevice() -> Int {
        return UIDevice.current.userInterfaceIdiom == .pad ? 10 : 6
    }
    
}