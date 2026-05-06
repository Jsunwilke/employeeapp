//
//  SubscriptionCacheTests.swift
//  Iconik EmployeeTests
//
//  FROM_SCRATCH_ARCHITECTURE.md §13 Phase H1 — cache substrate coverage.
//  Five named scenarios per the H1 exit criteria:
//    1. Initial hydration from state_sync.
//    2. In-order broadcast advances the cache version monotonically.
//    3. Out-of-order broadcast (version <= tracked) is ignored.
//    4. Drift detection: a gallery_state_summary heartbeat with a
//       last_change_version higher than the cache's tracked version
//       triggers a state_sync request.
//    5. Missed-broadcast recovery: a gap between cache version and
//       Surface heartbeat resolves on the next state_sync.
//
//  Plus parser coverage for the wire-row → FPSubject conversion that
//  state_sync's `subjects` array uses.
//
//  pbxproj-membership gap continues per §20.D.6 + §20.G.7. The file
//  lives on disk; manual Xcode "add to Iconik EmployeeTests target"
//  is required for these to run alongside CommandQueueTests etc. Mac-
//  side counterpart coverage (Surface state_sync builder + version
//  counter + receiver) lives in tests/repositories/state-sync.test.ts
//  and tests/repositories/gallery-version-counter.test.ts (62 tests
//  green at H1 close, exercising the wire shape this iPad cache
//  consumes).
//

import Testing
@testable import Iconik_Employee
import Foundation

struct SubscriptionCacheTests {

    private static let galleryA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    private static let galleryB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

    private func freshCache() -> SubscriptionCache {
        SubscriptionCache.shared._test_reset()
        return SubscriptionCache.shared
    }

    private func makeSubjectRow(
        id: String = UUID().uuidString.lowercased(),
        firstName: String = "Test",
        lastName: String = "Subject",
        galleryId: String = SubscriptionCacheTests.galleryA
    ) -> [String: Any] {
        return [
            "id": id,
            "gallery_id": galleryId,
            "organization_id": "org-1",
            "first_name": firstName,
            "last_name": lastName,
            "grade": "5",
            "teacher": "",
            "homeroom": "",
            "student_id": "",
            "roster_id": "",
            "is_absent": 0,
            "is_photographed": 0,
            "needs_retake": 0,
            "image_count": 0,
            "image_numbers": "",
            "notes": "",
            "created_at": "2026-05-04T00:00:00Z",
            "updated_at": "2026-05-04T00:00:00Z",
        ]
    }

    private func makeFields(firstName: String? = nil, lastName: String? = nil, grade: String? = nil) -> SubjectSyncFields {
        var f = SubjectSyncFields()
        f.firstName = firstName
        f.lastName = lastName
        f.grade = grade
        return f
    }

    // MARK: - Scenario 1: Initial hydration from state_sync

    @Test func appliesStateSyncHydration() {
        let cache = freshCache()
        let s1 = makeSubjectRow(firstName: "Alice", lastName: "Adams")
        let s2 = makeSubjectRow(firstName: "Bob", lastName: "Brown")
        let s3 = makeSubjectRow(firstName: "Carol", lastName: "Connor")

        cache.applyStateSync(galleryId: Self.galleryA, currentVersion: 10, subjects: [s1, s2, s3])
        cache._test_waitForPendingMutations()

        let snapshot = cache.subjects(forGalleryId: Self.galleryA)
        #expect(snapshot.count == 3)
        #expect(cache.lastVersion(forGalleryId: Self.galleryA) == 10)
        // Sorted by lastName ascending
        #expect(snapshot[0].lastName == "Adams")
        #expect(snapshot[1].lastName == "Brown")
        #expect(snapshot[2].lastName == "Connor")
    }

