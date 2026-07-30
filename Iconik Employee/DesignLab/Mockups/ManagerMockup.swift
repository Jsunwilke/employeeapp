//  ManagerMockup.swift
//  Iconik Employee — AMB.12's manager tools, built in batch 4
//
//  ARC SCAFFOLDING. Deleted at AMB.12's close, with the rest of the lab.
//
//  SELF-CONTAINED ON PURPOSE. At the conversion these private types become a
//  `Manager Features/ManagerKit.swift` the lab then imports, the way Class Groups
//  and Yearbook went at AMB.10.
//
//  WHAT THIS COVERS, and what it deliberately does not
//      `Manager Features/` is 8 files. The JOB BOX half of it — the tracker and
//      its settings sheet — is drawn in `JobBoxMockup` instead, because job-box
//      functionality straddles two phases by DIRECTORY while being one feature to
//      the person using it. That split needs ONE operator ruling, not two, and it
//      is the same shape the operator already ruled on for ManagerMileageView.
//      `ManagerMileageView` itself is DEFERRED TO AMB.12 by that ruling and is
//      unconverted; its capability inventory lives in `AMB_BATCH3_PARITY.md`
//      (§ManagerMileageView) and is NOT restated here, so this mockup does not
//      redraw its root screen. What IS drawn here is the screen that hangs off it
//      and belongs to no other inventory — `ManagerEmployeeDetailView` — plus the
//      two reconciliations AMB.9 named and left: that screen's period anchor and
//      its hand-rolled currency spellings.
//
//  WHAT THE DESIGN IS ARGUING, in five claims
//
//      1. A SCREEN SHOWS ONLY WHAT YOU CAN ACTUALLY DO.
//         `FlagUserView` hides its picker when there are no users, and then draws
//         the note field and the "Flag User" button ANYWAY — outside the
//         permission block — so a photographer with no rights gets a complete,
//         live-looking form whose only possible outcome is "You don't have
//         permission to flag users."
//
//      2. ONE STRING MUST NOT BE THREE STATES.
//         "Loading users…" is simultaneously the loading state, the empty state
//         and the failed state on the flag screen — and `.onAppear` is attached to
//         that very `Text`, so after a failed load it persists forever and cannot
//         re-fire. The unflag screen has the mirror image: NO loading state at all,
//         so a green "All users are currently in good standing" renders DURING the
//         fetch, before anything is known.
//
//      3. UNFLAGGING IS A DECISION, NOT A TAP.
//         Unflag is one tap, irreversible from that screen, with no confirmation
//         and nothing showing who flagged the person or why beyond one line.
//
//      4. THE PERSON WHO WAS FLAGGED CAN SEE IT AND ANSWER IT.
//         Drawn as PROPOSED — see the caption. Today a flagged photographer has NO
//         in-app way to respond: only a manager can clear a flag.
//
//      5. AN EMPLOYEE DETAIL SCREEN IS NOT A DEAD END.
//         `ManagerEmployeeDetailView` has ZERO controls: the thumbnails, the "+N"
//         overflow tile and the photo-count chip are all non-interactive, so
//         photos past the fifth are unreachable, and a blank list with 0.0 is
//         simultaneously its loading, empty and offline state.
//
//  WHAT IS NOT BEING PROPOSED
//      No data layer, service, permission or schema changes (D12). Specifically
//      NOT promised: an employee-side UNFLAG REQUEST as a working feature (the
//      screen that would do it is unreachable and the two columns it writes have
//      zero readers — building it is a feature with its own phase), any change to
//      the `flag_user` / `unflag_user` RPCs (which enforce permission, org and
//      self-target server-side — the app-side checks are convenience, not the
//      boundary), any per-manager-feature permission gate (all seven manager
//      features are all-or-nothing on `users:edit` today, and one of them opens a
//      screen that gates on a different area entirely), and job-box FLAGGING,
//      which writes three columns that do not exist — see `JobBoxMockup`.
//
//  THE FLAG EXPERIENCE SPANS TWO PHASES' FILES
//      What a flagged employee sees is rendered in `MainEmployeeView`, which AMB.4
//      already converted: a dismissible bottom banner, a NON-dismissible inline
//      note card in the home scroll, and the whole home background turning RED.
//      Those three are deliberate and are NOT touched here. A redesign of the two
//      manager screens alone leaves the employee-facing half exactly as it is,
//      which is worth knowing before judging this one.

