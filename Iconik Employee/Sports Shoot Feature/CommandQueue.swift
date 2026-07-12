//
//  CommandQueue.swift
//  Iconik Employee
//
//  FROM_SCRATCH_ARCHITECTURE.md §13 Phase D — iPad-side durable command
//  queue. Persists subject_command envelopes that fail their connected
//  send (timeout, transport throw, no Surface available) so the edit
//  isn't lost. Drains in FIFO order on WebSocket reconnect; the Surface
//  receiver dedupes replays via the existing idempotency_cache (per
//  §11.3) so re-sending the same idempotency_key returns a `dedupe` ack
//  rather than re-applying the write.
//
//  Backing store: SQLite via the system SQLite3 C library, in a
//  database file separate from PowerSync. Phase D body explicitly
//  scopes this as "SQLite table separate from PowerSync" — the queue
//  must not share PowerSync's database because (a) PowerSync's CRUD
//  upload semantics conflict with FIFO drain, and (b) the queue must
//  outlive PowerSync's lifecycle (it gets disconnected during capture
//  sessions on Surface; the iPad's queue is independent).
//
//  Non-goals (kept out by design):
//    - Retry backoff / max-retry counts. Surface is the source of
//      truth for command outcome; iPad just keeps re-sending until an
//      ack returns. The drain stops on transport throw and resumes on
//      next reconnect.
//    - Priority queues. Phase D body explicitly says FIFO.
//    - Per-row error handling. Failed drain returns to the queue at
//      head; corrupt rows are an audit concern, not a runtime one.
//
//  Replaces: SubjectSyncService.swift's five legacy fallback paths
//  (updateSubject, createSubject, batchCreateSubjects, deleteSubject,
//  batchUpdateSubjects). After Phase D, those methods enqueue here
//  instead of writing PowerSync + sendSubjectFullUpdate. Per delete-
//  first migration (rule 19.1) the fallback paths are deleted in the
//  same commit that adds this queue.
//

import Foundation
import SQLite3

/// A queued subject_command envelope ready to drain. Mirrors
/// SubjectCommand's wire shape but materialized from SQLite rows so
/// the drain loop can resend without re-encoding fields.
struct QueuedCommand {
    let rowId: Int64
    let commandId: String
    let commandType: String
    let galleryId: String
    let idempotencyKey: String
    let originatingDeviceId: String
    let payloadJSON: String
    let sentAt: String
    let createdAt: Date

    /// Reconstruct a SubjectCommand for re-send. The wire shape is
    /// identical to the original send so the receiver's idempotency
    /// check fires correctly.
    func toCommand() -> SubjectCommand? {
        guard let type = SubjectCommandType(rawValue: commandType),
              let payloadData = payloadJSON.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else { return nil }
        return SubjectCommand(
            commandId: commandId,
            commandType: type,
            galleryId: galleryId,
            idempotencyKey: idempotencyKey,
            originatingDeviceId: originatingDeviceId,
            payload: payload,
            sentAt: sentAt
        )
    }
}

/// Errors surfaced by the queue. These are forensic-only — callers in
/// SubjectSyncService never act on them beyond logging, since enqueue
/// failure on a transport-failure path means the edit is lost either
/// way (rare; only if the file system itself errors).
enum CommandQueueError: Error, CustomStringConvertible {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case payloadEncodeFailed
    case notInitialized

    var description: String {
        switch self {
        case .openFailed(let m):       return "queue open failed: \(m)"
        case .prepareFailed(let m):    return "queue prepare failed: \(m)"
        case .stepFailed(let m):       return "queue step failed: \(m)"
        case .bindFailed(let m):       return "queue bind failed: \(m)"
        case .payloadEncodeFailed:     return "queue payload encode failed"
        case .notInitialized:          return "queue not initialized"
        }
    }
}

/// Single-instance, thread-safe command queue. The shared singleton
/// is initialized lazily on first enqueue; SQLite's per-connection
/// mutex serializes inner operations, plus the public API uses an
/// internal serial DispatchQueue to keep enqueue/drain operations
/// linearized across threads.
final class CommandQueue {
    static let shared = CommandQueue()

    private var db: OpaquePointer?
    private let serial = DispatchQueue(label: "com.iconikschools.command-queue")
    private var initialized = false

    private init() {}

    // MARK: - Lifecycle

    /// Open or create the queue database. Idempotent. Called from
    /// every public entry point so callers never have to remember to
    /// initialize.
    private func ensureOpen() throws {
        if initialized { return }
        let url = try Self.databaseURL()
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard rc == SQLITE_OK, let opened = handle else {
            let msg = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw CommandQueueError.openFailed(msg)
        }
        db = opened
        try createSchema()
        initialized = true
    }

    private static func databaseURL() throws -> URL {
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
        return appDir.appendingPathComponent("command_queue.sqlite")
    }

