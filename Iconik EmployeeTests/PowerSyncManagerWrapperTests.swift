//
//  PowerSyncManagerWrapperTests.swift
//  Iconik EmployeeTests
//
//  Phase G G.8 (iPad-side) — unit coverage for the Layer 2 wrapper
//  added in G.5: ActiveCaptureSessionTracker on PowerSyncManager
//  + writeBlockedDuringActiveCaptureSession typed error + guards on
//  saveSubject / deleteSubject / deleteBatchSubjects (lock-only writes
//  via releaseExpiredSubjectLocks remain unguarded per Amendment 3).
//
//  Same pbxproj-membership caveat as Phase C's SubjectCommandBuilderTests
//  and Phase D's CommandQueueTests — the file exists on disk but the
//  Iconik EmployeeTests target's .pbxproj doesn't include it yet (per
//  §20.D.6 audit notes, no precedent for the membership pattern in the
//  pre-Phase-C target). The Layer 1 RLS coverage is end-to-end verified
//  on the FP Production side (forced-rollback DO block against live
//  Postgres at G.3 commit time, all 9 scenarios pass), so the iPad-side
//  unit gap is the wrapper's tracker semantics specifically.
//
//  Strategy: we exploit the wrapper guard ordering — the guard fires
//  BEFORE the `guard let db = database` check. So calls without an
//  initialized PowerSync database throw writeBlockedDuringActiveCaptureSession
//  when the gallery is registered, and notInitialized when it's not.
//  The two outcomes give us a binary signal for whether the wrapper is
//  doing its job, without needing a real SQLite to test against.
//

import Testing
// UUID is Foundation's. Without this the whole test TARGET fails to build, which
// takes every other test down with it — the sibling files that use Foundation
// types (CommandQueueTests, SubscriptionCacheTests) already import it. The header
// below predates the project moving to synchronized file groups: the file is no
// longer missing from the target, it is compiled, and that is what surfaced this.
import Foundation
@testable import Iconik_Employee

@MainActor
struct PowerSyncManagerWrapperTests {

    // MARK: - ActiveCaptureSessionTracker

    @Test func beginActiveCaptureSession_registersGallery() {
        let mgr = PowerSyncManager.shared
        let gid = "AAAAAAAA-1111-1111-1111-aaaaaaaaaaaa"
        // Cleanup from any prior test
        mgr.endActiveCaptureSession(galleryId: gid)

        #expect(!mgr.isGalleryInActiveCaptureSession(gid))
        mgr.beginActiveCaptureSession(galleryId: gid)
        #expect(mgr.isGalleryInActiveCaptureSession(gid))

        // Cleanup
        mgr.endActiveCaptureSession(galleryId: gid)
    }

    @Test func endActiveCaptureSession_removesGallery() {
        let mgr = PowerSyncManager.shared
        let gid = "BBBBBBBB-1111-1111-1111-bbbbbbbbbbbb"
        mgr.beginActiveCaptureSession(galleryId: gid)
        #expect(mgr.isGalleryInActiveCaptureSession(gid))

        mgr.endActiveCaptureSession(galleryId: gid)
        #expect(!mgr.isGalleryInActiveCaptureSession(gid))
    }

    @Test func tracker_isCaseInsensitive() {
        let mgr = PowerSyncManager.shared
        let gidUpper = "CCCCCCCC-1111-1111-1111-CCCCCCCCCCCC"
        let gidLower = gidUpper.lowercased()
        mgr.beginActiveCaptureSession(galleryId: gidUpper)
        // Either form should query positive — the tracker normalizes.
        #expect(mgr.isGalleryInActiveCaptureSession(gidUpper))
        #expect(mgr.isGalleryInActiveCaptureSession(gidLower))

        // Cleanup with the other form should still work
        mgr.endActiveCaptureSession(galleryId: gidLower)
        #expect(!mgr.isGalleryInActiveCaptureSession(gidUpper))
    }

