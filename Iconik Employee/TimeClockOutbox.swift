import Foundation

/// A persistent, offline-first queue for clock in/out events.
///
/// Clock events are payroll data and must never be lost just because a
/// photographer is out of signal. When offline, TimeTrackingService records
/// the event here and updates the UI immediately; the moment connectivity
/// returns (or the app relaunches online), the queued events are replayed to
/// Supabase in order.
///
/// Replays are idempotent: a clock-in is upserted by its client-generated id
/// (so a retry can't create a duplicate row), and a clock-out is an update
/// keyed by that same id. The queue survives app restarts (JSON on disk).
struct PendingClockOp: Codable, Identifiable {
    enum Kind: String, Codable { case clockIn, clockOut }

    let id: String            // unique per op, for precise removal after replay
    let kind: Kind
    let entryId: String       // the time_entries row id (shared by the in/out pair)
    let userId: String
    let organizationId: String
    let notes: String?
    let queuedAt: Date

    // clock-in fields
    let startTime: Date?
    let date: String?
    let sessionId: String?
    let sessionName: String?

    // clock-out fields
    let endTime: Date?
    let totalHours: Double?
}

actor TimeClockOutbox {
    static let shared = TimeClockOutbox()

    private var ops: [PendingClockOp] = []
    private var loaded = false
    private let fileURL: URL

    private init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Iconik Employee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("time_clock_outbox.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        ops = (try? decoder.decode([PendingClockOp].self, from: data)) ?? []
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(ops) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func enqueue(_ op: PendingClockOp) {
        loadIfNeeded()
        ops.append(op)
        persist()
    }

    /// FIFO snapshot of everything pending.
    func all() -> [PendingClockOp] {
        loadIfNeeded()
        return ops
    }

    func remove(id: String) {
        loadIfNeeded()
        ops.removeAll { $0.id == id }
        persist()
    }

    func isEmpty() -> Bool {
        loadIfNeeded()
        return ops.isEmpty
    }
}
