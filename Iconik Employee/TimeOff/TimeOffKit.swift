//  TimeOffKit.swift
//  Iconik Employee — the Time Off design, as production code
//
//  PRODUCTION CODE THAT THE LAB MOCKUP IMPORTS. That direction is the whole
//  mechanism: the mockup draws with these types and so do the real screens, so a
//  conversion is not a matching exercise — it is swapping sample data for a
//  service. Nothing can drift, because there is no second copy to drift from.
//
//  It is the answer to the operator's question on AMB.7 — "how will you ensure it
//  creates these exactly as we have designed instead of just using them as
//  inspiration?" — and it is here because the alternative already failed twice:
//  step 3b of the kickoff says to account for every difference, and that
//  instruction was in force when AMB.1 shipped a static day strip where the lab
//  scrolled, then shipped it scrolling at the wrong width.
//
//  WHAT IS DELIBERATELY NOT HERE: anything that knows about Supabase. These take
//  plain values, so the lab feeds them sample data and production feeds them a
//  service, and neither owns the other. The rules they enforce live next door in
//  TimeOffRules.swift, which is SwiftUI-free and RUN by scripts/test_timeoff_rules.sh.

import SwiftUI

// MARK: - Identity

enum TimeOffStyle {
    /// These features' ACCENTS (D11). Time off, approvals and time tracking are
    /// adjacent teals in the palette, so they read as a family without reading as
    /// identical. Read from FeatureTheme rather than restated, so the tile you tap
    /// and the screen you land on cannot disagree. They no longer reach the
    /// background: D14 gives every screen the one app wash.
    static var requests: Color { FeatureTheme.color(for: "timeOffRequests") }
    static var approvals: Color { FeatureTheme.color(for: "timeOffApprovals") }
}

// MARK: - Status, rendered ONE way

/// THE APP DREW STATUS THREE INCOMPATIBLE WAYS AND ALL THREE WERE WRONG SOMEWHERE.
///
///   1. The shared card built a filled capsule from `TimeOffStatus.colorName`, a
///      plain String handed to `Color(_:)` — the ASSET CATALOG initialiser.
///      `AccentColor` is the only colorset in the project, so "orange", "blue"
///      and "green" resolved to nothing at all.
///   2. `TimeOffDetailView` ignored `colorName`, hard-coded its own SwiftUI
///      colours, and printed `rawValue.capitalized` — which is where the shipped
///      "Underreview" came from.
///   3. `ScheduleStyleKit.accent(for:)` maps by status AND partial-day, making an
///      approved request ORANGE when partial and GREY when not.
///
/// This is the one rendering, and it is the design's second claim. Labels come
/// from `TimeOffRuleStatus`, which is compiled and tested.
enum TimeOffStatusDisplay: Equatable {
    case known(TimeOffRuleStatus)
    /// A status neither client's enum recognises — `partially_approved`, which
    /// the web app really does write, or `under_review`, its snake_case spelling.
    case unrecognised(String)

    /// The shipped code did `TimeOffStatus(rawValue: status) ?? .pending`, so a
    /// request the web app had PARTIALLY APPROVED rendered as an orange "Pending"
    /// badge — awaiting a decision that had already been made. Presenting an
    /// unknown value as a specific known one is a confident wrong answer, which is
    /// worse than an honest unknown.
    static func from(raw: String) -> TimeOffStatusDisplay {
        if let known = TimeOffRuleStatus.parse(raw) { return .known(known) }
        return .unrecognised(raw)
    }

    var label: String {
        switch self {
        case .known(let status): return status.label
        // Humanised rather than shown raw: "partially_approved" becomes
        // "Partially Approved". Still honest — it is what the column says.
        case .unrecognised(let raw):
            let spaced = raw
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            let humanised = spaced.split(separator: " ").map(\.capitalized).joined(separator: " ")
            // An empty or whitespace-only status would otherwise render a badge
            // with no text at all.
            return humanised.isEmpty ? "Unknown" : humanised
        }
    }

