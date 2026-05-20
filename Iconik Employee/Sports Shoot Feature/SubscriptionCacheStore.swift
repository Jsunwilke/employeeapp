//
//  SubscriptionCacheStore.swift
//  Iconik Employee
//
//  FROM_SCRATCH_ARCHITECTURE.md §13 H1.12 — disk-backed persistence layer
//  for the SubscriptionCache substrate added 2026-05-20 per the rule 19.7
//  retroactive amendment that retired the original H1.1 "no disk persistence"
//  deferral. See PHASE_AC_PLAN.md §13-§17 for the scope expansion contract
//  and §15 for the design rationale (this is the architecture, not a patch).
//
//  Storage shape mirrors CommandQueue.swift (the Phase D precedent named in
//  the original H1.1 doc comment "Pattern mirrors CommandQueue.swift"):
//    - SQLite via the system SQLite3 C library
//    - Application Support / Iconik Employee / subscription_cache.sqlite
//    - Lazy init via ensureOpen()
//    - Synchronous transactions per mutation (no debouncing; SQLite is fast
//      enough that per-mutation transactions amortize correctly)
//    - iOS default file protection (matches the codebase-wide pattern;
//      explicit FileProtectionType usage is reserved for the future uniform
//      SOC-2 hardening phase per PHASE_AC_PLAN.md §19.4)
//
//  Public API is synchronous, callable from inside SubscriptionCache's serial
//  DispatchQueue. The store does NOT own its own queue — SubscriptionCache's
//  queue provides the single-threaded contract; SQLite is opened with
//  SQLITE_OPEN_FULLMUTEX so internal mutex protects the handle from any
//  out-of-band call site too.
//
//  Schema:
//    cached_subjects:
//      (gallery_id, subject_id) composite PK
//      subject_json TEXT  — wire-dict JSON, parsed back via
//                           SubscriptionCache._parseSubjectFromWire on load
//      updated_at REAL    — timestamp for forensic ordering
//    cached_gallery_meta:
//      gallery_id PK
//      last_version INTEGER  — the lastVersionByGallery counter persisted
//      updated_at REAL
//
//  Captures are NOT persisted (preserves the H1 contract that captures only
//  hydrate via incremental capture_completed broadcasts; persisting them
//  would create a partial-cache scenario state-sync.ts:31-33 explicitly
//  doesn't support). See PHASE_AC_PLAN.md §19.5.
//

import Foundation
import SQLite3

/// Errors surfaced by the store. Forensic-only — production callers in
/// SubscriptionCache catch and log; a failed disk write does NOT block
/// the in-memory cache mutation it followed (data loss on next restart
/// is the worst case, not in-flight failure).
enum SubscriptionCacheStoreError: Error, CustomStringConvertible {
    case openFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)
    case payloadEncodeFailed
    case notInitialized

    var description: String {
        switch self {
        case .openFailed(let s):          return "open failed: \(s)"
        case .prepareFailed(let s):       return "prepare failed: \(s)"
        case .bindFailed(let s):          return "bind failed: \(s)"
        case .stepFailed(let s):          return "step failed: \(s)"
        case .payloadEncodeFailed:        return "payload encode failed"
        case .notInitialized:             return "store not initialized"
        }
    }
}

/// Loaded gallery state — passed back to SubscriptionCache for in-memory
/// hydration. The subject wire-dicts go through
/// SubscriptionCache._parseSubjectFromWire to become FPSubject values, so
/// the round-trip uses the same parser the state_sync wire path uses.
struct LoadedGalleryState {
    let galleryId: String
    let subjectWireDicts: [[String: Any]]
    let lastVersion: Int
}

final class SubscriptionCacheStore {
    static let shared = SubscriptionCacheStore()

    private var db: OpaquePointer?
    private var initialized = false

    /// Override for the database directory. Tests inject a temp directory
    /// to isolate from the production cache file. Production code never
    /// sets this; the default Application Support path is used.
    private var directoryOverride: URL?

