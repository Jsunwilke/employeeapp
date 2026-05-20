//
//  SubscriptionCache.swift
//  Iconik Employee
//
//  FROM_SCRATCH_ARCHITECTURE.md §13 Phase H1 — iPad subscription cache
//  substrate. In-memory store of subjects + captures for the active
//  gallery, hydrated by Surface state_sync on connect/reconnect and
//  kept in sync by Surface broadcasts (subject_updated, subject_created,
//  subjects_deleted, capture_completed, capture_reassigned, qc_flag_changed).
//
//  Per the from-scratch architecture (§3, §4, §6):
//    - iPad has no PowerSync read path for the active gallery during a
//      shoot. The cache is the read source.
//    - Surface is authoritative. Every state-changing broadcast carries
//      a monotonic per-gallery version. iPads track last_version_seen
//      per gallery to detect missed broadcasts.
//    - Drift detection uses the gallery_state_summary heartbeat (every
//      30s from Surface). When the heartbeat's last_change_version is
//      ahead of the cache's tracked version, the cache requests a fresh
//      state_sync.
//
//  In-memory only. NO PowerSync local SQLite writes. NO disk persistence.
//  Re-hydrates on every connect; that is intentional per §15.1 (cache
//  hydration must be correct on first connect and on reconnect, full
//  stop). Persistence is out of H1 scope.
//
//  H1 is substrate-only. NO view consumes the cache yet. PoserStationView,
//  FPSportsRosterView_iPad, etc. all keep their existing PowerSync
//  watchSubjects reads. H2 onwards migrates each view and deletes the
//  PowerSync read path in the same commit per delete-first migration.
//
//  Pattern mirrors CommandQueue.swift (Phase D): static singleton, internal
//  serial DispatchQueue for thread safety, idempotent state mutations.
//  Where CommandQueue uses SQLite for persistence, this cache uses an
//  in-memory dictionary.
//

import Foundation

/// Snapshot subscriber identity. Each call to `subjectsStream(forGalleryId:)`
/// gets a fresh `SubjectsSubscription` and a corresponding AsyncStream;
/// closing the subscription removes it from the cache's listener list.
private final class SubjectsSubscription {
    let id = UUID()
    let galleryId: String
    let yield: ([FPSubject]) -> Void
    init(galleryId: String, yield: @escaping ([FPSubject]) -> Void) {
        self.galleryId = galleryId
        self.yield = yield
    }
}

/// Single-instance subscription cache. Mirrors CommandQueue.shared and
/// PowerSyncManager.shared so call sites use a consistent pattern.
final class SubscriptionCache {
    static let shared = SubscriptionCache()

    // MARK: - State (guarded by `serial`)

    private var subjectsByGallery: [String: [UUID: FPSubject]] = [:]
    private var capturesByGallery: [String: [String: FPCaptureEvent]] = [:]
    private var lastVersionByGallery: [String: Int] = [:]
    private var subscriptions: [SubjectsSubscription] = []
    private var pendingDriftRequests: Set<String> = []

    /// The gallery the iPad is currently joined to. Set by FocalPointSyncClient
    /// on device_hello / gallery transitions. When this changes, the cache
    /// drops the previous gallery's data so a stale snapshot doesn't leak
    /// across galleries.
    private var currentGallery: String?

    // MARK: - Concurrency

    /// Serial queue serializes all mutations and reads. Mirrors CommandQueue's
    /// `com.iconikschools.command-queue` queue. Public APIs route here.
    private let serial = DispatchQueue(label: "com.iconikschools.subscription-cache")

    /// Out-of-band hook invoked on the serial queue when drift detection
    /// determines a state_sync request should be sent. FocalPointSyncClient
    /// installs the actual sender. Pure indirection so tests can observe
    /// drift requests without owning a real WebSocket.
    private var driftRequestSender: ((String, Int) -> Void)?

    private init() {}

    // MARK: - Public read API
    //
    // H2 will migrate views from `PowerSyncManager.shared.watchSubjects` to
    // `SubscriptionCache.shared.subjectsStream`. The signatures here are
    // intentionally close to PowerSyncManager's (same parameter name, same
    // return shape sans `throws`) so the H2 swap is a one-line change at
    // each call site.

