//
//  JobBoxPickupRules.swift
//  Iconik Employee
//
//  What may a non-Packed scan inherit from the box's history, and when must a
//  pickup warn before saving? SwiftUI-free and Supabase-free: plain values in,
//  decisions out — testable by scripts/test_jobbox_pickup_rules.sh the same way
//  JobBoxProgressRules is.
//
//  Born from a live failure (2026-07-29): the office packed the Pinckneyville
//  Jr High box under a mistyped number, so the photographer's pickup scan of the
//  real tag inherited the box's PREVIOUS trip — Mt Vernon High, already turned
//  in — and the Jr High session's tracker never saw the pickup.
//

import Foundation

/// A reason to stop and ask before saving a pickup. `message` is what the
/// photographer reads — plain words, both box numbers, no jargon.
public enum JobBoxPickupWarning: Equatable {
    /// The job this pickup will file under has a Packed record for a DIFFERENT box.
    case wrongBox(scanned: String, packed: String, school: String)
    /// The job this pickup will file under has no Packed record at all.
    case nothingPacked(school: String)
    /// No session was chosen and the box's history cannot safely supply one —
    /// saving now would leave the pickup invisible to every job's tracker.
    case noJobLink(lastSchool: String?)

    public var title: String { "Check This Pickup" }

    public var message: String {
        switch self {
        case .wrongBox(let scanned, let packed, let school):
            return "This is box \(scanned), but box \(packed) was packed for \(school). Make sure you have the right box."
        case .nothingPacked(let school):
            return "No packed box is on record for \(school). Make sure you have the right box."
        case .noJobLink(let lastSchool):
            let lastPlace = (lastSchool?.isEmpty == false) ? " The box was last at \(lastSchool!)." : ""
            return "This pickup isn't linked to a session, so the job's tracker won't show it.\(lastPlace) Go back and select a session, or save without one."
        }
    }

    /// Label for the proceed-anyway button.
    public var confirmLabel: String {
        switch self {
        case .noJobLink: return "Save Without a Session"
        default: return "Pick Up Anyway"
        }
    }
}

public struct JobBoxPickupRules {

    /// RULE: a scan may reuse the box's previous job link only within the box's
    /// CURRENT trip. "Turned In" ends a trip, so nothing inherits across it —
    /// inheriting past it is exactly how a Pinckneyville pickup got filed under
    /// Mt Vernon's finished job. A pickup additionally requires the previous
    /// record to be for the SAME school: picking a box up for school B when its
    /// last record says school A must not quietly attach the scan to A's job.
    /// (Left Job and Turned In scans skip the school test — Turned In flows
    /// deliberately rewrite the school field to the studio.)
    public static func inheritableShiftUid(
        lastStatus: String?,
        lastSchool: String?,
        lastShiftUid: String?,
        newStatus: String,
        selectedSchool: String
    ) -> String? {
        guard let lastShiftUid, !lastShiftUid.isEmpty else { return nil }
        guard newStatus.lowercased() != "packed" else { return nil }
        guard (lastStatus ?? "").lowercased() != "turned in" else { return nil }
        if newStatus.lowercased() == "picked up" {
            guard (lastSchool ?? "") == selectedSchool else { return nil }
        }
        return lastShiftUid
    }

    /// RULE: a pickup is checked against what was packed for the job it will
    /// file under. `packedBoxNumber` nil means the job has no Packed record;
    /// pass `packedLookupFailed: true` when the lookup itself failed — a network
    /// blink must not accuse anyone of grabbing the wrong box, so the check
    /// fails OPEN (no warning) on lookup failure.
    public static func pickupWarning(
        scannedBox: String,
        targetShiftUid: String?,
        selectedSchool: String,
        packedBoxNumber: String?,
        packedLookupFailed: Bool,
        lastSchool: String?
    ) -> JobBoxPickupWarning? {
        guard targetShiftUid?.isEmpty == false else {
            return .noJobLink(lastSchool: lastSchool)
        }
        if packedLookupFailed { return nil }
        guard let packedBoxNumber, !packedBoxNumber.isEmpty else {
            return .nothingPacked(school: selectedSchool)
        }
        if packedBoxNumber == scannedBox { return nil }
        return .wrongBox(scanned: scannedBox, packed: packedBoxNumber, school: selectedSchool)
    }
}
