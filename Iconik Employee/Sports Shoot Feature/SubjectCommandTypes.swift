//
//  SubjectCommandTypes.swift
//  Iconik Employee
//
//  Phase 0 sync rewrite — Swift port of the WebSocket subject_command
//  envelope from `src/data/repositories/transports/surface-command-transport.ts`
//  on the Mac side. iPad-originated subject mutations during a shoot are
//  serialized into one of these and sent to the Surface, which is the
//  single ordering authority per SYNC_ARCHITECTURE_SPEC.md §4.
//
//  The wire shape is locked: changing a field name here without changing
//  the TS counterpart breaks cross-platform parsing. Both sides use
//  `.passthrough()` (TS) / decodeIfPresent (Swift) so additive changes
//  are forward-compatible, but renames must be done in lockstep.
//

import Foundation

// MARK: - Command type enum (matches SubjectCommandType in TS)

enum SubjectCommandType: String, Codable {
    case updateSubject       = "update_subject"
    case insertSubjects      = "insert_subjects"
    case softDeleteSubject   = "soft_delete_subject"
    case restoreSubject      = "restore_subject"
    case bulkUpdateSubjects  = "bulk_update_subjects"
    case bulkDeleteSubjects  = "bulk_delete_subjects"
}

// MARK: - Command envelope (matches SubjectCommand in TS)

struct SubjectCommand {
    let commandId: String
    let commandType: SubjectCommandType
    let galleryId: String
    let idempotencyKey: String
    let originatingDeviceId: String
    let payload: [String: Any]
    let sentAt: String

    /// Encode to the wire dictionary used by FocalPointSyncClient.send.
    /// Keys match the TS schema in `local-sync-types.ts:SubjectCommandSchema`.
    func toWireDictionary() -> [String: Any] {
        return [
            "type": "subject_command",
            "command_id": commandId,
            "command_type": commandType.rawValue,
            "gallery_id": galleryId,
            "idempotency_key": idempotencyKey,
            "originating_device_id": originatingDeviceId,
            "payload": payload,
            "sent_at": sentAt,
        ]
    }
}

// MARK: - Ack envelope (matches CommandAck in TS)

enum CommandAckStatus: String {
    case applied
    case rejected
    case dedupe
}

struct CommandAck {
    let commandId: String
    let status: CommandAckStatus
    let reason: String?
    let resultingState: [String: Any]?

    /// Decode from the inbound wire dictionary in handleMessage.
    static func fromWire(_ msg: [String: Any]) -> CommandAck? {
        guard let commandId = msg["command_id"] as? String,
              let statusRaw = msg["status"] as? String,
              let status = CommandAckStatus(rawValue: statusRaw)
        else { return nil }
        return CommandAck(
            commandId: commandId,
            status: status,
            reason: msg["reason"] as? String,
            resultingState: msg["resulting_state"] as? [String: Any]
        )
    }
}

// MARK: - Errors

enum SubjectCommandError: Error, CustomStringConvertible {
    case timeout
    case rejected(reason: String)
    case notConnected
    case missingGalleryId

    var description: String {
        switch self {
        case .timeout:
            return "subject_command timed out waiting for ack"
        case .rejected(let reason):
            return "subject_command rejected: \(reason)"
        case .notConnected:
            return "subject_command cannot be sent: WebSocket not connected"
        case .missingGalleryId:
            return "subject_command requires gallery_id"
        }
    }
}

// MARK: - Builder helpers

enum SubjectCommandBuilder {

