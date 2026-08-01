//  UnflagUserView.swift
//  Iconik Employee — clearing a flag, converted to Ambient in AMB.12
//
//  THE DESIGN was `ManagerLabUnflag` in `DesignLab/Mockups/ManagerMockup.swift`,
//  approved at the batch-4 sitting (2026-07-30). The shared pieces live in
//  `Manager Features/ManagerKit.swift`.
//
//  WHAT THE CONVERSION CHANGED, and why each is in scope:
//    · THERE IS A LOADING STATE. This screen had NONE, so the green "All users are
//      currently in good standing" rendered DURING the fetch: for as long as the
//      query took, the app affirmatively told a manager that nobody was flagged,
//      before it knew. A FAILED fetch was drawn as that same green all-clear.
//    · UNFLAGGING ASKS FIRST. It was one tap on a blue "Unflag" button,
//      irreversible from this screen, with no confirmation. The row now expands
//      into what clearing does — and says that re-flagging is a new flag with a new
//      note rather than an undo.
//    · THE ROW SHOWS THE FULL NAME. The list SORTED by full name and DISPLAYED only
//      the first, so two people sharing a first name looked randomly ordered. It
//      also names who flagged them, resolved from the `flagged_by` id the
//      flagged-users query already returns.
//
//  UNCHANGED ON PURPOSE: the flag note on the row, the permission guard that gates
//  the FETCH as well as the view (FLG.1), the "Access Denied" copy, the
//  "No Flagged Users" / "All users are currently in good standing" all-clear, the
//  success sentence, and the write path (the `unflag_user` RPC). NOT ADDED: search,
//  sort or filter — there are none today and the list is a handful of people by
//  nature.
//
//  WHAT THE APPROVED DRAWING ASKS FOR AND THE DATABASE CANNOT GIVE: the mockup's
//  row reads "Flagged by X · <date>". `public.users` carries `flag_note` and
//  `flagged_by` (FLG.1) and NO flagged-at column, so there is no date to show and
//  inventing one would be a schema change (D12). The row states the flagger and
//  stops.
//
//  CLEARANCE: this is a SELF-NAV feature (`MainEmployeeView.isSelfNavFeature`) — it
//  owns its `NavigationView` and therefore applies `.homeToolbarItem()` and
//  `.tabBarClearance()` itself, inside that container, which is the only position
//  that works for a legacy NavigationView (AMB.4).

import SwiftUI

// Model representing a flagged user.
struct FlaggedUser: Identifiable, Hashable {
    let id: String
    /// The FULL name — the list has always sorted by it and shown only the first.
    let fullName: String
    let flagNote: String
    /// `users.flagged_by`, an id. Resolved to a name for display; never drawn raw.
    let flaggedByID: String?
}

struct UnflagUserView: View {
    @State private var flaggedUsers: [FlaggedUser] = []
    @State private var loadState: ManagerLoadState = .loading
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""

    /// The row awaiting its confirmation, if any. One at a time: opening a second
    /// closes the first, so two rows can never both be armed.
    @State private var confirmingID: String?
    /// The row whose clear is in flight.
    @State private var clearingID: String?

    /// flagged_by id → that person's name. Resolved once per id through the
    /// existing `TeamService.getTeamMember`, and left out of the row entirely when
    /// it cannot be resolved.
    @State private var flaggerNames: [String: String] = [:]

    // User role from AppStorage
    @AppStorage("userRole") private var storedUserRole: String = "employee"
    @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""

    private var tint: Color { ManagerStyle.unflagTint }

