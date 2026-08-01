//  FlagUserView.swift
//  Iconik Employee — flagging a photographer, converted to Ambient in AMB.12
//
//  THE DESIGN was `ManagerLabFlag` in `DesignLab/Mockups/ManagerMockup.swift`,
//  approved at the batch-4 sitting (2026-07-30). The shared pieces live in
//  `Manager Features/ManagerKit.swift`.
//
//  WHAT THE CONVERSION CHANGED, and why each is in scope:
//    · A SCREEN SHOWS ONLY WHAT YOU CAN DO. The note field and the "Flag User"
//      button used to sit OUTSIDE the permission block, so a photographer with no
//      rights got a complete, live-looking form whose only possible outcome was
//      "You don't have permission to flag users." A denied user now sees the
//      denial and nothing else — and the team query no longer runs for them.
//    · ONE STRING IS NO LONGER THREE STATES. "Loading users..." was the loading
//      state, the empty state AND the failed state, and `.onAppear` was attached to
//      that very `Text` — so after a failed load it persisted forever and could
//      never re-fire. Loading, empty and failed are three things now, the failure
//      offers a retry, and the load is attached to the screen rather than to a
//      string that disappears.
//    · FULL NAMES, AND INACTIVE PEOPLE ARE MARKED. Only `firstName` was carried
//      into the picker's model, so two photographers called Chris were
//      indistinguishable. This screen also calls `getTeamMembers`, which returns
//      rows with `is_active == false` — unlike `getPhotographers`, used everywhere
//      else — so people who have left were offered with no indication. Which query
//      is called is deliberately NOT changed (D12); the rows now say so.
//    · THE BUTTON IS DISABLED UNTIL IT CAN WORK. It was never disabled on any
//      path, and both validation messages arrived after the tap.
//    · THE CONFIRMATION NAMES WHAT HAPPENS NEXT — the person is notified on their
//      device and their home screen turns red until a manager clears it.
//
//  UNCHANGED ON PURPOSE: the write path (the `flag_user` RPC), yourself excluded
//  from the list, the case-insensitive sort by first name, and the success
//  sentence. The RPC checks permission, organization and self-targeting
//  SERVER-side; the `Permissions.has` check on this screen is convenience, not the
//  boundary, and nothing here presents it as security.
//
//  CLEARANCE: this is a SHELL-WRAPPED feature — `MainEmployeeView.featureContainer`
//  supplies the NavigationView, the Home button and the tab-bar clearance, so this
//  root adds only its own `AmbientBackdrop` (D14: no tint).

import SwiftUI

/// A user in the same organization, as this screen needs them.
struct Photographer: Identifiable, Hashable {
    let id: String
    /// The SORT key, kept because the list has always been ordered by first name.
    let firstName: String
    /// What the row SHOWS. Two people called Chris are two rows a manager can tell
    /// apart only if this is here.
    let fullName: String
    /// `getTeamMembers` returns people who have left; the row marks them.
    let isActive: Bool
}

struct FlagUserView: View {
    // Current user (flagger)'s UID.
    var currentUserID: String {
        UserManager.shared.getCurrentUserIDUnified() ?? "unknown"
    }

    // The current user's organization, from AppStorage.
    @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""
    @AppStorage("userRole") private var storedUserRole: String = "employee"

    // List of potential users to flag.
    @State private var photographers: [Photographer] = []
    @State private var selectedPhotographer: Photographer? = nil

    /// Loading, loaded and failed as three separate things — see `ManagerLoadState`.
    @State private var loadState: ManagerLoadState = .loading

    // Note for why we're flagging.
    @State private var flagNote: String = ""

    // Error/success feedback.
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""
    @State private var isFlagging = false

    private var tint: Color { ManagerStyle.flagTint }

    // Phase 7 RBAC — flagging team members is a users-edit operation
    var hasPermission: Bool {
        return Permissions.has("users", level: .edit)
    }

    /// The push trigger caps the note at 300 characters so an over-long note cannot
    /// blow the APNs payload limit invisibly. That cap is the FIELD's business too:
    /// a note that will be truncated in the notification is worth knowing about
    /// while it is being typed, not afterwards.
    private static let pushNoteLimit = 300