    private func createSchema() throws {
        // Single table. row_id is the FIFO ordering key (autoincrement).
        // command_id is unique per send attempt; idempotency_key is
        // unique per logical edit (used by Surface dedupe). Both are
        // indexed for cheap lookup during drain and dedupe checks.
        let sql = """
            CREATE TABLE IF NOT EXISTS command_queue (
                row_id INTEGER PRIMARY KEY AUTOINCREMENT,
                command_id TEXT NOT NULL,
                command_type TEXT NOT NULL,
                gallery_id TEXT NOT NULL,
                idempotency_key TEXT NOT NULL,
                originating_device_id TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                sent_at TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_command_queue_idempotency
                ON command_queue(idempotency_key);
            CREATE INDEX IF NOT EXISTS idx_command_queue_row
                ON command_queue(row_id);
            """
        try exec(sql)
    }

    // MARK: - Public API

    /// Enqueue a command envelope. Called from SubjectSyncService when
    /// the connected send path fails (transport throw, timeout, ack
    /// rejection). The envelope's existing idempotency_key is preserved
    /// so the Surface dedupes replays correctly.
    @discardableResult
    func enqueue(_ command: SubjectCommand) async throws -> Int64 {
        try await withSerial { [weak self] in
            guard let self else { throw CommandQueueError.notInitialized }
            try self.ensureOpen()

            let payload = try Self.encodePayload(command.payload)
            let sql = """
                INSERT INTO command_queue
                    (command_id, command_type, gallery_id, idempotency_key,
                     originating_device_id, payload_json, sent_at, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw CommandQueueError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            try self.bindText(stmt, 1, command.commandId)
            try self.bindText(stmt, 2, command.commandType.rawValue)
            try self.bindText(stmt, 3, command.galleryId)
            try self.bindText(stmt, 4, command.idempotencyKey)
            try self.bindText(stmt, 5, command.originatingDeviceId)
            try self.bindText(stmt, 6, payload)
            try self.bindText(stmt, 7, command.sentAt)
            sqlite3_bind_double(stmt, 8, Date().timeIntervalSince1970)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw CommandQueueError.stepFailed(self.lastErrorMessage())
            }
            let rowId = sqlite3_last_insert_rowid(self.db)
            return rowId
        }
    }

    /// Delete every queued command. Called on sign-out so pending
    /// edits (which can contain subject PII in payload_json) never
    /// survive across accounts on a shared device.
    func purgeAll() async throws {
        try await withSerial { [weak self] in
            guard let self else { throw CommandQueueError.notInitialized }
            try self.ensureOpen()
            try self.exec("DELETE FROM command_queue;")
        }
    }

    /// Read up to `limit` queued commands in FIFO order without
    /// removing them. The drain loop calls this, sends each command,
    /// and on `applied` or `dedupe` ack calls `remove(rowId:)` to
    /// finalize. Failed sends leave the row in place for the next
    /// drain attempt. `limit` keeps the per-tick batch bounded so a
    /// huge backlog doesn't block the main actor.
    func nextBatch(limit: Int = 50) async throws -> [QueuedCommand] {
        try await withSerial { [weak self] in
            guard let self else { throw CommandQueueError.notInitialized }
            try self.ensureOpen()
            let sql = """
                SELECT row_id, command_id, command_type, gallery_id,
                       idempotency_key, originating_device_id, payload_json,
                       sent_at, created_at
                  FROM command_queue
                 ORDER BY row_id ASC
                 LIMIT ?;
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw CommandQueueError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))

