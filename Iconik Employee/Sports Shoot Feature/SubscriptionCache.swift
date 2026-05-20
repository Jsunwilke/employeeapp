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
//  In-memory store for runtime, durable on disk for cold-launch survival.
//  Re-hydrates on every connect via Surface state_sync; that is intentional
//  per §15.1 (cache hydration must be correct on first connect and on
//  reconnect, full stop). Disk persistence added 2026-05-20 per the
//  FROM_SCRATCH_ARCHITECTURE.md §13 H1.11-H1.16 retroactive amendment that
//  retired the original H1.1 "no disk persistence" deferral — see those
//  sections + PHASE_AC_PLAN.md §13-§17 for the contract. Subjects round-trip
//  through SubscriptionCacheStore (SQLite at Application Support / Iconik
//  Employee / subscription_cache.sqlite). Captures stay in-memory only —
//  state-sync.ts establishes captures have no state_sync hydration source,
//  so persisting them would create a partial-cache scenario the contract
//  does not support.
//
//  Pattern mirrors CommandQueue.swift (Phase D): static singleton, internal
//  serial DispatchQueue for thread safety, idempotent state mutations.
//  SubscriptionCacheStore extends the precedent to persistence, also matching
//  CommandQueue's SQLite + Application Support + lazy ensureOpen shape.
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

    /// Switch the active gallery. Drops in-memory cached state for the
    /// previous gallery so a stale snapshot doesn't survive across joins.
    /// Disk persistence for the previous gallery STAYS (per H1.13) — the
    /// persistence layer outlives in-memory state so switching between
    /// pinned galleries does not lose roster data.
    ///
    /// Phase AC H1.14 — lazy hydration from disk: when setCurrentGallery
    /// is called with a new gallery whose in-memory state is empty AND
    /// disk persistence has rows for it, hydrate in-memory from disk
    /// BEFORE notifying subscribers. The view's initial snapshot then
    /// reflects the persisted state, eliminating the cold-launch flash
    /// of empty before state_sync arrives.
    func setCurrentGallery(_ galleryId: String?) {
        serial.async {
            let previous = self.currentGallery
            self.currentGallery = galleryId
            if let previous = previous, previous != galleryId {
                self.subjectsByGallery.removeValue(forKey: previous)
                self.capturesByGallery.removeValue(forKey: previous)
                self.lastVersionByGallery.removeValue(forKey: previous)
                self.pendingDriftRequests.remove(previous)
                self._notifyGalleryWithoutPersist(previous)
            }
            // H1.14 lazy hydrate. Only hydrate when in-memory is empty for
            // the new gallery — a fresh setCurrentGallery into a gallery
            // that already has in-memory state (e.g. during a session
            // already in progress) is a no-op for hydration. The in-memory
            // state stays authoritative because broadcasts may have arrived
            // since the last disk write.
            //
            // Per the Phase AC expansion Code Auditor M1 finding: when
            // loadGallery returns non-nil with empty subjects (an
            // authoritative-empty persisted state from a prior Surface-
            // initiated wipe), we MUST still record loaded.lastVersion so
            // the H1.16 version-gap guard at applyStateSync has the correct
            // cache_version to compare against. If we only set
            // lastVersionByGallery when subjects exist, the empty-with-
            // meta-version persisted state regresses cache_version to 0 on
            // hydrate, defeating the guard's defense against suspicious
            // empty payloads at lower wire_versions.
            if let newGallery = galleryId,
               !newGallery.isEmpty,
               (self.subjectsByGallery[newGallery] ?? [:]).isEmpty,
               let loaded = SubscriptionCacheStore.shared.loadGallery(newGallery) {
                var byId: [UUID: FPSubject] = [:]
                for raw in loaded.subjectWireDicts {
                    if let parsed = SubscriptionCache._parseSubjectFromWire(raw) {
                        byId[parsed.id] = parsed
                    }
                }
                // Version is recorded unconditionally on a successful
                // loadGallery — even when byId is empty (authoritative-
                // empty persisted state). Subjects are populated only when
                // byId is non-empty. Notify subscribers in either case
                // because the in-memory state did change (lastVersion
                // advanced, or subjects appeared, or both).
                self.lastVersionByGallery[newGallery] = loaded.lastVersion
                if !byId.isEmpty {
                    self.subjectsByGallery[newGallery] = byId
                }
                // Notify WITHOUT persist — we just LOADED from disk;
                // re-writing would be wasteful and could race with a
                // subsequent state_sync write.
                self._notifyGalleryWithoutPersist(newGallery)
            }
        }
    }

    /// Purge a single gallery's cache state from in-memory AND disk.
    /// Called from PowerSyncManager.unpinGallery when the user explicitly
    /// unpins the gallery — the persisted cache is no longer needed and
    /// must not survive the unpin.
    ///
    /// SYNCHRONOUS via serial.sync per Phase AC expansion Security Auditor
    /// M-1 finding: callers (PowerSyncManager.unpinGallery) need to know
    /// the disk purge completed before returning, so subsequent operations
    /// on the same gallery do not race a still-pending disk write. The
    /// only risk of serial.sync is deadlock if called from inside the
    /// cache's own serial queue — verified at trace time that no caller
    /// runs on the queue (PowerSyncManager runs on its own async context).
    func purgeGallery(_ galleryId: String) {
        serial.sync {
            self.subjectsByGallery.removeValue(forKey: galleryId)
            self.capturesByGallery.removeValue(forKey: galleryId)
            self.lastVersionByGallery.removeValue(forKey: galleryId)
            self.pendingDriftRequests.remove(galleryId)
            SubscriptionCacheStore.shared.purgeGallery(galleryId)
            self._notifyGalleryWithoutPersist(galleryId)
        }
    }

    /// Purge ALL galleries' cache state from in-memory AND disk. Called
    /// from SupabaseAuthService.signOut before the auth context flips to
    /// signed-out, so persisted state from the signed-in user does not
    /// survive into the next sign-in (which may be a different user).
    ///
    /// SYNCHRONOUS via serial.sync per Phase AC expansion Security Auditor
    /// M-1 finding: signOut must know the disk wipe completed before
    /// proceeding to the network auth.signOut call so a subsequent
    /// setCurrentGallery from a freshly-signed-in user cannot race a still-
    /// pending disk purge. Verified at trace time: signOut runs on a Task
    /// context, not the cache's serial queue — no deadlock risk.
    func purgeAll() {
        serial.sync {
            let galleryIds = Array(self.subjectsByGallery.keys)
            self.subjectsByGallery.removeAll()
            self.capturesByGallery.removeAll()
            self.lastVersionByGallery.removeAll()
            self.pendingDriftRequests.removeAll()
            self.currentGallery = nil
            SubscriptionCacheStore.shared.purgeAll()
            for g in galleryIds {
                self._notifyGalleryWithoutPersist(g)
            }
        }
    }

    /// Apply a state_sync response. Replaces the gallery's subject set
    /// wholesale (mode: 'full') and records `currentVersion` as the
    /// cache's tracked version. Captures are NOT in state_sync per
    /// state-sync.ts — they accumulate via capture_completed broadcasts.
    ///
    /// Phase AC empty-payload guard — REVISED per H1.16 (PHASE_AC_PLAN.md
    /// §13 scope expansion 2026-05-20) to the version-gap heuristic:
    ///   - empty-on-empty cache: legitimate initial-hydration no-op,
    ///     version advances to the wire value (Surface's authoritative
    ///     empty claim recorded).
    ///   - empty-on-populated cache + wire_version <= cache_version:
    ///     suspicious empty (pre-Phase-AC Surface emitting destructive
    ///     empty when mirror unloaded, OR a race / regression). Refuse
    ///     the wipe; keep the populated cache; emit the metric counter.
    ///   - empty-on-populated cache + wire_version > cache_version:
    ///     authoritative empty (Surface deleted all subjects, counter
    ///     advanced past iPad's cache_version). Accept the wipe.
    ///   - non-empty wire payload (any size): existing wholesale-replace
    ///     runs unchanged.
    ///
    /// The version-gap heuristic is sound because the Surface counter
    /// (gallery-version-counter.ts) is persisted to localStorage and
    /// monotonic per gallery, never resets in production. So
    /// wire_version > cache_version reliably signals authoritative state
    /// advancement.
    func applyStateSync(galleryId: String, currentVersion: Int, subjects: [[String: Any]]) {
        serial.async {
            let existing = self.subjectsByGallery[galleryId] ?? [:]
            let cacheVersion = self.lastVersionByGallery[galleryId] ?? 0
            // H1.16 version-gap empty-guard. The empty payload could be
            // authoritative (Surface genuinely has zero subjects, counter
            // advanced) or destructive (pre-Phase-AC Surface emitting empty
            // when mirror unloaded). The wire_version vs cache_version
            // comparison distinguishes them.
            if subjects.isEmpty && !existing.isEmpty && currentVersion <= cacheVersion {
                print("[FPSync] state_sync_empty_payload_refused: gallery=\(galleryId) cached_subjects=\(existing.count) wire_version=\(currentVersion) cache_version=\(cacheVersion) — wire_version did not advance past cache_version, refusing to wipe populated cache (Phase AC H1.16 version-gap guard)")
                FocalPointMetrics.shared.counter(
                    "state_sync_empty_payload_refused_total",
                    module: "subscription-cache"
                )
                // Do NOT advance lastVersionByGallery — the empty payload was
                // discarded as invalid, so the Surface's claimed version is
                // not authoritative. Do NOT clear pendingDriftRequests — the
                // pending flag stays set; combined with the checkDrift throttle
                // (guard against duplicate in-flight requests), this leaves
                // the drift sender pinned until a non-empty state_sync clears
                // the flag at the legitimate apply path below, OR
                // setCurrentGallery is called with a new gallery (which clears
                // via pendingDriftRequests.remove(previous)). The pin is
                // intentional: a Surface with an unloaded mirror has nothing
                // authoritative to share, and re-polling every 30s would just
                // refire the same refuse. In practice the cache also
                // re-hydrates via applyBroadcast on the next Surface-side
                // write (subject_updated, capture_completed, etc.), which
                // advances lastVersionByGallery normally — so the
                // pinned-state is benign and self-recovering once the
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

    /// Test-only — clear in-memory state WITHOUT touching disk. Used to
    /// simulate app process death + relaunch in tests (the lazy hydration
    /// on setCurrentGallery should then re-populate from disk). Production
    /// never calls this.
    func _test_clearInMemoryOnly() {
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

    /// Reset all internal state. Test-only.
    ///
    /// Phase AC H1.12 — also clears any disk persistence so tests start
    /// from a clean state on BOTH in-memory and disk. Tests that want
    /// the store fully disabled (no I/O at all) should call
    /// SubscriptionCacheStore.shared._testDisable() in their setUp.
    func _test_reset() {
        serial.sync {
            subjectsByGallery.removeAll()
            capturesByGallery.removeAll()
            lastVersionByGallery.removeAll()
            subscriptions.removeAll()
            pendingDriftRequests.removeAll()
            currentGallery = nil
            driftRequestSender = nil
            SubscriptionCacheStore.shared._testClearAll()
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

    /// Notify subscribers of the gallery's current state AND persist the
    /// state to disk. Per Phase AC H1.13, this is the persistence
    /// chokepoint — every cache mutation that changes subjects routes
    /// through _notifyGallery, so a single hook here covers all mutation
    /// paths (applyStateSync wholesale-replace, _applySubjectUpdate,
    /// _applySubjectCreate, _applySubjectsDelete). The empty-payload-
    /// refused branch of applyStateSync does NOT call this — preserving
    /// the cache's pre-refuse contents on disk too.
    ///
    /// Disk write happens before subscriber notify so a subscriber
    /// closure that mutates the cache (rare but possible per
    /// AsyncStream yield semantics) does not race with the persist.
    /// Subscriber notify is best-effort if disk write throws — the
    /// in-memory state already changed; preserving the notify path
    /// keeps the view in sync even if disk fails.
    private func _notifyGallery(_ galleryId: String) {
        _persistGalleryStateLocked(galleryId)
        _notifyGalleryWithoutPersist(galleryId)
    }

    /// Variant of _notifyGallery that ONLY notifies subscribers without
    /// touching disk. Used by setCurrentGallery (in-memory-only drop of
    /// previous gallery; disk persistence survives) and by the lazy
    /// hydrate-from-disk path (just loaded from disk; re-writing would
    /// be wasteful and could race with a subsequent state_sync).
    private func _notifyGalleryWithoutPersist(_ galleryId: String) {
        let snapshot = _sortedSubjects(forGalleryId: galleryId)
        for sub in subscriptions where sub.galleryId == galleryId {
            sub.yield(snapshot)
        }
    }

    /// Persist the current in-memory state for a gallery to disk via
    /// SubscriptionCacheStore. Called from _notifyGallery's persistence
    /// hook. Skips when persistence is disabled (tests). MUST be called
    /// inside the serial queue (no external locking on the maps).
    private func _persistGalleryStateLocked(_ galleryId: String) {
        guard SubscriptionCacheStore.shared.isEnabled else { return }
        let map = subjectsByGallery[galleryId] ?? [:]
        let wireDicts: [[String: Any]] = map.values.map { $0.toWireDict() }
        let lastVersion = lastVersionByGallery[galleryId] ?? 0
        SubscriptionCacheStore.shared.persistGalleryState(
            galleryId: galleryId,
            subjectWireDicts: wireDicts,
            lastVersion: lastVersion
        )
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
