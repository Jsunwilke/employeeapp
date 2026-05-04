//
//  SubjectCommandBuilderTests.swift
//  Iconik EmployeeTests
//
//  Phase C C.7 — unit coverage for the new factory functions added to
//  SubjectCommandBuilder + the FPSubject↔wire helpers on SubjectSyncService.
//
//  The receiver-side handlers these wire shapes feed are covered on the
//  Mac side by tests/repositories/surface-command-receiver.test.ts (32
//  tests, all green at Phase C kickoff per the C.7 verification step).
//  These iPad-side tests confirm the factory output matches the wire
//  shape the receiver consumes — the matching pair completes the
//  end-to-end coverage Phase C C.7 requires.
//
//  SubjectSyncService.{create,delete,batchCreate,batchUpdate}Subjects
//  themselves are not exercised here — they depend on
//  FocalPointSyncClient.shared and PowerSyncManager.shared singletons
//  that aren't injectable. End-to-end behavior verification lives in
//  the C.9 field-test smoke (operator-run, not in this file).
//

import Testing
@testable import Iconik_Employee

struct SubjectCommandBuilderTests {

    // MARK: - .create

    @Test func create_producesInsertSubjectsWireShape() throws {
        let cmd = SubjectCommandBuilder.create(
            galleryId: "g1",
            row: ["first_name": "Alice", "last_name": "Anderson", "roster_id": "101"],
            originatingDeviceId: "ipad-1"
        )

        #expect(cmd.commandType == .insertSubjects)
        #expect(cmd.galleryId == "g1")
        #expect(cmd.originatingDeviceId == "ipad-1")
        #expect(!cmd.commandId.isEmpty)
        #expect(!cmd.idempotencyKey.isEmpty)

        let wire = cmd.toWireDictionary()
        #expect(wire["type"] as? String == "subject_command")
        #expect(wire["command_type"] as? String == "insert_subjects")
        #expect(wire["gallery_id"] as? String == "g1")
        #expect(wire["originating_device_id"] as? String == "ipad-1")

        let payload = wire["payload"] as? [String: Any]
        let rows = payload?["rows"] as? [[String: Any]]
        #expect(rows?.count == 1)
        #expect(rows?[0]["first_name"] as? String == "Alice")
        #expect(rows?[0]["roster_id"] as? String == "101")
    }

    @Test func create_acceptsCallerIdempotencyKey() throws {
        let cmd = SubjectCommandBuilder.create(
            galleryId: "g1",
            row: ["first_name": "A"],
            originatingDeviceId: "ipad-1",
            idempotencyKey: "fixed-key-123"
        )
        #expect(cmd.idempotencyKey == "fixed-key-123")
    }

    // MARK: - .batchCreate

    @Test func batchCreate_packsAllRowsInOnePayload() throws {
        let rows: [[String: Any]] = [
            ["first_name": "A"],
            ["first_name": "B"],
            ["first_name": "C"],
        ]
        let cmd = SubjectCommandBuilder.batchCreate(
            galleryId: "g1",
            rows: rows,
            originatingDeviceId: "ipad-1"
        )

        #expect(cmd.commandType == .insertSubjects)

        let wire = cmd.toWireDictionary()
        #expect(wire["command_type"] as? String == "insert_subjects")
        let payload = wire["payload"] as? [String: Any]
        let outRows = payload?["rows"] as? [[String: Any]]
        #expect(outRows?.count == 3)
        #expect(outRows?[0]["first_name"] as? String == "A")
        #expect(outRows?[2]["first_name"] as? String == "C")
    }

    @Test func batchCreate_emptyRowsStillProducesValidCommand() throws {
        let cmd = SubjectCommandBuilder.batchCreate(
            galleryId: "g1",
            rows: [],
            originatingDeviceId: "ipad-1"
        )
        let wire = cmd.toWireDictionary()
        let rows = (wire["payload"] as? [String: Any])?["rows"] as? [[String: Any]]
        #expect(rows?.isEmpty == true)
    }

    // MARK: - .delete

    @Test func delete_producesSoftDeleteSubjectWireShape() throws {
        let cmd = SubjectCommandBuilder.delete(
            galleryId: "g1",
            subjectId: "abcd-uuid",
            originatingDeviceId: "ipad-1"
        )

        #expect(cmd.commandType == .softDeleteSubject)
        let wire = cmd.toWireDictionary()
        #expect(wire["command_type"] as? String == "soft_delete_subject")
        let payload = wire["payload"] as? [String: Any]
        #expect(payload?["subject_id"] as? String == "abcd-uuid")
    }

