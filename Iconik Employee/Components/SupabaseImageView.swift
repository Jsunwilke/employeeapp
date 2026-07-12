//
//  SupabaseImageView.swift
//  Iconik Employee
//
//  A reusable component for displaying images from private Supabase storage
//  buckets using signed URLs for authenticated access.
//

import SwiftUI
import Supabase

/// Caches Supabase signed URLs by storage path so the same image isn't
/// re-signed (and, crucially, re-downloaded by AsyncImage/URLCache) on every
/// appearance. Previously each scroll of a list re-minted a fresh signature,
/// giving every avatar a new URL and forcing a full re-download.
///
/// Reuse window is deliberately shorter than the URL's 1-hour validity so a
/// changed photo (uploaded to the same path) refreshes within a few minutes.
/// Callers that overwrite an image can force-refresh via `invalidate(key:)`.
actor SignedURLCache {
    static let shared = SignedURLCache()
    private var entries: [String: (url: URL, expiresAt: Date)] = [:]

    func url(for key: String) -> URL? {
        guard let entry = entries[key], entry.expiresAt > Date() else { return nil }
        return entry.url
    }

    func store(_ url: URL, for key: String, ttl: TimeInterval) {
        entries[key] = (url, Date().addingTimeInterval(ttl))
    }

    func invalidate(key: String) {
        entries.removeValue(forKey: key)
    }
}

struct SupabaseImageView: View {
    let storageURL: String
    let bucket: String
    let width: CGFloat?
    let height: CGFloat?
    let contentMode: ContentMode
    let cornerRadius: CGFloat
    let isCircle: Bool

    @State private var signedURL: URL?
    @State private var isLoading = true
    @State private var hasError = false

    init(
        storageURL: String,
        bucket: String = "user-photos",
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        contentMode: ContentMode = .fill,
        cornerRadius: CGFloat = 0,
        isCircle: Bool = false
    ) {
        self.storageURL = storageURL
        self.bucket = bucket
        self.width = width
        self.height = height
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
        self.isCircle = isCircle
    }

    var body: some View {
        Group {
            if let url = signedURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: width, height: height)
                    case .success(let image):
                        if isCircle {
                            image
                                .resizable()
                                .aspectRatio(contentMode: contentMode)
                                .frame(width: width, height: height)
                                .clipShape(Circle())
                        } else {
                            image
                                .resizable()
                                .aspectRatio(contentMode: contentMode)
                                .frame(width: width, height: height)
                                .clipped()
                                .cornerRadius(cornerRadius)
                        }
                    case .failure:
                        errorPlaceholder
                    @unknown default:
                        EmptyView()
                    }
                }
            } else if isLoading {
                ProgressView()
                    .frame(width: width, height: height)
            } else {
                errorPlaceholder
            }
        }
        .task {
            await loadSignedURL()
        }
    }

    private var errorPlaceholder: some View {
        Image(systemName: "person.crop.circle.badge.exclamationmark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: height)
            .foregroundColor(.gray)
    }

    private func loadSignedURL() async {
        guard !storageURL.isEmpty else {
            isLoading = false
            hasError = true
            return
        }

        // Extract the path from the full URL
        guard let path = extractStoragePath(from: storageURL) else {
            print("SupabaseImageView: Could not extract path from URL: \(storageURL)")
            isLoading = false
            hasError = true
            return
        }

        let cacheKey = "\(bucket)/\(path)"

        // Reuse a still-valid signed URL so AsyncImage/URLCache can serve the
        // image from cache instead of re-downloading on every appearance.
        if let cached = await SignedURLCache.shared.url(for: cacheKey) {
            await MainActor.run {
                self.signedURL = cached
                self.isLoading = false
            }
            return
        }

        do {
            let supabase = SupabaseManager.shared.client
            let url = try await supabase.storage
                .from(bucket)
                .createSignedURL(path: path, expiresIn: 3600) // URL valid 1 hour

            // Reuse for 5 minutes — long enough to kill scroll re-downloads,
            // short enough that a re-uploaded photo refreshes quickly.
            await SignedURLCache.shared.store(url, for: cacheKey, ttl: 300)

            await MainActor.run {
                self.signedURL = url
                self.isLoading = false
            }
        } catch {
            print("SupabaseImageView: ❌ Error generating signed URL for path '\(path)': \(error.localizedDescription)")
            await MainActor.run {
                self.isLoading = false
                self.hasError = true
            }
        }
    }

    /// Extracts the storage path from a full Supabase storage URL or path
    /// Handles multiple formats:
    /// - Full URL: https://xxx.supabase.co/storage/v1/object/public/user-photos/userId/avatar.jpg -> userId/avatar.jpg
    /// - Path with bucket: user-photos/userId/avatar.jpg -> userId/avatar.jpg
    /// - Path without bucket: userId/avatar.jpg -> userId/avatar.jpg
    private func extractStoragePath(from url: String) -> String? {
        // Pattern: .../storage/v1/object/public/{bucket}/{path}
        // We need to extract the path after the bucket name

        // First try to find the bucket in a full URL
        if let bucketRange = url.range(of: "/\(bucket)/") {
            let pathStart = bucketRange.upperBound
            let path = String(url[pathStart...])
            return path
        }

        // Alternative: check for /object/public/ or /object/sign/ patterns
        if let range = url.range(of: "/object/public/\(bucket)/") {
            let pathStart = range.upperBound
            return String(url[pathStart...])
        }

        if let range = url.range(of: "/object/sign/\(bucket)/") {
            let pathStart = range.upperBound
            return String(url[pathStart...])
        }

        // If it's a path that starts with the bucket name (e.g., "user-photos/userId/file.jpg")
        if url.hasPrefix("\(bucket)/") {
            let pathStart = url.index(url.startIndex, offsetBy: bucket.count + 1)
            return String(url[pathStart...])
        }

        // If it's just a path without the full URL or bucket prefix, return as-is
        if !url.hasPrefix("http") {
            return url
        }

        return nil
    }
}

// Convenience initializer for circular avatars
struct SupabaseAvatarView: View {
    let storageURL: String
    let size: CGFloat

    init(storageURL: String, size: CGFloat = 40) {
        self.storageURL = storageURL
        self.size = size
    }

    var body: some View {
        SupabaseImageView(
            storageURL: storageURL,
            bucket: "user-photos",
            width: size,
            height: size,
            contentMode: .fill,
            isCircle: true
        )
    }
}

#if DEBUG
struct SupabaseImageView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            SupabaseAvatarView(
                storageURL: "test/avatar.jpg",
                size: 80
            )

            SupabaseImageView(
                storageURL: "test/photo.jpg",
                width: 200,
                height: 150,
                cornerRadius: 8
            )
        }
        .padding()
    }
}
#endif