    private var trimmedNote: String {
        flagNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        selectedPhotographer != nil && !trimmedNote.isEmpty
    }

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .navigationTitle("Flag User")
        .navigationBarTitleDisplayMode(.inline)
        // ON THE SCREEN, NOT ON A STRING. This used to hang off the "Loading
        // users..." Text, which the first failed load replaced — taking the only
        // trigger with it, permanently.
        .onAppear(perform: loadPhotographersIfNeeded)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !hasPermission {
            // Claim 1: this is the WHOLE screen for a denied user. No field, no
            // button, nothing that looks like it could work.
            ManagerAccessDenied(message: "Only administrators and managers can flag users.")
        } else {
            switch loadState {
            case .loading:
                AmbientLoadingRow(message: "Loading photographers…")

            case .failed(let detail):
                VStack(alignment: .leading, spacing: 8) {
                    AmbientFailureCard(message: "Couldn't load the team list.",
                                       action: loadPhotographers)
                    // The server's own sentence is kept rather than swallowed —
                    // it is the only thing that distinguishes "no network" from
                    // "this organization id is wrong".
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

            case .loaded:
                if photographers.isEmpty {
                    AmbientEmptyState(
                        title: "No one to flag",
                        message: "There is nobody else in this organization yet.",
                        systemImage: "person.2")
                } else {
                    picker
                    noteField
                    submit
                    feedback
                }
            }
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Photographer",
                                trailing: selectedPhotographer == nil ? "required" : nil)
            ForEach(photographers) { user in
                ManagerPersonPickRow(fullName: user.fullName,
                                     isActive: user.isActive,
                                     isSelected: selectedPhotographer?.id == user.id,
                                     tint: tint) {
                    selectedPhotographer = user
                }
            }
        }
    }

    private var noteField: some View {
        AmbientFormSection(title: "Note",
                           status: flagNote.isEmpty
                               ? "required"
                               : "\(flagNote.count)/\(Self.pushNoteLimit)",
                           statusTint: flagNote.isEmpty ? .orange : nil) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Enter a note for flagging", text: $flagNote, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(3...6)
                Text("The note is what the photographer READS — it is pushed to their device and drawn on their home screen. Past \(Self.pushNoteLimit) characters the notification is truncated; the note itself is not.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var submit: some View {
        AmbientActionButton(title: submitTitle,
                            systemImage: "flag.fill",
                            tint: tint,
                            isLoading: isFlagging,
                            // DRAWN DISABLED, not just refused after the tap.
                            isEnabled: canSubmit) {
            flagSelectedUser()
        }
    }

    private var submitTitle: String {
        guard let name = selectedPhotographer?.fullName else { return "Flag photographer" }
        return "Flag \(name)"
    }

    @ViewBuilder
    private var feedback: some View {
        if !errorMessage.isEmpty {
            AmbientFailureCard(message: errorMessage, tint: .red)
        }
        if !successMessage.isEmpty {
            // WHAT HAPPENS NEXT, named. The old screen said only that the flag
            // succeeded, which is the one thing the manager already knew.
            AmbientNoteCard(
                title: "Flagged",
                text: "\(successMessage) They are notified on their device, and their home screen stays red until a manager clears the flag.",
                accent: tint,
                density: .compact)
        }
    }

    // MARK: - Loading

    /// Fires once per appearance while there is nothing loaded; the failure card's
    /// Retry calls `loadPhotographers` directly.
    private func loadPhotographersIfNeeded() {
        // FLG.1's lesson, applied here: the guard belongs on the FETCH, not only on
        // the rendered branch. This query returns the whole team to a device that
        // is being told it has no access.
        guard hasPermission else { return }
        guard photographers.isEmpty else { return }
        if case .failed = loadState { return }   // don't re-fire into a shown failure
        loadPhotographers()
    }

    /// Load photographers from Supabase, excluding current user.
    func loadPhotographers() {
        guard hasPermission else { return }
        loadState = .loading
        Task {
            do {
                let members = try await TeamService.shared.getTeamMembers(organizationID: storedUserOrganizationID)
                await MainActor.run {
                    // Exclude self and map to Photographer model
                    var temp: [Photographer] = []
                    for member in members {
                        if member.id == currentUserID { continue }
                        temp.append(Photographer(id: member.id,
                                                 firstName: member.firstName,
                                                 fullName: member.fullName,
                                                 isActive: member.isActive))
                    }
                    temp.sort { $0.firstName.lowercased() < $1.firstName.lowercased() }
                    photographers = temp
                    loadState = .loaded
                }
            } catch {
                await MainActor.run {
                    loadState = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Flag the selected user by calling the flag_user database function.
    func flagSelectedUser() {
        // These three guards are now unreachable from the button, which is disabled
        // until the first two are satisfied. They stay because this is the write
        // path: a screen state that ever gets ahead of them must refuse, not send.
        guard hasPermission else {
            errorMessage = "You don't have permission to flag users."
            return
        }

        guard let target = selectedPhotographer else {
            errorMessage = "Please select a user to flag."
            return
        }
        guard !trimmedNote.isEmpty else {
            errorMessage = "Please enter a flag note."
            return
        }
        // FLG.2: flagged_by is no longer sent from here -- the flag_user database function
        // records auth.uid() itself, so the attribution cannot be spoofed and the old
        // "unknown" fallback can no longer be persisted. This guard stays because the screen
        // should still refuse to act when there is no session, rather than surfacing a
        // permission error from the server.
        guard currentUserID != "unknown" else {
            errorMessage = "You appear to be signed out. Sign in again before flagging."
            return
        }
        errorMessage = ""
        successMessage = ""
        isFlagging = true

        Task {
            do {
                try await TeamService.shared.flagUser(
                    userId: target.id,
                    note: flagNote
                )

                // The push is fired by the trg_user_flagged_notification database trigger on
                // the is_flagged transition, not from here -- sending from the app would mean
                // calling send-notification, and that function is locked to service-role
                // callers because it accepts an arbitrary recipient list and arbitrary text
                // on a database shared with the web app and Captura.
                //
                // CORRECTION (FLG.1): the comment here previously said PSH.1 had done this.
                // It had not. PSH.1 created that trigger against flag_note and flagged_by,
                // which did not exist, then DROPPED it live when testing showed it would
                // raise and roll back every is_flagged update on a shared table. The trigger
                // is real as of FLG.1, which added the columns first:
                // 20260727_flg1_user_flag_notification.sql. Its payload follows PSH.1's own,
                // recovered from the sendFlagNotification function deleted from this file in
                // d61d475 -- same title, type and data, and the same note as the body except
                // that the trigger caps it at 300 characters so an over-long note cannot
                // blow the 4KB APNs payload limit invisibly.
                await MainActor.run {
                    successMessage = "\(target.fullName) flagged successfully."
                    isFlagging = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isFlagging = false
                }
            }
        }
    }
}
