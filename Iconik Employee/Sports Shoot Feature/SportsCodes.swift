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
import SwiftUI

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

/// Color for the per-row teacher badge. Distinct per code so operators
/// recognize the role at a glance without reading the label. Defaults to
/// systemGray2 for real teacher names.
public func sportsTeacherBadgeColor(_ raw: String) -> Color {
    switch raw.lowercased() {
    case "c": return .purple   // Coach — authority/leadership
    case "s": return .brown    // Senior — graduating, distinct from sport blue
    case "8": return .teal     // 8th grader — fresh/underclass
    default: return Color(.systemGray2)
    }
}

/// Deterministic color for a sport/group name. Same algorithm as
/// FPSportsRosterView_iPad.colorForGroup so a given sport ("Football",
/// "Basketball", etc.) gets the same color across views and across
/// app launches. Empty input returns gray.
public func sportBadgeColor(_ sport: String) -> Color {
    if sport.isEmpty { return Color.gray }
    let hash = abs(sport.utf8.reduce(0) { ($0 &* 31) &+ Int($1) })
    let palette: [Color] = [
        .blue,
        .green,
        Color(red: 0.0, green: 0.6, blue: 0.4),  // Teal green
        .purple,
        .pink,
        .teal,
        .indigo,
        .red,
        Color(red: 0.2, green: 0.5, blue: 0.9),  // Light blue
        Color(red: 0.1, green: 0.6, blue: 0.4),  // Forest green
        Color(red: 0.8, green: 0.4, blue: 0.0),  // Amber
        Color(red: 0.5, green: 0.1, blue: 0.7),  // Violet
        Color(red: 0.9, green: 0.2, blue: 0.5),  // Rose
    ]
    return palette[hash % palette.count]
}
