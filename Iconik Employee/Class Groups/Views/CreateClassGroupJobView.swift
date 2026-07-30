//  CreateClassGroupJobView.swift
//  Iconik Employee — picking a session, converted to Ambient in AMB.10
//
//  The old screen is GONE from this file: the bare `NavigationView` with no style
//  modifier (so this sheet could render SPLIT on iPad while the add sheet could
//  not), the `InsetGroupedListStyle` rows, the private `ClassGroupSessionRowView`
//  with its per-row `DateFormatter` and its `Color.blue.opacity(0.1)` selection
//  wash, and the emoji `print`s.
//
//  THE TYPE NAME AND THE `(initialJobType:onComplete:)` SIGNATURE ARE KEPT ON
//  PURPOSE: `DashboardWidgets.swift:1382` presents this sheet DIRECTLY, bypassing
//  the feature screen entirely, and renaming it would push churn into a surface
//  AMB.4 already shipped.
//
//  THE DESIGN CHANGE IS HONESTY ABOUT THE WINDOW. The old empty state said "in the
//  next 2 weeks" and offered no escape, and that window is hard-coded SERVER-SIDE
//  (`ClassGroupJobService.swift:90-91`) — so a date-range control here would be a
//  promise the service cannot keep. Two captions say what the list is instead: what
//  "available" means, and that the choice cannot be cleared once made (which is how
//  the screen has always behaved, discovered rather than stated).
//
//  ALSO FIXED, because it is this view's own bug rather than the service's: the
//  loaders wrote `@State` straight from the `UserManager` callback thread with no
//  main hop.

import SwiftUI

struct CreateClassGroupJobView: View {
    @Environment(\.dismiss) private var dismiss

    let onComplete: (String) -> Void // Pass back the job ID
    let initialJobType: String

    @State private var availableSessions: [Session] = []
    @State private var selectedSession: Session?
    @State private var selectedJobType: String
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false

    private let service = ClassGroupJobService.shared

    private var tint: Color { ClassGroupsStyle.tint }

    init(initialJobType: String = "classGroups", onComplete: @escaping (String) -> Void) {
        self.initialJobType = initialJobType
        self.onComplete = onComplete
        self._selectedJobType = State(initialValue: initialJobType)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: tint, intensity: 0.6)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .ambientNoBounceWhenShort()
            }
            .navigationTitle("Create \(ClassGroupJobType.singularTitle(selectedJobType)) Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Job") { createJob() }
                        .disabled(selectedSession == nil || isLoading)
                }
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                // The type comes from wherever the sheet was opened and is never
                // changed here — there is no job-type picker on this screen.
                selectedJobType = initialJobType
                loadAvailableSessions()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && availableSessions.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading available sessions…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else if availableSessions.isEmpty {
            noSessionsState
        } else {
            sessionList
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Available sessions", trailing: "\(availableSessions.count)")

            LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                ForEach(availableSessions) { session in
                    Button {
                        withAnimation(AmbientMotion.snappy) { selectedSession = session }
                        AmbientHaptics.selection()
                    } label: {
                        ClassGroupSessionCard(
                            dateLabel: ClassGroupSessionCard.dateLabel(for: session.startDate),
                            schoolName: session.schoolName,
                            sessionTypes: session.sessionType,
                            isSelected: selectedSession?.id == session.id,
                            tint: tint)
                    }
                    .buttonStyle(.plain)
                    .ambientScrollFade()
                }
            }

            Text("Sessions in the next 2 weeks without a \(ClassGroupJobType.rowNoun(selectedJobType)) job. The window is set on the server — there is no date range to change here.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("One session per job, and the choice can't be cleared once made.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var noSessionsState: some View {
        VStack(spacing: 10) {
            AmbientEmptyState(
                title: "No Available Sessions",
                message: "There are no upcoming sessions without \(ClassGroupJobType.rowNoun(selectedJobType)) jobs in the next 2 weeks.",
                systemImage: "calendar.badge.exclamationmark")
            Text("\"Available\" means a scheduled session in the next 2 weeks that has no \(ClassGroupJobType.rowNoun(selectedJobType)) job yet. The window is set on the server, so there is nothing to widen from here.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Data

    private func loadAvailableSessions() {
        isLoading = true

        // Captured on the main thread, so the callback below never READS `@State`
        // off-actor — the writes are hopped, and the read has to match.
        let jobType = selectedJobType

        UserManager.shared.getCurrentUserOrganizationID { organizationId in
            guard let orgId = organizationId else {
                DispatchQueue.main.async {
                    self.errorMessage = "Unable to determine organization"
                    self.showingErrorAlert = true
                    self.isLoading = false
                }
                return
            }

            service.getUpcomingSessions(organizationId: orgId, jobType: jobType) { result in
                DispatchQueue.main.async {
                    self.isLoading = false

                    switch result {
                    case .success(let sessions):
                        self.availableSessions = sessions
                    case .failure(let error):
                        self.errorMessage = "Failed to load sessions: \(error.localizedDescription)"
                        self.showingErrorAlert = true
                    }
                }
            }
        }
    }

    private func createJob() {
        guard let session = selectedSession else { return }
        let schoolId = session.schoolId

        isLoading = true

        // Same capture as the loader: no `@State` read from the callback thread.
        let jobType = selectedJobType

        UserManager.shared.getCurrentUserOrganizationID { organizationId in
            guard let orgId = organizationId else {
                DispatchQueue.main.async {
                    self.errorMessage = "Unable to determine organization"
                    self.showingErrorAlert = true
                    self.isLoading = false
                }
                return
            }

            service.createClassGroupJob(
                sessionId: session.id,
                sessionDate: session.startDate ?? Date(),
                schoolId: schoolId,
                schoolName: session.schoolName,
                organizationId: orgId,
                jobType: jobType
            ) { result in
                DispatchQueue.main.async {
                    self.isLoading = false

                    switch result {
                    case .success(let jobId):
                        self.onComplete(jobId)
                        self.dismiss()
                    case .failure(let error):
                        self.errorMessage = "Failed to create job: \(error.localizedDescription)"
                        self.showingErrorAlert = true
                    }
                }
            }
        }
    }
}