    @Test func stateSyncReplacesExistingState() {
        // A second state_sync arriving (e.g. on reconnect) wholesale
        // replaces the prior subject set so a removed subject doesn't
        // ghost in the cache.
        let cache = freshCache()
        let aliceRow = makeSubjectRow(firstName: "Alice", lastName: "Adams")
        let bobRow = makeSubjectRow(firstName: "Bob", lastName: "Brown")
        cache.applyStateSync(galleryId: Self.galleryA, currentVersion: 5, subjects: [aliceRow, bobRow])
        cache._test_waitForPendingMutations()
        #expect(cache.subjects(forGalleryId: Self.galleryA).count == 2)

        // Reconnect: only Alice now (Bob was deleted between sessions).
        cache.applyStateSync(galleryId: Self.galleryA, currentVersion: 12, subjects: [aliceRow])
        cache._test_waitForPendingMutations()

        let snapshot = cache.subjects(forGalleryId: Self.galleryA)
        #expect(snapshot.count == 1)
        #expect(snapshot[0].lastName == "Adams")
        #expect(cache.lastVersion(forGalleryId: Self.galleryA) == 12)
    }

    // MARK: - Scenario 2: In-order broadcast advances version monotonically

    @Test func inOrderBroadcastsAdvanceVersion() {
        let cache = freshCache()
        let row = makeSubjectRow(firstName: "Alice", lastName: "Adams")
        cache.applyStateSync(galleryId: Self.galleryA, currentVersion: 10, subjects: [row])
        cache._test_waitForPendingMutations()

        let subjectId = UUID(uuidString: row["id"] as! String)!

        cache.applyBroadcast(.subjectUpdated(
            galleryId: Self.galleryA,
            subjectId: subjectId,
            fields: makeFields(firstName: "Alicia"),
            version: 11
        ))
        cache._test_waitForPendingMutations()
        #expect(cache.lastVersion(forGalleryId: Self.galleryA) == 11)
        #expect(cache.subjects(forGalleryId: Self.galleryA).first?.firstName == "Alicia")

        cache.applyBroadcast(.subjectUpdated(
            galleryId: Self.galleryA,
            subjectId: subjectId,
            fields: makeFields(grade: "6"),
            version: 12
        ))
        cache._test_waitForPendingMutations()
        #expect(cache.lastVersion(forGalleryId: Self.galleryA) == 12)
        #expect(cache.subjects(forGalleryId: Self.galleryA).first?.grade == "6")
        // First-name change from version 11 is preserved.
        #expect(cache.subjects(forGalleryId: Self.galleryA).first?.firstName == "Alicia")
    }

    // MARK: - Scenario 3: Out-of-order broadcasts ignored

    @Test func outOfOrderBroadcastIsIgnored() {
        let cache = freshCache()
        let row = makeSubjectRow(firstName: "Alice", lastName: "Adams")
        cache.applyStateSync(galleryId: Self.galleryA, currentVersion: 10, subjects: [row])
        cache._test_waitForPendingMutations()

        let subjectId = UUID(uuidString: row["id"] as! String)!

        // Advance to version 15.
        cache.applyBroadcast(.subjectUpdated(
            galleryId: Self.galleryA,
            subjectId: subjectId,
            fields: makeFields(firstName: "Alicia"),
            version: 15
        ))
        cache._test_waitForPendingMutations()
        #expect(cache.lastVersion(forGalleryId: Self.galleryA) == 15)

        // Out-of-order broadcast at version 12 must NOT reset firstName.
        cache.applyBroadcast(.subjectUpdated(
            galleryId: Self.galleryA,
            subjectId: subjectId,
            fields: makeFields(firstName: "STALE"),
            version: 12
        ))
        cache._test_waitForPendingMutations()
        #expect(cache.lastVersion(forGalleryId: Self.galleryA) == 15)
        #expect(cache.subjects(forGalleryId: Self.galleryA).first?.firstName == "Alicia")

        // Duplicate at the same version is also dropped.
        cache.applyBroadcast(.subjectUpdated(
            galleryId: Self.galleryA,
            subjectId: subjectId,
            fields: makeFields(firstName: "DUP"),
            version: 15
        ))
        cache._test_waitForPendingMutations()
        #expect(cache.subjects(forGalleryId: Self.galleryA).first?.firstName == "Alicia")
    }

