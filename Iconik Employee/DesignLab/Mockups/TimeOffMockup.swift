//  TimeOffMockup.swift
//  Iconik Employee — AMB.8's mockup, built in batch 2
//
//  ARC SCAFFOLDING. Deleted at AMB.8's close, with the rest of the lab going at
//  AMB.12.
//
//  WHY THIS EXISTS NOW RATHER THAN AT AMB.8
//      Batch 2 belonged to AMB.6, which spent itself discovering that Chat had
//      never worked. D10 is a hard gate — no real screen is touched before the
//      operator has approved a running design on a device — so these mockups had
//      to be built before AMB.7 could start. They cover BOTH batch-2 phases:
//      Reports (AMB.7, the sibling file) and Time Off (AMB.8, this one).
//
//  WHAT THE DESIGN IS ARGUING, in four claims the operator can accept or reject
//
//      1. THE BALANCE LEADS.
//         Today the only dedicated balance screen lives in SETTINGS — a
//         different feature, reached from a different place, by someone who has
//         to know it is there. Meanwhile the request form already computes and
//         shows a PROJECTED balance, which is the app conceding that you cannot
//         reason about time off without the number. So the number moves to the
//         top of the surface that is about time off. Nothing is deleted: the
//         full breakdown is still one tap away, and Settings can keep its route.
//
//      2. ONE STATUS RENDERING, PICKED KNOWINGLY.
//         The app currently draws status three incompatible ways (parity finding
//         6): the shared card's filled capsule takes a colour NAME string and
//         hands it to Color(_:), the asset-catalog initialiser, which finds
//         nothing because AccentColor is the project's only colorset; the detail
//         screen uses real colours and prints rawValue.capitalized, so
//         underReview reads as the literal "Underreview"; and the schedule maps
//         approved to ORANGE when partial and GREY when not. This mockup uses
//         one enum, real colours, and labels a person would say out loud.
//
//      3. THE MANAGER QUEUE SAYS IT IS A QUEUE.
//         Pending and In Review sort OLDEST FIRST, deliberately reversing the
//         employee list, because a manager works a queue. That is real workflow
//         knowledge buried in a sort call where nobody can see it. The design
//         says it on the screen.
//
//      4. THE MISSING STATES ARE DRAWN.
//         No Time Off screen has an error state or an offline state today
//         (finding 10), and a PTO shortfall is swallowed so the request is
//         created anyway (finding 8). Those are drawn here as PROPOSALS, marked
//         as such — see the note on the shortfall state below.
//
//  WHAT IS NOT BEING PROPOSED
//      No data layer, service, loader, business rule or permission changes (D12).
//      Two payroll-adjacent defects found while inventorying — the approval
//      screen having NO permission check, and the swallowed PTO shortfall — are
//      recorded in AMB_BATCH2_PARITY.md and are NOT fixed by this phase. Where
//      this mockup draws a state those fixes would need, it is labelled PROPOSED
//      so an approval here is not mistaken for an approval of the fix.

import SwiftUI

// MARK: - Destinations

/// One enum, one `.ambientPush` — the AMB.3 rule. Two stacked
/// `NavigationLink(isActive:)` is the shape that produced AMB.1's dead tap.
private enum TimeOffDestination: String, Identifiable {
    case request
    case approvals
    case detail
    case balance

    var id: String { rawValue }
}

/// Which state the root list is showing. A lab control, not a design element —
/// it exists so the operator can see the empty, error and offline states without
/// having to arrange for them.
private enum TimeOffListState: String, CaseIterable, Identifiable {
    case populated = "Requests"
    case empty = "Empty"
    case filteredEmpty = "No matches"
    case error = "Error"
    case offline = "Offline"

    var id: String { rawValue }
}

// MARK: - Root: My Time Off

struct TimeOffMockup: View {
    /// The feature's own colour (D11). Time off, approvals and time tracking are
    /// a family in the palette — adjacent teals — so they read as related without
    /// reading as identical.
    static let featureTint = Color(hex: "#0D9B8A")

    @State private var filter: LabTimeOffStatus?
    @State private var state: TimeOffListState = .populated
    @State private var destination: TimeOffDestination?
    @State private var showBalanceDetail = false

