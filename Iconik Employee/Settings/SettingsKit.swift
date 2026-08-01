//  SettingsKit.swift
//  Iconik Employee — the Settings design, as production code (AMB.12)
//
//  PRODUCTION CODE THAT THE LAB MOCKUP'S PRIVATE TYPES BECAME. Same mechanism as
//  ClassGroupsKit (AMB.10) and TimeOffKit (AMB.8): `DesignLab/Mockups/SettingsMockup.swift`
//  declared these privately only because a lab mockup has to compile standalone.
//
//  WHAT IS DELIBERATELY *NOT* HERE: the loading row, the failure card, the
//  label/value line, the search field, the nav row and the buttons. Those were
//  promoted into `DesignSystem/AmbientControls.swift` at the start of this phase
//  precisely because three batch-4 mockups each redeclared them. Settings uses the
//  shared ones; it does not keep a second copy.
//
//  WHAT IS HERE is the part that is genuinely Settings-specific:
//    · the tree's colour, decided once (claim 1)
//    · the editable/read-only field row every Account Info line is drawn with
//    · the photo-library permission gate the tree had none of (G35)
//    · the school SEASON window, which was copied verbatim into two files with
//      two force-unwrapped `calendar.date(...)!` between them (G28)

import SwiftUI
import Photos

// MARK: - Identity

enum SettingsStyle {
    /// CLAIM 1 — SETTINGS HAS A COLOUR, AND IT IS THE COMPANY'S.
    ///
    /// There is no `"settings"` case in `DesignTokens.swift`'s FeatureTheme map, so
    /// `FeatureTheme.color(for:)` would hand this tree its `default: .gray`.
    /// `AmbientStyle.brand` is the Iconik blue from the logo — what the app already
    /// uses when a surface needs to feel like THIS APP rather than like one of its
    /// features. That is a deliberate choice, not a fallback.
    ///
    /// This is an ACCENT (D11): icons, buttons, checkmarks, the mileage figure. It
    /// does NOT reach the background — since D14 every screen takes the one app
    /// wash through a bare `AmbientBackdrop()`.
    static var tint: Color { AmbientStyle.brand }
}

// MARK: - The editable field row

/// One line of a form that has two modes.
///
/// Editing draws a labelled `TextField`; not editing draws the shared
/// `AmbientStatLine`, with the shipped **"Not set"** orange fallback for an empty
/// value. Both modes are the SAME row in the same place, which is the point —
/// Account Info used to swap whole sections in and out on Edit.
struct SettingsField: View {
    let label: String
    @Binding var text: String
    let isEditing: Bool
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .words
    /// What to show when NOT editing, when that differs from the edit buffer —
    /// Account Info reads the freshest server value for the read-only view while
    /// the buffer holds what the user last seeded.
    var displayValue: String?

    private var shown: String { displayValue ?? text }

    var body: some View {
        if isEditing {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(label, text: $text)
                    .font(.subheadline)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
            }
        } else {
            AmbientStatLine(label: label,
                            value: shown.isEmpty ? "Not set" : shown,
                            valueTint: shown.isEmpty ? .orange : nil)
        }
    }
}

// MARK: - Photo library access

/// The permission gate this tree did not have (G35).
///
/// `ImagePicker` wraps `UIImagePickerController` with `.photoLibrary`, which — unlike
/// `PHPickerViewController` — runs IN PROCESS and therefore needs authorisation. A
/// user who has refused it got an empty picker and no explanation, on both screens
/// that pick a photo.
enum SettingsPhotoAccess {

    /// Resolves on the main queue. `false` means the user refused, or the device
    /// forbids it; either way the caller must say so rather than present a picker.
    static func request(_ completion: @escaping (Bool) -> Void) {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    completion(status == .authorized || status == .limited)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    /// One sentence, said the same way on both screens.
    static let deniedMessage =
        "Photo access is turned off for this app. Turn it on in iOS Settings › Privacy & Security › Photos, then try again."
}

// MARK: - The school season

/// THE SEASON WINDOW, IN ONE PLACE (G28).
///
/// Jul 15 → Jun 1 was hardcoded and duplicated verbatim in `SchoolInfoListView` and
/// `SchoolDetailView`, with two force-unwrapped `calendar.date(...)!` between them.
/// The dates are unchanged; the force-unwraps are gone.
enum SettingsSeason {
    /// The label the section header has always carried. Kept exactly, hyphen and all.
    static let label = "Jul 15 - Jun 1"

    /// The season containing `now`: from July 15 of the season's opening year to
    /// June 1 of the next.
    static func currentWindow(now: Date = Date()) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)

        func date(year: Int, month: Int, day: Int) -> Date? {
            calendar.date(from: DateComponents(year: year, month: month, day: day))
        }

        guard let july15ThisYear = date(year: year, month: 7, day: 15),
              let june1ThisYear = date(year: year, month: 6, day: 1) else { return nil }

        if now >= july15ThisYear {
            guard let june1NextYear = date(year: year + 1, month: 6, day: 1) else { return nil }
            return (july15ThisYear, june1NextYear)
        } else {
            guard let july15LastYear = date(year: year - 1, month: 7, day: 15) else { return nil }
            return (july15LastYear, june1ThisYear)
        }
    }
}