    // Phase 7 RBAC — unflagging team members is a users-edit operation
    var hasPermission: Bool {
        return Permissions.has("users", level: .edit)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        feedback
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .ambientNoBounceWhenShort()
            }
            .navigationTitle("Unflag Users")
            .homeToolbarItem()
            // Room for the app's floating bar. Applied inside this screen's own
            // navigation container, because the shell cannot reach into a self-nav
            // feature (AMB.4).
            .tabBarClearance()
            .onAppear {
                // FLG.1: gated on the permission, not just the rendered branch. This is the
                // ONE query that deliberately returns flag_note and flagged_by, and it was
                // firing even for someone shown "Access Denied" -- so the note reached a
                // device that was being told it had no access. The view's own guard is not a
                // fetch guard.
                guard hasPermission else { return }
                loadFlaggedUsers()
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var feedback: some View {
        // A failure of the WRITE, which is a different claim from a failure of the
        // fetch and is drawn beside the list rather than instead of it.
        if !errorMessage.isEmpty {
            AmbientFailureCard(message: errorMessage, tint: .red)
        }
        if !successMessage.isEmpty {
            AmbientNoteCard(title: "Cleared",
                            text: successMessage,
                            accent: tint,
                            density: .compact)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !hasPermission {
            ManagerAccessDenied(message: "Only administrators and managers can unflag users.")
        } else {
            switch loadState {
            case .loading:
                AmbientLoadingRow(message: "Checking who is flagged…")

            case .failed(let detail):
                VStack(alignment: .leading, spacing: 8) {
                    // NOT the green all-clear, which is what a failed fetch used to
                    // draw. An empty state is a statement about the data; this is a
                    // statement about the connection.
                    AmbientFailureCard(message: "Couldn't check flag status.",
                                       action: loadFlaggedUsers)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

            case .loaded:
                if flaggedUsers.isEmpty {
                    AmbientEmptyState(
                        title: "No Flagged Users",
                        message: "All users are currently in good standing",
                        systemImage: "checkmark.seal.fill")
                } else {
                    list
                }
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Flagged", trailing: "\(flaggedUsers.count)")
            ForEach(flaggedUsers) { user in
                ManagerFlaggedUserRow(
                    fullName: user.fullName,
                    flaggedByName: user.flaggedByID.flatMap { flaggerNames[$0] },
                    note: user.flagNote,
                    isConfirming: confirmingID == user.id,
                    isClearing: clearingID == user.id,
                    tint: tint,
                    onToggleConfirm: {
                        withAnimation(AmbientMotion.snappy) {
                            confirmingID = confirmingID == user.id ? nil : user.id
                        }
                    },
                    onConfirmClear: { unflagUser(user) })
            }
        }
    }

    // MARK: - Data

    // Fetch flagged users from Supabase.
    func loadFlaggedUsers() {
        loadState = .loading
        Task {
            do {
                let members = try await TeamService.shared.getFlaggedUsers(organizationID: storedUserOrganizationID)
                await MainActor.run {
                    flaggedUsers = members.map { member in
                        FlaggedUser(
                            id: member.id,
                            fullName: member.fullName,
                            flagNote: member.flagNote ?? "",
                            flaggedByID: member.flaggedBy
                        )
                    }
                    loadState = .loaded
                }
                await resolveFlaggerNames(in: members)
            } catch {
                await MainActor.run {
                    loadState = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Turn the `flagged_by` ids into names, one lookup per DISTINCT id.
    ///
    /// The id is passed to the query EXACTLY as it was stored. `users.id` is mostly
    /// lowercase but carries one 28-character mixed-case Firebase id from the
    /// migration, and a PostgREST `.eq` on a TEXT column is case-SENSITIVE while a
    /// zero-row result is a silent nothing — normalising the case here would drop
    /// that person's name for no reason.
    @MainActor
    private func resolveFlaggerNames(in members: [TeamMember]) async {
        // The FETCHED rows, not the @State copy — the ids are read from the same
        // array the names are being resolved for.
        let pending = Set(members.compactMap { $0.flaggedBy })
            .filter { !$0.isEmpty && flaggerNames[$0] == nil }
        for id in pending {
            // A name that cannot be resolved is simply not drawn — the row omits
            // the line rather than printing an id at a manager.
            if let member = try? await TeamService.shared.getTeamMember(userId: id) {
                flaggerNames[id] = member.fullName
            }
        }
    }

    // Unflag the selected user.
    func unflagUser(_ user: FlaggedUser) {
        // Check permission first
        guard hasPermission else {
            errorMessage = "You don't have permission to unflag users."
            return
        }

        // FLG.1: clear BOTH messages before starting. unflagUser now throws when the update
        // matched no row, and without this a manager who unflags one person successfully and
        // then fails on the next sees a green success and a red failure at the same time --
        // which defeats the point of making the failure visible in the first place.
        errorMessage = ""
        successMessage = ""
        clearingID = user.id

        Task {
            do {
                try await TeamService.shared.unflagUser(userId: user.id)
                await MainActor.run {
                    successMessage = "\(user.fullName) has been unflagged."
                    clearingID = nil
                    confirmingID = nil
                    // Refresh the list.
                    loadFlaggedUsers()
                }
            } catch {
                await MainActor.run {
                    successMessage = ""
                    errorMessage = error.localizedDescription
                    clearingID = nil
                }
            }
        }
    }
}

struct UnflagUserView_Previews: PreviewProvider {
    static var previews: some View {
        UnflagUserView()
    }
}