    private var requests: [LabTimeOffRequest] {
        let all = DesignLabSampleData.myTimeOff
        guard let filter else { return all }
        return all.filter { $0.status == filter }
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Self.featureTint, intensity: 0.8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    labControl
                    balanceLead
                    newRequestButton
                    chipRow
                    content
                    managerEntry
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .ambientPush(item: $destination) { destination in
            switch destination {
            case .request: TimeOffRequestMockup()
            case .approvals: TimeOffApprovalMockup()
            case .detail: TimeOffDetailMockup()
            case .balance: PTOBalanceMockup()
            }
        }
    }

    // MARK: lab chrome

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · state", trailing: "not a design element")
            Picker("State", selection: $state) {
                ForEach(TimeOffListState.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: 1 — the balance, which today lives in Settings

    /// The claim: you cannot decide whether to ask for four days off without
    /// knowing you have 16 hours left. Today that number is in a different
    /// feature. Tapping it opens the full breakdown, so nothing is lost.
    private var balanceLead: some View {
        let balance = DesignLabSampleData.ptoBalance
        return Button {
            destination = .balance
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(balance.available, specifier: "%.1f")")
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

                // The one line that is genuinely new information rather than a
                // restatement: what is already spoken for. It is the difference
                // between the balance and what you can actually ask for, and
                // today you can only get it by opening Settings.
                if balance.pendingHours > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("\(balance.pendingHours, specifier: "%.1f") hours already requested and not yet decided")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .ambientCard(density: .hero, state: .highlighted, glow: Self.featureTint, fillWidth: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: 2 — the primary action, always present

    private var newRequestButton: some View {
        Button {
            destination = .request
        } label: {
            Label("New Time Off Request", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                // ambient-allow: a filled primary action is a control, not a
                // card — it needs a solid tint to read as tappable over the wash.
                .background(Capsule().fill(Self.featureTint))
        }
        .buttonStyle(.plain)
    }

    // MARK: 3 — the chips

    /// All six chips are ALWAYS rendered, even at zero — the app's real
    /// behaviour, and the deliberate opposite of the call AMB.5 made for Tasks.
    /// Only the numeric badge is conditional. Kept as-is rather than quietly
    /// harmonised, because a status you can never see is a status you forget you
    /// can be in.
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, label: "All", count: DesignLabSampleData.myTimeOff.count, tint: .secondary)
                ForEach(LabTimeOffStatus.allCases, id: \.self) { status in
                    chip(status,
                         label: status.label,
                         count: DesignLabSampleData.myTimeOff.filter { $0.status == status }.count,
                         tint: status.color)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    private func chip(_ status: LabTimeOffStatus?, label: String, count: Int, tint: Color) -> some View {
        let selected = filter == status
        return Button {
            withAnimation(AmbientMotion.snappy) { filter = status }
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 5) {
                Text(label).font(.caption.weight(.semibold))
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

    // MARK: 4 — the list, and the four states it can be in

    @ViewBuilder
    private var content: some View {
        switch state {
        case .populated:
            if requests.isEmpty { filteredEmptyState } else { list }
        case .empty:
            unfilteredEmptyState
        case .filteredEmpty:
            filteredEmptyState
        case .error:
            errorState
        case .offline:
            offlineState
        }
    }

    private var list: some View {
        LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
            ForEach(requests) { request in
                Button { destination = .detail } label: {
                    LabTimeOffRequestCard(request: request, showsActions: true)
                }
                .buttonStyle(.plain)
                .ambientScrollFade()
            }
        }
    }

    /// The app's real unfiltered empty copy, plus the call to action it already
    /// has. Chat lost exactly this button in AMB.6 by swapping a hand-rolled
    /// empty state for a component with no action slot; the slot now exists, so
    /// the loss cannot repeat by accident.
    private var unfilteredEmptyState: some View {
        AmbientEmptyState(
            title: "No Time Off Requests",
            message: "You haven't submitted any time off requests yet.",
            systemImage: "calendar.badge.clock",
            actionTitle: "Create First Request",
            actionIcon: "plus.circle.fill",
            action: { destination = .request },
            actionTint: Self.featureTint)
    }

    /// Filtered empty is a DIFFERENT state with different copy and — critically —
    /// NO call to action, because "create your first request" is wrong when you
    /// have six of them and are looking at a filter.
    private var filteredEmptyState: some View {
        AmbientEmptyState(
            title: "No \(filter?.label ?? "Matching") Requests",
            message: "You don't have any \(filter?.label.lowercased() ?? "matching") requests.",
            systemImage: "line.3.horizontal.decrease.circle")
    }

    /// PROPOSED — no Time Off screen has an error state today (finding 10).
    /// TimeOffService publishes an errorMessage that no view ever displays, so a
    /// failed load is presented as "you have no requests". That is the exact
    /// shape of the defect that hid Chat for a year.
    private var errorState: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("Couldn't load your requests").font(.headline)
            Text("The server didn't answer. Your requests are safe — this screen just can't show them right now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                withAnimation(AmbientMotion.gentle) { state = .populated }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    // ambient-allow: a control, not a card.
                    .background(Capsule().fill(Self.featureTint))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    /// PROPOSED — likewise absent today. The distinction that matters is that
    /// this is NOT an error: the data is simply older than now.
    private var offlineState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash").font(.footnote.weight(.semibold))
                Text("Offline — showing what was last synced")
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.orange)
            .ambientCard(density: .compact, border: .dashed(Color.orange.opacity(0.5)), fillWidth: true)

            LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                ForEach(DesignLabSampleData.myTimeOff.prefix(3)) { request in
                    LabTimeOffRequestCard(request: request, showsActions: false)
                }
            }
        }
    }

    // MARK: 5 — the manager route

    /// Time Off Approvals is a SEPARATE feature row today, gated on a permission
    /// area that is not its own. It is shown here so the operator can reach the
    /// queue mockup; whether the real app should surface it from this screen is a
    /// navigation question, not a design one, and is deliberately left open.
    private var managerEntry: some View {
        Button {
            destination = .approvals
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(hex: "#0C8577"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Approvals queue").font(AmbientDensity.compact.titleFont)
                    Text("Manager view — the other batch-2 Time Off surface")
                        .font(AmbientDensity.compact.subtitleFont)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .ambientCard(density: .compact, fillWidth: true)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}

// MARK: - The shared request card

/// ONE card, used by the employee list AND the manager queue — which is what the
/// app already does, and worth keeping: the thing a manager approves should look
/// like the thing the employee submitted.
private struct LabTimeOffRequestCard: View {
    let request: LabTimeOffRequest
    /// The employee list shows Edit and Cancel; the manager queue suppresses them
    /// and shows its own actions instead.
    var showsActions: Bool
    var managerActions: Bool = false
    var onApprove: (() -> Void)? = nil
    var onDeny: (() -> Void)? = nil
    var onReview: (() -> Void)? = nil
    /// The manager queue shows WHOSE request it is; your own list does not.
    var showsPhotographer: Bool = false

    private var density: AmbientDensity { .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let notes = request.notes, !notes.isEmpty {
                Text(notes)
                    .font(density.subtitleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            attribution
            if showsActions { actions }
        }
        .ambientCard(density: density,
                     state: request.status == .cancelled ? .receded : .normal,
                     border: .hairline(request.status.color.opacity(0.28)),
                     fillWidth: true)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            // The reason carries its own icon and colour — the app already does
            // this and it is the fastest read on the card.
            Image(systemName: request.reason.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(request.reason.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(request.dateLabel).font(density.titleFont)
                    if request.isPartialDay {
                        AmbientBadge(text: "Partial", tint: .indigo)
                    }
                }
                HStack(spacing: 6) {
                    if showsPhotographer {
                        Text(request.photographer).font(density.subtitleFont.weight(.semibold))
                        Text("·").foregroundStyle(.tertiary)
                    }
                    Text(request.timeLabel).font(density.subtitleFont).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(request.durationLabel).font(density.subtitleFont).foregroundStyle(.secondary)
                }
                // PTO is a payroll fact and belongs on the card, not buried in
                // the detail — a manager approving 48 hours should see 48 hours.
                if request.usesPTO, let hours = request.ptoHours {
                    Text("\(hours, specifier: "%.1f") PTO hours")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            AmbientBadge(text: request.status.label,
                         systemImage: request.status.symbol,
                         tint: request.status.color)
        }
    }

    /// Three conditional attribution lines. Each is conditional on BOTH the name
    /// and the date existing — the app's real condition, which is why sample row
    /// t5 is approved with no approver and must draw nothing here.
    @ViewBuilder
    private var attribution: some View {
        if let name = request.actionedBy, let date = request.actionedAt {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: request.status.symbol)
                        .font(.system(size: 10, weight: .bold))
                    Text(verbLabel(name))
                        .font(.caption)
                    Text(Formatters.monthDay.string(from: date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(request.status.color)

                if let reason = request.denialReason {
                    Text("Reason: \(reason)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 15)
                }
            }
        }
    }

    private func verbLabel(_ name: String) -> String {
        switch request.status {
        case .approved: return "Approved by \(name)"
        case .denied: return "Denied by \(name)"
        case .underReview: return "In review by \(name)"
        default: return name
        }
    }

    @ViewBuilder
    private var actions: some View {
        if managerActions {
            HStack(spacing: 8) {
                if request.status == .pending, let onReview {
                    pill("Put in Review", "magnifyingglass", .blue, onReview)
                }
                if request.status.isEditable {
                    if let onApprove { pill("Approve", "checkmark", .green, onApprove) }
                    if let onDeny { pill("Deny", "xmark", .red, onDeny) }
                }
            }
        } else if request.status.isEditable {
            HStack(spacing: 8) {
                pill("Edit", "pencil", .blue) {}
                pill("Cancel", "xmark", .red) {}
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

// MARK: - Request form

/// Create AND edit, one form — as today. The design question this screen answers
/// is what to do about the PTO numbers, which are currently four separate rows
/// the user has to assemble in their head.
private struct TimeOffRequestMockup: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case sufficient = "Enough PTO"
        case shortfall = "Not enough PTO"
        case futureAccrual = "Future accrual"
        var id: String { rawValue }
    }

    @State private var isPartialDay = false
    @State private var reason: LabTimeOffReason = .vacation
    @State private var usePTO = true
    @State private var mode: Mode = .sufficient
    @State private var notes = ""

    private var requestedHours: Double {
        switch mode {
        case .sufficient: return 8
        case .shortfall: return 64
        case .futureAccrual: return 24
        }
    }

    private var projected: Double {
        DesignLabSampleData.ptoBalance.available - requestedHours
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: TimeOffMockup.featureTint, intensity: 0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    labControl
                    typeSection
                    datesSection
                    reasonSection
                    ptoSection
                    notesSection
                    summarySection
                    submitButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Request Time Off")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · PTO case", trailing: "not a design element")
            Picker("Case", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Type")
            Picker("Type", selection: $isPartialDay) {
                Text("Full Day").tag(false)
                Text("Partial Day").tag(true)
            }
            .pickerStyle(.segmented)
            // The real rule, kept: switching to partial FORCES end date = start
            // date. Said out loud rather than left as a surprise.
            if isPartialDay {
                Text("A partial day is a single date. Minimum 30 minutes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var datesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle(isPartialDay ? "Date and time" : "Dates")
            VStack(spacing: 0) {
                if isPartialDay {
                    formRow("Date", "Aug 14")
                    Divider()
                    formRow("Start Time", "1:00 PM")
                    Divider()
                    formRow("End Time", "5:00 PM")
                } else {
                    formRow("Start Date", "Aug 19")
                    Divider()
                    // End is bounded BY START — moving start past end drags end
                    // with it. A real rule worth preserving.
                    formRow("End Date", "Aug 23")
                }
                Divider()
                // Read-only, and INCLUSIVE of both endpoints: days + 1.
                formRow("Duration", isPartialDay ? "4.0 hours" : "5 days", emphasised: true)
            }
            .ambientCard(density: .compact, fillWidth: true)

            if isPartialDay {
                Text("If the end time lands before the start, it is corrected to start + 1 hour rather than rejected.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Reason")
            // Six reasons, each with its own icon and colour — the same identity
            // the card uses, so the choice you make here is the mark you see on
            // the list afterwards.
            AmbientFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(LabTimeOffReason.allCases, id: \.self) { option in
                    Button {
                        withAnimation(AmbientMotion.snappy) { reason = option }
                        AmbientHaptics.selection()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: option.symbol).font(.system(size: 11, weight: .semibold))
                            Text(option.rawValue).font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(reason == option ? .white : option.color)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        // ambient-allow: a selection chip is a control.
                        .background(Capsule().fill(reason == option
                                                   ? AnyShapeStyle(option.color)
                                                   : AnyShapeStyle(option.color.opacity(0.13))))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: the PTO block — the one real redesign on this screen

    /// Today this is four separate rows: a current balance (omitted entirely when
    /// nil), a projected balance that turns orange when insufficient, a hours
    /// field, and two inline validation messages. The user assembles the
    /// arithmetic themselves. Here it is one block that states the sum.
    private var ptoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Paid time off")

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $usePTO) {
                    Text("Use PTO Balance").font(.subheadline.weight(.semibold))
                }
                .tint(TimeOffMockup.featureTint)

                if usePTO {
                    Divider()
                    HStack {
                        Text("PTO Hours Requested").font(.subheadline)
                        Spacer()
                        Text("\(requestedHours, specifier: "%.1f")")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
                    }
                    // Auto-filled, but manual entry wins once touched — a real
                    // behaviour that has to survive.
                    Text("Filled from the dates. Type over it if payroll agreed something else.")
                        .font(.caption2).foregroundStyle(.tertiary)

                    Divider()
                    balanceMath
                }
            }
            .ambientCard(density: .roomy, fillWidth: true)

            if usePTO { ptoMessage }
        }
    }

    private var balanceMath: some View {
        VStack(spacing: 6) {
            mathRow("Available now", DesignLabSampleData.ptoBalance.available, .secondary)
            mathRow("This request", -requestedHours, .secondary)
            Divider()
            mathRow("Left afterwards", projected, projected < 0 ? .orange : .green, emphasised: true)
        }
    }

    private func mathRow(_ label: String, _ value: Double, _ tint: Color, emphasised: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasised ? .subheadline.weight(.semibold) : .subheadline)
            Spacer()
            Text("\(value >= 0 ? "" : "−")\(abs(value), specifier: "%.1f") h")
                .font(.system(size: emphasised ? 17 : 15,
                              weight: emphasised ? .bold : .medium,
                              design: .rounded))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
    }

    /// PROPOSED, and the most important thing on this screen.
    ///
    /// Today a shortfall produces an ORANGE WARNING and the request is submitted
    /// anyway — the service throws "Insufficient PTO balance", the caller catches
    /// it and prints a warning, and the row is already inserted by then (parity
    /// finding 8). So the balance never moves and the request looks fine.
    ///
    /// This draws what the screen should say. It is marked PROPOSED because the
    /// underlying fix is a payroll change that this design phase has NOT been
    /// authorised to make, and approving a mockup is not approving that fix.
    @ViewBuilder
    private var ptoMessage: some View {
        switch mode {
        case .sufficient:
            EmptyView()
        case .futureAccrual:
            inlineNote("This uses PTO you haven't accrued yet — you'll have enough by the request date.",
                       icon: "clock.arrow.circlepath", tint: .blue)
        case .shortfall:
            VStack(alignment: .leading, spacing: 6) {
                inlineNote(String(format: "You are %.1f hours short. Reduce the request, or turn off \"Use PTO Balance\" to request it unpaid.", abs(projected)),
                           icon: "exclamationmark.triangle.fill", tint: .orange)
                Text("PROPOSED — today this warns and submits anyway, and the balance is never reserved. See AMB_BATCH2_PARITY.md finding 8.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func inlineNote(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon).font(.caption.weight(.semibold))
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .ambientCard(density: .compact, border: .hairline(tint.opacity(0.35)), fillWidth: true)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Notes", trailing: "optional")
            TextEditor(text: $notes)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .ambientCard(density: .compact, fillWidth: true)
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Summary")
            VStack(spacing: 0) {
                formRow("Type", isPartialDay ? "Partial day" : "Full day")
                Divider()
                formRow("Dates", isPartialDay ? "Aug 14, 1:00–5:00 PM" : "Aug 19 – Aug 23")
                Divider()
                formRow("Duration", isPartialDay ? "4.0 hours" : "5 days")
                Divider()
                formRow("Reason", reason.rawValue)
            }
            .ambientCard(density: .compact, fillWidth: true)
        }
    }

    private var submitButton: some View {
        let blocked = usePTO && mode == .shortfall
        return VStack(spacing: 6) {
            Button {} label: {
                Text(blocked ? "Not enough PTO" : "Submit Request")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    // ambient-allow: a control.
                    .background(Capsule().fill(blocked ? Color.gray : TimeOffMockup.featureTint))
            }
            .buttonStyle(.plain)
            .disabled(blocked)

            // The real rule today: full-day requests are NEVER blocked, and the
            // only thing that disables submit is the 30-minute partial-day
            // minimum. Kept, and said out loud.
            if isPartialDay {
                Text("A partial day must be at least 30 minutes.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 4)
    }

    private func formRow(_ label: String, _ value: String, emphasised: Bool = false) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(emphasised ? .subheadline.weight(.semibold) : .subheadline)
        }
        .padding(.vertical, 7)
    }
}

// MARK: - Approval queue

/// Three tabs, and the FIFO order is the design's main assertion.
private struct TimeOffApprovalMockup: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case pending = "Pending"
        case inReview = "In Review"
        case history = "History"
        var id: String { rawValue }
    }

    /// PROPOSED — see the note on `accessState`.
    private enum Access: String, CaseIterable, Identifiable {
        case manager = "Has permission"
        case noAccess = "No permission (proposed)"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .pending
    @State private var access: Access = .manager
    @State private var denying: LabTimeOffRequest?

    private var queue: [LabTimeOffRequest] {
        let all = DesignLabSampleData.approvalQueue
        switch tab {
        case .pending:
            // OLDEST FIRST. A manager works a queue.
            return all.filter { $0.status == .pending }.sorted { $0.createdAt < $1.createdAt }
        case .inReview:
            return all.filter { $0.status == .underReview }.sorted { $0.createdAt < $1.createdAt }
        case .history:
            // History sorts by when it was ACTIONED, newest first.
            return all.filter { $0.status == .approved || $0.status == .denied }
                .sorted { ($0.actionedAt ?? $0.createdAt) > ($1.actionedAt ?? $1.createdAt) }
        }
    }

    private func count(_ tab: Tab) -> Int {
        switch tab {
        case .pending: return DesignLabSampleData.approvalQueue.filter { $0.status == .pending }.count
        case .inReview: return DesignLabSampleData.approvalQueue.filter { $0.status == .underReview }.count
        // History DELIBERATELY carries no badge — the app passes none, and a
        // count on a history tab is a number nobody acts on.
        case .history: return 0
        }
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Color(hex: "#0C8577"), intensity: 0.75)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    labControl
                    if access == .noAccess {
                        noAccessState
                    } else {
                        tabBar
                        queueOrderNote
                        content
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Time Off Approvals")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · access", trailing: "not a design element")
            Picker("Access", selection: $access) {
                ForEach(Access.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { option in
                Button {
                    withAnimation(AmbientMotion.snappy) { tab = option }
                    AmbientHaptics.selection()
                } label: {
                    HStack(spacing: 5) {
                        Text(option.rawValue).font(.caption.weight(.semibold))
                        if count(option) > 0 {
                            Text("\(count(option))")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.red))
                        }
                    }
                    .foregroundStyle(tab == option ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    // ambient-allow: a tab control, not a container.
                    .background(Capsule().fill(tab == option
                                               ? AnyShapeStyle(Color(hex: "#0C8577"))
                                               : AnyShapeStyle(.ultraThinMaterial)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The queue order is real workflow knowledge that today lives only in a sort
    /// call. If the design does not say it, the next person to touch this screen
    /// will "fix" it to newest-first.
    @ViewBuilder
    private var queueOrderNote: some View {
        if tab != .history {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.to.line").font(.caption2.weight(.bold))
                Text("Oldest first — work the queue from the top")
                    .font(.caption2.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if queue.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                ForEach(Array(queue.enumerated()), id: \.element.id) { index, request in
                    VStack(alignment: .leading, spacing: 4) {
                        // Position in the queue, which is the thing FIFO order
                        // exists to communicate and which nothing shows today.
                        if tab != .history {
                            Text("\(index + 1) of \(queue.count) · waiting \(waitingDays(request)) days")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        LabTimeOffRequestCard(
                            request: request,
                            showsActions: tab != .history,
                            managerActions: true,
                            onApprove: {},
                            onDeny: { denying = request },
                            onReview: {},
                            showsPhotographer: true)
                    }
                    .ambientScrollFade()
                }
            }
        }
    }

    private func waitingDays(_ request: LabTimeOffRequest) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: request.createdAt, to: Date()).day ?? 0)
    }

    private var emptyState: some View {
        switch tab {
        case .pending:
            return AmbientEmptyState(title: "All Caught Up!",
                                     message: "There are no pending requests to review.",
                                     systemImage: "checkmark.circle")
        case .inReview:
            return AmbientEmptyState(title: "No Requests In Review",
                                     message: "Nothing is currently being looked at.",
                                     systemImage: "magnifyingglass")
        case .history:
            return AmbientEmptyState(title: "No History",
                                     message: "Approved and denied requests will appear here.",
                                     systemImage: "clock.arrow.circlepath")
        }
    }

    /// PROPOSED — TimeOffApprovalView has NO permission check of any kind today.
    /// Approve, Deny and Put-in-Review are gated only by the VISIBILITY of a row
    /// in AllFeaturesView, and that row is gated on a DIFFERENT permission area
    /// (users.edit, not timeOffApprovals). TimeOffService.canManageRequests()
    /// exists, does exactly the right check, and has zero callers.
    ///
    /// This is what the screen should show when the check fails. It is marked
    /// PROPOSED because wiring the check is a permission change this design phase
    /// has NOT been authorised to make.
    private var noAccessState: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text("You don't have approval access").font(.headline)
            Text("Approving time off needs the Time Off Approvals permission. Ask an administrator if you think that's wrong.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("PROPOSED — today this screen has no permission check at all. See AMB_BATCH2_PARITY.md finding 1.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

// MARK: - Detail

/// Reached ONLY from the Schedule today, and it operates on a CALENDAR ENTRY —
/// one per DAY of a multi-day request — not on the request. That distinction is
/// invisible in the current screen and is why cancelling from one day cancels the
/// whole request with no warning. The design says which it is.
private struct TimeOffDetailMockup: View {
    private let request = DesignLabSampleData.myTimeOff[0]

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: TimeOffMockup.featureTint, intensity: 0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    detailRows
                    spanNote
                    cancelButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Time Off")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: request.reason.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(request.reason.color)
                Text(request.reason.rawValue).font(.headline)
                Spacer(minLength: 0)
                AmbientBadge(text: request.status.label,
                             systemImage: request.status.symbol,
                             tint: request.status.color)
            }
            Text(Formatters.longDate.string(from: request.startDate))
                .font(.system(size: 22, weight: .bold))
            Text("\(request.timeLabel) · \(request.durationLabel)")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .ambientCard(density: .hero, state: .highlighted, glow: TimeOffMockup.featureTint, fillWidth: true)
    }

    private var detailRows: some View {
        VStack(spacing: 0) {
            row("Photographer", request.photographer)
            Divider()
            row("Type", request.isPartialDay ? "Partial day request" : "Full day request")
            Divider()
            if request.usesPTO, let hours = request.ptoHours {
                row("PTO hours", String(format: "%.1f", hours))
                Divider()
            }
            // Notes row is OMITTED ENTIRELY when empty — the app's real
            // behaviour, and better than an empty labelled row.
            if let notes = request.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes").font(.subheadline).foregroundStyle(.secondary)
                    Text(notes).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    /// The thing the current screen never says: this is one day of a five-day
    /// request, and cancelling cancels all of it.
    @ViewBuilder
    private var spanNote: some View {
        if request.dayCount > 1 {
            AmbientNoteCard(
                title: "Part of a longer request",
                text: "This is one day of a \(request.dayCount)-day request (\(request.dateLabel)). Cancelling here cancels all \(request.dayCount) days.",
                accent: .orange,
                density: .compact)
        }
    }

    /// Conditional on pending — as today. "Delete Time Off" is deliberately NOT
    /// drawn: it is shown only for APPROVED entries and calls a service that
    /// rejects anything that is not pending or under review, so every press is a
    /// guaranteed failure (parity finding 3). A button that can only fail is not
    /// a feature to preserve.
    @ViewBuilder
    private var cancelButton: some View {
        if request.status == .pending {
            Button {} label: {
                Label("Cancel Request", systemImage: "xmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    // ambient-allow: a control.
                    .background(Capsule().fill(Color.red.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - PTO balance

/// Today this is the only dedicated balance screen and it lives in Settings. The
/// redesign keeps it whole — every row, the accrual policy card and the
/// projection — and simply gives it a second, obvious route in from the surface
/// it is about.
private struct PTOBalanceMockup: View {
    private let balance = DesignLabSampleData.ptoBalance
    @State private var showUsedThisYear = false

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: TimeOffMockup.featureTint, intensity: 0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    breakdown
                    yearToDate
                    accrualPolicy
                    projection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("PTO Balance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(balance.available, specifier: "%.1f")")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text("hours available")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .ambientCard(density: .hero, state: .highlighted, glow: TimeOffMockup.featureTint, fillWidth: true)
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Breakdown")
            VStack(spacing: 0) {
                signedRow("Total Balance", balance.totalBalance, .primary)
                // Pending is conditional on being greater than zero.
                if balance.pendingHours > 0 {
                    Divider()
                    signedRow("Pending Requests", -balance.pendingHours, .orange)
                }
                Divider()
                signedRow("Available to Use", balance.available, .green, emphasised: true)
                // Banking is conditional on existing at all.
                if let banking = balance.bankingBalance {
                    Divider()
                    signedRow("Banking Balance", banking, .blue)
                }
            }
            .ambientCard(density: .compact, fillWidth: true)
        }
    }

    private var yearToDate: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Year to date")
            HStack(spacing: 10) {
                AmbientStatTile(value: Int(balance.usedThisYear), label: "Used this year",
                                systemImage: "calendar.badge.minus", tint: .orange)
                AmbientStatTile(value: Int(balance.totalAccrued), label: "Total accrued",
                                systemImage: "plus.circle", tint: .green)
            }
            // "Used This Year" is ALWAYS ZERO in the live app — the property is
            // declared outside CodingKeys so it is never decoded, and nothing
            // assigns it (parity finding 7). Drawn here with a real number
            // because a tile that always reads 0 is worse than no tile: it is a
            // wrong answer presented confidently.
            Text("Note: this number is never decoded in the live app and always reads 0. See AMB_BATCH2_PARITY.md finding 7 — either it gets decoded or the tile goes.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Conditional on the org having accrual settings AND having enabled them —
    /// and enabled DEFAULTS TO FALSE, so for most orgs this card simply is not
    /// there. Worth knowing when judging the screen with it present.
    @ViewBuilder
    private var accrualPolicy: some View {
        if balance.accrualEnabled {
            VStack(alignment: .leading, spacing: 8) {
                AmbientSectionTitle("Accrual policy", trailing: "off by default")
                VStack(spacing: 0) {
                    row("Rate", balance.accrualRate)
                    Divider()
                    row("Cap", balance.accrualCap)
                    Divider()
                    row("Rollover", balance.rolloverPolicy)
                }
                .ambientCard(density: .compact, fillWidth: true)
                Text("Accrual counts business days only, Monday to Friday, at 8 hours a day.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var projection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Projection")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Calculate balance for").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(Formatters.monthDay.string(from: DesignLabSampleData.day(30)))
                        .font(.subheadline.weight(.semibold))
                }
                Divider()
                HStack {
                    Text("Projected balance").font(.subheadline)
                    Spacer()
                    Text("\(balance.available + 6, specifier: "%.1f") h")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }
                Text("You will accrue 6.0 more hours by this date.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .ambientCard(density: .roomy, fillWidth: true)
        }
    }

    private func signedRow(_ label: String, _ value: Double, _ tint: Color, emphasised: Bool = false) -> some View {
        HStack {
            Text(label).font(emphasised ? .subheadline.weight(.semibold) : .subheadline)
            Spacer()
            Text("\(value >= 0 ? "+" : "−")\(abs(value), specifier: "%.1f") h")
                .font(.system(size: emphasised ? 17 : 15,
                              weight: emphasised ? .bold : .medium,
                              design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(.vertical, 7)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 7)
    }
}