import SwiftUI

// MARK: - Lab state

private enum ManagerLabSurface: String, CaseIterable, Identifiable {
    case flag = "Flag"
    case unflag = "Unflag"
    case flagged = "Flagged"
    case employee = "Employee"

    var id: String { rawValue }
}

private enum ManagerLabState: String, CaseIterable, Identifiable {
    case ready = "Ready"
    case loading = "Loading"
    case empty = "Empty"
    case failed = "Failed"
    case denied = "No access"

    var id: String { rawValue }
}

// MARK: - Root

struct ManagerMockup: View {
    /// Two registered colours, both deliberately desaturated because manager tools
    /// are not daily photographer work: `flagUser` #C62A2F and `unflagUser`
    /// #5F8A6E. Note that `flagUser` sits in the PLANNING family beside the
    /// schedule rather than with the other manager tools — a palette oddity worth
    /// seeing on a device before it is either accepted or re-cut.
    static var flagTint: Color { FeatureTheme.color(for: "flagUser") }
    static var unflagTint: Color { FeatureTheme.color(for: "unflagUser") }
    static var mileageTint: Color { FeatureTheme.color(for: "managerMileage") }

    static var featureTint: Color { flagTint }

    @State private var surface: ManagerLabSurface = .flag
    @State private var state: ManagerLabState = .ready