    // MARK: - Scenario 4: Drift detection triggers state_sync request

    @Test func driftHeartbeatTriggersStateSyncRequest() async {
        let cache = freshCache()
        let row = makeSubjectRow(firstName: "Alice", lastName: "Adams")
        cache.applyStateSync(galleryId: Self.galleryA, currentVersion: 10, subjects: [row])
        cache._test_waitForPendingMutations()

        // Capture drift requests via a mock sender.
        let captured = DriftCaptured()
        cache.setDriftRequestSender { galleryId, lastVersion in
            captured.append((galleryId, lastVersion))
        }
        cache._test_waitForPendingMutations()

        // Surface heartbeat says version 18; cache is at 10. Drift.
        cache.checkDrift(galleryId: Self.galleryA, surfaceVersion: 18)

        // checkDrift hops off the serial queue to invoke the sender —
        // wait for the dispatch to land before asserting.
        try? await Task.sleep(nanoseconds: 100_000_000)

        let calls = captured.snapshot()
        #expect(calls.count == 1)
        #expect(calls.first?.0 == Self.galleryA)
        #expect(calls.first?.1 == 10)
    }

    @Test func aheadOrEqualHeartbeatDoesNotTriggerRequest() async {
        let cache = freshCache()
        let row = makeSubjectRow()
        cache.applyStateSync(galleryId: Self.galleryA, currentVersion: 20, subjects: [row])
        cache._test_waitForPendingMutations()

        let captured = DriftCaptured()
        cache.setDriftRequestSender { galleryId, lastVersion in
            captured.append((galleryId, lastVersion))
        }
        cache._test_waitForPendingMutations()

        // Surface caught up but not ahead — no request.
        cache.checkDrift(galleryId: Self.galleryA, surfaceVersion: 20)
        // Surface behind cache — also no request (shouldn't happen in
        // production but defensive against clock drift edge cases).
        cache.checkDrift(galleryId: Self.galleryA, surfaceVersion: 15)

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(captured.snapshot().isEmpty)
    }

    @Test func driftRequestIsThrottledPerGallery() async {
        let cache = freshCache()
        let row = makeSubjectRow()
        cache.applyStateSync(galleryId: Self.galleryA, currentVersion: 10, subjects: [row])
        cache._test_waitForPendingMutations()

        let captured = DriftCaptured()
        cache.setDriftRequestSender { galleryId, lastVersion in
            captured.append((galleryId, lastVersion))
        }
        cache._test_waitForPendingMutations()

        // Three back-to-back heartbeats while drift is unresolved should
        // produce only ONE request — the cache throttles via a pending
        // set so we don't flood Surface with redundant state_sync rebuilds.
        cache.checkDrift(galleryId: Self.galleryA, surfaceVersion: 25)
        cache.checkDrift(galleryId: Self.galleryA, surfaceVersion: 26)
        cache.checkDrift(galleryId: Self.galleryA, surfaceVersion: 27)

        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(captured.snapshot().count == 1)

        // Once the next state_sync arrives (clearing the pending flag),
        // a subsequent drift heartbeat triggers a new request.
        cache.applyStateSync(galleryId: Self.galleryA, currentVersion: 27, subjects: [row])
        cache._test_waitForPendingMutations()
        cache.checkDrift(galleryId: Self.galleryA, surfaceVersion: 30)
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(captured.snapshot().count == 2)
    }

    // MARK: - Scenario 5: Missed-broadcast recovery via state_sync

