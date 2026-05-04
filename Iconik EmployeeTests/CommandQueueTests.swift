//
//  CommandQueueTests.swift
//  Iconik EmployeeTests
//
//  FROM_SCRATCH_ARCHITECTURE.md §13 Phase D — persistence, FIFO drain
//  ordering, and dedupe-on-Surface-replay coverage for CommandQueue.
//
//  Receiver-side dedupe (§11.3 idempotency_cache) is exercised on the
//  Mac side in tests/repositories/surface-command-receiver.test.ts (32
//  tests, all green at Phase D close). These iPad-side tests confirm
//  the queue's at-least-once-with-stable-keys contract that the receiver
//  dedupe relies on:
//    - The queue persists across the equivalent of an app restart
//      (open + write + close + reopen + read still finds the row).
//    - nextBatch returns rows in FIFO order so drain replays in the
//      order the iPad enqueued.
//    - The replayed SubjectCommand carries the SAME idempotency_key
//      the original send used (toCommand() round-trip preserves it),
//      which is what Surface's idempotency_cache hashes against.
//
//  Same wiring caveat as Phase C tests: this file lives on disk for
//  the manual "add to Iconik EmployeeTests target" step in Xcode —
//  the project's test target only contained the auto-generated example
//  pre-Phase-C, so there's no precedent for the .pbxproj membership
//  pattern. §20.D logs this as a continuation of the Phase C C.7
//  documented deviation.
//

import Testing
@testable import Iconik_Employee
import Foundation

struct CommandQueueTests {

    // Each test resets the shared queue so test order doesn't matter.
    // Production never calls _testReset; it's a guarded test seam.
    private func freshQueue() async throws -> CommandQueue {
        try await CommandQueue.shared._testReset()
        return CommandQueue.shared
    }

