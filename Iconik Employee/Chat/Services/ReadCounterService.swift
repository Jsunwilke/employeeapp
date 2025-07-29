import Foundation

// MARK: - Read Counter Protocol
protocol ReadCounterProtocol {
    func recordRead(operation: String, collection: String, component: String, count: Int)
    func recordCacheHit(collection: String, component: String, savedReads: Int)
    func recordCacheMiss(collection: String, component: String)
    func getSessionStats() -> ReadStats
    func getDailyStats() -> ReadStats
    func resetSessionStats()
}

// MARK: - Read Operation Model
struct ReadOperation: Codable {
    let timestamp: Date
    let operation: String
    let collection: String
    let component: String
    let count: Int
    let cacheHit: Bool
    let savedReads: Int?
}

// MARK: - Read Statistics Model
struct ReadStats {
    let totalReads: Int
    let cacheHits: Int
    let cacheMisses: Int
    let savedReads: Int
    let operationsByCollection: [String: Int]
    let operationsByComponent: [String: Int]
    let startTime: Date
    let endTime: Date
    
    var cacheHitRate: Double {
        let total = cacheHits + cacheMisses
        return total > 0 ? Double(cacheHits) / Double(total) * 100 : 0
    }
    
    var formattedCacheHitRate: String {
        return String(format: "%.1f%%", cacheHitRate)
    }
    
    var duration: TimeInterval {
        return endTime.timeIntervalSince(startTime)
    }
}

// MARK: - Read Counter Service
class ReadCounterService: ReadCounterProtocol {
    private let userDefaults = UserDefaults.standard
    private let sessionKey: String
    private let dailyKey: String
    private var sessionOperations: [ReadOperation] = []
    private let sessionStartTime = Date()
    
    static let shared = ReadCounterService()
    
    private init() {
        let sessionId = UUID().uuidString
        self.sessionKey = "focal_read_session_\(sessionId)"
        self.dailyKey = "focal_read_daily_\(Date().toYYYYMMDD())"
        
        // Load existing daily operations
        loadDailyOperations()
    }
    
    // MARK: - Recording Operations
    
    func recordRead(operation: String, collection: String, component: String, count: Int) {
        let read = ReadOperation(
            timestamp: Date(),
            operation: operation,
            collection: collection,
            component: component,
            count: count,
            cacheHit: false,
            savedReads: nil
        )
        
        sessionOperations.append(read)
        appendToDailyOperations(read)
        
        // Log for debugging
        print("📊 Read Operation: \(operation) - \(collection) - Count: \(count)")
    }
    
    func recordCacheHit(collection: String, component: String, savedReads: Int) {
        let read = ReadOperation(
            timestamp: Date(),
            operation: "cache_hit",
            collection: collection,
            component: component,
            count: 0,
            cacheHit: true,
            savedReads: savedReads
        )
        
        sessionOperations.append(read)
        appendToDailyOperations(read)
        
        // Log for debugging
        print("✅ Cache Hit: \(collection) - Saved \(savedReads) reads")
    }
    
    func recordCacheMiss(collection: String, component: String) {
        let read = ReadOperation(
            timestamp: Date(),
            operation: "cache_miss",
            collection: collection,
            component: component,
            count: 0,
            cacheHit: false,
            savedReads: nil
        )
        
        sessionOperations.append(read)
        appendToDailyOperations(read)
        
        // Log for debugging
        print("❌ Cache Miss: \(collection)")
    }
    
    // MARK: - Statistics
    
    func getSessionStats() -> ReadStats {
        return calculateStats(from: sessionOperations, startTime: sessionStartTime, endTime: Date())
    }
    
    func getDailyStats() -> ReadStats {
        let dailyOps = loadDailyOperations()
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return calculateStats(from: dailyOps, startTime: startOfDay, endTime: Date())
    }
    
    func resetSessionStats() {
        sessionOperations.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func calculateStats(from operations: [ReadOperation], startTime: Date, endTime: Date) -> ReadStats {
        var totalReads = 0
        var cacheHits = 0
        var cacheMisses = 0
        var savedReads = 0
        var operationsByCollection: [String: Int] = [:]
        var operationsByComponent: [String: Int] = [:]
        
        for op in operations {
            if op.cacheHit {
                cacheHits += 1
                savedReads += op.savedReads ?? 0
            } else if op.operation == "cache_miss" {
                cacheMisses += 1
            } else {
                totalReads += op.count
            }
            
            operationsByCollection[op.collection, default: 0] += op.count
            operationsByComponent[op.component, default: 0] += op.count
        }
        
        return ReadStats(
            totalReads: totalReads,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            savedReads: savedReads,
            operationsByCollection: operationsByCollection,
            operationsByComponent: operationsByComponent,
            startTime: startTime,
            endTime: endTime
        )
    }
    
    private func loadDailyOperations() -> [ReadOperation] {
        guard let data = userDefaults.data(forKey: dailyKey),
              let operations = try? JSONDecoder().decode([ReadOperation].self, from: data) else {
            return []
        }
        
        // Filter out operations from previous days
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return operations.filter { $0.timestamp >= startOfDay }
    }
    
    private func appendToDailyOperations(_ operation: ReadOperation) {
        var dailyOps = loadDailyOperations()
        dailyOps.append(operation)
        
        // Keep only last 1000 operations to prevent excessive memory usage
        if dailyOps.count > 1000 {
            dailyOps = Array(dailyOps.suffix(1000))
        }
        
        if let encoded = try? JSONEncoder().encode(dailyOps) {
            userDefaults.set(encoded, forKey: dailyKey)
        }
    }
}

// MARK: - Analytics Helper
extension ReadCounterService {
    func generateAnalyticsReport() -> String {
        let sessionStats = getSessionStats()
        let dailyStats = getDailyStats()
        
        var report = "📊 Firebase Read Analytics Report\n"
        report += "================================\n\n"
        
        report += "Session Statistics:\n"
        report += "- Total Reads: \(sessionStats.totalReads)\n"
        report += "- Cache Hits: \(sessionStats.cacheHits)\n"
        report += "- Cache Misses: \(sessionStats.cacheMisses)\n"
        report += "- Cache Hit Rate: \(sessionStats.formattedCacheHitRate)\n"
        report += "- Reads Saved by Cache: \(sessionStats.savedReads)\n"
        report += "- Session Duration: \(Int(sessionStats.duration / 60)) minutes\n\n"
        
        report += "Daily Statistics:\n"
        report += "- Total Reads: \(dailyStats.totalReads)\n"
        report += "- Cache Hits: \(dailyStats.cacheHits)\n"
        report += "- Cache Misses: \(dailyStats.cacheMisses)\n"
        report += "- Cache Hit Rate: \(dailyStats.formattedCacheHitRate)\n"
        report += "- Reads Saved by Cache: \(dailyStats.savedReads)\n\n"
        
        report += "Collections Accessed:\n"
        for (collection, count) in dailyStats.operationsByCollection.sorted(by: { $0.value > $1.value }) {
            report += "- \(collection): \(count) reads\n"
        }
        
        return report
    }
    
    func shouldShowCostWarning() -> Bool {
        let dailyStats = getDailyStats()
        // Show warning if daily reads exceed 50,000 (configurable threshold)
        return dailyStats.totalReads > 50000
    }
}