    @Test func beginActiveCaptureSession_isIdempotent() {
        let mgr = PowerSyncManager.shared
        let gid = "DDDDDDDD-1111-1111-1111-dddddddddddd"
        mgr.endActiveCaptureSession(galleryId: gid)
        mgr.beginActiveCaptureSession(galleryId: gid)
        mgr.beginActiveCaptureSession(galleryId: gid)
        mgr.beginActiveCaptureSession(galleryId: gid)
        #expect(mgr.isGalleryInActiveCaptureSession(gid))
        // One end call removes the (single) registration regardless of
        // how many times we registered — this is a Set, not a counter.
        mgr.endActiveCaptureSession(galleryId: gid)
        #expect(!mgr.isGalleryInActiveCaptureSession(gid))
    }

    @Test func hasAnyActiveCaptureSession_reflectsTrackerState() {
        let mgr = PowerSyncManager.shared
        let gid1 = "EEEEEEEE-1111-1111-1111-eeeeeeeeeeee"
        let gid2 = "FFFFFFFF-1111-1111-1111-ffffffffffff"
        mgr.endActiveCaptureSession(galleryId: gid1)
        mgr.endActiveCaptureSession(galleryId: gid2)

        // hasAnyActiveCaptureSession should be false initially. We can't
        // assert false here because other tests may leak state if they
        // don't clean up — but we can assert the membership semantics
        // via the round-trip below.
        mgr.beginActiveCaptureSession(galleryId: gid1)
        mgr.beginActiveCaptureSession(galleryId: gid2)
        #expect(mgr.hasAnyActiveCaptureSession)

        mgr.endActiveCaptureSession(galleryId: gid1)
        #expect(mgr.hasAnyActiveCaptureSession) // gid2 still active

        mgr.endActiveCaptureSession(galleryId: gid2)
        // Don't assert false here — other tests/environment may have
        // their own registrations. The positive assertions are the
        // load-bearing ones.
    }

    // MARK: - saveSubject guard

