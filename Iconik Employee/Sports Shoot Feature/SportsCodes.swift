//
//  SportsCodes.swift
//  Iconik Employee
//
//  Shared decoders for the short codes that get stored in subject fields
//  on sports rosters. The teacher field carries single-letter codes:
//      "c" → Coach, "s" → Senior, "8" → 8th Grader
//  These come from how the rosters are imported from school SIS systems.
//
//  Display layer should always go through these helpers — never show the
//  raw single-letter code to a user. FP Sports view has its own copies of
//  this logic (specialTranslation in FPSportsRosterView_iPad.swift); they
//  should be migrated to call these helpers in a follow-up.
//

import Foundation

/// Decode a sports "teacher" field code to its display label. Returns the
/// input unchanged (case-preserved) when it's not a known code — schools
/// that use the teacher field for an actual teacher name still display
/// correctly.
public func decodeSportsTeacherCode(_ raw: String) -> String {
    switch raw.lowercased() {
    case "c": return "Coach"
    case "s": return "Senior"
    case "8": return "8th Grader"
    default: return raw
    }
}

/// Compact (badge-friendly) version of the decoder. Same semantics as
/// decodeSportsTeacherCode but shorter labels for tight UI spots like
/// per-row badges where "8th Grader" wraps awkwardly.
public func decodeSportsTeacherCodeShort(_ raw: String) -> String {
    switch raw.lowercased() {
    case "c": return "Coach"
    case "s": return "Senior"
    case "8": return "8th"
    default: return raw
    }
}