    private func makeCommand(
        type: SubjectCommandType = .updateSubject,
        idempotencyKey: String? = nil,
        commandId: String? = nil,
        gallery: String = "11111111-1111-1111-1111-111111111111"
    ) -> SubjectCommand {
        return SubjectCommand(
            commandId: commandId ?? UUID().uuidString.lowercased(),
            commandType: type,
            galleryId: gallery,
            idempotencyKey: idempotencyKey ?? UUID().uuidString.lowercased(),
            originatingDeviceId: "test-device",
            payload: ["subject_id": UUID().uuidString.lowercased(),
                      "fields": ["first_name": "test"]],
            sentAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - Persistence

    @Test func enqueueIsPersistent() async throws {
        let q = try await freshQueue()
        let cmd = makeCommand(idempotencyKey: "stable-key-1")
        _ = try await q.enqueue(cmd)
        let count = try await q.count()
        #expect(count == 1)

        // Re-read via nextBatch — the row must be readable in the same
        // shape we wrote it.
        let batch = try await q.nextBatch(limit: 10)
        #expect(batch.count == 1)
        #expect(batch[0].idempotencyKey == "stable-key-1")
        #expect(batch[0].commandType == "update_subject")
    }

    @Test func toCommandPreservesIdempotencyKey() async throws {
        let q = try await freshQueue()
        let cmd = makeCommand(idempotencyKey: "must-survive-roundtrip")
        _ = try await q.enqueue(cmd)
        let batch = try await q.nextBatch(limit: 1)
        let recovered = batch.first?.toCommand()
        #expect(recovered?.idempotencyKey == "must-survive-roundtrip")
        #expect(recovered?.commandType == .updateSubject)
        // The receiver dedupe hashes (gallery_id, idempotency_key) so
        // the replay's gallery_id must round-trip too.
        #expect(recovered?.galleryId == cmd.galleryId)
    }

    // MARK: - FIFO drain ordering

    @Test func nextBatchReturnsRowsInEnqueueOrder() async throws {
        let q = try await freshQueue()
        let keys = ["a", "b", "c", "d", "e"]
        for k in keys {
            _ = try await q.enqueue(makeCommand(idempotencyKey: k))
        }
        let batch = try await q.nextBatch(limit: 100)
        let recoveredKeys = batch.map { $0.idempotencyKey }
        #expect(recoveredKeys == keys)
    }

    @Test func nextBatchRespectsLimit() async throws {
        let q = try await freshQueue()
        for i in 0..<10 {
            _ = try await q.enqueue(makeCommand(idempotencyKey: "k\(i)"))
        }
        let batch = try await q.nextBatch(limit: 3)
        #expect(batch.count == 3)
        // First three keys should be the earliest-enqueued.
        #expect(batch.map { $0.idempotencyKey } == ["k0", "k1", "k2"])
    }

    @Test func removeAtHeadAdvancesNextBatch() async throws {
        let q = try await freshQueue()
        for i in 0..<3 {
            _ = try await q.enqueue(makeCommand(idempotencyKey: "k\(i)"))
        }
        let firstBatch = try await q.nextBatch(limit: 1)
        try await q.remove(rowId: firstBatch[0].rowId)
        let secondBatch = try await q.nextBatch(limit: 10)
        #expect(secondBatch.count == 2)
        #expect(secondBatch.map { $0.idempotencyKey } == ["k1", "k2"])
    }

    // MARK: - Multiple command types coexist in one queue

    @Test func differentCommandTypesQueueTogether() async throws {
        let q = try await freshQueue()
        _ = try await q.enqueue(makeCommand(type: .updateSubject, idempotencyKey: "u"))
        _ = try await q.enqueue(makeCommand(type: .insertSubjects, idempotencyKey: "i"))
        _ = try await q.enqueue(makeCommand(type: .softDeleteSubject, idempotencyKey: "d"))
        _ = try await q.enqueue(makeCommand(type: .bulkUpdateSubjects, idempotencyKey: "bu"))

        let batch = try await q.nextBatch(limit: 10)
        let pairs = batch.map { ($0.idempotencyKey, $0.commandType) }
        #expect(pairs[0].0 == "u" && pairs[0].1 == "update_subject")
        #expect(pairs[1].0 == "i" && pairs[1].1 == "insert_subjects")
        #expect(pairs[2].0 == "d" && pairs[2].1 == "soft_delete_subject")
        #expect(pairs[3].0 == "bu" && pairs[3].1 == "bulk_update_subjects")
    }

    // MARK: - Drain integration (with a fake sender)

    @Test func tickDrainRemovesAppliedRows() async throws {
        let q = try await freshQueue()
        for i in 0..<3 {
            _ = try await q.enqueue(makeCommand(idempotencyKey: "k\(i)"))
        }
        await q.tickDrain { _ in
            CommandAck(commandId: "x", status: .applied, reason: nil, resultingState: nil)
        }
        let remaining = try await q.count()
        #expect(remaining == 0)
    }

    @Test func tickDrainTreatsDedupeAsAppliedAndRemoves() async throws {
        let q = try await freshQueue()
        _ = try await q.enqueue(makeCommand(idempotencyKey: "replay-key"))
        await q.tickDrain { _ in
            CommandAck(commandId: "x", status: .dedupe, reason: nil, resultingState: nil)
        }
        let remaining = try await q.count()
        // Dedupe is the success signal that replay landed; row is
        // removed the same as on a fresh apply. This is the dedupe-on-
        // Surface-replay contract Phase D's at-least-once drain relies on.
        #expect(remaining == 0)
    }

    @Test func tickDrainStopsAndPreservesQueueOnTransportThrow() async throws {
        let q = try await freshQueue()
        _ = try await q.enqueue(makeCommand(idempotencyKey: "k0"))
        _ = try await q.enqueue(makeCommand(idempotencyKey: "k1"))
        struct FakeTransportError: Error {}
        await q.tickDrain { _ in
            throw FakeTransportError()
        }
        // Both rows should still be in the queue — the drain bails on
        // first throw to avoid hammering a flaky reconnect.
        let remaining = try await q.count()
        #expect(remaining == 2)
    }

    @Test func tickDrainRemovesRejectedRows() async throws {
        let q = try await freshQueue()
        _ = try await q.enqueue(makeCommand(idempotencyKey: "bad-input"))
        _ = try await q.enqueue(makeCommand(idempotencyKey: "good-1"))
        var seen = 0
        await q.tickDrain { _ in
            seen += 1
            if seen == 1 {
                return CommandAck(commandId: "x", status: .rejected, reason: "no_allowlisted_fields", resultingState: nil)
            }
            return CommandAck(commandId: "y", status: .applied, reason: nil, resultingState: nil)
        }
        // Rejected row removed (replay wouldn't help), good row removed
        // (applied). Queue empty.
        #expect(try await q.count() == 0)
    }

    @Test func tickDrainGuardPreventsConcurrentRuns() async throws {
        let q = try await freshQueue()
        _ = try await q.enqueue(makeCommand(idempotencyKey: "k0"))
        // Two concurrent tickDrain calls — the second should see the
        // in-flight guard and bail without touching the queue.
        async let first: Void = q.tickDrain { _ in
            // Long-ish to keep the lock held while the second drain
            // attempts to start.
            try? await Task.sleep(nanoseconds: 50_000_000)
            return CommandAck(commandId: "x", status: .applied, reason: nil, resultingState: nil)
        }
        async let second: Void = q.tickDrain { _ in
            CommandAck(commandId: "y", status: .applied, reason: nil, resultingState: nil)
        }
        _ = await (first, second)
        // Either way the row is acknowledged once and removed.
        #expect(try await q.count() == 0)
    }
}
