//
//  SubjectSyncService.swift
//  Iconik Employee
//
//  The single entry point for subject mutations on the iPad. Every place
//  that wants to update, create, or delete a subject goes through here.
//  Eliminates the "five callers each with their own logic" problem
//  documented in §2.1 of the rewrite plan.
//
//  Behavior is gated on `isV2Enabled` (UserDefaults: fp_subject_sync_v2_enabled).
//  When OFF (default), this is a thin wrapper around the legacy
//  PowerSyncManager.saveSubject + FocalPointSyncClient.sendSubjectFullUpdate
//  pair so behavior is unchanged. When ON, it activates the new architecture:
//  optimistic overlay, structured event log, ack-aware routing.
//
//  Mirror of src/data/sync/subject-sync-service.ts on the Mac side.
//
//  See IPAD_SURFACE_SYNC_REWRITE.md §5.
//

import Foundation
import Combine

// MARK: - Feature flag

let kSubjectSyncV2DefaultsKey = "fp_subject_sync_v2_enabled"

func isSubjectSyncV2Enabled() -> Bool {
    UserDefaults.standard.bool(forKey: kSubjectSyncV2DefaultsKey)
}

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

    /// Apply a subject update. Routes through v2 (overlay + WebSocket) when
    /// the flag is on, otherwise through the legacy save path. Returns the
    /// idempotency key used so the caller can correlate with structured events.
    @discardableResult
    func updateSubject(
        _ req: SubjectMutationRequest,
        currentSubject: FPSubject
    ) async -> String {
        let idempotencyKey = req.idempotencyKey ?? UUID().uuidString.lowercased()
        let fieldsTouched = req.fields.fieldsTouched
        let deviceId = SubjectSyncService.deviceIdOrUnknown()

        if !isSubjectSyncV2Enabled() {
            // Legacy path — preserve the existing two-step behavior:
            //   1. Local PowerSync write (saveSubject) so iPad UI persists.
            //   2. Best-effort WebSocket broadcast so Surface picks it up.
            // Emit a 'committed' event so the debug panel doesn't go silent
            // when v2 is off.
            let merged = SubjectSyncService.applyFieldsToSubject(req.fields, base: currentSubject)
            do {
                try await PowerSyncManager.shared.saveSubject(merged)
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

        // ----- v2 path -----
        // 1. Apply optimistic overlay so the UI sees the new values immediately,
        //    independent of whether we write locally or only broadcast.
        SubjectSyncOverlay.shared.apply(
            subjectId: req.subjectId,
            fields: req.fields,
            idempotencyKey: idempotencyKey,
            source: .localEdit
        )

        let merged = SubjectSyncService.applyFieldsToSubject(req.fields, base: currentSubject)

        // 2. Routing decision. Single source of truth: SyncConnection state.
        //    - Active (connected/degraded/reconnecting): Surface is the cloud
        //      writer. Send via WebSocket only — skip local PowerSync write to
        //      avoid the dual-sync race that clobbered Surface-typed names with
        //      stale iPad values (see 2026-04-21 Serenity Braun bug). Cloud
        //      round-trip via PowerSync brings the value back into iPad SQLite,
        //      and reconcileLocalRow then clears the overlay.
        //    - Terminal (disconnected/failed): standalone iPad. We MUST write
        //      to PowerSync because there's no other path to durability.
        if SyncConnection.shared.canDeliverEventually {
            FocalPointSyncClient.shared.sendSubjectFullUpdate(merged)
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: deviceId,
                operation: .update,
                outcome: .sent,
                sourcePath: req.sourcePath,
                subjectId: req.subjectId,
                galleryId: req.galleryId,
                idempotencyKey: idempotencyKey,
                fieldsTouched: fieldsTouched
            ))
        } else {
            do {
                try await PowerSyncManager.shared.saveSubject(merged)
                // Standalone — also try a best-effort broadcast in case the
                // socket comes back up before the cloud round-trip completes.
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
                // Clear the overlay — local SQLite now matches our promised value.
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
        if let v = f.firstName       { out.firstName = v }
        if let v = f.lastName        { out.lastName = v }
        if let v = f.grade           { out.grade = v }
        if let v = f.teacher         { out.teacher = v }
        if let v = f.homeroom        { out.homeroom = v }
        if let v = f.studentId       { out.studentId = v }
        if let v = f.rosterId        { out.rosterId = v }
        if let v = f.jerseyNumber    { out.jerseyNumber = v }
        if let v = f.sport           { out.sport = v }
        if let v = f.position        { out.position = v }
        if let v = f.email           { out.email = v }
        if let v = f.phone           { out.phone = v }
        if let v = f.notes           { out.notes = v }
        if let v = f.imageNumbers    { out.imageNumbers = v }
        if let v = f.isAbsent        { out.isAbsent = v }
        if let v = f.needsRetake     { out.needsRetake = v }
        if let v = f.isPhotographed  { out.isPhotographed = v }
        if let v = f.checkedInAt     { out.checkedInAt = v }
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