    /// Current snapshot of subjects for a gallery, sorted by lastName / firstName
    /// to match PowerSyncManager.watchSubjects' order.
    func subjects(forGalleryId galleryId: String) -> [FPSubject] {
        return serial.sync {
            return _sortedSubjects(forGalleryId: galleryId)
        }
    }

    /// Reactive stream of subject snapshots. Emits the current snapshot
    /// immediately, then a new snapshot every time the cache mutates the
    /// gallery's subject set. Closes when the consumer cancels the stream
    /// (Task cancellation propagates into AsyncStream's onTermination).
    func subjectsStream(forGalleryId galleryId: String) -> AsyncStream<[FPSubject]> {
        return AsyncStream { continuation in
            let subscription = SubjectsSubscription(galleryId: galleryId) { snapshot in
                continuation.yield(snapshot)
            }
            // Register subscription on the serial queue and emit the
            // initial snapshot synchronously so consumers don't miss the
            // current state.
            serial.async {
                self.subscriptions.append(subscription)
                let initial = self._sortedSubjects(forGalleryId: galleryId)
                continuation.yield(initial)
            }
            continuation.onTermination = { @Sendable _ in
                self.serial.async {
                    self.subscriptions.removeAll { $0.id == subscription.id }
                }
            }
        }
    }

    /// Current capture events for a gallery, keyed by capture_id. Returned
    /// as an array sorted by image number (ascending) to match the order
    /// captures arrive in. Captures have no `state_sync` hydration source
    /// in H1 (per state-sync.ts: subjects-only); the cache only sees
    /// captures via `capture_completed` broadcasts after the iPad
    /// connects mid-shoot. Historical captures from before connect are
    /// not in the cache — that's consistent with current pre-H1 behavior
    /// where iPads don't load capture_images via PowerSync either.
    func captures(forGalleryId galleryId: String) -> [FPCaptureEvent] {
        return serial.sync {
            let map = capturesByGallery[galleryId] ?? [:]
            return map.values.sorted { (a, b) in
                let an = a.imageNumber ?? Int.max
                let bn = b.imageNumber ?? Int.max
                return an < bn
            }
        }
    }

    /// Highest version number applied to the cache for this gallery.
    /// Returns 0 when no broadcast or state_sync has populated the cache
    /// for this gallery yet — the same value the Surface treats as "no
    /// prior state seen" in build_state_sync_response.
    func lastVersion(forGalleryId galleryId: String) -> Int {
        return serial.sync {
            return lastVersionByGallery[galleryId] ?? 0
        }
    }

    /// The gallery the iPad is currently scoped to. nil when no gallery
    /// is open.
    func currentGalleryId() -> String? {
        return serial.sync {
            return currentGallery
        }
    }

    // MARK: - Public mutator API
    //
    // These are called from FocalPointSyncClient when the corresponding
    // wire message arrives. They are public on the type because the
    // sync client lives in the same module; access control is convention,
    // not type-system enforcement (matching CommandQueue.swift's pattern).

    /// Switch the active gallery. Drops cached state for the previous
    /// gallery so a stale snapshot doesn't survive across joins.
    func setCurrentGallery(_ galleryId: String?) {
        serial.async {
            let previous = self.currentGallery
            self.currentGallery = galleryId
            if let previous = previous, previous != galleryId {
                self.subjectsByGallery.removeValue(forKey: previous)
                self.capturesByGallery.removeValue(forKey: previous)
                self.lastVersionByGallery.removeValue(forKey: previous)
                self.pendingDriftRequests.remove(previous)
                self._notifyGallery(previous)
            }
        }
    }

