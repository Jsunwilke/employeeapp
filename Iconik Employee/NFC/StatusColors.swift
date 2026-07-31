//  StatusColors.swift
//  Iconik Employee — SD-card status colour, and nothing else
//
//  JOB-BOX COLOURS ARE NOT HERE ANY MORE. They live SOLELY in
//  `JobBoxTripStage.meterTint` (`JobBox/JobBoxProgressMeter.swift`), which is the
//  single iOS↔web contract per the operator's ruling of 2026-07-30 (no grey for
//  any status; green reserved for Turned In; the rest unique calming colours).
//
//  This file used to carry a SECOND job-box map that disagreed with the shipped
//  meter on three of the four statuses — including a green Picked Up, which the
//  ruling forbids — so the same box could be two colours on two screens of the
//  same app. That map is deleted rather than reconciled: a second source of truth
//  is the defect, not the values in it.
//
//  Deleted in the same change and for the same reason: `jobBoxHexColors`,
//  `sdCardHexColors` and `hexColor(for:isJobBox:)` (zero call sites — the web
//  contract is documented in `STATUS_COLORS_DOCUMENTATION.md`, not read out of
//  Swift), and an `rgbComponents` extension on `Color` that returned (0, 0, 0)
//  and was never called.
//
//  The SD-card map below is UNCHANGED and remains the iOS↔web standard for cards.

import SwiftUI

struct StatusColors {
    // MARK: - SD Card Status Colors
    static let sdCardColors: [String: Color] = [
        "job box": Color(red: 255/255, green: 149/255, blue: 0/255),      // Orange
        "camera": Color(red: 52/255, green: 199/255, blue: 89/255),       // Green
        "envelope": Color(red: 255/255, green: 204/255, blue: 0/255),     // Yellow
        "uploaded": Color(red: 0/255, green: 122/255, blue: 255/255),     // Blue
        "cleared": Color(red: 142/255, green: 142/255, blue: 147/255),    // Gray
        "camera bag": Color(red: 175/255, green: 82/255, blue: 222/255),  // Purple
        "personal": Color(red: 88/255, green: 86/255, blue: 214/255)      // Indigo
    ]

    /// The colour for an SD-card status. Job boxes go through
    /// `JobBoxTripStage(stored:)?.meterTint` — there is no `isJobBox` flag any
    /// more, because there is no second map for it to select.
    static func color(forSDStatus status: String) -> Color {
        sdCardColors[status.lowercased()] ?? Color.gray
    }
}
