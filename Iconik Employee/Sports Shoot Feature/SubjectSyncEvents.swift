//
//  SubjectSyncEvents.swift
//  Iconik Employee
//
//  Structured event log for subject sync. Every operation (queue, send,
//  receive, commit, fail, abandon) emits a SubjectSyncEvent with consistent
//  shape. Aggregated in memory for the debug panel and mirrored to the
//  console via print().
//
//  Mirror of src/data/sync/subject-sync-events.ts on the Mac side.
//
//  See IPAD_SURFACE_SYNC_REWRITE.md §8.
//

import Foundation
import Combine

enum SubjectSyncOutcome: String {
    case queued
    case sent
    case received
    case committed
    case failed
    case abandoned
    case duplicate
    case rejected
}

enum SubjectSyncOperation: String {
    case update
    case create
    case delete
    case ack
    case summary
    case reconcile
    case hello
    case heartbeat
}

struct SubjectSyncEvent {
    let ts: Date
    let deviceId: String
    let deviceRole: String         // "iPad" | "Surface"
    let operation: SubjectSyncOperation
    let subjectId: String?
    let galleryId: String?
    let idempotencyKey: String?
    let fieldsTouched: [String]?
    let outcome: SubjectSyncOutcome
    let errorCode: String?
    let errorMessage: String?
    let retryAttempt: Int?
    let queueDepth: Int?
    let latencyMs: Int?
    let sourcePath: String

    init(
        deviceId: String,
        deviceRole: String = "iPad",
        operation: SubjectSyncOperation,
        outcome: SubjectSyncOutcome,
        sourcePath: String,
        subjectId: String? = nil,
        galleryId: String? = nil,
        idempotencyKey: String? = nil,
        fieldsTouched: [String]? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        retryAttempt: Int? = nil,
        queueDepth: Int? = nil,
        latencyMs: Int? = nil,
        ts: Date = Date()
    ) {
        self.ts = ts
        self.deviceId = deviceId
        self.deviceRole = deviceRole
        self.operation = operation
        self.outcome = outcome
        self.sourcePath = sourcePath
        self.subjectId = subjectId
        self.galleryId = galleryId
        self.idempotencyKey = idempotencyKey
        self.fieldsTouched = fieldsTouched
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.retryAttempt = retryAttempt
        self.queueDepth = queueDepth
        self.latencyMs = latencyMs
    }
}

@MainActor
final class SubjectSyncEvents: ObservableObject {
    static let shared = SubjectSyncEvents()

    @Published private(set) var recent: [SubjectSyncEvent] = []

    private let maxBufferedEvents = 500
    // Listeners keyed by a UUID token so removal is order-independent.
    // The previous index-based scheme would remove the wrong listener if
    // an earlier registrant unsubscribed first.
    private var listeners: [UUID: (SubjectSyncEvent) -> Void] = [:]

    private init() {}

    func emit(_ event: SubjectSyncEvent) {
        recent.append(event)
        if recent.count > maxBufferedEvents {
            recent.removeFirst(recent.count - maxBufferedEvents)
        }
        // Mirror to console — the existing infrastructure has no central
        // logger sink so print() is the available channel.
        print("[FP-SYNC] \(event.operation.rawValue)_\(event.outcome.rawValue) " +
              "subject=\(event.subjectId ?? "-") " +
              "key=\(event.idempotencyKey ?? "-") " +
              "src=\(event.sourcePath) " +
              "err=\(event.errorMessage ?? "-")")
        for cb in listeners.values {
            cb(event)
        }
    }

    func getRecent(limit: Int = 100) -> [SubjectSyncEvent] {
        if limit >= recent.count { return recent }
        return Array(recent.suffix(limit))
    }

    @discardableResult
    func onEvent(_ listener: @escaping (SubjectSyncEvent) -> Void) -> () -> Void {
        let token = UUID()
        listeners[token] = listener
        return { [weak self] in
            self?.listeners.removeValue(forKey: token)
        }
    }

    func countByOutcome() -> [SubjectSyncOutcome: Int] {
        var counts: [SubjectSyncOutcome: Int] = [:]
        for e in recent {
            counts[e.outcome, default: 0] += 1
        }
        return counts
    }

    func _testReset() {
        recent.removeAll()
        listeners.removeAll()  // [UUID: callback] dict — removeAll empties it
    }
}