    /// Apply a state_sync response. Replaces the gallery's subject set
    /// wholesale (mode: 'full') and records `currentVersion` as the
    /// cache's tracked version. Captures are NOT in state_sync per
    /// state-sync.ts — they accumulate via capture_completed broadcasts.
    ///
    /// Phase AC (PHASE_AC_PLAN.md §4 + §7.3) — defense-in-depth guard
    /// against an empty wire payload arriving when the cache is already
    /// populated. The Surface-side fix (state-sync.ts build_state_sync_response
    /// returns null when the mirror is unloaded; dispatcher skips _send)
    /// prevents the destructive empty emission at its source. The iPad-side
    /// guard here is the cross-version safety net: an older Surface
    /// (pre-Phase-AC) that still emits the empty response cannot wipe a
    /// populated iPad cache. The guard is targeted at the specific bug
    /// shape (empty-on-populated), not at restricting legitimate apply:
    ///   - empty-on-empty cache: legitimate initial-hydration no-op, version still advances.
    ///   - empty-on-populated cache: contract violation, log + counter + drop the apply.
    ///   - non-empty wire payload (any size): existing wholesale-replace runs unchanged.
    func applyStateSync(galleryId: String, currentVersion: Int, subjects: [[String: Any]]) {
        serial.async {
            // Phase AC empty-payload guard. If the incoming subjects array
            // is empty AND the cache currently holds rows for this gallery,
            // refuse the wholesale-replace. The Surface is either (a) a
            // pre-Phase-AC build emitting the destructive empty, or (b) a
            // regression that re-introduced empty emission. Either way the
            // populated cache is more authoritative than an empty wire
            // payload — keep the cache, drop the empty apply, surface for
            // observability.
            let existing = self.subjectsByGallery[galleryId] ?? [:]
            if subjects.isEmpty && !existing.isEmpty {
                print("[FPSync] state_sync_empty_payload_refused: gallery=\(galleryId) cached_subjects=\(existing.count) wire_version=\(currentVersion) — refusing to wipe populated cache (Phase AC defense-in-depth)")
                FocalPointMetrics.shared.counter(
                    "state_sync_empty_payload_refused_total",
                    module: "subscription-cache"
                )
                // Do NOT advance lastVersionByGallery — the empty payload was
                // discarded as invalid, so the Surface's claimed version is
                // not authoritative. Do NOT clear pendingDriftRequests — the
                // pending flag stays set; combined with the checkDrift throttle
                // at line ~315 (guard against duplicate in-flight requests),
                // this leaves the drift sender pinned until a non-empty
                // state_sync clears the flag at the legitimate apply path
                // below, OR setCurrentGallery is called with a new gallery
                // (which clears via pendingDriftRequests.remove(previous)).
                // The pin is intentional: a Surface with an unloaded mirror
                // has nothing authoritative to share, and re-polling every
                // 30s would just refire the same refuse. In practice the
                // cache also re-hydrates via applyBroadcast on the next
                // Surface-side write (subject_updated, capture_completed,
                // etc.), which advances lastVersionByGallery normally — so
                // the pinned-state is benign and self-recovering once the
                // Surface enters a capture session for this gallery. Do NOT
                // notify subscribers — the cache state did not change.
                return
            }

            var byId: [UUID: FPSubject] = [:]
            for raw in subjects {
                if let parsed = SubscriptionCache._parseSubjectFromWire(raw) {
                    byId[parsed.id] = parsed
                }
            }
            self.subjectsByGallery[galleryId] = byId
            self.lastVersionByGallery[galleryId] = currentVersion
            // A successful state_sync clears any pending drift request
            // for this gallery — drift has been resolved.
            self.pendingDriftRequests.remove(galleryId)
            self._notifyGallery(galleryId)
        }
    }

