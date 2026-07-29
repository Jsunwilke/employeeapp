//  JobBoxProgressRules.swift
//  Iconik Employee — how a job box's scan rows become a progress reading
//
//  SwiftUI-FREE ON PURPOSE. `scripts/test_jobbox_progress_rules.sh` compiles THIS
//  FILE (the one the app builds, not a paraphrase of it) and runs it. A rule that
//  is a compiled type with a failing test holds; a rule that is a sentence in a
//  comment does not.
//
//  WHY THIS FILE EXISTS AT ALL
//
//  `job_boxes` is an APPEND-ONLY SCAN LOG. Every scan INSERTs a row —
//  `DatabaseManager.saveJobBoxRecord` and the manager tracker's status advance
//  both insert, and there is no status-update path anywhere in either app. So the
//  rows for a box ARE its history: stage, who, when.
//
//  Both screens that drew a progress bar ignored that. Each took ONE row, turned
//  its status into a number 1–4, and then drew every lower stage as complete
//  (`done = step >= number`). That asserts scans that do not exist, and it is not
//  a rare case. Live counts over the 351 boxes carrying a shift (2026-07-29):
//
//      Packed only .................................. 199
//      Packed + Picked Up ............................ 47
//      all four stages ............................... 35
//      Packed + Turned In ............................ 31   <- skips two
//      Packed + Picked Up + Turned In ................ 22   <- skips one
//      ...11 more across six shapes, four never packed at all
//
//  Ten per cent of boxes walk all four stages. A box scanned Packed then Turned
//  In was drawn with four ticks — two of them fiction.
//
//  THE TWO RULES THAT MAKE A METER HONEST
//
//  1. POSITION IS NOT COMPLETENESS. Where the box IS comes from the furthest
//     stage it reached; which stages actually HAPPENED comes from whether a row
//     exists for each. Conflating them is what made an early draft fill a bar
//     100% solid for a box that had been scanned twice.
//
//  2. A BOX IS A REUSED PHYSICAL OBJECT, SO "PROGRESS" MEANS THE CURRENT TRIP.
//     Box 3028 goes out and comes back all season. The manager tracker groups
//     rows by box number across ALL TIME (correctly — it answers "where is box
//     3028 now"), which means a naive per-stage reading of the group would mix
//     June's trip with October's and report stages complete that belong to a
//     different job. `currentTrip` cuts the log at the LAST Packed scan.

import Foundation

// MARK: - Stages

/// The four stages a box moves through.
///
/// `stored` is the exact text in `job_boxes.status`, and `init(stored:)` is
/// deliberately tolerant of case and surrounding whitespace: the column is plain
/// text written by two different clients, so a strict match is a silent
/// mis-read waiting to happen.
public enum JobBoxTripStage: Int, CaseIterable, Comparable {
    case packed = 1
    case pickedUp = 2
    case leftJob = 3
    case turnedIn = 4

    public var stored: String {
        switch self {
        case .packed: return "Packed"
        case .pickedUp: return "Picked Up"
        case .leftJob: return "Left Job"
        case .turnedIn: return "Turned In"
        }
    }

    /// What a person says out loud.
    public var label: String {
        switch self {
        case .packed: return "Packed"
        case .pickedUp: return "Picked up"
        case .leftJob: return "Left job"
        case .turnedIn: return "Turned in"
        }
    }