            var rows: [QueuedCommand] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let rowId = sqlite3_column_int64(stmt, 0)
                guard
                    let cmdId = self.columnText(stmt, 1),
                    let cmdType = self.columnText(stmt, 2),
                    let gid = self.columnText(stmt, 3),
                    let key = self.columnText(stmt, 4),
                    let device = self.columnText(stmt, 5),
                    let payload = self.columnText(stmt, 6),
                    let sentAt = self.columnText(stmt, 7)
                else { continue }
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8))
                rows.append(QueuedCommand(
                    rowId: rowId,
                    commandId: cmdId,
                    commandType: cmdType,
                    galleryId: gid,
                    idempotencyKey: key,
                    originatingDeviceId: device,
                    payloadJSON: payload,
                    sentAt: sentAt,
                    createdAt: createdAt
                ))
            }
            return rows
        }
    }

    /// Remove a row by row_id. Called after the Surface acks the
    /// command applied/dedupe — the iPad's queue obligation is
    /// satisfied either way.
    func remove(rowId: Int64) async throws {
        try await withSerial { [weak self] in
            guard let self else { throw CommandQueueError.notInitialized }
            try self.ensureOpen()
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, "DELETE FROM command_queue WHERE row_id = ?;", -1, &stmt, nil) == SQLITE_OK else {
                throw CommandQueueError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, rowId)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw CommandQueueError.stepFailed(self.lastErrorMessage())
            }
        }
    }

    /// Total queued rows. Surfaces depth in the SubjectSyncEvents
    /// debug panel and in tests asserting drain progress.
    func count() async throws -> Int {
        try await withSerial { [weak self] in
            guard let self else { throw CommandQueueError.notInitialized }
            try self.ensureOpen()
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, "SELECT COUNT(*) FROM command_queue;", -1, &stmt, nil) == SQLITE_OK else {
                throw CommandQueueError.prepareFailed(self.lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                throw CommandQueueError.stepFailed(self.lastErrorMessage())
            }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    /// Test-only: drop every row. Production never calls this — the
    /// queue is meant to drain naturally via reconnect.
    func _testReset() async throws {
        try await withSerial { [weak self] in
            guard let self else { throw CommandQueueError.notInitialized }
            try self.ensureOpen()
            try self.exec("DELETE FROM command_queue;")
        }
    }

    // MARK: - Drain on reconnect

    /// In-flight drain guard. Concurrent drain ticks are wasteful (the
    /// queue is single-row-FIFO, two drainers contend for the same
    /// row_id) and risk double-sending commands across the LAN. The
    /// guard short-circuits a tickDrain that fires while a previous
    /// one is still running.
    private var draining = false

    /// One drain pass: read up to `limit` rows in FIFO order, send
    /// each via `sender` (typically FocalPointSyncClient.shared.sendSubjectCommand),
    /// and on `applied`/`dedupe` ack remove the row. Stops on the
    /// first transport error so a flaky reconnect doesn't burn the
    /// whole queue. The Surface receiver dedupes replays via §11.3,
    /// so a re-sent command that already applied returns dedupe and
    /// the row removes the same as on a fresh apply.
    ///
    /// Called from FocalPointSyncClient on connection-state transition
    /// to .connected. Safe to call repeatedly — the in-flight guard
    /// prevents overlapping work.
    func tickDrain(
        sender: @escaping (SubjectCommand) async throws -> CommandAck,
        limit: Int = 50
    ) async {
        // Cheap guard against re-entrance. Read+set is on the serial
        // queue's actor-equivalent through withSerial below.
        let shouldRun: Bool = await withSerialOrFalse { [weak self] in
            guard let self else { return false }
            if self.draining { return false }
            self.draining = true
            return true
        }
        if !shouldRun { return }

        defer {
            // Best-effort clear; if it fails the next tick will see
            // draining=true and bail until the app restarts.
            Task { [weak self] in
                _ = await self?.withSerialOrFalse { [weak self] in
                    self?.draining = false
                    return true
                }
            }
        }

        let batch: [QueuedCommand]
        do {
            batch = try await nextBatch(limit: limit)
        } catch {
            return
        }
        if batch.isEmpty { return }

        for queued in batch {
            guard let cmd = queued.toCommand() else {
                // Corrupt row — remove it so a subsequent drain isn't
                // permanently blocked. Audit trail lives in the
                // payload_json we just discarded; the row_id is the
                // forensic anchor.
                try? await remove(rowId: queued.rowId)
                continue
            }
            do {
                let ack = try await sender(cmd)
                switch ack.status {
                case .applied, .dedupe:
                    try? await remove(rowId: queued.rowId)
                case .rejected:
                    // Surface refused this command on its merits
                    // (validation, allowlist, etc). Replaying won't
                    // make it acceptable, so drop it from the queue
                    // — leaving it in would block every later row
                    // behind it forever.
                    try? await remove(rowId: queued.rowId)
                }
            } catch {
                // Transport failure — leave this row at the head of
                // the queue and abort the rest of this tick. Next
                // reconnect will retry.
                return
            }
        }
    }

    /// Variant of withSerial that returns false on error rather than
    /// throwing — used by the drain guard where any failure means "we
    /// can't claim the lock, skip this tick."
    private func withSerialOrFalse(_ work: @escaping () -> Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            serial.async {
                continuation.resume(returning: work())
            }
        }
    }

    // MARK: - SQLite helpers

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw CommandQueueError.stepFailed(msg)
        }
    }

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) throws {
        // SQLITE_TRANSIENT (-1) tells SQLite to copy the string before
        // returning. Without it, Swift's String memory could be freed
        // before sqlite3_step runs and we'd read corrupt data.
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let rc = sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
        if rc != SQLITE_OK {
            throw CommandQueueError.bindFailed(lastErrorMessage())
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

    private static func encodePayload(_ payload: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw CommandQueueError.payloadEncodeFailed
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let s = String(data: data, encoding: .utf8) else {
            throw CommandQueueError.payloadEncodeFailed
        }
        return s
    }

    /// Bridge async/await to the serial dispatch queue. Each call runs
    /// the closure on the serial queue and returns its result, so the
    /// SQLite handle is only ever touched from one thread at a time.
    private func withSerial<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            serial.async {
                do {
                    let value = try work()
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
