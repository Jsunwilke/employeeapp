//  ManagerKit.swift
//  Iconik Employee — the Manager tools design, as production code
//
//  PRODUCTION CODE, the way TimeOffKit (AMB.8), MileageKit (AMB.9) and
//  ClassGroupsKit (AMB.10) are. The design was approved at the batch-4 sitting
//  (2026-07-30) as `DesignLab/Mockups/ManagerMockup.swift`; these are its private
//  types made real, so the four manager screens draw one vocabulary instead of
//  four. The mockup dies with the lab at AMB.12's tail — the design lives here.
//
//  WHAT IS DELIBERATELY NOT HERE: anything that knows about Supabase, and any
//  arithmetic. These views take plain values — a name, a note, miles, a rate — so
//  the screens above them can swap a service without touching a pixel.
//
//  THE FIVE CLAIMS THE OPERATOR APPROVED, and where each one lives:
//    1. A SCREEN SHOWS ONLY WHAT YOU CAN DO   — `ManagerAccessDenied`, and the
//                                               permission branches in FlagUserView
//    2. ONE STRING MUST NOT BE THREE STATES   — `ManagerLoadState`, drawn through
//                                               `AmbientLoadingRow` /
//                                               `AmbientFailureCard` /
//                                               `AmbientEmptyState`
//    3. UNFLAGGING IS A DECISION, NOT A TAP   — `ManagerFlaggedUserRow`
//    4. (the employee's own answer to a flag)  — NOT BUILT. It is a feature with
//                                               its own phase; `FlaggedStatusView`
//                                               is left exactly as it is.
//    5. AN EMPLOYEE DETAIL SCREEN IS NOT A DEAD END
//                                             — `ManagerMileageDayRow`'s photo count
//
//  MONEY IS SPELLED ONCE, through `Formatters.currency`. AMB.9 named the manager
//  screens' four hand-rolled spellings as this phase's to reconcile — two of them
//  read wrong (`$%.0f` truncated a whole-dollar total, and a four-figure total ran
//  together as "$1234.50"). Nothing in this file formats a dollar itself.

import SwiftUI

// MARK: - Identity

enum ManagerStyle {
    /// `#C62A2F`. Note where it sits: `flagUser` is registered in the PLANNING
    /// family beside the schedule rather than with the other manager tools. That
    /// is a palette oddity the batch-4 sitting saw and left alone; it is read from
    /// `FeatureTheme` rather than restated here so the tile you tap and the screen
    /// you land on cannot disagree (D11).
    static var flagTint: Color { FeatureTheme.color(for: "flagUser") }

    /// `#5F8A6E` — deliberately desaturated, like the rest of the manager family.
    static var unflagTint: Color { FeatureTheme.color(for: "unflagUser") }

    /// `#8A7A5F` — manager mileage, and the employee detail it pushes to.
    static var mileageTint: Color { FeatureTheme.color(for: "managerMileage") }
}

// MARK: - States

/// Loading, loaded and failed as THREE things.
///
/// Claim 2, and it is the defect these screens shared from opposite ends:
/// `FlagUserView` drew one string ("Loading users...") for the load, the empty
/// list AND the failure, with `.onAppear` attached to that very `Text` so a failed
/// load could never re-fire; `UnflagUserView` had no loading state at all, so a
/// green "All users are currently in good standing" rendered DURING the fetch —
/// the app affirmatively telling a manager nobody is flagged before it knew.
///
/// Emptiness is deliberately NOT a case here. An empty state is a statement about
/// the DATA and belongs to the loaded case; a failure is a statement about the
/// CONNECTION. Collapsing them is what produced both defects above.
enum ManagerLoadState: Equatable {
    case loading
    case loaded
    case failed(String)
}

/// The one thing a manager without `users:edit` sees on these screens.
///
/// Claim 1. It is the WHOLE branch: today `FlagUserView` draws its note field and
/// its "Flag User" button outside the permission block, so a denied user gets a
/// complete, live-looking form whose only possible outcome is an error.
///
/// SAID PLAINLY, because the design must not present this as security: the real
/// boundary is the `flag_user` / `unflag_user` database functions, which check
/// permission, organization and self-targeting themselves. This screen-side check
/// is convenience — it stops a manager filling in a form that cannot be sent.
struct ManagerAccessDenied: View {
    let message: String

