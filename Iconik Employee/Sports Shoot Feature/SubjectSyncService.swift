//
//  SubjectSyncService.swift
//  Iconik Employee
//
//  The single entry point for subject mutations on the iPad. Every place
//  that wants to update, create, or delete a subject goes through here.
//  Eliminates the "five callers each with their own logic" problem
//  documented in §2.1 of the rewrite plan.
//
//  No feature flag — the rewrite is the only path. Rollback is the
//  `pre-sync-rewrite` git tag.
//
//  Mirror of src/data/sync/subject-sync-service.ts on the Mac side.
//
//  See IPAD_SURFACE_SYNC_REWRITE.md §5.
//

import Foundation
import Combine

// MARK: - Request shape

struct SubjectMutationRequest {
    let subjectId: String
    let galleryId: String
    let fields: SubjectSyncFields
    /// Where the request came from — used in the structured event log.
    let sourcePath: String
    /// Optional caller-supplied idempotency key. Generated if absent.
    var idempotencyKey: String? = nil
}

// MARK: - Service

@MainActor
final class SubjectSyncService {
    static let shared = SubjectSyncService()

    private init() {}

    // MARK: - Public API

    /// Apply a subject update.
    ///
    /// Per SYNC_ARCHITECTURE_SPEC.md §11.1 + FROM_SCRATCH_ARCHITECTURE.md
    /// §13 Phase D: when the iPad is connected to a Surface in this
    /// gallery, the subject_command path runs (send command, await typed
    /// ack, Surface owns the cloud write). On transport failure (timeout,
    /// throw) or when the iPad isn't in a Surface-connected shoot, the
    /// command enqueues into the persistent CommandQueue and drains on
    /// the next reconnect — replacing the Phase 0 / Phase C dual-write
    /// PowerSync fallback that this method previously held at lines
    /// 147-191. Surface's idempotency_cache (§11.3) dedupes replayed
    /// commands so the queue's at-least-once semantics don't double-apply.
    ///
    /// On `rejected` ack the overlay is rolled back and no enqueue
    /// happens — replaying a rejection won't make it acceptable. The
    /// caller learns about rejection via SubjectSyncEvents.
    @discardableResult
    func updateSubject(
        _ req: SubjectMutationRequest,
        currentSubject: FPSubject
    ) async -> String {
        let idempotencyKey = req.idempotencyKey ?? UUID().uuidString.lowercased()
        let fieldsTouched = req.fields.fieldsTouched
        let deviceId = SubjectSyncService.deviceIdOrUnknown()

        // 1. Apply optimistic overlay so the UI sees the new values immediately,
        //    independent of whether we send now or enqueue for later drain.
        SubjectSyncOverlay.shared.apply(
            subjectId: req.subjectId,
            fields: req.fields,
            idempotencyKey: idempotencyKey,
            source: .localEdit
        )

        let cmd: SubjectCommand
        do {
            cmd = try SubjectCommandBuilder.update(
                galleryId: req.galleryId,
                subjectId: req.subjectId,
                fields: req.fields,
                originatingDeviceId: deviceId,
                idempotencyKey: idempotencyKey
            )
        } catch {
            // Field encoding failed before we ever sent — log and bail.
            // No enqueue: a malformed field dict won't get healthier with
            // a replay. Overlay clears so the UI doesn't keep promising
            // an edit that was never well-formed.
            _ = SubjectSyncOverlay.shared.clearIfMatches(
                subjectId: req.subjectId,
                localSubject: currentSubject
            )
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .update,
                outcome: .failed,
                sourcePath: req.sourcePath + ":build_failed",
                subjectId: req.subjectId,
                galleryId: req.galleryId,
                idempotencyKey: idempotencyKey,
                fieldsTouched: fieldsTouched,
                errorMessage: String(describing: error)
            ))
            return idempotencyKey
        }

        if FocalPointSyncClient.shared.isConnectedAndInGallery(req.galleryId) {
            do {
                let ack = try await FocalPointSyncClient.shared.sendSubjectCommand(cmd)
                switch ack.status {
                case .applied, .dedupe:
                    SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                        deviceId: deviceId,
                        operation: .update,
                        outcome: .committed,
                        sourcePath: req.sourcePath + ":cmd",
                        subjectId: req.subjectId,
                        galleryId: req.galleryId,
                        idempotencyKey: idempotencyKey,
                        fieldsTouched: fieldsTouched
                    ))
                    // Surface acked. Surface's subject_updated broadcast
                    // (or eventual cloud-sync delivery) will land in
                    // SQLite for this iPad too.
                    return idempotencyKey
                case .rejected:
                    // Surface refused on its merits (validation, allowlist,
                    // etc). Roll the overlay back; no enqueue (replay
                    // won't help — same input, same rejection).
                    _ = SubjectSyncOverlay.shared.clearIfMatches(
                        subjectId: req.subjectId,
                        localSubject: currentSubject
                    )
                    SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                        deviceId: deviceId,
                        operation: .update,
                        outcome: .rejected,
                        sourcePath: req.sourcePath + ":cmd_rejected",
                        subjectId: req.subjectId,
                        galleryId: req.galleryId,
                        idempotencyKey: idempotencyKey,
                        fieldsTouched: fieldsTouched,
                        errorMessage: ack.reason ?? "rejected"
                    ))
                    return idempotencyKey
                }
            } catch {
                // Transport error or ack timeout. Fall through to the
                // enqueue path below so the edit is preserved across the
                // reconnect.
                SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                    deviceId: deviceId,
                    operation: .update,
                    outcome: .failed,
                    sourcePath: req.sourcePath + ":cmd_threw",
                    subjectId: req.subjectId,
                    galleryId: req.galleryId,
                    idempotencyKey: idempotencyKey,
                    fieldsTouched: fieldsTouched,
                    errorMessage: String(describing: error)
                ))
            }
        }

        // Enqueue for drain on next reconnect. Overlay stays in place
        // until drain succeeds — reconcileLocalRow / clearIfMatches
        // clears it once the eventual subject_updated broadcast
        // (Surface-emitted after applying the queued command) lands.
        do {
            _ = try await CommandQueue.shared.enqueue(cmd)
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .update,
                outcome: .queued,
                sourcePath: req.sourcePath + ":enqueued",
                subjectId: req.subjectId,
                galleryId: req.galleryId,
                idempotencyKey: idempotencyKey,
                fieldsTouched: fieldsTouched
            ))
        } catch {
            // Enqueue is the last line of defense; if it fails the edit
            // is genuinely lost. The overlay still shows the user's
            // intent for 5 minutes so the UI doesn't snap back instantly,
            // but durability is gone. SubjectSyncEvents records the
            // forensic trail.
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .update,
                outcome: .abandoned,
                sourcePath: req.sourcePath + ":enqueue_failed",
                subjectId: req.subjectId,
                galleryId: req.galleryId,
                idempotencyKey: idempotencyKey,
                fieldsTouched: fieldsTouched,
                errorMessage: String(describing: error)
            ))
        }
        return idempotencyKey
    }

    /// Apply an inbound subject update from a remote device (Surface → iPad
    /// via WebSocket). Goes into the optimistic overlay rather than writing
    /// PowerSync directly — Surface is the cloud writer and PowerSync will
    /// deliver the cloud-confirmed value back to iPad SQLite. The overlay
    /// bridges the gap so the iPad UI shows Surface's edit immediately;
    /// reconcileLocalRow clears the overlay once SQLite catches up.
    ///
    /// This eliminates the dual-write race that caused names to revert: iPad
    /// writing to PowerSync from a WebSocket message AND from cloud sync
    /// would race, and whichever lost would silently clobber the other.
    @discardableResult
    func applyRemoteUpdate(
        _ req: SubjectMutationRequest,
        senderDeviceId: String,
        currentSubject: FPSubject
    ) async -> String {
        let idempotencyKey = req.idempotencyKey ?? UUID().uuidString.lowercased()
        SubjectSyncEvents.shared.emit(SubjectSyncEvent(
            deviceId: senderDeviceId,
            operation: .update,
            outcome: .received,
            sourcePath: req.sourcePath,
            subjectId: req.subjectId,
            galleryId: req.galleryId,
            idempotencyKey: idempotencyKey,
            fieldsTouched: req.fields.fieldsTouched
        ))
        // Stash the incoming fields in the overlay tagged as remote-websocket.
        // Views read overlay-merged subjects so the new values appear instantly.
        SubjectSyncOverlay.shared.apply(
            subjectId: req.subjectId,
            fields: req.fields,
            idempotencyKey: idempotencyKey,
            source: .remoteWebsocket
        )
        // currentSubject and the merged result aren't needed on this path —
        // overlay.merge happens at view-read time, not here. Reference the
        // arg to silence "unused" warnings without changing behavior.
        _ = currentSubject
        return idempotencyKey
    }

    /// Clear an overlay entry when the local PowerSync row catches up to the
    /// overlay's promised value. Called from the row-observation pipeline.
    @discardableResult
    func reconcileLocalRow(_ subject: FPSubject) -> Bool {
        let id = subject.id.uuidString.lowercased()
        return SubjectSyncOverlay.shared.clearIfMatches(subjectId: id, localSubject: subject)
    }

    // MARK: - Helpers

    /// Apply only the non-nil fields from a SubjectSyncFields onto an FPSubject.
    /// Pure — doesn't mutate the input. Used by both local and remote paths so
    /// the field application logic lives in exactly one place.
    static func applyFieldsToSubject(_ f: SubjectSyncFields, base: FPSubject) -> FPSubject {
        var out = base
        if let v = f.firstName        { out.firstName = v }
        if let v = f.lastName         { out.lastName = v }
        if let v = f.grade            { out.grade = v }
        if let v = f.teacher          { out.teacher = v }
        if let v = f.homeroom         { out.homeroom = v }
        if let v = f.studentId        { out.studentId = v }
        if let v = f.rosterId         { out.rosterId = v }
        if let v = f.onlineCode       { out.onlineCode = v }
        if let v = f.jerseyNumber     { out.jerseyNumber = v }
        if let v = f.sport            { out.sport = v }
        if let v = f.position         { out.position = v }
        if let v = f.organizationName { out.organizationName = v }
        if let v = f.year             { out.year = v }
        if let v = f.subjectType      { out.subjectType = v }
        if let v = f.title            { out.title = v }
        if let v = f.referenceNumber  { out.referenceNumber = v }
        if let v = f.photographer     { out.photographer = v }
        if let v = f.photoSessionDate { out.photoSessionDate = v }
        if let v = f.expirationDate   { out.expirationDate = v }
        if let v = f.email            { out.email = v }
        if let v = f.phone            { out.phone = v }
        if let v = f.phone2           { out.phone2 = v }
        if let v = f.address1         { out.address1 = v }
        if let v = f.address2         { out.address2 = v }
        if let v = f.city             { out.city = v }
        if let v = f.state            { out.state = v }
        if let v = f.zip              { out.zip = v }
        if let v = f.country          { out.country = v }
        if let v = f.mother           { out.mother = v }
        if let v = f.father           { out.father = v }
        if let v = f.personalization  { out.personalization = v }
        if let v = f.discountCode     { out.discountCode = v }
        if let v = f.custom1          { out.custom1 = v }
        if let v = f.custom2          { out.custom2 = v }
        if let v = f.custom3          { out.custom3 = v }
        if let v = f.custom4          { out.custom4 = v }
        if let v = f.custom5          { out.custom5 = v }
        if let v = f.custom6          { out.custom6 = v }
        if let v = f.custom7          { out.custom7 = v }
        if let v = f.custom8          { out.custom8 = v }
        if let v = f.custom9          { out.custom9 = v }
        if let v = f.custom10         { out.custom10 = v }
        if let v = f.custom11         { out.custom11 = v }
        if let v = f.custom12         { out.custom12 = v }
        if let v = f.custom13         { out.custom13 = v }
        if let v = f.custom14         { out.custom14 = v }
        if let v = f.custom15         { out.custom15 = v }
        if let v = f.custom16         { out.custom16 = v }
        if let v = f.custom17         { out.custom17 = v }
        if let v = f.custom18         { out.custom18 = v }
        if let v = f.custom19         { out.custom19 = v }
        if let v = f.custom20         { out.custom20 = v }
        if let v = f.notes            { out.notes = v }
        if let v = f.imageNumbers     { out.imageNumbers = v }
        if let v = f.isAbsent         { out.isAbsent = v }
        if let v = f.needsRetake      { out.needsRetake = v }
        if let v = f.isPhotographed   { out.isPhotographed = v }
        if let v = f.checkedInAt      { out.checkedInAt = v }
        out.updatedAt = Date()
        return out
    }

    private static func deviceIdOrUnknown() -> String {
        // Match the iPad device id used by FocalPointSyncClient. We read the
        // same UserDefaults key directly so we don't depend on the private
        // computed property over there. If the key hasn't been written yet
        // (sync client never initialized), return "unknown" — better than
        // generating a fresh id that nothing else recognizes.
        if let id = UserDefaults.standard.string(forKey: "fp_sync_device_id") {
            return id
        }
        return "unknown"
    }

    // MARK: - Phase D — create / delete / batch entry points
    //
    // Per FROM_SCRATCH_ARCHITECTURE.md §13 Phase D: every iPad save
    // site for new/deleted/batch-affected subjects routes through
    // SubjectSyncService. When connected to Surface in the gallery, the
    // canonical command is sent and the typed ack determines outcome
    // (applied/dedupe → committed; rejected → failed, no replay because
    // a rejection on its merits won't get healthier with retry).
    //
    // On transport failure (timeout, throw) or when the iPad isn't in a
    // Surface-connected shoot, the command is enqueued into the
    // persistent CommandQueue (CommandQueue.swift) and drains on the
    // next reconnect via FocalPointSyncClient's connection-state hook.
    // This REPLACES the Phase 0 / Phase C dual-write PowerSync fallback
    // that previously lived in this file — per §17.10 and rule 19.1,
    // the legacy substrate (sendSubjectFullUpdate, the in-fallback
    // PowerSyncManager.saveSubject calls) is deleted in this commit.
    //
    // Captura coexistence per §17.10 (Phase D kickoff re-grep verified):
    //   - broadcastSubjectCreated retains: AddRosterEntryView.swift:387
    //   - sendSubjectUpdated retains: AddRosterEntryView.swift:396
    //   - broadcastEntriesDeleted retains: SportsShoot{List,Detail}View
    //     and the independently-scheduled FPSportsRosterView_iPad caller.
    //   - sendSubjectFullUpdate has zero retained callers and is deleted
    //     from FocalPointSyncClient.swift in this commit.

    /// Insert a single new subject. Connected → `insert_subjects`
    /// command (Surface owns the cloud write); otherwise enqueue for
    /// drain on next reconnect.
    @discardableResult
    func createSubject(
        _ subject: FPSubject,
        sourcePath: String,
        idempotencyKey: String? = nil
    ) async -> String {
        let key = idempotencyKey ?? UUID().uuidString.lowercased()
        let deviceId = SubjectSyncService.deviceIdOrUnknown()
        let galleryId = subject.galleryId
        let subjectId = subject.id.uuidString.lowercased()
        let row = SubjectSyncService.insertRowDictionary(from: subject)
        let cmd = SubjectCommandBuilder.create(
            galleryId: galleryId,
            row: row,
            originatingDeviceId: deviceId,
            idempotencyKey: key
        )

        if FocalPointSyncClient.shared.isConnectedAndInGallery(galleryId) {
            do {
                let ack = try await FocalPointSyncClient.shared.sendSubjectCommand(cmd)
                switch ack.status {
                case .applied, .dedupe:
                    SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                        deviceId: deviceId,
                        operation: .create,
                        outcome: .committed,
                        sourcePath: sourcePath + ":cmd",
                        subjectId: subjectId,
                        galleryId: galleryId,
                        idempotencyKey: key
                    ))
                    return key
                case .rejected:
                    SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                        deviceId: deviceId,
                        operation: .create,
                        outcome: .rejected,
                        sourcePath: sourcePath + ":cmd_rejected",
                        subjectId: subjectId,
                        galleryId: galleryId,
                        idempotencyKey: key,
                        errorMessage: ack.reason ?? "rejected"
                    ))
                    return key
                }
            } catch {
                SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                    deviceId: deviceId,
                    operation: .create,
                    outcome: .failed,
                    sourcePath: sourcePath + ":cmd_threw",
                    subjectId: subjectId,
                    galleryId: galleryId,
                    idempotencyKey: key,
                    errorMessage: String(describing: error)
                ))
            }
        }

        do {
            _ = try await CommandQueue.shared.enqueue(cmd)
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .create,
                outcome: .queued,
                sourcePath: sourcePath + ":enqueued",
                subjectId: subjectId,
                galleryId: galleryId,
                idempotencyKey: key
            ))
        } catch {
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .create,
                outcome: .abandoned,
                sourcePath: sourcePath + ":enqueue_failed",
                subjectId: subjectId,
                galleryId: galleryId,
                idempotencyKey: key,
                errorMessage: String(describing: error)
            ))
        }
        return key
    }

    /// Insert many new subjects in one batch. Connected → single
    /// `insert_subjects` command with all rows; otherwise enqueue once
    /// (the batch is one logical unit — we don't fragment it into per-row
    /// queue rows because that would multiply the wire round-trips on
    /// drain and lose the receiver's per-batch idempotency dedupe).
    @discardableResult
    func batchCreateSubjects(
        _ subjects: [FPSubject],
        sourcePath: String,
        idempotencyKey: String? = nil
    ) async -> String {
        let key = idempotencyKey ?? UUID().uuidString.lowercased()
        let deviceId = SubjectSyncService.deviceIdOrUnknown()
        guard let first = subjects.first else { return key }
        let galleryId = first.galleryId
        let rows = subjects.map { SubjectSyncService.insertRowDictionary(from: $0) }
        let cmd = SubjectCommandBuilder.batchCreate(
            galleryId: galleryId,
            rows: rows,
            originatingDeviceId: deviceId,
            idempotencyKey: key
        )

        if FocalPointSyncClient.shared.isConnectedAndInGallery(galleryId) {
            do {
                let ack = try await FocalPointSyncClient.shared.sendSubjectCommand(cmd)
                switch ack.status {
                case .applied, .dedupe:
                    SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                        deviceId: deviceId,
                        operation: .create,
                        outcome: .committed,
                        sourcePath: sourcePath + ":cmd",
                        subjectId: nil,
                        galleryId: galleryId,
                        idempotencyKey: key
                    ))
                    return key
                case .rejected:
                    SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                        deviceId: deviceId,
                        operation: .create,
                        outcome: .rejected,
                        sourcePath: sourcePath + ":cmd_rejected",
                        subjectId: nil,
                        galleryId: galleryId,
                        idempotencyKey: key,
                        errorMessage: ack.reason ?? "rejected"
                    ))
                    return key
                }
            } catch {
                SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                    deviceId: deviceId,
                    operation: .create,
                    outcome: .failed,
                    sourcePath: sourcePath + ":cmd_threw",
                    subjectId: nil,
                    galleryId: galleryId,
                    idempotencyKey: key,
                    errorMessage: String(describing: error)
                ))
            }
        }

        do {
            _ = try await CommandQueue.shared.enqueue(cmd)
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .create,
                outcome: .queued,
                sourcePath: sourcePath + ":enqueued",
                subjectId: nil,
                galleryId: galleryId,
                idempotencyKey: key
            ))
        } catch {
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .create,
                outcome: .abandoned,
                sourcePath: sourcePath + ":enqueue_failed",
                subjectId: nil,
                galleryId: galleryId,
                idempotencyKey: key,
                errorMessage: String(describing: error)
            ))
        }
        return key
    }

    /// Soft-delete a subject. Connected → `soft_delete_subject` command
    /// (receiver cascades to capture_images and subject_images per
    /// surface-local-transport.ts:178-207); otherwise enqueue for drain.
    /// Captura's batch-delete broadcast (`broadcastEntriesDeleted` in
    /// §17.10) is intentionally NOT emitted here — it's a Captura-only
    /// producer; FP-aware peer iPads see the delete via the receiver's
    /// `subjects_deleted` broadcast on the connected path or via the
    /// drained command's broadcast on the queued path.
    @discardableResult
    func deleteSubject(
        subjectId: UUID,
        galleryId: String,
        sourcePath: String,
        idempotencyKey: String? = nil
    ) async -> String {
        let key = idempotencyKey ?? UUID().uuidString.lowercased()
        let deviceId = SubjectSyncService.deviceIdOrUnknown()
        let sid = subjectId.uuidString.lowercased()
        let cmd = SubjectCommandBuilder.delete(
            galleryId: galleryId,
            subjectId: sid,
            originatingDeviceId: deviceId,
            idempotencyKey: key
        )

        if FocalPointSyncClient.shared.isConnectedAndInGallery(galleryId) {
            do {
                let ack = try await FocalPointSyncClient.shared.sendSubjectCommand(cmd)
                switch ack.status {
                case .applied, .dedupe:
                    SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                        deviceId: deviceId,
                        operation: .delete,
                        outcome: .committed,
                        sourcePath: sourcePath + ":cmd",
                        subjectId: sid,
                        galleryId: galleryId,
                        idempotencyKey: key
                    ))
                    return key
                case .rejected:
                    SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                        deviceId: deviceId,
                        operation: .delete,
                        outcome: .rejected,
                        sourcePath: sourcePath + ":cmd_rejected",
                        subjectId: sid,
                        galleryId: galleryId,
                        idempotencyKey: key,
                        errorMessage: ack.reason ?? "rejected"
                    ))
                    return key
                }
            } catch {
                SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                    deviceId: deviceId,
                    operation: .delete,
                    outcome: .failed,
                    sourcePath: sourcePath + ":cmd_threw",
                    subjectId: sid,
                    galleryId: galleryId,
                    idempotencyKey: key,
                    errorMessage: String(describing: error)
                ))
            }
        }

        do {
            _ = try await CommandQueue.shared.enqueue(cmd)
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .delete,
                outcome: .queued,
                sourcePath: sourcePath + ":enqueued",
                subjectId: sid,
                galleryId: galleryId,
                idempotencyKey: key
            ))
        } catch {
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .delete,
                outcome: .abandoned,
                sourcePath: sourcePath + ":enqueue_failed",
                subjectId: sid,
                galleryId: galleryId,
                idempotencyKey: key,
                errorMessage: String(describing: error)
            ))
        }
        return key
    }

    /// Apply the same field set to many subjects in one batch. Connected
    /// → single `bulk_update_subjects` command (receiver re-broadcasts
    /// one `subject_updated` per id sharing one gallery version, per
    /// surface-command-receiver.ts:360-371); otherwise enqueue the
    /// batch as one logical command — the drain replays it as a unit
    /// so the receiver's bulk dedupe semantics still hold.
    ///
    /// `currentSubjects` is retained on the signature for caller
    /// compatibility (the Phase C signature took it as a per-id
    /// fallback prerequisite). It is no longer consulted because the
    /// batch is now one command, not N — kept as a parameter so the
    /// callers' sites don't churn during this commit. A subsequent
    /// signature-cleanup commit can drop it.
    @discardableResult
    func batchUpdateSubjects(
        subjectIds: [UUID],
        galleryId: String,
        fields: SubjectSyncFields,
        currentSubjects: [UUID: FPSubject] = [:],
        sourcePath: String,
        idempotencyKey: String? = nil
    ) async -> String {
        _ = currentSubjects // unused after Phase D; retained for signature compatibility
        let key = idempotencyKey ?? UUID().uuidString.lowercased()
        let deviceId = SubjectSyncService.deviceIdOrUnknown()
        let stringIds = subjectIds.map { $0.uuidString.lowercased() }
        let cmd: SubjectCommand
        do {
            cmd = try SubjectCommandBuilder.batchUpdate(
                galleryId: galleryId,
                subjectIds: stringIds,
                fields: fields,
                originatingDeviceId: deviceId,
                idempotencyKey: key
            )
        } catch {
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .update,
                outcome: .failed,
                sourcePath: sourcePath + ":build_failed",
                subjectId: nil,
                galleryId: galleryId,
                idempotencyKey: key,
                fieldsTouched: fields.fieldsTouched,
                errorMessage: String(describing: error)
            ))
            return key
        }

        if FocalPointSyncClient.shared.isConnectedAndInGallery(galleryId) {
            do {
                let ack = try await FocalPointSyncClient.shared.sendSubjectCommand(cmd)
                switch ack.status {
                case .applied, .dedupe:
                    SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                        deviceId: deviceId,
                        operation: .update,
                        outcome: .committed,
                        sourcePath: sourcePath + ":cmd",
                        subjectId: nil,
                        galleryId: galleryId,
                        idempotencyKey: key,
                        fieldsTouched: fields.fieldsTouched
                    ))
                    return key
                case .rejected:
                    SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                        deviceId: deviceId,
                        operation: .update,
                        outcome: .rejected,
                        sourcePath: sourcePath + ":cmd_rejected",
                        subjectId: nil,
                        galleryId: galleryId,
                        idempotencyKey: key,
                        fieldsTouched: fields.fieldsTouched,
                        errorMessage: ack.reason ?? "rejected"
                    ))
                    return key
                }
            } catch {
                SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                    deviceId: deviceId,
                    operation: .update,
                    outcome: .failed,
                    sourcePath: sourcePath + ":cmd_threw",
                    subjectId: nil,
                    galleryId: galleryId,
                    idempotencyKey: key,
                    fieldsTouched: fields.fieldsTouched,
                    errorMessage: String(describing: error)
                ))
            }
        }

        do {
            _ = try await CommandQueue.shared.enqueue(cmd)
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .update,
                outcome: .queued,
                sourcePath: sourcePath + ":enqueued",
                subjectId: nil,
                galleryId: galleryId,
                idempotencyKey: key,
                fieldsTouched: fields.fieldsTouched
            ))
        } catch {
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .update,
                outcome: .abandoned,
                sourcePath: sourcePath + ":enqueue_failed",
                subjectId: nil,
                galleryId: galleryId,
                idempotencyKey: key,
                fieldsTouched: fields.fieldsTouched,
                errorMessage: String(describing: error)
            ))
        }
        return key
    }

    /// Soft-delete many subjects in one batch. Connected → single
    /// `bulk_delete_subjects` command (receiver routes through
    /// SurfaceLocalTransport.bulk_delete_subjects which cascades each
    /// id to capture_images and subject_images, then emits one
    /// subjects_deleted broadcast for the full id set per
    /// surface-command-receiver.ts:332-336); otherwise enqueue the
    /// batch as one logical command — the drain replays it as a unit
    /// so the receiver's bulk semantics still hold (no per-row split
    /// that would multiply wire round-trips and break batch dedupe).
    ///
    /// Phase G G.6 — adds the iPad sender pair for the bulk_delete
    /// receiver handler that Phase B already deployed. The sole UI
    /// caller is FPSportsRosterView_iPad.swift's batchDeleteRosterEntries
    /// (Phase C tail per Amendment 4 / G.6).
    @discardableResult
    func batchDeleteSubjects(
        subjectIds: [UUID],
        galleryId: String,
        sourcePath: String,
        idempotencyKey: String? = nil
    ) async -> String {
        let key = idempotencyKey ?? UUID().uuidString.lowercased()
        let deviceId = SubjectSyncService.deviceIdOrUnknown()
        let stringIds = subjectIds.map { $0.uuidString.lowercased() }
        let cmd = SubjectCommandBuilder.batchDelete(
            galleryId: galleryId,
            subjectIds: stringIds,
            originatingDeviceId: deviceId,
            idempotencyKey: key
        )

        if FocalPointSyncClient.shared.isConnectedAndInGallery(galleryId) {
            do {
                let ack = try await FocalPointSyncClient.shared.sendSubjectCommand(cmd)
                switch ack.status {
                case .applied, .dedupe:
                    SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                        deviceId: deviceId,
                        operation: .delete,
                        outcome: .committed,
                        sourcePath: sourcePath + ":cmd",
                        subjectId: nil,
                        galleryId: galleryId,
                        idempotencyKey: key
                    ))
                    return key
                case .rejected:
                    SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                        deviceId: deviceId,
                        operation: .delete,
                        outcome: .rejected,
                        sourcePath: sourcePath + ":cmd_rejected",
                        subjectId: nil,
                        galleryId: galleryId,
                        idempotencyKey: key,
                        errorMessage: ack.reason ?? "rejected"
                    ))
                    return key
                }
            } catch {
                SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                    deviceId: deviceId,
                    operation: .delete,
                    outcome: .failed,
                    sourcePath: sourcePath + ":cmd_threw",
                    subjectId: nil,
                    galleryId: galleryId,
                    idempotencyKey: key,
                    errorMessage: String(describing: error)
                ))
            }
        }

        do {
            _ = try await CommandQueue.shared.enqueue(cmd)
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .delete,
                outcome: .queued,
                sourcePath: sourcePath + ":enqueued",
                subjectId: nil,
                galleryId: galleryId,
                idempotencyKey: key
            ))
        } catch {
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .delete,
                outcome: .abandoned,
                sourcePath: sourcePath + ":enqueue_failed",
                subjectId: nil,
                galleryId: galleryId,
                idempotencyKey: key,
                errorMessage: String(describing: error)
            ))
        }
        return key
    }

    /// Build a SubjectSyncFields delta carrying every iPad-editable
    /// field on `subject`. Used by Phase C migration sites that
    /// previously called PowerSyncManager.saveSubject(updated) with a
    /// full row — the equivalent through SubjectSyncService.updateSubject
    /// is a SubjectMutationRequest whose `fields` describes the entire
    /// row. The connected path encodes this once on the wire; the
    /// fallback path's applyFieldsToSubject reconstructs the same row
    /// for PowerSync. Inverse of applyFieldsToSubject.
    static func fieldsFromFullSubject(_ s: FPSubject) -> SubjectSyncFields {
        var f = SubjectSyncFields()
        f.firstName = s.firstName
        f.lastName = s.lastName
        f.grade = s.grade
        f.teacher = s.teacher
        f.homeroom = s.homeroom
        f.studentId = s.studentId
        f.rosterId = s.rosterId
        f.onlineCode = s.onlineCode
        f.jerseyNumber = s.jerseyNumber
        f.sport = s.sport
        f.position = s.position
        f.organizationName = s.organizationName
        f.year = s.year
        f.subjectType = s.subjectType
        f.title = s.title
        f.referenceNumber = s.referenceNumber
        f.photographer = s.photographer
        f.photoSessionDate = s.photoSessionDate
        f.expirationDate = s.expirationDate
        f.email = s.email
        f.phone = s.phone
        f.phone2 = s.phone2
        f.address1 = s.address1
        f.address2 = s.address2
        f.city = s.city
        f.state = s.state
        f.zip = s.zip
        f.country = s.country
        f.mother = s.mother
        f.father = s.father
        f.personalization = s.personalization
        f.discountCode = s.discountCode
        f.custom1 = s.custom1
        f.custom2 = s.custom2
        f.custom3 = s.custom3
        f.custom4 = s.custom4
        f.custom5 = s.custom5
        f.custom6 = s.custom6
        f.custom7 = s.custom7
        f.custom8 = s.custom8
        f.custom9 = s.custom9
        f.custom10 = s.custom10
        f.custom11 = s.custom11
        f.custom12 = s.custom12
        f.custom13 = s.custom13
        f.custom14 = s.custom14
        f.custom15 = s.custom15
        f.custom16 = s.custom16
        f.custom17 = s.custom17
        f.custom18 = s.custom18
        f.custom19 = s.custom19
        f.custom20 = s.custom20
        f.notes = s.notes
        f.imageNumbers = s.imageNumbers
        f.isAbsent = s.isAbsent
        f.needsRetake = s.needsRetake
        f.isPhotographed = s.isPhotographed
        if let checkedIn = s.checkedInAt { f.checkedInAt = checkedIn }
        return f
    }

    /// Build the snake_case insert-row dictionary the Surface receiver
    /// expects for `insert_subjects.payload.rows[]`. The receiver re-
    /// validates against INSERTABLE_SUBJECT_FIELDS in
    /// subject-repository.ts:79-104 and force-overrides gallery_id from
    /// the command envelope, so any forbidden keys we accidentally
    /// include are dropped server-side. We omit them up front for wire
    /// hygiene anyway.
    static func insertRowDictionary(from subject: FPSubject) -> [String: Any] {
        var row: [String: Any] = [
            "organization_id": subject.organizationId,
            "first_name": subject.firstName,
            "last_name": subject.lastName,
            "grade": subject.grade,
            "teacher": subject.teacher,
            "homeroom": subject.homeroom,
            "student_id": subject.studentId,
            "roster_id": subject.rosterId,
            "online_code": subject.onlineCode,
            "jersey_number": subject.jerseyNumber,
            "sport": subject.sport,
            "position": subject.position,
            "organization_name": subject.organizationName,
            "year": subject.year,
            "subject_type": subject.subjectType,
            "title": subject.title,
            "reference_number": subject.referenceNumber,
            "photographer": subject.photographer,
            "photo_session_date": subject.photoSessionDate,
            "expiration_date": subject.expirationDate,
            "email": subject.email,
            "phone": subject.phone,
            "phone2": subject.phone2,
            "address1": subject.address1,
            "address2": subject.address2,
            "city": subject.city,
            "state": subject.state,
            "zip": subject.zip,
            "country": subject.country,
            "mother": subject.mother,
            "father": subject.father,
            "personalization": subject.personalization,
            "discount_code": subject.discountCode,
            "notes": subject.notes,
            "image_numbers": subject.imageNumbers,
            "is_absent": subject.isAbsent,
            "needs_retake": subject.needsRetake,
            "is_photographed": subject.isPhotographed,
            "custom1": subject.custom1, "custom2": subject.custom2, "custom3": subject.custom3,
            "custom4": subject.custom4, "custom5": subject.custom5, "custom6": subject.custom6,
            "custom7": subject.custom7, "custom8": subject.custom8, "custom9": subject.custom9,
            "custom10": subject.custom10, "custom11": subject.custom11, "custom12": subject.custom12,
            "custom13": subject.custom13, "custom14": subject.custom14, "custom15": subject.custom15,
            "custom16": subject.custom16, "custom17": subject.custom17, "custom18": subject.custom18,
            "custom19": subject.custom19, "custom20": subject.custom20,
        ]
        if let checkedIn = subject.checkedInAt {
            row["checked_in_at"] = checkedIn
        }
        return row
    }
}