    var color: Color {
        switch self {
        case .known(.pending): return .orange
        case .known(.underReview): return .blue
        case .known(.approved): return .green
        case .known(.denied): return .red
        case .known(.cancelled): return .gray
        // Deliberately neutral. A colour would assert a meaning we do not have.
        case .unrecognised: return .secondary
        }
    }

    var symbol: String {
        switch self {
        case .known(.pending): return "clock.fill"
        case .known(.underReview): return "magnifyingglass"
        case .known(.approved): return "checkmark.circle.fill"
        case .known(.denied): return "xmark.circle.fill"
        case .known(.cancelled): return "slash.circle.fill"
        case .unrecognised: return "questionmark.circle.fill"
        }
    }

    /// Drives the Edit and Cancel pills. An unrecognised status is NOT editable —
    /// offering Edit on a state we cannot name would invite a write we cannot
    /// reason about, against a row another client owns.
    var isEditable: Bool {
        switch self {
        case .known(let status): return status.isEditable
        case .unrecognised: return false
        }
    }

    var ruleStatus: TimeOffRuleStatus? {
        if case .known(let status) = self { return status }
        return nil
    }
}

// MARK: - Reason, resolved across BOTH clients

/// See the long note on `TimeOffReasonVocabulary`: the web app and iOS share ZERO
/// reason strings, so before this every web-created request drew a grey ellipsis
/// and the card's fastest read was dead on real data.
enum TimeOffReasonDisplay: Equatable {
    case known(TimeOffReasonVocabulary)
    case unrecognised(String)

    static func from(raw: String) -> TimeOffReasonDisplay {
        if let known = TimeOffReasonVocabulary.parse(raw) { return .known(known) }
        return .unrecognised(raw)
    }

    var label: String {
        switch self {
        case .known(let reason): return reason.label
        // Shown as written rather than flattened to "Other" — if someone typed
        // it, the photographer should see it.
        case .unrecognised(let raw): return raw
        }
    }

    var symbol: String {
        switch self {
        case .known(.vacation): return "beach.umbrella.fill"
        case .known(.sick): return "cross.case.fill"
        case .known(.personal): return "person.fill"
        case .known(.emergency): return "exclamationmark.triangle.fill"
        case .known(.bereavement): return "heart.fill"
        case .known(.medical): return "stethoscope"
        case .known(.other), .unrecognised: return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .known(.vacation): return .teal
        case .known(.sick): return .red
        case .known(.personal): return .indigo
        case .known(.emergency): return .orange
        case .known(.bereavement): return .brown
        case .known(.medical): return .pink
        case .known(.other), .unrecognised: return .gray
        }
    }
}

// MARK: - The card's data

/// PLAIN VALUES. The lab builds one from sample data; production builds one from
/// a `TimeOffRequest`. Neither the kit nor the mockup knows what a Supabase row is.
struct TimeOffCardModel: Identifiable, Equatable {
    let id: String
    let photographer: String
    let status: TimeOffStatusDisplay
    let reason: TimeOffReasonDisplay
    let dateLabel: String
    let timeLabel: String
    let durationLabel: String
    let isPartialDay: Bool
    let dayCount: Int
    let notes: String?
    let usesPTO: Bool
    let ptoHours: Double?
    /// Nil unless BOTH a name and a date are present — see `TimeOffAttribution`.
    let attribution: TimeOffAttribution?
    /// Held SEPARATELY from the attribution, and that is a bug fix, not a style
    /// choice. The shipped card nested the denial reason INSIDE the "Denied by X"
    /// block, and the web app's deny path writes `denial_reason` while leaving
    /// `denied_by` / `denier_name` / `denied_at` NULL (it stamps the APPROVAL
    /// columns instead — its own code carries a comment saying so). So every
    /// web-denied request showed a red badge, no denier, and NO REASON — the one
    /// thing the photographer actually needs. Now the reason draws whether or not
    /// the attribution line can.
    let denialReason: String?
    let createdAt: Date
}

// MARK: - The shared card