    @Test func saveSubject_throwsBlockedWhenGalleryActive() async {
        let mgr = PowerSyncManager.shared
        let gid = "11111111-2222-3333-4444-555555555555"
        mgr.beginActiveCaptureSession(galleryId: gid)
        defer { mgr.endActiveCaptureSession(galleryId: gid) }

        let subject = FPSubject(
            galleryId: gid,
            organizationId: "test-org"
        )

        do {
            try await mgr.saveSubject(subject)
            Issue.record("Expected saveSubject to throw, but it returned")
        } catch PowerSyncManagerError.writeBlockedDuringActiveCaptureSession(let blockedGid) {
            #expect(blockedGid == gid)
        } catch PowerSyncManagerError.notInitialized {
            Issue.record("Wrong error — got notInitialized, expected writeBlockedDuringActiveCaptureSession (the wrapper guard should fire BEFORE the database guard)")
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func saveSubject_doesNotThrowBlockedWhenGalleryInactive() async {
        let mgr = PowerSyncManager.shared
        let gid = "AAAAAAAA-9999-9999-9999-AAAAAAAAAAAA".lowercased()
        // Ensure no registration
        mgr.endActiveCaptureSession(galleryId: gid)

        let subject = FPSubject(
            galleryId: gid,
            organizationId: "test-org"
        )

        do {
            try await mgr.saveSubject(subject)
            // If the test environment somehow has the database initialized,
            // the call may succeed — that's not a failure of the wrapper.
        } catch PowerSyncManagerError.writeBlockedDuringActiveCaptureSession(let blockedGid) {
            Issue.record("Wrapper threw blocked when gallery \(blockedGid) was NOT registered as active")
        } catch PowerSyncManagerError.notInitialized {
            // Expected when running outside a real PowerSync init context
            // — confirms the wrapper guard let through and the database
            // guard fired next.
        } catch {
            // Any other error (DB error, FK violation, etc.) means the
            // wrapper let through, which is what we're testing here.
        }
    }

    // MARK: - deleteSubject / deleteBatchSubjects guards (id-only paths)

    @Test func deleteSubject_throwsBlockedWhenAnySessionActive() async {
        let mgr = PowerSyncManager.shared
        let activeGid = "DEADBEEF-2222-3333-4444-555555555555"
        let subjectId = UUID()
        mgr.beginActiveCaptureSession(galleryId: activeGid)
        defer { mgr.endActiveCaptureSession(galleryId: activeGid) }

        do {
            try await mgr.deleteSubject(id: subjectId)
            Issue.record("Expected deleteSubject to throw")
        } catch PowerSyncManagerError.writeBlockedDuringActiveCaptureSession {
            // Pass — id-only path refuses conservatively when ANY
            // session is active (no SQL round-trip to discover row's
            // gallery_id, so block on any registration).
        } catch PowerSyncManagerError.notInitialized {
            Issue.record("Wrong error — got notInitialized, expected writeBlockedDuringActiveCaptureSession")
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func deleteBatchSubjects_throwsBlockedWhenAnySessionActive() async {
        let mgr = PowerSyncManager.shared
        let activeGid = "BAADF00D-2222-3333-4444-555555555555"
        mgr.beginActiveCaptureSession(galleryId: activeGid)
        defer { mgr.endActiveCaptureSession(galleryId: activeGid) }

        do {
            try await mgr.deleteBatchSubjects(ids: [UUID(), UUID()])
            Issue.record("Expected deleteBatchSubjects to throw")
        } catch PowerSyncManagerError.writeBlockedDuringActiveCaptureSession {
            // Pass — same conservative refusal as deleteSubject.
        } catch PowerSyncManagerError.notInitialized {
            Issue.record("Wrong error — got notInitialized")
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func deleteBatchSubjects_emptyIdsStillGuards() async {
        let mgr = PowerSyncManager.shared
        let activeGid = "C0FFEE00-2222-3333-4444-555555555555"
        mgr.beginActiveCaptureSession(galleryId: activeGid)
        defer { mgr.endActiveCaptureSession(galleryId: activeGid) }

        do {
            try await mgr.deleteBatchSubjects(ids: [])
            Issue.record("Expected deleteBatchSubjects to throw even on empty ids — wrapper fires before the empty-guard")
        } catch PowerSyncManagerError.writeBlockedDuringActiveCaptureSession {
            // Pass — wrapper guard runs before the empty-ids early-return,
            // so even a no-op call surfaces the contract violation. This
            // is intentional: callers should not be hitting deleteBatchSubjects
            // at all during an active session per Phase G G.6.
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    // MARK: - Lock-column exemption (Amendment 3)

    @Test func releaseExpiredSubjectLocks_isNotGuarded() async {
        // releaseExpiredSubjectLocks is intentionally unguarded by the
        // wrapper — lock columns are control-plane state for multi-device
        // coordination and Phase G Amendment 3 exempts them.
        //
        // We can't easily assert "the call succeeded" because the test
        // environment doesn't have a real database, but we CAN assert
        // that whatever error fires is NOT writeBlockedDuringActiveCaptureSession
        // — i.e., the wrapper guard wasn't invoked.
        let mgr = PowerSyncManager.shared
        let activeGid = "BABEFACE-2222-3333-4444-555555555555"
        mgr.beginActiveCaptureSession(galleryId: activeGid)
        defer { mgr.endActiveCaptureSession(galleryId: activeGid) }

        do {
            try await mgr.releaseExpiredSubjectLocks(forGalleryId: activeGid)
            // Either succeeded (DB initialized in test env) or returned
            // silently (notInitialized treated as no-op per the func's
            // existing `guard let db = database else { return }` shape).
        } catch PowerSyncManagerError.writeBlockedDuringActiveCaptureSession {
            Issue.record("releaseExpiredSubjectLocks should be exempt per Amendment 3 — lock columns are control-plane state. The wrapper must NOT guard this method.")
        } catch {
            // Any non-block error is fine — confirms the wrapper let through.
        }
    }
}
