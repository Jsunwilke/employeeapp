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
    /// Per SYNC_ARCHITECTURE_SPEC.md §11.1, when the iPad is connected to a
    /// Surface in this gallery, the subject_command path runs: send a
    /// command, await ack, let the Surface be the sole writer. The overlay
    /// gives instant UI; Surface's subject_updated broadcast back refreshes
    /// other iPads; PowerSync eventually delivers the row to this iPad too
    /// (reconcileLocalRow clears the overlay then).
    ///
    /// If the command path fails (timeout, rejection, no connection) — or
    /// if the iPad simply isn't in a Surface-connected shoot — the legacy
    /// local-write path runs. The iPad never loses an edit because the
    /// WebSocket wobbled.
    @discardableResult
    func updateSubject(
        _ req: SubjectMutationRequest,
        currentSubject: FPSubject
    ) async -> String {
        let idempotencyKey = req.idempotencyKey ?? UUID().uuidString.lowercased()
        let fieldsTouched = req.fields.fieldsTouched
        let deviceId = SubjectSyncService.deviceIdOrUnknown()

        // 1. Apply optimistic overlay so the UI sees the new values immediately,
        //    independent of whether we write locally or only broadcast.
        SubjectSyncOverlay.shared.apply(
            subjectId: req.subjectId,
            fields: req.fields,
            idempotencyKey: idempotencyKey,
            source: .localEdit
        )

        if FocalPointSyncClient.shared.isConnectedAndInGallery(req.galleryId) {
            do {
                let cmd = try SubjectCommandBuilder.update(
                    galleryId: req.galleryId,
                    subjectId: req.subjectId,
                    fields: req.fields,
                    originatingDeviceId: deviceId
                )
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
                    // Surface acked; do NOT write PowerSync. The
                    // subsequent subject_updated broadcast from Surface +
                    // eventual cloud-sync delivery will land in SQLite.
                    return idempotencyKey
                case .rejected:
                    // Surface rejected the command. Roll back the overlay
                    // so the UI doesn't show a value that won't persist.
                    // Then fall through to the legacy path so the edit
                    // isn't silently lost — local PowerSync remains the
                    // safety net.
                    _ = SubjectSyncOverlay.shared.clearIfMatches(
                        subjectId: req.subjectId,
                        localSubject: currentSubject
                    )
                    SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                        deviceId: deviceId,
                        operation: .update,
                        outcome: .failed,
                        sourcePath: req.sourcePath + ":cmd_rejected",
                        subjectId: req.subjectId,
                        galleryId: req.galleryId,
                        idempotencyKey: idempotencyKey,
                        fieldsTouched: fieldsTouched,
                        errorMessage: ack.reason ?? "rejected"
                    ))
                    // Reapply overlay so the legacy path's overlay write
                    // re-overrides correctly.
                    SubjectSyncOverlay.shared.apply(
                        subjectId: req.subjectId,
                        fields: req.fields,
                        idempotencyKey: idempotencyKey,
                        source: .localEdit
                    )
                    // intentional fall-through to legacy path below
                }
            } catch {
                // Timeout or transport error — fall through to legacy path.
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
                // Overlay is still in place from step 1 above.
            }
        }

        let merged = SubjectSyncService.applyFieldsToSubject(req.fields, base: currentSubject)

        // 2. Always write to local PowerSync. The audit caught a data-loss
        //    case in the WS-only routing: if Surface receives the broadcast
        //    but crashes before its Supabase write commits, AND the iPad
        //    goes offline before reconnecting, the edit is permanently lost
        //    (overlay expires after 5 min, no PowerSync row was written).
        //
        //    PowerSync's eventual-consistency model handles the dual-write
        //    case fine: both sides upload the same row keyed by id, and
        //    last-write-wins on updated_at. Worst case is one extra cloud
        //    write per edit. Original "Serenity Braun" bug was iPad writing
        //    a STALE value (because of the splice-then-update race in the
        //    WebSocket receive handler), not the local write itself —
        //    that's fixed by FPSportsRosterView_iPad's overlay-only receive
        //    path.
        do {
            try await PowerSyncManager.shared.saveSubject(merged)
            // Best-effort broadcast — may queue if the socket is mid-reconnect.
            FocalPointSyncClient.shared.sendSubjectFullUpdate(merged)
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .update,
                outcome: .committed,
                sourcePath: req.sourcePath,
                subjectId: req.subjectId,
                galleryId: req.galleryId,
                idempotencyKey: idempotencyKey,
                fieldsTouched: fieldsTouched
            ))
            // Local SQLite now matches the promised value — clear overlay.
            _ = SubjectSyncOverlay.shared.clearIfMatches(subjectId: req.subjectId, localSubject: merged)
        } catch {
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .update,
                outcome: .failed,
                sourcePath: req.sourcePath,
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
}
