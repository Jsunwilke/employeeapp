//  NFCRoutingRules.swift
//  Iconik Employee — the NFC surface's business constants, in ONE place
//
//  SwiftUI-FREE ON PURPOSE, the same contract as `JobBoxProgressRules.swift`:
//  `scripts/test_nfc_routing_rules.sh` compiles THIS FILE — the one the app
//  builds, not a paraphrase — and runs its rules. A rule that is a compiled type
//  with a failing test holds; a rule that is a sentence in a comment does not.
//
//  WHY THIS FILE EXISTS
//
//  Every constant below was written out longhand in two to four separate files,
//  and the copies had already drifted:
//
//      the 12-hour "left at a job" threshold ....... 43200 in ScanView:410 and
//                                                    JobBoxBubbleView:50, and the
//                                                    words "over 12 hours" typed
//                                                    separately into
//                                                    JobBoxNotification:36 — so a
//                                                    threshold change (ScanView
//                                                    already drops to 300s in
//                                                    debug) leaves the banner
//                                                    lying. Here the copy is
//                                                    DERIVED from the number.
//      the job-box number floor 3001 ............... ScanView:151
//      the four job-box statuses ................... ScanView:41,
//                                                    ManualEntryView:13,
//                                                    SearchView:46,
//                                                    JobBoxFormView:35
//      the SD status advance ....................... ScanView:628-638,
//                                                    ManualEntryView:435-456,
//                                                    FormView:196-214
//
//  NOTHING IS UNIFIED HERE THAT WAS NOT ALREADY IDENTICAL. Where two call sites
//  genuinely behave differently — and one pair does, see `SDAdvanceVariant` — both
//  behaviours are modelled explicitly. This is a design phase; D12 says the
//  business rules do not change in one.
//
//  The consuming views still hold their own copies today: this slice builds and
//  tests the rules, and the later conversion slices adopt them.

import Foundation

public enum NFCRoutingRules {

    // MARK: - Which kind of tag is this?

    /// A scanned number at or above this is a JOB BOX. Below it — or not a whole
    /// number at all — is an SD card. (`ScanView.swift:151`.)
    public static let jobBoxNumberFloor = 3001

    /// The SD-card number range as the tags are actually written. Documentary:
    /// the routing rule does NOT test it, and must not start to — a card numbered
    /// outside it still has to route somewhere, and "SD card" is the fallback by
    /// construction.
    public static let sdCardNumberRange = 1001...2000

    /// The routing rule, exactly as `ScanView.swift:146-158` performs it: an
    /// integer at or above the floor is a job box; ANYTHING else — a lower
    /// integer, a leading-zero string that still parses, a non-number, an empty
    /// string — is an SD card.
    ///
    /// Note `Int("0301") == 301`, which is below the floor, so it routes to SD.
    /// The leading zero is not what decides it; the value is.
    public static func isJobBoxNumber(_ text: String) -> Bool {
        guard let number = Int(text) else { return false }
        return number >= jobBoxNumberFloor
    }

    // MARK: - The "left at a job" alert

    /// How long a box may sit in Left Job before the scan screen's banner calls
    /// it out: 12 hours. (`ScanView.swift:410` production value;
    /// `JobBoxBubbleView.swift:50`.)
    public static let leftJobAlertThreshold: TimeInterval = 43200

    /// The threshold in words, for banner copy — DERIVED, so the sentence can
    /// never disagree with the number it describes. The shipped banner types
    /// "over 12 hours" as a literal while the threshold is a variable that drops
    /// to 5 minutes in debug builds.
    public static var leftJobAlertThresholdDescription: String {
        let hours = leftJobAlertThreshold / 3600
        if hours >= 1 {
            let whole = Int(hours.rounded())
            return "\(whole) hour\(whole == 1 ? "" : "s")"
        }
        let minutes = Int((leftJobAlertThreshold / 60).rounded())
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    // MARK: - Job box status ring

    /// The four job-box statuses in trip order — the exact text stored in
    /// `job_boxes.status`.
    public static let jobBoxStatusRing = ["Packed", "Picked Up", "Left Job", "Turned In"]

    /// The status a scan should default to, given the box's last one: the next
    /// step round the ring, wrapping Turned In back to Packed (the box is
    /// repacked for its next trip).
    ///
    /// Unrecognised — including an empty string and a never-scanned box —
    /// defaults to the first status, "Packed".
    ///
    /// MATCHING is case-insensitive, as `ScanView.swift:686` does it.
    /// `ManualEntryView.swift:470` compares case-SENSITIVELY; the two agree on
    /// every value the column actually holds (live 2026-07-30: 1,059 rows, zero
    /// outside the four exact strings), and the tolerant form is the one that
    /// cannot silently reset a box to Packed because another client wrote
    /// "picked up". The widening is deliberate and is the only difference.
    public static func nextJobBoxStatus(after status: String) -> String {
        let key = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let index = jobBoxStatusRing.firstIndex(where: { $0.lowercased() == key }) else {
            return jobBoxStatusRing[0]
        }
        return jobBoxStatusRing[(index + 1) % jobBoxStatusRing.count]
    }

    // MARK: - SD card status ring

    /// The SD statuses that form the ordinary lifecycle ring.
    ///
    /// The pickers offer two MORE — "Camera Bag" and "Personal" — which are
    /// deliberately excluded from the ring: they are side states, not steps, and
    /// every advance path filters them out before indexing.
    public static let sdStatusRing = ["Job Box", "Camera", "Envelope", "Uploaded", "Cleared"]

    /// The two side statuses, excluded from the ring.
    public static let sdSideStatuses = ["Camera Bag", "Personal"]

    /// WHICH SCREEN IS ASKING — because the two paths genuinely differ, and the
    /// difference is preserved deliberately (D12: a design phase does not change
    /// business rules).
    ///
    /// Verified 2026-07-30 by reading all three call sites:
    ///   - `ScanView.swift:628-638` filters the side statuses out and then looks
    ///     the last status up in the FILTERED list. A box coming off "Camera Bag"
    ///     or "Personal" is therefore not found, and falls through to the ring's
    ///     first entry, "Job Box".
    ///   - `ManualEntryView.swift:425-458` and `FormView.swift:183-220` are
    ///     identical to each other and handle those two first: "Camera Bag" →
    ///     "Camera", "Personal" → "Cleared". Everything else takes the same ring
    ///     step as `.scan`.
    ///
    /// Do not unify these without an operator ruling: they are different answers
    /// to "where does a card go after it comes out of the bag", and only one of
    /// them can be right.
    public enum SDAdvanceVariant {
        /// `ScanView` — side statuses fall through to the head of the ring.
        case scan
        /// `FormView` / `ManualEntryView` — side statuses have explicit landings.
        case form
    }

    /// The status a scan should default to, given the card's last one.
    ///
    /// Unrecognised — including an empty string and a never-scanned card —
    /// defaults to the ring's first entry, "Job Box", in both variants.
    public static func nextSDStatus(after status: String,
                                    variant: SDAdvanceVariant) -> String {
        let key = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if variant == .form {
            if key == "camera bag" { return "Camera" }
            if key == "personal" { return "Cleared" }
        }

        guard let index = sdStatusRing.firstIndex(where: { $0.lowercased() == key }) else {
            return sdStatusRing[0]
        }
        return sdStatusRing[(index + 1) % sdStatusRing.count]
    }
}
