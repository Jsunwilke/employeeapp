//
//  ThumbnailCache.swift
//  Iconik Employee
//
//  Disk-backed thumbnail cache for capture photos received via WebSocket.
//  Photos persist across app restarts during a shoot session.
//  Cleaned up when the shoot is archived/finalized.
//
//  Storage: Documents/capture-thumbs/{shoot_id}/{subject_id}/{index}.jpg
//

import UIKit

class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.iconik.thumbnailcache", qos: .utility)

    // LRU eviction
    private var accessOrder: [(shootId: String, subjectId: String, index: Int, accessedAt: Date)] = []
    private let maxCacheSize = 500

    private var cacheDir: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("capture-thumbs")
    }

    // MARK: - Save

    /// Save a thumbnail to disk. Returns immediately, writes in background.
    func save(shootId: String, subjectId: String, imageNumber: Int?, image: UIImage) {
        queue.async { [self] in
            let dir = subjectDir(shootId: shootId, subjectId: subjectId)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

            // Use image number as filename if available, otherwise use next index
            let filename: String
            if let num = imageNumber {
                filename = "\(num).jpg"
            } else {
                let existing = (try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []
                let nextIndex = existing.count
                filename = "no_\(nextIndex).jpg"
            }

            let filePath = dir.appendingPathComponent(filename)
            // Skip if already saved (idempotent)
            guard !fileManager.fileExists(atPath: filePath.path) else { return }

            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: filePath, options: .atomic)

                // Track in LRU access order
                let index = imageNumber ?? 0
                self.accessOrder.append((shootId: shootId, subjectId: subjectId, index: index, accessedAt: Date()))

                // Evict oldest entries if over limit
                if self.accessOrder.count > self.maxCacheSize {
                    self.evictOldest(100)
                }
            }
        }
    }

    // MARK: - Load

    /// Load all cached thumbnails for a shoot. Call from background, returns on caller's thread.
    func loadAll(shootId: String) -> [String: [CaptureThumb]] {
        let shootDir = cacheDir.appendingPathComponent(shootId)
        guard fileManager.fileExists(atPath: shootDir.path) else { return [:] }

        var result: [String: [CaptureThumb]] = [:]

        guard let subjectDirs = try? fileManager.contentsOfDirectory(atPath: shootDir.path) else { return [:] }

        for subjectId in subjectDirs {
            let dir = shootDir.appendingPathComponent(subjectId)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }

            guard let files = try? fileManager.contentsOfDirectory(atPath: dir.path) else { continue }
            let sortedFiles = files.sorted() // alphabetical = numeric order for image numbers

            var thumbs: [CaptureThumb] = []
            for file in sortedFiles {
                guard file.hasSuffix(".jpg") else { continue }
                let filePath = dir.appendingPathComponent(file)
                guard let data = try? Data(contentsOf: filePath),
                      let image = UIImage(data: data) else { continue }

                // Parse image number from filename (e.g., "2902.jpg" -> 2902)
                let name = file.replacingOccurrences(of: ".jpg", with: "")
                let imageNumber: Int? = name.hasPrefix("no_") ? nil : Int(name)

                thumbs.append(CaptureThumb(image: image, imageNumber: imageNumber))
            }

            if !thumbs.isEmpty {
                result[subjectId] = thumbs

                // Update LRU access times for loaded entries
                let now = Date()
                for (i, thumb) in thumbs.enumerated() {
                    let index = thumb.imageNumber ?? i
                    // Remove old entry if present, then re-add with fresh timestamp
                    accessOrder.removeAll { $0.shootId == shootId && $0.subjectId == subjectId && $0.index == index }
                    accessOrder.append((shootId: shootId, subjectId: subjectId, index: index, accessedAt: now))
                }
            }
        }

        return result
    }

    // MARK: - Delete

    /// Delete all cached thumbnails for a shoot (call on archive/finalize).
    func deleteShoot(shootId: String) {
        queue.async { [self] in
            let shootDir = cacheDir.appendingPathComponent(shootId)
            try? fileManager.removeItem(at: shootDir)
        }
    }

    /// Delete all cached thumbnails (nuclear option).
    func deleteAll() {
        queue.async { [self] in
            try? fileManager.removeItem(at: cacheDir)
        }
    }

    // MARK: - LRU Eviction

    /// Remove the oldest `count` entries from disk and access tracking.
    /// Must be called on `queue`.
    private func evictOldest(_ count: Int) {
        guard accessOrder.count > count else {
            // Not enough entries to evict
            accessOrder.removeAll()
            return
        }

        // Sort by accessedAt ascending (oldest first)
        let sorted = accessOrder.sorted { $0.accessedAt < $1.accessedAt }
        let toEvict = Array(sorted.prefix(count))

        for entry in toEvict {
            let dir = subjectDir(shootId: entry.shootId, subjectId: entry.subjectId)
            // Try both naming conventions
            let numberedPath = dir.appendingPathComponent("\(entry.index).jpg")
            let fallbackPath = dir.appendingPathComponent("no_\(entry.index).jpg")
            try? fileManager.removeItem(at: numberedPath)
            try? fileManager.removeItem(at: fallbackPath)
        }

        // Remove evicted entries from tracking
        let evictedSet = Set(toEvict.map { "\($0.shootId)/\($0.subjectId)/\($0.index)" })
        accessOrder.removeAll { evictedSet.contains("\($0.shootId)/\($0.subjectId)/\($0.index)") }
    }

    // MARK: - Private

    private func subjectDir(shootId: String, subjectId: String) -> URL {
        cacheDir.appendingPathComponent(shootId).appendingPathComponent(subjectId)
    }
}