    /// Build an `update_subject` command. The fields dictionary should
    /// match the snake_case keys used by SubjectSyncFields.CodingKeys —
    /// we encode the SubjectSyncFields struct via JSONEncoder to produce
    /// the right wire shape. `idempotencyKey` is caller-supplied so the
    /// SubjectSyncService can correlate the command's outcome with the
    /// originating UI action and so the persistent CommandQueue's drain
    /// replays carry the same key the Surface receiver already saw
    /// (Phase D — §11.3 dedupe relies on stable keys across replays).
    static func update(
        galleryId: String,
        subjectId: String,
        fields: SubjectSyncFields,
        originatingDeviceId: String,
        idempotencyKey: String? = nil
    ) throws -> SubjectCommand {
        let encoder = JSONEncoder()
        let data = try encoder.encode(fields)
        guard let fieldDict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SubjectCommandError.rejected(reason: "fields_encoding_failed")
        }
        return SubjectCommand(
            commandId: UUID().uuidString.lowercased(),
            commandType: .updateSubject,
            galleryId: galleryId,
            idempotencyKey: idempotencyKey ?? UUID().uuidString.lowercased(),
            originatingDeviceId: originatingDeviceId,
            payload: ["subject_id": subjectId, "fields": fieldDict],
            sentAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    /// Build an `insert_subjects` command for a single new subject.
    ///
    /// Per FROM_SCRATCH_ARCHITECTURE.md §13 Phase C C.2: the wire
    /// command_type is the canonical Section 7 verb `insert_subjects` (not
    /// a new "create" verb), matching the receiver handler shipped in
    /// Phase B at surface-command-receiver.ts:265-281. The Swift method
    /// name `.create` is an iPad-side ergonomic affordance only.
    ///
    /// `row` keys must use snake_case to match INSERTABLE_SUBJECT_FIELDS
    /// in subject-repository.ts — the receiver re-validates the allowlist
    /// before writing. Forbidden keys (id, gallery_id, is_deleted,
    /// last_originating_device_id, identity_id, created_at, updated_at,
    /// idempotency_key, locked_*) are stripped on the Mac side. Surface
    /// generates the row id; the iPad's optimistic state is the legacy
    /// fallback's local PowerSync write (gone in Phase D).
    static func create(
        galleryId: String,
        row: [String: Any],
        originatingDeviceId: String,
        idempotencyKey: String? = nil
    ) -> SubjectCommand {
        return SubjectCommand(
            commandId: UUID().uuidString.lowercased(),
            commandType: .insertSubjects,
            galleryId: galleryId,
            idempotencyKey: idempotencyKey ?? UUID().uuidString.lowercased(),
            originatingDeviceId: originatingDeviceId,
            payload: ["rows": [row]],
            sentAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    /// Build an `insert_subjects` command for many new subjects in one
    /// batch. Mirrors `.create` but with multiple rows in the payload —
    /// one Surface command_log row, one wire round-trip, instead of N.
    static func batchCreate(
        galleryId: String,
        rows: [[String: Any]],
        originatingDeviceId: String,
        idempotencyKey: String? = nil
    ) -> SubjectCommand {
        return SubjectCommand(
            commandId: UUID().uuidString.lowercased(),
            commandType: .insertSubjects,
            galleryId: galleryId,
            idempotencyKey: idempotencyKey ?? UUID().uuidString.lowercased(),
            originatingDeviceId: originatingDeviceId,
            payload: ["rows": rows],
            sentAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    /// Build a `soft_delete_subject` command. Wire command_type matches
    /// Section 7's canonical verb. Receiver handler at
    /// surface-command-receiver.ts:282-286 cascades the delete to
    /// capture_images and subject_images for the same subject.
    static func delete(
        galleryId: String,
        subjectId: String,
        originatingDeviceId: String,
        idempotencyKey: String? = nil
    ) -> SubjectCommand {
        return SubjectCommand(
            commandId: UUID().uuidString.lowercased(),
            commandType: .softDeleteSubject,
            galleryId: galleryId,
            idempotencyKey: idempotencyKey ?? UUID().uuidString.lowercased(),
            originatingDeviceId: originatingDeviceId,
            payload: ["subject_id": subjectId],
            sentAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    /// Build a `bulk_update_subjects` command — applies the same
    /// SubjectSyncFields to every subject in `subjectIds`. Receiver
    /// handler at surface-command-receiver.ts:292-298 re-validates the
    /// id list as UUIDs and the fields against UPDATABLE_SUBJECT_FIELDS.
    /// Receiver also broadcasts one `subject_updated` per id (line
    /// 360-371) so peer iPads see each row update with one shared
    /// gallery version.
    static func batchUpdate(
        galleryId: String,
        subjectIds: [String],
        fields: SubjectSyncFields,
        originatingDeviceId: String,
        idempotencyKey: String? = nil
    ) throws -> SubjectCommand {
        let encoder = JSONEncoder()
        let data = try encoder.encode(fields)
        guard let fieldDict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SubjectCommandError.rejected(reason: "fields_encoding_failed")
        }
        return SubjectCommand(
            commandId: UUID().uuidString.lowercased(),
            commandType: .bulkUpdateSubjects,
            galleryId: galleryId,
            idempotencyKey: idempotencyKey ?? UUID().uuidString.lowercased(),
            originatingDeviceId: originatingDeviceId,
            payload: ["subject_ids": subjectIds, "fields": fieldDict],
            sentAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}