    /// Master switch — when false, all public API calls are no-ops. The
    /// SubscriptionCache caller checks this via isEnabled. Tests that want
    /// pure in-memory semantics call _testDisable() at setUp.
    private var enabled: Bool = true

    private init() {}

    // MARK: - Configuration (production app launch / tests)

    /// Production app launch wiring (no-op if already enabled). Currently
    /// kept enabled-by-default because the default Application Support
    /// directory is correct out of the box; explicit enable is here for
    /// symmetry with future configuration needs and for test seam shape.
    func enable() {
        enabled = true
    }

    /// Test-only — disable all disk I/O for the lifetime of the test.
    /// Tests that exercise pure in-memory behavior call this in setUp.
    func _testDisable() {
        enabled = false
    }

    /// Test-only — set a directory override (use a unique temp dir per
    /// test class so tests don't pollute the production cache file).
    func _testSetDirectory(_ url: URL?) {
        directoryOverride = url
        // Force re-open against the new directory on next ensureOpen call.
        if let db = db {
            sqlite3_close(db)
        }
        db = nil
        initialized = false
    }

    var isEnabled: Bool { enabled }

    // MARK: - Lifecycle

    private func ensureOpen() throws {
        if initialized { return }
        let url = try databaseURL()
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard rc == SQLITE_OK, let opened = handle else {
            let msg = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw SubscriptionCacheStoreError.openFailed(msg)
        }
        db = opened
        try createSchema()
        initialized = true
    }