    // MARK: - .batchUpdate

    @Test func batchUpdate_producesBulkUpdateSubjectsWireShape() throws {
        var fields = SubjectSyncFields()
        fields.isAbsent = true
        fields.notes = "checked in late"

        let cmd = try SubjectCommandBuilder.batchUpdate(
            galleryId: "g1",
            subjectIds: ["s1", "s2", "s3"],
            fields: fields,
            originatingDeviceId: "ipad-1"
        )

        #expect(cmd.commandType == .bulkUpdateSubjects)
        let wire = cmd.toWireDictionary()
        #expect(wire["command_type"] as? String == "bulk_update_subjects")

        let payload = wire["payload"] as? [String: Any]
        let ids = payload?["subject_ids"] as? [String]
        #expect(ids == ["s1", "s2", "s3"])

        let outFields = payload?["fields"] as? [String: Any]
        #expect(outFields?["is_absent"] as? Bool == true)
        #expect(outFields?["notes"] as? String == "checked in late")
    }

    @Test func batchUpdate_omitsNilFieldsOnTheWire() throws {
        // Only firstName is set; every other property is nil. The wire
        // payload's `fields` dict should only carry the keys that were
        // actually set — verifies SubjectSyncFields' default Codable
        // behavior strips nil-valued keys, which is what makes
        // UPDATABLE_SUBJECT_FIELDS-allowlist sanitization on the receiver
        // a no-op for unset fields.
        var fields = SubjectSyncFields()
        fields.firstName = "Onlyname"
        let cmd = try SubjectCommandBuilder.batchUpdate(
            galleryId: "g1",
            subjectIds: ["s1"],
            fields: fields,
            originatingDeviceId: "ipad-1"
        )
        let wire = cmd.toWireDictionary()
        let payload = wire["payload"] as? [String: Any]
        let outFields = payload?["fields"] as? [String: Any]
        #expect(outFields?["first_name"] as? String == "Onlyname")
        #expect(outFields?.keys.contains("last_name") == false)
        #expect(outFields?.keys.contains("notes") == false)
    }

    // MARK: - .batchDelete (Phase G G.6 — Phase C tail substrate)

    @Test func batchDelete_producesBulkDeleteSubjectsWireShape() throws {
        let cmd = SubjectCommandBuilder.batchDelete(
            galleryId: "g1",
            subjectIds: ["s1", "s2", "s3"],
            originatingDeviceId: "ipad-1"
        )

        #expect(cmd.commandType == .bulkDeleteSubjects)
        #expect(cmd.galleryId == "g1")
        #expect(cmd.originatingDeviceId == "ipad-1")
        #expect(!cmd.commandId.isEmpty)
        #expect(!cmd.idempotencyKey.isEmpty)

        let wire = cmd.toWireDictionary()
        #expect(wire["type"] as? String == "subject_command")
        #expect(wire["command_type"] as? String == "bulk_delete_subjects")
        #expect(wire["gallery_id"] as? String == "g1")

        let payload = wire["payload"] as? [String: Any]
        let ids = payload?["subject_ids"] as? [String]
        #expect(ids == ["s1", "s2", "s3"])
        // No `fields` on the delete payload — the receiver schema only
        // accepts subject_ids for bulk_delete_subjects (see
        // surface-command-receiver.ts:332-336).
        #expect(payload?.keys.contains("fields") == false)
    }

    @Test func batchDelete_acceptsCallerIdempotencyKey() throws {
        let cmd = SubjectCommandBuilder.batchDelete(
            galleryId: "g1",
            subjectIds: ["s1"],
            originatingDeviceId: "ipad-1",
            idempotencyKey: "fixed-batch-delete-key"
        )
        #expect(cmd.idempotencyKey == "fixed-batch-delete-key")
    }