    public init?(stored raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "packed": self = .packed
        case "picked up", "pickedup": self = .pickedUp
        case "left job", "leftjob": self = .leftJob
        case "turned in", "turnedin": self = .turnedIn
        default: return nil
        }
    }

    public static func < (lhs: JobBoxTripStage, rhs: JobBoxTripStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// How one stage should be drawn once the log has been read.
public enum JobBoxStageState {
    /// A scan exists for it.
    case scanned
    /// No scan — but a LATER stage was scanned, so this one was jumped.
    case skipped
    /// Not reached yet.
    case pending
}

// MARK: - A scan

/// One row of the scan log, reduced to what a meter needs. Deliberately NOT
/// `JobBox`: that type imports Supabase, and this file has to compile on its own
/// so its rules can be run by a script.
public struct JobBoxScanPoint {
    public let stage: JobBoxTripStage
    /// Nil is REAL and common: a Packed row usually has no photographer, because
    /// packing happens before anyone is assigned (NULL on 199 live rows).
    public let who: String?
    public let at: Date

    public init(stage: JobBoxTripStage, who: String?, at: Date) {
        self.stage = stage
        self.who = who
        self.at = at
    }
}

// MARK: - The reading

public struct JobBoxProgressReading {

    /// The scans of ONE trip, oldest first.
    public let scans: [JobBoxScanPoint]

    /// Build a reading for the current trip out of a box's whole log.
    ///
    /// Pass every row you have for the box; this cuts to the current trip itself.
    public init(log: [JobBoxScanPoint]) {
        self.scans = Self.currentTrip(from: log)
    }

    /// Build a reading from scans already known to be one trip.
    public init(trip: [JobBoxScanPoint]) {
        self.scans = trip.sorted { $0.at < $1.at }
    }

    /// The rows belonging to the box's current trip: everything from the LAST
    /// Packed scan onward.
    ///
    /// A box with no Packed row at all is a real shape (4 live boxes) — the whole
    /// log is then one trip, because there is no seam to cut on.
    public static func currentTrip(from log: [JobBoxScanPoint]) -> [JobBoxScanPoint] {
        let ordered = log.sorted { $0.at < $1.at }
        guard let lastPacked = ordered.lastIndex(where: { $0.stage == .packed }) else {
            return ordered
        }
        return Array(ordered[lastPacked...])
    }

    public var isEmpty: Bool { scans.isEmpty }

    public var latest: JobBoxScanPoint? { scans.last }

    /// The furthest stage any scan reached — NOT the latest scan's stage. They
    /// differ whenever a box is scanned out of order, which the live table does
    /// contain.
    public var furthest: JobBoxTripStage? {
        scans.map(\.stage).max()
    }

    public func scan(for stage: JobBoxTripStage) -> JobBoxScanPoint? {
        scans.first { $0.stage == stage }
    }

    public func state(_ stage: JobBoxTripStage) -> JobBoxStageState {
        if scan(for: stage) != nil { return .scanned }
        guard let furthest, stage < furthest else { return .pending }
        return .skipped
    }

    public var scannedCount: Int {
        JobBoxTripStage.allCases.filter { state($0) == .scanned }.count
    }

    public var skipped: [JobBoxTripStage] {
        JobBoxTripStage.allCases.filter { state($0) == .skipped }
    }

    /// How far along the trip the box actually IS, 0–1.
    ///
    /// Rule 1: this is POSITION, not completeness. A turned-in box is at the end
    /// of its trip however few stages were scanned on the way, and the per-stage
    /// states are what carry which ones really happened.
    public var positionFraction: Double {
        guard let furthest else { return 0 }
        return Double(furthest.rawValue) / Double(JobBoxTripStage.allCases.count)
    }

    public var isFinished: Bool { furthest == .turnedIn }

    /// The stage to name on the card.
    public var headline: String { furthest?.label ?? "Not scanned" }

    /// Who is on the hook for the box now, or nil when it is in the warehouse.
    /// Never a Packed row's photographer.
    public var holder: String? {
        guard let furthest, furthest != .packed, furthest != .turnedIn else { return nil }
        if let named = scan(for: furthest)?.who, !named.isEmpty { return named }
        return scans.reversed().first(where: { ($0.who ?? "").isEmpty == false })?.who
    }

    /// Named only when there is something to say, so a normal box gets no
    /// apology line.
    public var skipNote: String? {
        let names = skipped.map(\.label)
        guard !names.isEmpty else { return nil }
        let list: String
        if names.count == 1 {
            list = names[0]
        } else {
            list = names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
        return "\(list) never scanned"
    }
}