    private var tint: Color {
        switch surface {
        case .flag: return Self.flagTint
        case .unflag, .flagged: return Self.unflagTint
        case .employee: return Self.mileageTint
        }
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: tint, intensity: 0.75)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    labControl
                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
    }

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · screen and state", trailing: "not a design element")
            Picker("Screen", selection: $surface) {
                ForEach(ManagerLabSurface.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("State", selection: $state) {
                ForEach(ManagerLabState.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch surface {
        case .flag: ManagerLabFlag(state: state)
        case .unflag: ManagerLabUnflag(state: state)
        case .flagged: ManagerLabFlaggedStatus()
        case .employee: ManagerLabEmployeeDetail(state: state)
        }
    }
}

// MARK: - Flag a photographer

private struct ManagerLabFlag: View {
    let state: ManagerLabState

    @State private var selected: String?
    @State private var note = ""

    private var members: [LabTeamMember] { DesignLabSampleData.teamMembers }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch state {
            case .denied:
                // 1 — a denied user sees ONLY this.
                VStack(spacing: 10) {
                    AmbientEmptyState(
                        title: "Access Denied",
                        message: "Only administrators and managers can flag users.",
                        systemImage: "lock.fill")
                    Text("Nothing else renders. Today the note field and the \"Flag User\" button sit OUTSIDE the permission block, so a denied user gets a complete, live-looking form that can only ever produce an error — and the button is never disabled on any path.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .loading:
                ManagerLabLoading(message: "Loading photographers…")
            case .failed:
                ManagerLabFailure(
                    message: "Couldn't load the team list.",
                    detail: "PROPOSED — a distinct failure state with a retry. Today \"Loading users…\" IS the loading state, the empty state and the failed state, and `.onAppear` is attached to that Text, so on a failed load it persists forever and can never re-fire.")
            case .empty:
                AmbientEmptyState(
                    title: "No one to flag",
                    message: "There is nobody else in this organization yet.",
                    systemImage: "person.2")
            case .ready:
                picker
                noteField
                submit
                captions
            }
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Photographer", trailing: selected == nil ? "required" : nil)
            ForEach(members) { member in
                Button {
                    withAnimation(AmbientMotion.snappy) { selected = member.id }
                    AmbientHaptics.selection()
                } label: {
                    HStack(spacing: 10) {
                        AmbientAvatar(name: member.fullName, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            // The FULL name, which is what makes two people called
                            // Chris distinguishable.
                            Text(member.fullName).font(AmbientDensity.compact.titleFont)
                            if !member.isActive {
                                Text("Inactive").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        Spacer(minLength: 0)
                        if selected == member.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ManagerMockup.flagTint)
                        }
                    }
                    .ambientCard(density: .compact, fillWidth: true)
                }
                .buttonStyle(.plain)
            }

            Text("FULL NAMES, and inactive people are marked. Today only the first name is carried into the picker's model, so two photographers called Chris are indistinguishable — and this screen calls the team query that returns INACTIVE users too, unlike the photographer query used everywhere else, so people who have left are offered with no indication.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var noteField: some View {
        AmbientFormSection(title: "Note",
                           status: note.isEmpty ? "required" : "\(note.count)/300",
                           statusTint: note.isEmpty ? .orange : nil) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Enter a note for flagging", text: $note, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(3...6)
                Text("The note is what the photographer READS — it is pushed to their device and drawn on their home screen. The 300-character limit is the push trigger's, not the field's; it is shown here because a note that gets truncated in the notification is worth knowing about while typing it.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var submit: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Flag \(selectedName ?? "photographer")")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                // ambient-allow: the primary action — a control, not a container.
                .background(Capsule().fill(selected == nil || note.isEmpty
                                           ? AnyShapeStyle(Color.secondary.opacity(0.4))
                                           : AnyShapeStyle(ManagerMockup.flagTint)))

            Text("Disabled until a person and a note exist. Today the button is never disabled and the two validation messages (\"Please select a user to flag.\", \"Please enter a flag note.\") arrive after the tap.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var selectedName: String? {
        members.first { $0.id == selected }?.fullName
    }

    private var captions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("KEPT: yourself excluded from the list, the case-insensitive sort, and the success message \"\\(name) flagged successfully.\" The write is unchanged — an RPC that checks permission, organization and self-targeting SERVER-side. That server check is the real boundary; the checks on this screen are convenience, and this design does not present them as security.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("PROPOSED — a success confirmation that names what happens next: the person is notified on their device and their home screen turns red until a manager clears it. Today the screen says only that the flag succeeded.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Unflag

private struct ManagerLabUnflag: View {
    let state: ManagerLabState
    @State private var confirming: String?

    private var flagged: [LabFlaggedUser] { DesignLabSampleData.flaggedUsers }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch state {
            case .denied:
                AmbientEmptyState(
                    title: "Access Denied",
                    message: "Only administrators and managers can unflag users.",
                    systemImage: "lock.fill")
            case .loading:
                VStack(alignment: .leading, spacing: 8) {
                    ManagerLabLoading(message: "Checking who is flagged…")
                    Text("PROPOSED — a loading state. This screen has NONE, so the green \"All users are currently in good standing\" renders DURING the fetch: for as long as the query takes, the app affirmatively tells a manager that nobody is flagged, before it knows.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .failed:
                ManagerLabFailure(
                    message: "Couldn't check flag status.",
                    detail: "PROPOSED — a failure state. Today a failed fetch is also drawn as the green all-clear.")
            case .empty:
                AmbientEmptyState(
                    title: "No Flagged Users",
                    message: "All users are currently in good standing",
                    systemImage: "checkmark.seal.fill")
            case .ready:
                VStack(alignment: .leading, spacing: 10) {
                    AmbientSectionTitle("Flagged", trailing: "\(flagged.count)")
                    ForEach(flagged) { user in
                        ManagerLabFlaggedRow(user: user,
                                             confirming: confirming == user.id) {
                            withAnimation(AmbientMotion.snappy) {
                                confirming = confirming == user.id ? nil : user.id
                            }
                        }
                    }
                    Text("Sorted by FULL name and showing the full name. Today the list sorts by full name and displays only the first, so two people sharing one look randomly ordered.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("3 — PROPOSED: unflagging asks first, and says what it does. Today it is a single tap on a blue \"Unflag\" button, irreversible from this screen, with no confirmation.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("KEPT: the flag note on the row, the permission guard that now gates the fetch as well as the view, and the success message \"\\(name) has been unflagged.\" NOT ADDED: search, sort or filter — there are none today and the list is a handful of people by nature.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct ManagerLabFlaggedRow: View {
    let user: LabFlaggedUser
    let confirming: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AmbientAvatar(name: user.fullName, size: 32, ringColor: ManagerMockup.flagTint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.fullName).font(AmbientDensity.compact.titleFont)
                    Text("Flagged by \(user.flaggedBy) · \(Formatters.mediumDate.string(from: user.flaggedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(user.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if confirming {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Clear this flag? \(user.fullName) stops seeing the note on their home screen. This cannot be undone from here — re-flagging is a new flag with a new note.")
                        .font(.caption2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button(action: onTap) {
                            Text("Cancel")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                // ambient-allow: an inline confirm button.
                                .background(Capsule().fill(.ultraThinMaterial))
                        }
                        .buttonStyle(.plain)
                        Text("Clear flag")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            // ambient-allow: the destructive-ish confirm — a control.
                            .background(Capsule().fill(ManagerMockup.unflagTint))
                    }
                }
            } else {
                Button(action: onTap) {
                    Text("Unflag")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        // ambient-allow: a row action — a control, not a container.
                        .background(Capsule().fill(ManagerMockup.unflagTint))
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}

// MARK: - What the flagged person sees, and cannot do

/// 4 — PROPOSED, and it is a FEATURE proposal rather than a restyle.
private struct ManagerLabFlaggedStatus: View {
    @State private var reply = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AmbientNoteCard(
                title: "Flag note from Alex Fontaine",
                text: "Three Lincoln retake cards came back with no job box scan at all — please scan the box in and out on every job this week so the tracker matches the cards.",
                accent: .red, density: .roomy)

            Text("This half already exists and is NOT redesigned here: the note is drawn twice on the home screen on purpose — a dismissible banner and a non-dismissible inline card — and the whole home background turns red while a flag is live. All three live in `MainEmployeeView`, which AMB.4 converted.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            AmbientFormSection(title: "Respond",
                               status: reply.isEmpty ? "optional" : "\(reply.count) characters",
                               statusTint: reply.isEmpty ? nil : ManagerMockup.unflagTint) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Tell your manager what happened", text: $reply, axis: .vertical)
                        .font(.subheadline)
                        .lineLimit(3...6)
                    Text("Ask to clear this flag")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        // ambient-allow: the primary action — a control.
                        .background(Capsule().fill(ManagerMockup.unflagTint))
                }
            }

            Text("PROPOSED — AND THIS ONE IS A FEATURE, NOT A RESTYLE. A screen for exactly this exists in the codebase and is UNREACHABLE: 104 lines with zero call sites anywhere in the tree. It is the only employee-side response to being flagged that has ever been written, and the two columns it writes have ZERO readers — nothing in either app, iOS or web, ever looks at them. So today a flagged photographer has no way at all to answer; only a manager can clear it.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("WHAT APPROVING THIS DRAWING WOULD AND WOULD NOT MEAN: it would not wire anything. Making it real needs a route into the screen, a reader for the request on the manager side (a queue, or a line on the unflag row), and a decision about whether a photographer asking to be unflagged should notify anyone. That is a phase. Drawn here because the alternative — deleting the dead screen quietly — throws away the only evidence that somebody once thought this was needed.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Manager employee detail

private struct ManagerLabEmployeeDetail: View {
    let state: ManagerLabState

    private var days: [LabManagerMileageDay] { DesignLabSampleData.managerMileageDays }
    private var total: Double { days.reduce(0) { $0 + $1.miles } }
    private var company: Double { days.filter(\.isCompany).reduce(0) { $0 + $1.miles } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch state {
            case .loading:
                VStack(alignment: .leading, spacing: 8) {
                    ManagerLabLoading(message: "Loading mileage…")
                    Text("PROPOSED — this screen has no loading, no empty and no offline state: a blank list under a 0.0 total is all three at once, on a screen a manager uses to check what someone is owed.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .failed:
                ManagerLabFailure(
                    message: "Couldn't load this photographer's mileage.",
                    detail: "PROPOSED — today the failure is an alert titled \"Error\" over an empty list showing 0.0 miles, and the zero stays on screen behind it.")
            case .empty:
                AmbientEmptyState(
                    title: "No mileage in this period",
                    message: "Nothing was filed in the last 14 days.",
                    systemImage: "car")
            case .denied, .ready:
                header
                rows
                captions
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AmbientAvatar(name: "Maria Alvarez", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Maria Alvarez").font(.system(size: 20, weight: .semibold))
                    Text("Last 14 days · \(Formatters.mediumDate.string(from: DesignLabSampleData.day(-13))) – \(Formatters.mediumDate.string(from: Date()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                AmbientStatTile(value: Int(total.rounded()), label: "miles this period",
                                systemImage: "car.fill", tint: ManagerMockup.mileageTint)
                AmbientStatTile(value: Int(company.rounded()), label: "company miles",
                                systemImage: "building.2.fill", tint: .orange)
                AmbientStatTile(value: days.count, label: "days filed",
                                systemImage: "calendar", tint: .secondary)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Days", trailing: "newest first")
            ForEach(days) { day in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Formatters.mediumDate.string(from: day.date))
                            .font(AmbientDensity.compact.titleFont)
                        Spacer(minLength: 8)
                        Text(String(format: "%.1f miles", day.miles))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ManagerMockup.mileageTint)
                    }
                    HStack(spacing: 8) {
                        Text(day.school).font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if day.isCompany { AmbientBadge(text: "Company", tint: .orange) }
                        if day.photoCount > 0 {
                            AmbientBadge(text: "\(day.photoCount) photos",
                                         systemImage: "photo.fill",
                                         tint: ManagerMockup.mileageTint)
                        }
                    }
                }
                .ambientCard(density: .compact, fillWidth: true)
            }
        }
    }

    private var captions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("5 — the photo count becomes a TAP. Today the thumbnails, the \"+N\" overflow tile and the count chip are all non-interactive: the screen has zero controls other than the system Back button, and any photo past the fifth is unreachable. Drawn here as a count that opens the day's report, which is where those photos already live.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("KEPT: the fixed 14-day window, the date-descending order, the personal/company split hidden when company mileage is zero, and the \"Unknown\" fallbacks. The nav bar stays deliberately empty of a title, with the name in the content.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("TWO RECONCILIATIONS AMB.9 HANDED TO THIS PHASE, and this drawing takes both: money is spelled ONCE, through the app's shared currency formatter — the manager mileage screen this pushes from has four hand-rolled spellings of it, two of which read wrong (a whole-dollar total as \"$12\", four figures as \"$1234.50\"). And the period: the manager screen anchors its own 14-day cycles to a hardcoded 2/25/2024 while the employee-facing screen uses the organization's configured pay periods, so the same fortnight can be two different windows depending on who is looking. This drawing labels the window explicitly rather than implying it agrees with anything; making the two agree is a data-layer change and is NOT proposed here.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("SCOPE, stated so it is not mistaken for done: `ManagerMileageView` — the root screen this one is pushed from — is deferred to AMB.12 by operator ruling and is NOT redrawn in this mockup. Its capabilities are inventoried in `AMB_BATCH3_PARITY.md`, not in batch 4's inventory, so a design for it belongs with that list in front of the operator.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Components

private struct ManagerLabLoading: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .ambientCard(density: .roomy, fillWidth: true, contentAlignment: .center)
    }
}

private struct ManagerLabFailure: View {
    let message: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button {} label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        // ambient-allow: a retry control, not a container.
                        .background(Capsule().fill(Color.orange))
                }
                .buttonStyle(.plain)
            }
            .ambientCard(density: .compact, fillWidth: true)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