    @Test func missedBroadcastsRecoveredByStateSync() {
        // Cache hydrates at version 10 with one subject.
        let cache = freshCache()
        let aliceId = UUID().uuidString.lowercased()
        let aliceRow = makeSubjectRow(id: aliceId, firstName: "Alice", lastName: "Adams")
        cache.applyStateSync(galleryId: Self.galleryA, currentVersion: 10, subjects: [aliceRow])
        cache._test_waitForPendingMutations()
        #expect(cache.subjects(forGalleryId: Self.galleryA).count == 1)
        #expect(cache.lastVersion(forGalleryId: Self.galleryA) == 10)

        // Imagine versions 11-19 happened on Surface but got dropped
        // before reaching the iPad (network blip). Drift detection
        // would normally fire, but here we simulate it directly:
        // Surface returns a state_sync at version 20 with two new
        // subjects added during the gap.
        let bobRow = makeSubjectRow(firstName: "Bob", lastName: "Brown")
        let carolRow = makeSubjectRow(firstName: "Carol", lastName: "Connor")
        cache.applyStateSync(galleryId: Self.galleryA, currentVersion: 20, subjects: [aliceRow, bobRow, carolRow])
        cache._test_waitForPendingMutations()

        let snapshot = cache.subjects(forGalleryId: Self.galleryA)
        #expect(snapshot.count == 3)
        #expect(snapshot[0].lastName == "Adams")
        #expect(snapshot[1].lastName == "Brown")
        #expect(snapshot[2].lastName == "Connor")
        #expect(cache.lastVersion(forGalleryId: Self.galleryA) == 20)
    }

    // MARK: - Gallery scoping

    @Test func switchingCurrentGalleryDropsPriorState() {
        let cache = freshCache()
        cache.setCurrentGallery(Self.galleryA)
        let row = makeSubjectRow(galleryId: Self.galleryA)
        cache.applyStateSync(galleryId: Self.galleryA, currentVersion: 5, subjects: [row])
        cache._test_waitForPendingMutations()
        #expect(cache.subjects(forGalleryId: Self.galleryA).count == 1)

        cache.setCurrentGallery(Self.galleryB)
        cache._test_waitForPendingMutations()
        // Switching gallery clears the previous gallery's state so a
        // stale snapshot doesn't survive the join transition.
        #expect(cache.subjects(forGalleryId: Self.galleryA).isEmpty)
        #expect(cache.lastVersion(forGalleryId: Self.galleryA) == 0)
    }

    // MARK: - Subject delete via broadcast

    @Test func subjectsDeletedBroadcastRemovesRow() {
        let cache = freshCache()
        let aliceId = UUID().uuidString.lowercased()
        let aliceRow = makeSubjectRow(id: aliceId, firstName: "Alice", lastName: "Adams")
        let bobRow = makeSubjectRow(firstName: "Bob", lastName: "Brown")
        cache.applyStateSync(galleryId: Self.galleryA, currentVersion: 10, subjects: [aliceRow, bobRow])
        cache._test_waitForPendingMutations()

        let aliceUUID = UUID(uuidString: aliceId)!
        cache.applyBroadcast(.subjectsDeleted(
            galleryId: Self.galleryA,
            subjectIds: [aliceUUID],
            version: 11
        ))
        cache._test_waitForPendingMutations()

        let snapshot = cache.subjects(forGalleryId: Self.galleryA)
        #expect(snapshot.count == 1)
        #expect(snapshot.first?.lastName == "Brown")
        #expect(cache.lastVersion(forGalleryId: Self.galleryA) == 11)
    }

    // MARK: - Capture broadcasts

    @Test func captureCompletedBroadcastIsStored() {
        let cache = freshCache()
        let captureId = "capture-1"
        let event = FPCaptureEvent(
            subjectId: UUID().uuidString.lowercased(),
            rosterEntryId: nil,
            imageNumber: 42,
            captureFilename: "img-001.jpg",
            stationName: "Camera A",
            fromDeviceId: "device-1"
        )
        cache.applyBroadcast(.captureCompleted(
            galleryId: Self.galleryA,
            captureId: captureId,
            event: event,
            version: 5
        ))
        cache._test_waitForPendingMutations()

        let captures = cache.captures(forGalleryId: Self.galleryA)
        #expect(captures.count == 1)
        #expect(captures.first?.imageNumber == 42)
        #expect(cache.lastVersion(forGalleryId: Self.galleryA) == 5)
    }