    @Test func batchDelete_emptyIdsStillProducesValidCommand() throws {
        // Mirrors batchCreate_emptyRowsStillProducesValidCommand —
        // empty input is the caller's contract violation, not the
        // builder's. The receiver will reject ([] fails the
        // validate_uuid_array shape check in
        // surface-command-receiver.ts:333).
        let cmd = SubjectCommandBuilder.batchDelete(
            galleryId: "g1",
            subjectIds: [],
            originatingDeviceId: "ipad-1"
        )
        let wire = cmd.toWireDictionary()
        let payload = wire["payload"] as? [String: Any]
        let ids = payload?["subject_ids"] as? [String]
        #expect(ids?.isEmpty == true)
    }

    // MARK: - SubjectSyncService.insertRowDictionary

    @Test func insertRowDictionary_carriesEditableFieldsInSnakeCase() throws {
        let subject = FPSubject(
            galleryId: "g1",
            organizationId: "org1",
            firstName: "Alice",
            lastName: "Anderson",
            grade: "5",
            teacher: "MS_SMITH",
            homeroom: "101",
            studentId: "STU-1",
            rosterId: "1001",
            jerseyNumber: "7",
            sport: "BASKETBALL",
            position: "PG",
            email: "alice@example.com",
            phone: "555-1212",
            imageNumbers: "12;13;14"
        )

        let row = SubjectSyncService.insertRowDictionary(from: subject)

        #expect(row["organization_id"] as? String == "org1")
        #expect(row["first_name"] as? String == "Alice")
        #expect(row["last_name"] as? String == "Anderson")
        #expect(row["grade"] as? String == "5")
        #expect(row["sport"] as? String == "BASKETBALL")
        #expect(row["roster_id"] as? String == "1001")
        #expect(row["jersey_number"] as? String == "7")
        #expect(row["email"] as? String == "alice@example.com")
        #expect(row["image_numbers"] as? String == "12;13;14")
    }

    @Test func insertRowDictionary_excludesForbiddenStructuralKeys() throws {
        let subject = FPSubject(galleryId: "g1", organizationId: "org1", firstName: "A", lastName: "B")
        let row = SubjectSyncService.insertRowDictionary(from: subject)
        // The receiver force-overrides gallery_id from cmd.gallery_id and
        // strips id/created_at/updated_at/last_originating_device_id/etc.
        // — for wire hygiene we omit those up front.
        #expect(row.keys.contains("id") == false)
        #expect(row.keys.contains("gallery_id") == false)
        #expect(row.keys.contains("created_at") == false)
        #expect(row.keys.contains("updated_at") == false)
        #expect(row.keys.contains("locked_by") == false)
        #expect(row.keys.contains("is_deleted") == false)
    }

    // MARK: - SubjectSyncService.fieldsFromFullSubject

    @Test func fieldsFromFullSubject_carriesEverySubjectSyncField() throws {
        let subject = FPSubject(
            galleryId: "g1",
            organizationId: "org1",
            firstName: "Alice",
            lastName: "Anderson",
            grade: "5",
            teacher: "MS_SMITH",
            homeroom: "101",
            studentId: "STU-1",
            rosterId: "1001",
            jerseyNumber: "7",
            sport: "BASKETBALL",
            position: "PG"
        )

        let fields = SubjectSyncService.fieldsFromFullSubject(subject)

        #expect(fields.firstName == "Alice")
        #expect(fields.lastName == "Anderson")
        #expect(fields.grade == "5")
        #expect(fields.teacher == "MS_SMITH")
        #expect(fields.homeroom == "101")
        #expect(fields.studentId == "STU-1")
        #expect(fields.rosterId == "1001")
        #expect(fields.jerseyNumber == "7")
        #expect(fields.sport == "BASKETBALL")
        #expect(fields.position == "PG")
    }

    @Test func fieldsFromFullSubject_isInverseOfApplyFieldsToSubject() throws {
        let original = FPSubject(
            galleryId: "g1",
            organizationId: "org1",
            firstName: "Alice",
            lastName: "Anderson",
            grade: "5"
        )
        let fields = SubjectSyncService.fieldsFromFullSubject(original)
        // Apply onto a different base — should overwrite every editable
        // field back to original's values. Inverse round-trip property
        // is what makes the helper safe to use in the migration sites
        // that previously passed full FPSubjects through PowerSync.
        let blank = FPSubject(galleryId: "g1", organizationId: "org1")
        let recovered = SubjectSyncService.applyFieldsToSubject(fields, base: blank)

        #expect(recovered.firstName == "Alice")
        #expect(recovered.lastName == "Anderson")
        #expect(recovered.grade == "5")
    }
}
