/// Phase 7 RBAC permission helpers — iOS client.
///
/// Mirrors the SQL helpers (permission_level, has_view, has_edit, has_delete)
/// for use in SwiftUI views and services.
///
/// Usage:
///     await PermissionsService.shared.load(roleId: "<uuid>")
///     if PermissionsService.shared.has("schedule", level: .edit) { ... }
///     PermissionsService.shared.clear()
///
/// Cache loaded once on auth, persisted to UserDefaults so offline launches
/// still know what the user can do.

import Foundation
import SwiftUI

enum PermissionLevel: Int {
    case none   = 0
    case view   = 1
    case edit   = 2
    case admin  = 3  // delete
}

@MainActor
final class PermissionsService: ObservableObject {
    static let shared = PermissionsService()

    /// Published so SwiftUI views can observe permission changes (e.g. after
    /// a role change pushed via realtime).
    @Published private(set) var areaLevels: [String: Int] = [:]

    private let userDefaultsKey = "permissionsCacheJSON"
    private let supabase = SupabaseManager.shared.client

    private init() {
        // Restore from UserDefaults so offline-launches start with a populated
        // cache instead of locking the UI until first network round-trip.
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.areaLevels = decoded
        }
    }

    // MARK: - Loading

    /// Load the user's permission set from Supabase. Idempotent.
    func load(roleId: String) async {
        guard !roleId.isEmpty else {
            await MainActor.run { self.clearInternal() }
            return
        }
        do {
            struct Row: Decodable { let area_code: String; let level: Int }
            let rows: [Row] = try await supabase
                .from("role_permissions")
                .select("area_code, level")
                .eq("role_id", value: roleId)
                .execute()
                .value

            var map: [String: Int] = [:]
            for row in rows { map[row.area_code] = row.level }
            await MainActor.run {
                self.areaLevels = map
                self.persist()
            }
        } catch {
            print("[PermissionsService] load failed: \(error.localizedDescription)")
            // Leave existing cache in place (could be stale but better than empty)
        }
    }

    /// Clear cache. Call on sign-out.
    func clear() {
        clearInternal()
    }

    private func clearInternal() {
        areaLevels = [:]
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(areaLevels) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    // MARK: - Synchronous checks

    /// Returns true if the current user has at least `level` on `area`.
    func has(_ area: String, level: PermissionLevel = .view) -> Bool {
        let have = areaLevels[area] ?? 0
        return have >= level.rawValue
    }

    /// Returns the int level (0–3) for an area; 0 if unknown.
    func level(_ area: String) -> Int {
        return areaLevels[area] ?? 0
    }
}

/// Static convenience for non-View call sites (services, helpers).
/// Reads from the singleton's snapshot.
enum Permissions {
    @MainActor
    static func has(_ area: String, level: PermissionLevel = .view) -> Bool {
        PermissionsService.shared.has(area, level: level)
    }

    @MainActor
    static func level(_ area: String) -> Int {
        PermissionsService.shared.level(area)
    }
}
