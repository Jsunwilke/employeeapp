//  JobBoxFlagRules.swift
//  Iconik Employee — how a box's flag rows become one flag reading
//
//  SwiftUI-FREE ON PURPOSE, the same contract as `JobBoxProgressRules.swift`:
//  `scripts/test_jobbox_flag_rules.sh` compiles THIS FILE — the one the app
//  builds — and runs its rules.
//
//  WHY THERE IS A RULE AT ALL
//
//  `job_boxes` is an APPEND-ONLY SCAN LOG: every scan INSERTs a row, and nothing
//  anywhere updates a status. Flagging UPDATEs the box's LATEST row at the moment
//  it is flagged — so the flag sits on one row of many, and the next ordinary
//  scan inserts a NEW row that carries no flag. Reading "is this box flagged"
//  off the latest row alone would therefore CLEAR a manager's flag the moment a
//  photographer scans the box, which is precisely the situation the flag exists
//  to survive.
//
//  So: a box reads as flagged when ANY row of its current trip is flagged, and
//  the note and date come from the most recently flagged row.
//
//  THE TRIP CUT IS THE CALLER'S. This function takes rows ALREADY cut to one
//  trip — `JobBoxProgressRules.currentTrip(from:)` performs that cut, but it
//  works in `JobBoxScanPoint`, which deliberately does not carry the flag
//  columns. Handing this function a whole log would let a flag from a previous
//  trip mark a freshly packed box, and the tests below cover only what this
//  function owns.

import Foundation

/// What this file needs off a `job_boxes` row. `JobBox` conforms (in
/// `Manager Features/JobBoxStatus.swift`); the protocol exists so THIS file
/// compiles with nothing but Foundation — `JobBox` imports Supabase, and a rules
/// file that cannot be compiled on its own cannot be tested on its own.
public protocol JobBoxFlagRow {
    var flagged: Bool { get }
    var flag_note: String? { get }
    var flagged_at: Date? { get }
}

public enum JobBoxFlagRules {

    /// The flag state of one box, read from the rows of its CURRENT TRIP.
    ///
    /// - Parameter currentTripRows: the box's rows, already cut to one trip.
    /// - Returns: whether any of them is flagged, and the note and moment of the
    ///   most recently flagged one.
    ///
    /// "Most recently flagged" is decided by `flagged_at`, not by the scan
    /// `timestamp` — the flag's own moment is the one being reported, and a
    /// manager can flag an older row after a newer one exists. A flagged row with
    /// no `flagged_at` at all (possible: the column is nullable) LOSES to any
    /// dated flag but still makes the box read as flagged.
    public static func flagReading<Row: JobBoxFlagRow>(currentTripRows rows: [Row])
    -> (flagged: Bool, note: String?, flaggedAt: Date?) {
        let flaggedRows = rows.filter(\.flagged)
        guard !flaggedRows.isEmpty else { return (false, nil, nil) }

        let newest = flaggedRows.max { a, b in
            (a.flagged_at ?? .distantPast) < (b.flagged_at ?? .distantPast)
        }
        return (true, newest?.flag_note, newest?.flagged_at)
    }
}