    // MARK: - Wire-row parser

    @Test func parserHandlesCompleteRow() {
        let id = UUID().uuidString.lowercased()
        let row: [String: Any] = [
            "id": id,
            "gallery_id": Self.galleryA,
            "organization_id": "org-1",
            "first_name": "Alice",
            "last_name": "Adams",
            "grade": "5",
            "teacher": "Ms. Brown",
            "image_count": 3,
            "is_absent": 1,
            "is_photographed": 0,
            "needs_retake": 1,
            "custom1": "X",
            "custom20": "Y",
            "image_numbers": "1;2;3",
            "created_at": "2026-05-04T10:00:00Z",
            "updated_at": "2026-05-04T11:00:00Z",
        ]
        let parsed = SubscriptionCache._parseSubjectFromWire(row)
        #expect(parsed != nil)
        #expect(parsed?.firstName == "Alice")
        #expect(parsed?.lastName == "Adams")
        #expect(parsed?.grade == "5")
        #expect(parsed?.teacher == "Ms. Brown")
        #expect(parsed?.imageCount == 3)
        #expect(parsed?.isAbsent == true)
        #expect(parsed?.isPhotographed == false)
        #expect(parsed?.needsRetake == true)
        #expect(parsed?.custom1 == "X")
        #expect(parsed?.custom20 == "Y")
        #expect(parsed?.imageNumbers == "1;2;3")
    }

    @Test func parserHandlesMissingOptionalFields() {
        let id = UUID().uuidString.lowercased()
        // Minimal row — no custom fields, no contact info, no defaults.
        let row: [String: Any] = [
            "id": id,
            "gallery_id": Self.galleryA,
            "first_name": "Bob",
            "last_name": "",
        ]
        let parsed = SubscriptionCache._parseSubjectFromWire(row)
        #expect(parsed != nil)
        #expect(parsed?.firstName == "Bob")
        #expect(parsed?.lastName == "")
        #expect(parsed?.custom1 == "")
        #expect(parsed?.email == "")
        #expect(parsed?.imageCount == 0)
        #expect(parsed?.isAbsent == false)
    }

    @Test func parserRejectsRowWithNoUsableId() {
        let row: [String: Any] = [
            "first_name": "Anonymous",
            "last_name": "Subject",
        ]
        let parsed = SubscriptionCache._parseSubjectFromWire(row)
        #expect(parsed == nil)
    }

    @Test func parserAcceptsBoolFieldsAsIntOrBool() {
        let id = UUID().uuidString.lowercased()
        // Surface PowerSync schema declares is_absent as integer; PowerSync
        // sometimes serializes as Int 0/1, sometimes as a String "1", and
        // some receivers may emit Bool. Defensive parsing covers all three.
        let intRow: [String: Any] = [
            "id": id,
            "gallery_id": Self.galleryA,
            "is_absent": 1,
        ]
        #expect(SubscriptionCache._parseSubjectFromWire(intRow)?.isAbsent == true)

        let boolRow: [String: Any] = [
            "id": id,
            "gallery_id": Self.galleryA,
            "is_absent": true,
        ]
        #expect(SubscriptionCache._parseSubjectFromWire(boolRow)?.isAbsent == true)

        let stringRow: [String: Any] = [
            "id": id,
            "gallery_id": Self.galleryA,
            "is_absent": "1",
        ]
        #expect(SubscriptionCache._parseSubjectFromWire(stringRow)?.isAbsent == true)
    }
}

/// Test helper: thread-safe ordered list of drift-request invocations.
/// Drift requests fire on a global queue; tests collect them via this
/// helper so assertions don't race the scheduler.
private final class DriftCaptured {
    private let serial = DispatchQueue(label: "test.drift-captured")
    private var calls: [(String, Int)] = []

    func append(_ entry: (String, Int)) {
        serial.sync { calls.append(entry) }
    }

    func snapshot() -> [(String, Int)] {
        return serial.sync { calls }
    }
}