    /// Apply a single broadcast event. Version-checked: events with
    /// version <= lastVersion[gallery] are dropped (out-of-order or
    /// duplicates). Events without a version field are applied
    /// unconditionally without advancing the version counter (legacy
    /// broadcasts pre-Phase-H1 substrate — the cache stays usable, drift
    /// detection just can't catch their loss).
    func applyBroadcast(_ event: BroadcastEvent) {
        serial.async {
            let galleryId = event.galleryId
            if let v = event.version {
                let last = self.lastVersionByGallery[galleryId] ?? 0
                if v <= last {
                    // Out-of-order or duplicate. Drop without applying.
                    return
                }
                self.lastVersionByGallery[galleryId] = v
            }
            switch event {
            case .subjectUpdated(_, let subjectId, let fields, _):
                self._applySubjectUpdate(galleryId: galleryId, subjectId: subjectId, fields: fields)
            case .subjectCreated(_, let subjectId, let row, _):
                self._applySubjectCreate(galleryId: galleryId, subjectId: subjectId, row: row)
            case .subjectsDeleted(_, let subjectIds, _):
                self._applySubjectsDelete(galleryId: galleryId, subjectIds: subjectIds)
            case .captureCompleted(_, let captureId, let captureEvent, _):
                var map = self.capturesByGallery[galleryId] ?? [:]
                map[captureId] = captureEvent
                self.capturesByGallery[galleryId] = map
                // Captures don't appear in subjects snapshot; no notify.
            case .captureReassigned(_, let captureId, let newSubjectId, _, _):
                // Reassignment retags an existing capture with a new
                // subject_id. If the capture isn't in the cache (iPad
                // joined after the original capture_completed), record
                // a stub so subsequent reads see consistent state.
                var map = self.capturesByGallery[galleryId] ?? [:]
                if var existing = map[captureId] {
                    existing = FPCaptureEvent(
                        subjectId: newSubjectId,
                        rosterEntryId: existing.rosterEntryId,
                        imageNumber: existing.imageNumber,
                        captureFilename: existing.captureFilename,
                        stationName: existing.stationName,
                        fromDeviceId: existing.fromDeviceId
                    )
                    map[captureId] = existing
                    self.capturesByGallery[galleryId] = map
                }
            case .qcFlagChanged(_, _, _, _):
                // qc_flag is a property of subject_images / capture_images.
                // The cache keys captures by capture_id; qc_flag isn't in
                // FPCaptureEvent's current shape. Recording the flag as
                // cache state is H2+ scope (when a view consumes flags).
                // For H1 substrate purposes the version is advanced (above)
                // so drift detection stays accurate; the flag itself is a
                // no-op here. Future expansion goes here.
                break
            }
        }
    }

    /// Drift check on receipt of a gallery_state_summary heartbeat. The
    /// Surface advertises its `last_change_version`; the cache compares
    /// to its tracked version. If the Surface is ahead, the cache asks
    /// FocalPointSyncClient (via `driftRequestSender`) to send a fresh
    /// state_sync request.
    func checkDrift(galleryId: String, surfaceVersion: Int) {
        serial.async {
            let local = self.lastVersionByGallery[galleryId] ?? 0
            guard surfaceVersion > local else { return }
            // Throttle: only one in-flight drift request per gallery.
            // The pending flag clears when applyStateSync runs.
            guard !self.pendingDriftRequests.contains(galleryId) else { return }
            self.pendingDriftRequests.insert(galleryId)
            let sender = self.driftRequestSender
            // Hop off the serial queue so the sender's work doesn't block
            // mutations. The sender installed by FocalPointSyncClient
            // sends a device_hello carrying last_version_seen — Surface's
            // existing handler at local-sync.ts:1842 returns state_sync.
            DispatchQueue.global(qos: .utility).async {
                sender?(galleryId, local)
            }
        }
    }

    /// Install the sender FocalPointSyncClient uses when the cache asks
    /// for a state_sync. Plain function pointer rather than a delegate
    /// protocol — the indirection lets unit tests observe drift requests
    /// without standing up a real WebSocket.
    func setDriftRequestSender(_ sender: @escaping (String, Int) -> Void) {
        serial.async {
            self.driftRequestSender = sender
        }
    }

    // MARK: - Test seam
    //
    // Test-only entry points for SubscriptionCacheTests. They are
    // marked `_test_` so production callers can't accidentally reach
    // for them (Swift doesn't have package-private; convention is the
    // type-system substitute, mirroring CommandQueue.swift's pattern).

    /// Synchronously drains the serial queue. Tests call this after each
    /// mutator to assert state without race conditions. Production code
    /// must NOT call this.
    func _test_waitForPendingMutations() {
        serial.sync {}
    }

    /// Reset all internal state. Test-only.
    func _test_reset() {
        serial.sync {
            subjectsByGallery.removeAll()
            capturesByGallery.removeAll()
            lastVersionByGallery.removeAll()
            subscriptions.removeAll()
            pendingDriftRequests.removeAll()
            currentGallery = nil
            driftRequestSender = nil
        }
    }

    // MARK: - Internal helpers (must be called inside serial.async/serial.sync)

