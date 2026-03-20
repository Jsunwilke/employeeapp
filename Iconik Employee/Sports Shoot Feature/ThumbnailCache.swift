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

    // MARK: - Private

    private func subjectDir(shootId: String, subjectId: String) -> URL {
        cacheDir.appendingPathComponent(shootId).appendingPathComponent(subjectId)
    }
}