/// ONE card for the employee list AND the manager queue — which is what the app
/// already did and is worth keeping: the thing a manager approves should look
/// like the thing the employee submitted.
struct TimeOffRequestCard: View {
    let model: TimeOffCardModel
    /// The employee list shows Edit and Cancel; the manager queue suppresses them
    /// and shows its own.
    var showsActions: Bool = false
    var managerActions: Bool = false
    /// The manager queue shows WHOSE request it is; your own list does not.
    var showsPhotographer: Bool = false
    /// True while a write for this request is in flight. The pills go inert and
    /// say so, rather than silently swallowing the tap.
    var actionsBusy: Bool = false
    var onEdit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onApprove: (() -> Void)?
    var onDeny: (() -> Void)?
    var onReview: (() -> Void)?

    private var density: AmbientDensity { .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let notes = model.notes, !notes.isEmpty {
                Text(notes)
                    .font(density.subtitleFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            attribution
            if showsActions { actions }
        }
        .ambientCard(density: density,
                     state: model.status == .known(.cancelled) ? .receded : .normal,
                     border: .hairline(model.status.color.opacity(0.28)),
                     fillWidth: true)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.reason.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.reason.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.dateLabel).font(density.titleFont)
                    if model.isPartialDay {
                        AmbientBadge(text: "Partial", tint: .indigo)
                    }
                }
                Text(model.reason.label)
                    .font(density.subtitleFont.weight(.semibold))
                    .foregroundStyle(model.reason.color)
                HStack(spacing: 6) {
                    if showsPhotographer {
                        Text(model.photographer).font(density.subtitleFont.weight(.semibold))
                        Text("·").foregroundStyle(.tertiary)
                    }
                    Text(model.timeLabel).font(density.subtitleFont).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(model.durationLabel).font(density.subtitleFont).foregroundStyle(.secondary)
                }
                // PTO is a payroll fact and belongs on the card, not buried in the
                // detail — a manager approving 48 hours should see 48 hours.
                if model.usesPTO, let hours = model.ptoHours {
                    Text("\(hours, specifier: "%.1f") PTO hours")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            AmbientBadge(text: model.status.label,
                         systemImage: model.status.symbol,
                         tint: model.status.color)
        }
    }

    /// The attribution line and the denial reason are drawn INDEPENDENTLY — see
    /// the note on `TimeOffCardModel.denialReason`.
    @ViewBuilder
    private var attribution: some View {
        if model.attribution != nil || (model.denialReason?.isEmpty == false) {
            VStack(alignment: .leading, spacing: 3) {
                if let attribution = model.attribution {
                    HStack(spacing: 5) {
                        Image(systemName: model.status.symbol)
                            .font(.system(size: 10, weight: .bold))
                        Text(attribution.verb).font(.caption)
                        Text(Formatters.mediumDate.string(from: attribution.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(model.status.color)
                }

                if let reason = model.denialReason, !reason.isEmpty {
                    Text("Reason: \(reason)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        // Indented under the attribution when there is one, flush
                        // when there is not — so a web denial does not read as an
                        // orphaned fragment.
                        .padding(.leading, model.attribution == nil ? 0 : 15)
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if managerActions {
            HStack(spacing: 8) {
                if actionsBusy {
                    ProgressView().scaleEffect(0.7)
                    Text("Working…").font(.caption).foregroundStyle(.secondary)
                }
                if !actionsBusy {
                    if model.status == .known(.pending), let onReview {
                        pill("Put in Review", "magnifyingglass", .blue, onReview)
                    }
                    if model.status.isEditable {
                        if let onApprove { pill("Approve", "checkmark", .green, onApprove) }
                        if let onDeny { pill("Deny", "xmark", .red, onDeny) }
                    }
                }
            }
        } else if model.status.isEditable {
            HStack(spacing: 8) {
                // THE EMPLOYEE BRANCH HONOURS `actionsBusy` TOO. It did not, and
                // that was the double-submit guard being fixed on the manager
                // screen only while the identical hazard sat on this one:
                // `cancelTimeOffRequest` reaches `PTOService.releasePTOHours`,
                // which is a read-modify-write over a 300-second cache that also
                // writes the released balance BACK into that cache. Two taps on a
                // 16-hour request release 32 hours of reservation, and the balance
                // is then overstated for every later request.
                if actionsBusy {
                    ProgressView().scaleEffect(0.7)
                    Text("Working…").font(.caption).foregroundStyle(.secondary)
                } else {
                    if let onEdit { pill("Edit", "pencil", .blue, onEdit) }
                    if let onCancel { pill("Cancel", "xmark", .red, onCancel) }
                }
            }
        }
    }

    private func pill(_ title: String, _ icon: String, _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                // ambient-allow: an inline action pill is a control.
                .background(Capsule().fill(tint.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The balance lead

/// THE DESIGN'S FIRST CLAIM: the balance leads the surface that is about time off.
///
/// Today the only dedicated balance screen lives in SETTINGS — a different
/// feature, reached from a different place, by someone who has to know it is
/// there. Meanwhile the request form already computes a projected balance, which
/// is the app conceding you cannot reason about time off without the number.
/// Nothing is deleted: the full breakdown is one tap away and Settings keeps its
/// route.
struct TimeOffBalanceLead: View {
    /// Nil while loading or after a failure — and those are DIFFERENT, see below.
    let available: Double?
    let pendingHours: Double?
    /// A failure must never render as "0.0 hours available". A payroll number that
    /// is confidently wrong is worse than one that is honestly missing, and a
    /// failure presentable as a legitimate value is the exact shape that hid a
    /// broken feature in this app for a year.
    let failed: Bool
    /// Whether the stored figures mean anything yet. PTO HAS NEVER FUNCTIONED in
    /// this app, so leading a daily-use screen with "0.0 hours available" would be
    /// the most prominent thing on it and permanently false. When this is not
    /// `.tracked` the card keeps its ROUTE and drops its CLAIM.
    var tracking: PTOTracking = .tracked
    let tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                if failed {
                    unavailable
                } else if !tracking.showsFigures {
                    dormant
                } else if let available {
                    figure(available)
                } else {
                    loading
                }
            }
            // DEMOTED WHEN DORMANT. The design's first claim was that the balance
            // LEADS this surface; leading with a number that has never been real
            // is the claim doing harm. Hero treatment only when there is something
            // real to lead with.
            .ambientCard(density: tracking.showsFigures ? .hero : .compact,
                         state: tracking.showsFigures ? .highlighted : .normal,
                         glow: tracking.showsFigures ? tint : nil,
                         fillWidth: true)
        }
        .buttonStyle(.plain)
    }

    private func figure(_ available: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(available, specifier: "%.1f")")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                VStack(alignment: .leading, spacing: 0) {
                    Text("hours").font(.subheadline.weight(.semibold))
                    Text("available to use").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }

            // The one genuinely new line rather than a restatement: what is
            // already spoken for. It is the difference between the balance and
            // what you can actually ask for, and today you can only get it by
            // opening Settings.
            if let pendingHours, pendingHours > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("\(pendingHours, specifier: "%.1f") hours already requested and not yet decided")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// NO NUMBER. The row still opens the balance screen — nothing is taken away —
    /// but it does not state hours the system has never actually tracked.
    /// Self-healing: the moment real hours accrue this reverts to the figure with
    /// no code change.
    private var dormant: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("PTO balance").font(.subheadline.weight(.semibold))
                Text(tracking == .notConfigured
                     ? "Paid time off isn't switched on for your organisation."
                     : "No PTO hours have been tracked yet. Payroll has the authoritative figure.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
        }
    }

    private var loading: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading your balance…").font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var unavailable: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Balance unavailable").font(.subheadline.weight(.semibold))
                Text("Your balance couldn't be loaded, so it isn't shown rather than shown wrong.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Filter chips

/// A selectable chip with an optional count. There is no such component in the
/// design system — `AmbientPillRow` is a wrapping, non-interactive badge row, and
/// AMB.7's chips carry no counts — so this is the Time Off one, kept here rather
/// than hand-rolled twice on two screens.
struct TimeOffChip: View {
    let label: String
    let count: Int
    let tint: Color
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label).font(.caption.weight(.semibold))
                // ALWAYS RENDERED even at zero count — only the numeric badge is
                // conditional. That is the app's real behaviour and the deliberate
                // opposite of the call AMB.5 made for Tasks: a status you can never
                // see is a status you forget you can be in.
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.25) : tint.opacity(0.16)))
                }
            }
            .foregroundStyle(selected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            // ambient-allow: a selection chip is a control, not a container.
            .background(Capsule().fill(selected ? AnyShapeStyle(tint) : AnyShapeStyle(.ultraThinMaterial)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Rows

/// A read-only key/value row. The design system has no such component and AMB.7
/// hand-rolled the same HStack in three places; this is Time Off's one copy.
struct TimeOffDetailRow: View {
    let label: String
    let value: String
    var emphasised: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(emphasised ? .subheadline.weight(.semibold) : .subheadline)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
    }
}

/// A signed hours row — "+62.5 h", "−46.5 h".
///
/// THE SIGN IS DRAWN FROM THE VALUE. The shipped `PTOBalanceView.BalanceRow` did
/// `value < 0 ? "" : "+"`, which prints a leading "+" on positives and NOTHING on
/// negatives — so "Pending Requests", passed `-pendingBalance`, rendered 8 hours
/// of pending time off as "8", visually identical to a credit. Every figure there
/// was also `Int(...)`-truncated, so a 4.5-hour balance read "4".
struct TimeOffSignedRow: View {
    let label: String
    let value: Double
    let tint: Color
    var emphasised: Bool = false

    var body: some View {
        HStack {
            Text(label).font(emphasised ? .subheadline.weight(.semibold) : .subheadline)
            Spacer(minLength: 8)
            Text("\(value >= 0 ? "+" : "−")\(abs(value), specifier: "%.1f") h")
                .font(.system(size: emphasised ? 17 : 15,
                              weight: emphasised ? .bold : .medium,
                              design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(.vertical, 7)
    }
}

/// An inline note — the PTO shortfall and future-accrual messages.
struct TimeOffInlineNote: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon).font(.caption.weight(.semibold))
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .ambientCard(density: .compact, border: .hairline(tint.opacity(0.35)), fillWidth: true)
    }
}

// MARK: - Failure banner

/// NO TIME OFF SCREEN HAS EVER SHOWN AN ERROR. `TimeOffService` publishes an
/// `errorMessage`, sets it on every failure path, and not one view reads it — so
/// a failed load renders as "You haven't submitted any time off requests yet."
/// That is the defect that hid Chat for a year, sitting in this surface too.
/// THE FULL PANEL, for when there is nothing else on the screen.
///
/// The mockup drew this shape for a failed load — 30pt triangle, headline,
/// centred body, a filled Try Again capsule. The banner below is the right shape
/// when there are still rows to keep, and the wrong one when the failure IS the
/// whole page. The first cut of this conversion used the banner for both; the
/// design audit caught it.
struct TimeOffFailurePanel: View {
    let title: String
    let message: String
    let tint: Color
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: retry) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    // ambient-allow: a control, not a card.
                    .background(Capsule().fill(tint))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// The BANNER, for when a refresh failed but there are still rows worth keeping.
struct TimeOffFailureBanner: View {
    /// Takes a title, like its sibling panel. It hardcoded "Couldn't load your
    /// requests" and is reused on the MANAGER queue, where the rows are not yours.
    var title: String = "Couldn't load your requests"
    let message: String
    let tint: Color
    var retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: retry) {
                Text("Retry")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    // ambient-allow: a control, not a card.
                    .background(Capsule().fill(tint))
            }
            .buttonStyle(.plain)
        }
        .ambientCard(density: .compact,
                     border: .hairline(Color.orange.opacity(0.45)),
                     fillWidth: true)
    }
}

// MARK: - Primary action

/// A full-width filled capsule. Used for "New Time Off Request" and "Submit".
struct TimeOffPrimaryButton: View {
    let title: String
    var systemImage: String?
    let tint: Color
    /// The mockup used 13 for "New Time Off Request" and 14 for "Submit Request".
    /// Collapsing both to 13 was a silent 1pt regression on the form's primary
    /// action — small, but exactly the class of drift that has reached the
    /// operator on this arc twice.
    var verticalPadding: CGFloat = 13
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            // ambient-allow: a filled primary action is a control, not a card —
            // it needs a solid tint to read as tappable over the wash.
            .background(Capsule().fill(enabled ? tint : Color.gray))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