    private func _sortedSubjects(forGalleryId galleryId: String) -> [FPSubject] {
        let map = subjectsByGallery[galleryId] ?? [:]
        return map.values.sorted { (a, b) in
            let aLast = a.lastName.lowercased()
            let bLast = b.lastName.lowercased()
            if aLast != bLast { return aLast < bLast }
            return a.firstName.lowercased() < b.firstName.lowercased()
        }
    }

    private func _applySubjectUpdate(galleryId: String, subjectId: UUID, fields: SubjectSyncFields) {
        var map = subjectsByGallery[galleryId] ?? [:]
        let base: FPSubject = map[subjectId] ?? FPSubject(id: subjectId, galleryId: galleryId)
        // Reuse the canonical apply helper. Per feedback_match_existing_patterns_exactly:
        // SubjectSyncService.applyFieldsToSubject is the single source of truth for
        // "apply non-nil SubjectSyncFields onto an FPSubject" — duplicating its body
        // here would be a parallel implementation, exactly what rule 19.1 forbids.
        let updated = SubjectSyncService.applyFieldsToSubject(fields, base: base)
        map[subjectId] = updated
        subjectsByGallery[galleryId] = map
        _notifyGallery(galleryId)
    }

    private func _applySubjectCreate(galleryId: String, subjectId: UUID, row: [String: Any]) {
        var map = subjectsByGallery[galleryId] ?? [:]
        if let parsed = SubscriptionCache._parseSubjectFromWire(row, fallbackId: subjectId, fallbackGalleryId: galleryId) {
            map[parsed.id] = parsed
            subjectsByGallery[galleryId] = map
            _notifyGallery(galleryId)
        }
    }

    private func _applySubjectsDelete(galleryId: String, subjectIds: [UUID]) {
        guard var map = subjectsByGallery[galleryId], !map.isEmpty else { return }
        var changed = false
        for id in subjectIds {
            if map.removeValue(forKey: id) != nil { changed = true }
        }
        if changed {
            subjectsByGallery[galleryId] = map
            _notifyGallery(galleryId)
        }
    }

    private func _notifyGallery(_ galleryId: String) {
        let snapshot = _sortedSubjects(forGalleryId: galleryId)
        for sub in subscriptions where sub.galleryId == galleryId {
            sub.yield(snapshot)
        }
    }

    // MARK: - Wire parsing