    private func databaseURL() throws -> URL {
        if let override = directoryOverride {
            let fm = FileManager.default
            if !fm.fileExists(atPath: override.path) {
                try fm.createDirectory(at: override, withIntermediateDirectories: true)
            }
            return override.appendingPathComponent("subscription_cache.sqlite")
        }
        let fm = FileManager.default
        let dir = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDir = dir.appendingPathComponent("Iconik Employee", isDirectory: true)
        if !fm.fileExists(atPath: appDir.path) {
            try fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        return appDir.appendingPathComponent("subscription_cache.sqlite")
    }

    private func createSchema() throws {
        let sql = """
            CREATE TABLE IF NOT EXISTS cached_subjects (
                gallery_id TEXT NOT NULL,
                subject_id TEXT NOT NULL,
                subject_json TEXT NOT NULL,
                updated_at REAL NOT NULL,
                PRIMARY KEY (gallery_id, subject_id)
            );
            CREATE INDEX IF NOT EXISTS idx_cached_subjects_gallery
                ON cached_subjects(gallery_id);
            CREATE TABLE IF NOT EXISTS cached_gallery_meta (
                gallery_id TEXT PRIMARY KEY,
                last_version INTEGER NOT NULL,
                updated_at REAL NOT NULL
            );
            """
        try exec(sql)
    }

    // MARK: - Public API (called from SubscriptionCache inside its serial queue)

    /// Wholesale persist a gallery's subject set + version counter. Called
    /// from SubscriptionCache._notifyGallery after every mutation that
    /// changes the gallery's in-memory state (applyStateSync wholesale-
    /// replace, _applySubjectUpdate, _applySubjectCreate, _applySubjectsDelete).
    /// Single transaction: DELETE existing rows for gallery, INSERT each
    /// subject, UPSERT meta. Atomic — a crash mid-write leaves the previous
    /// state intact (transaction rolls back on close).
    func persistGalleryState(galleryId: String, subjectWireDicts: [[String: Any]], lastVersion: Int) {
        if !enabled { return }
        do {
            try ensureOpen()
            try beginTransaction()
            do {
                try deleteSubjects(galleryId: galleryId)
                let now = Date().timeIntervalSince1970
                for dict in subjectWireDicts {
                    guard let subjectId = dict["id"] as? String else { continue }
                    let json = try encodeJson(dict)
                    try insertSubject(
                        galleryId: galleryId,
                        subjectId: subjectId,
                        subjectJson: json,
                        updatedAt: now
                    )
                }
                try upsertGalleryMeta(galleryId: galleryId, lastVersion: lastVersion, updatedAt: now)
                try commitTransaction()
            } catch {
                try? rollbackTransaction()
                throw error
            }
        } catch {
            print("[SubscriptionCacheStore] persistGalleryState failed: gallery=\(galleryId) error=\(error)")
            // Best-effort: in-memory state still mutated correctly, only
            // disk durability is lost. Next mutation's persist will refresh.
        }
    }

    /// Purge one gallery's persisted state. Called from
    /// PowerSyncManager.unpinGallery hook + SubscriptionCache.purgeGallery.
    func purgeGallery(_ galleryId: String) {
        if !enabled { return }
        do {
            try ensureOpen()
            try beginTransaction()
            try deleteSubjects(galleryId: galleryId)
            try deleteGalleryMeta(galleryId: galleryId)
            try commitTransaction()
        } catch {
            print("[SubscriptionCacheStore] purgeGallery failed: gallery=\(galleryId) error=\(error)")
            try? rollbackTransaction()
        }
    }

    /// Purge all persisted state. Called from SupabaseAuthService.signOut
    /// hook + SubscriptionCache.purgeAll. Drops every row in both tables.
    func purgeAll() {
        if !enabled { return }
        do {
            try ensureOpen()
            try beginTransaction()
            try exec("DELETE FROM cached_subjects;")
            try exec("DELETE FROM cached_gallery_meta;")
            try commitTransaction()
        } catch {
            print("[SubscriptionCacheStore] purgeAll failed: error=\(error)")
            try? rollbackTransaction()
        }
    }

    /// Load a single gallery's persisted state for lazy hydration on first
    /// setCurrentGallery for that gallery. Returns nil when no persisted
    /// state exists OR when persistence is disabled.
    func loadGallery(_ galleryId: String) -> LoadedGalleryState? {
        if !enabled { return nil }
        do {
            try ensureOpen()
            let lastVersion = try readGalleryMeta(galleryId: galleryId)
            let subjects = try readSubjects(galleryId: galleryId)
            // No subjects + no meta → return nil (caller skips hydration).
            // No subjects but meta exists → return empty subjects with meta version (genuinely-empty gallery).
            // Subjects exist → return both.
            if subjects.isEmpty && lastVersion == nil { return nil }
            return LoadedGalleryState(
                galleryId: galleryId,
                subjectWireDicts: subjects,
                lastVersion: lastVersion ?? 0
            )
        } catch {
            print("[SubscriptionCacheStore] loadGallery failed: gallery=\(galleryId) error=\(error)")
            return nil
        }
    }

    /// Load all persisted galleries — used by tests for verification and
    /// by potential eager-hydration call sites (currently not used in
    /// production; production uses lazy loadGallery on first setCurrentGallery).
    func loadAll() -> [LoadedGalleryState] {
        if !enabled { return [] }
        do {
            try ensureOpen()
            let galleryIds = try readAllGalleryIds()
            return galleryIds.compactMap { loadGallery($0) }
        } catch {
            print("[SubscriptionCacheStore] loadAll failed: error=\(error)")
            return []
        }
    }

    // MARK: - Test seam

    /// Test-only — drop every row and close. Tests call this between
    /// cases to isolate. Production never calls this.
    func _testReset() {
        if let db = db {
            sqlite3_close(db)
        }
        db = nil
        initialized = false
        directoryOverride = nil
        enabled = true
    }

    /// Test-only — drop every row but keep open. For sub-test cleanup.
    func _testClearAll() {
        if !enabled { return }
        do {
            try ensureOpen()
            try exec("DELETE FROM cached_subjects;")
            try exec("DELETE FROM cached_gallery_meta;")
        } catch {
            print("[SubscriptionCacheStore] _testClearAll failed: \(error)")
        }
    }

    // MARK: - Internal SQL helpers

    private func beginTransaction() throws {
        try exec("BEGIN TRANSACTION;")
    }

    private func commitTransaction() throws {
        try exec("COMMIT;")
    }

    private func rollbackTransaction() throws {
        try exec("ROLLBACK;")
    }

    private func deleteSubjects(galleryId: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM cached_subjects WHERE gallery_id = ?;", -1, &stmt, nil) == SQLITE_OK else {
            throw SubscriptionCacheStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        try bindText(stmt, 1, galleryId)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SubscriptionCacheStoreError.stepFailed(lastErrorMessage())
        }
    }