    var body: some View {
        AmbientEmptyState(title: "Access Denied",
                          message: message,
                          systemImage: "lock.fill")
    }
}

// MARK: - Picking a person

/// One selectable person on the flag screen.
///
/// THE FULL NAME, which is what makes two photographers called Chris
/// distinguishable — only `firstName` was ever carried into the old picker's
/// model, so the dropdown could list "Chris" twice with no way to tell them apart.
///
/// INACTIVE IS MARKED. This screen calls `getTeamMembers`, which returns rows with
/// `is_active == false`; `getPhotographers` — used everywhere else — filters them
/// out. Which query is called is NOT changed here (that is a data-layer decision,
/// D12); what changes is that a person who has left is no longer offered as though
/// they were still on the team.
struct ManagerPersonPickRow: View {
    let fullName: String
    let isActive: Bool
    let isSelected: Bool
    var tint: Color = ManagerStyle.flagTint
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(AmbientMotion.snappy) { action() }
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 10) {
                AmbientAvatar(name: fullName, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(fullName).font(AmbientDensity.compact.titleFont)
                    if !isActive {
                        Text("Inactive").font(.caption2).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(tint)
                }
            }
            .ambientCard(density: .compact, fillWidth: true)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Clearing a flag

/// One flagged person, and the decision to clear them.
///
/// Claim 3. Unflagging was a single tap on a blue "Unflag" button — irreversible
/// from this screen, with no confirmation — so the row expands into what clearing
/// actually does before it does it.
///
/// THE ROW SHOWS THE FULL NAME. The list has always SORTED by full name while
/// DISPLAYING only the first, so two people sharing a first name looked randomly
/// ordered.
struct ManagerFlaggedUserRow: View {
    let fullName: String
    /// Resolved from `users.flagged_by`, which the flagged-users query already
    /// returns as an id. Nil when the flagger could not be resolved — the line is
    /// then omitted rather than printed as a raw id.
    let flaggedByName: String?
    let note: String
    let isConfirming: Bool
    /// True while this row's own clear is in flight.
    var isClearing: Bool = false
    var tint: Color = ManagerStyle.unflagTint
    let onToggleConfirm: () -> Void
    let onConfirmClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AmbientAvatar(name: fullName, size: 32, ringColor: ManagerStyle.flagTint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fullName).font(AmbientDensity.compact.titleFont)
                    if let flaggedByName, !flaggedByName.isEmpty {
                        Text("Flagged by \(flaggedByName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            // The note a manager needs in order to decide, kept from the old row.
            if !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isConfirming {
                confirm
            } else {
                AmbientActionButton(title: "Unflag",
                                    role: .primary,
                                    size: .small,
                                    tint: tint,
                                    fillWidth: false,
                                    isLoading: isClearing,
                                    action: onToggleConfirm)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    /// The sentence says what clearing DOES and what it does not undo, because
    /// re-flagging is not an undo — it is a new flag with a new note, and it
    /// notifies the person again.
    private var confirm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clear this flag? \(fullName) stops seeing the note on their home screen. This cannot be undone from here — re-flagging is a new flag with a new note.")
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                AmbientActionButton(title: "Cancel",
                                    role: .secondary,
                                    size: .small,
                                    action: onToggleConfirm)
                AmbientActionButton(title: "Clear flag",
                                    role: .primary,
                                    size: .small,
                                    tint: tint,
                                    isLoading: isClearing,
                                    action: onConfirmClear)
            }
        }
    }
}

// MARK: - The window a manager is looking at

/// The fortnight, spelled out.
///
/// BOTH manager mileage screens count their own 14-day cycles from a hardcoded
/// 2/25/2024 anchor, while the employee-facing mileage screen reads the
/// organization's configured pay periods — so the same fortnight can be two
/// different windows depending on who is looking. Making them agree is a
/// data-layer change and is NOT in this phase (D12). What IS in it is refusing to
/// imply agreement: every manager screen states the window it is actually showing.
enum ManagerPeriodText {
    /// "Jul 20, 2026 – Aug 2, 2026"
    static func range(_ start: Date, _ end: Date) -> String {
        "\(Formatters.mediumDate.string(from: start)) – \(Formatters.mediumDate.string(from: end))"
    }

    /// "Last 14 days · Jul 20, 2026 – Aug 2, 2026" — the employee detail's header,
    /// where the 14 days are fixed rather than chosen.
    static func fixedWindow(_ start: Date, _ end: Date) -> String {
        "Last 14 days · \(range(start, end))"
    }

    /// The caption under the manager mileage carousel. It names the cycle these
    /// chips step in, so a manager can see which fortnight they are reading rather
    /// than inferring one.
    static let cycleCaption =
        "Fixed 14-day periods, counted by this screen. Your organization's own pay-period settings drive the photographer's Mileage Reports screen, so a period here can start on a different day."
}

// MARK: - A day of someone else's mileage

/// One filed daily job report on the employee detail screen.
///
/// Claim 5: THE PHOTO COUNT IS A CONTROL. The old screen had zero of them — the
/// thumbnails, the "+N" overflow tile and the count chip were all inert, so any
/// photo past the fifth was unreachable. The count now opens the day's report,
/// which is where those photos already live.
struct ManagerMileageDayRow: View {
    let date: Date
    let school: String
    let miles: Double
    let isCompany: Bool
    let photoCount: Int
    var tint: Color = ManagerStyle.mileageTint
    /// Nil when there are no photos to reach.
    var openReport: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(Formatters.mediumDate.string(from: date))
                    .font(AmbientDensity.compact.titleFont)
                Spacer(minLength: 8)
                Text("\(MileageFigures.oneDecimal(miles)) miles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            HStack(spacing: 8) {
                Text(school).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if isCompany { AmbientBadge(text: "Company", tint: .orange) }
                if photoCount > 0 {
                    photoChip
                }
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    @ViewBuilder
    private var photoChip: some View {
        if let openReport {
            Button(action: openReport) {
                HStack(spacing: 3) {
                    AmbientBadge(text: "\(photoCount) photos",
                                 systemImage: "photo.fill",
                                 tint: tint)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open the report for \(Formatters.mediumDate.string(from: date)), \(photoCount) photos")
        } else {
            AmbientBadge(text: "\(photoCount) photos", systemImage: "photo.fill", tint: tint)
        }
    }
}

// MARK: - One employee's period on the manager mileage list

/// A photographer's row on the manager mileage screen: their rate, the split when
/// there is one, and the three spans with the money each one pays.
///
/// EVERY DOLLAR GOES THROUGH `Formatters.currency`. This row replaces four
/// hand-rolled spellings, two of which read wrong.
///
/// The month line is labelled from the SELECTED period, not from today — the old
/// row read "Miles in July" over a June period's figures, because the label came
/// from `Date()` while the number came from the selection.
struct ManagerEmployeeMileageRow: View {
    let name: String
    let rate: Double
    let periodMiles: Double
    let periodPay: Double
    let periodCompanyMiles: Double
    let companyRate: Double
    /// "July 2026", derived from the SELECTED period — see the note above.
    let monthLabel: String
    let monthMiles: Double
    let monthPay: Double
    /// "2026 total", derived from the selected period for the same reason.
    let yearLabel: String
    let yearMiles: Double
    let yearPay: Double
    var tint: Color = ManagerStyle.mileageTint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name).font(AmbientDensity.compact.titleFont)
                    Spacer(minLength: 8)
                    Text("Rate \(Formatters.currency(rate))/mi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }

                // KEPT: the split caption appears only once company miles exist,
                // which is how this row has always read.
                if periodCompanyMiles > 0 {
                    Text("Personal \(MileageFigures.oneDecimal(periodMiles - periodCompanyMiles)) mi · Company \(MileageFigures.oneDecimal(periodCompanyMiles)) mi at \(Formatters.currency(companyRate))/mi")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                figureLine(label: "This period", miles: periodMiles, pay: periodPay, emphasised: true)
                figureLine(label: monthLabel, miles: monthMiles, pay: monthPay)
                figureLine(label: yearLabel, miles: yearMiles, pay: yearPay)
            }
            .ambientCard(density: .compact, fillWidth: true)
        }
        .buttonStyle(.plain)
    }

    private func figureLine(label: String, miles: Double, pay: Double, emphasised: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text("\(MileageFigures.oneDecimal(miles)) mi")
                .font(.caption.weight(.semibold))
            Text(Formatters.currency(pay))
                .font(.caption.weight(.semibold))
                .foregroundStyle(emphasised ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                .frame(minWidth: 62, alignment: .trailing)
        }
    }
}