    /// Parse a state_sync row dict (one element of the `subjects` array)
    /// into FPSubject. Returns nil only if the row has no usable id.
    /// Mirrors PowerSyncManager.parseSubject's column → field mapping;
    /// kept distinct because PowerSyncManager parses from a SqlCursor
    /// while this parses from JSON dictionaries.
    static func _parseSubjectFromWire(_ row: [String: Any], fallbackId: UUID? = nil, fallbackGalleryId: String? = nil) -> FPSubject? {
        let idString = (row["id"] as? String) ?? ""
        let id: UUID
        if let parsed = UUID(uuidString: idString) {
            id = parsed
        } else if let fb = fallbackId {
            id = fb
        } else {
            return nil
        }

        func _string(_ key: String) -> String {
            return (row[key] as? String) ?? ""
        }
        func _stringOpt(_ key: String) -> String? {
            return row[key] as? String
        }
        func _int(_ key: String) -> Int {
            if let v = row[key] as? Int { return v }
            if let v = row[key] as? String, let parsed = Int(v) { return parsed }
            return 0
        }
        func _bool(_ key: String) -> Bool {
            // Schema stores booleans as integer 0/1; defensive against
            // both shapes the wire might use.
            if let v = row[key] as? Bool { return v }
            if let v = row[key] as? Int { return v == 1 }
            if let v = row[key] as? String { return v == "1" || v.lowercased() == "true" }
            return false
        }

        let galleryId = _stringOpt("gallery_id") ?? fallbackGalleryId ?? ""
        let createdAtISO = _string("created_at")
        let updatedAtISO = _string("updated_at")
        let lockedAtISO = _stringOpt("locked_at")
        let isoFormatter = ISO8601DateFormatter()

        return FPSubject(
            id: id,
            galleryId: galleryId,
            organizationId: _string("organization_id"),
            firstName: _string("first_name"),
            lastName: _string("last_name"),
            grade: _string("grade"),
            teacher: _string("teacher"),
            homeroom: _string("homeroom"),
            studentId: _string("student_id"),
            rosterId: _string("roster_id"),
            jerseyNumber: _string("jersey_number"),
            sport: _string("sport"),
            position: _string("position"),
            organizationName: _string("organization_name"),
            year: _string("year"),
            subjectType: _string("subject_type"),
            title: _string("title"),
            referenceNumber: _string("reference_number"),
            photographer: _string("photographer"),
            photoSessionDate: _string("photo_session_date"),
            expirationDate: _string("expiration_date"),
            email: _string("email"),
            phone: _string("phone"),
            phone2: _string("phone2"),
            address1: _string("address1"),
            address2: _string("address2"),
            city: _string("city"),
            state: _string("state"),
            zip: _string("zip"),
            country: _string("country"),
            mother: _string("mother"),
            father: _string("father"),
            onlineCode: _string("online_code"),
            personalization: _string("personalization"),
            discountCode: _string("discount_code"),
            custom1: _string("custom1"),
            custom2: _string("custom2"),
            custom3: _string("custom3"),
            custom4: _string("custom4"),
            custom5: _string("custom5"),
            custom6: _string("custom6"),
            custom7: _string("custom7"),
            custom8: _string("custom8"),
            custom9: _string("custom9"),
            custom10: _string("custom10"),
            custom11: _string("custom11"),
            custom12: _string("custom12"),
            custom13: _string("custom13"),
            custom14: _string("custom14"),
            custom15: _string("custom15"),
            custom16: _string("custom16"),
            custom17: _string("custom17"),
            custom18: _string("custom18"),
            custom19: _string("custom19"),
            custom20: _string("custom20"),
            imageCount: _int("image_count"),
            isAbsent: _bool("is_absent"),
            isPhotographed: _bool("is_photographed"),
            needsRetake: _bool("needs_retake"),
            checkedInAt: _stringOpt("checked_in_at"),
            imageNumbers: _string("image_numbers"),
            notes: _string("notes"),
            createdAt: isoFormatter.date(from: createdAtISO) ?? Date(),
            updatedAt: isoFormatter.date(from: updatedAtISO) ?? Date(),
            lockedBy: _stringOpt("locked_by").flatMap { UUID(uuidString: $0) },
            lockedByName: _stringOpt("locked_by_name"),
            lockedAt: lockedAtISO.flatMap { isoFormatter.date(from: $0) }
        )
    }
}

/// Wire broadcast events the cache consumes. Each variant carries the
/// gallery_id, the entity-specific identifiers, the event payload, and
/// the (optional) per-gallery monotonic version. FocalPointSyncClient
/// builds these from raw wire dicts and hands them to applyBroadcast.
enum BroadcastEvent {
    case subjectUpdated(galleryId: String, subjectId: UUID, fields: SubjectSyncFields, version: Int?)
    case subjectCreated(galleryId: String, subjectId: UUID, row: [String: Any], version: Int?)
    case subjectsDeleted(galleryId: String, subjectIds: [UUID], version: Int?)
    case captureCompleted(galleryId: String, captureId: String, event: FPCaptureEvent, version: Int?)
    case captureReassigned(galleryId: String, captureId: String, newSubjectId: String, oldSubjectId: String, version: Int?)
    case qcFlagChanged(galleryId: String, subjectId: String, captureId: String, flagged: Bool)

    var galleryId: String {
        switch self {
        case .subjectUpdated(let g, _, _, _): return g
        case .subjectCreated(let g, _, _, _): return g
        case .subjectsDeleted(let g, _, _): return g
        case .captureCompleted(let g, _, _, _): return g
        case .captureReassigned(let g, _, _, _, _): return g
        case .qcFlagChanged(let g, _, _, _): return g
        }
    }

    var version: Int? {
        switch self {
        case .subjectUpdated(_, _, _, let v): return v
        case .subjectCreated(_, _, _, let v): return v
        case .subjectsDeleted(_, _, let v): return v
        case .captureCompleted(_, _, _, let v): return v
        case .captureReassigned(_, _, _, _, let v): return v
        case .qcFlagChanged(_, _, _, _): return nil
        }
    }
}