    private func deleteGalleryMeta(galleryId: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM cached_gallery_meta WHERE gallery_id = ?;", -1, &stmt, nil) == SQLITE_OK else {
            throw SubscriptionCacheStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        try bindText(stmt, 1, galleryId)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SubscriptionCacheStoreError.stepFailed(lastErrorMessage())
        }
    }

    private func insertSubject(galleryId: String, subjectId: String, subjectJson: String, updatedAt: Double) throws {
        let sql = """
            INSERT INTO cached_subjects (gallery_id, subject_id, subject_json, updated_at)
            VALUES (?, ?, ?, ?);
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SubscriptionCacheStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        try bindText(stmt, 1, galleryId)
        try bindText(stmt, 2, subjectId)
        try bindText(stmt, 3, subjectJson)
        sqlite3_bind_double(stmt, 4, updatedAt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SubscriptionCacheStoreError.stepFailed(lastErrorMessage())
        }
    }

    private func upsertGalleryMeta(galleryId: String, lastVersion: Int, updatedAt: Double) throws {
        let sql = """
            INSERT INTO cached_gallery_meta (gallery_id, last_version, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(gallery_id) DO UPDATE SET
                last_version = excluded.last_version,
                updated_at = excluded.updated_at;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SubscriptionCacheStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        try bindText(stmt, 1, galleryId)
        sqlite3_bind_int64(stmt, 2, Int64(lastVersion))
        sqlite3_bind_double(stmt, 3, updatedAt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SubscriptionCacheStoreError.stepFailed(lastErrorMessage())
        }
    }

    private func readGalleryMeta(galleryId: String) throws -> Int? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT last_version FROM cached_gallery_meta WHERE gallery_id = ?;", -1, &stmt, nil) == SQLITE_OK else {
            throw SubscriptionCacheStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        try bindText(stmt, 1, galleryId)
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        } else if rc == SQLITE_DONE {
            return nil
        } else {
            throw SubscriptionCacheStoreError.stepFailed(lastErrorMessage())
        }
    }

    private func readSubjects(galleryId: String) throws -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT subject_json FROM cached_subjects WHERE gallery_id = ?;", -1, &stmt, nil) == SQLITE_OK else {
            throw SubscriptionCacheStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        try bindText(stmt, 1, galleryId)

        var results: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let jsonStr = columnText(stmt, 0),
                  let data = jsonStr.data(using: .utf8),
                  let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }
            results.append(dict)
        }
        return results
    }

    private func readAllGalleryIds() throws -> [String] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT DISTINCT gallery_id FROM cached_gallery_meta;", -1, &stmt, nil) == SQLITE_OK else {
            throw SubscriptionCacheStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        var ids: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let s = columnText(stmt, 0) { ids.append(s) }
        }
        return ids
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw SubscriptionCacheStoreError.stepFailed(msg)
        }
    }

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) throws {
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let rc = sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
        if rc != SQLITE_OK {
            throw SubscriptionCacheStoreError.bindFailed(lastErrorMessage())
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let cstr = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: cstr)
    }

    private func lastErrorMessage() -> String {
        guard let cstr = sqlite3_errmsg(db) else { return "unknown" }
        return String(cString: cstr)
    }

    private func encodeJson(_ dict: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(dict) else {
            throw SubscriptionCacheStoreError.payloadEncodeFailed
        }
        let data = try JSONSerialization.data(withJSONObject: dict, options: [])
        guard let s = String(data: data, encoding: .utf8) else {
            throw SubscriptionCacheStoreError.payloadEncodeFailed
        }
        return s
    }
}
