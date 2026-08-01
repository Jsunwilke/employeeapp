//  AllFeaturesView.swift
//  Iconik Employee — every feature, and the order they sit in
//
//  CONVERTED IN AMB.12. It carried a drift-allowlist row and belonged to no
//  phase — one of the shell orphans the operator folded into the tail (D15).
//
//  IT STAYS A `List`, deliberately, and that is the one place this screen
//  departs from the arc's usual "ScrollView of ambient cards". Drag-to-reorder is
//  a real feature here — the order persists to `UserDefaults` and drives the home
//  dashboard — and `.onMove` needs a `List`. So the List keeps the behaviour and
//  loses the chrome: hidden scroll background, clear row backgrounds, no
//  separators, and every row drawn as an ambient card. Converting the container
//  and silently dropping the drag would be exactly the feature loss D12 exists to
//  stop.
//
//  FIXED HERE:
//    - THE 1Hz TIMER LEAK (batch 4 §0.31 / K5). `.task` installed a `Timer` AFTER
//      an `await` with no `Task.isCancelled` check — the precise leak the AMB.4
//      dashboard widget documents and guards against. Three independent 1Hz
//      timers for ONE clock could be live at once: the service's, this one, and
//      the HoursWidget's. The `Timer` is gone; the tick is now a structured loop
//      inside `.task`, which SwiftUI cancels when the view goes away.
//    - THE DEAD `userRole` (K11). Declared, passed in from the shell, never read.
//      Gone here and at the call site.
//    - THE THREE-ID LIST IN THREE PLACES. The photoshoot-notes org flag hid the
//      same three report ids from three separate hardcoded copies (here and twice
//      in `MainEmployeeView`). It now has ONE home, `FeatureItem.dailyReportIDs`.
//    - THE CLOCK CAPSULE was a hand-rolled `RoundedRectangle` — the allowlist row
//      this file carried. It is a CONTROL, so it is drawn as one and the row is
//      deleted from the gate rather than moved.
//
//  NOT CHANGED, and named so it is not mistaken for an oversight: the seven
//  manager features are all-or-nothing on `users:edit` with no per-item gate, and
//  the `timeOffApprovals` row is visible on that permission while the screen it
//  opens gates on a DIFFERENT area (`TimeOff/Views/TimeOffApprovalView.swift:14`).
//  That mismatch is real, documented, and belongs to TOF.1 — a restyle must not
//  quietly change who can see what.

import SwiftUI

struct AllFeaturesView: View {
    @ObservedObject var viewModel: MainEmployeeViewModel
    @ObservedObject var tabBarManager: TabBarManager
    @ObservedObject private var organizationService = OrganizationService.shared
    @State private var localEditMode: EditMode = .inactive
    @ObservedObject private var timeTrackingService = TimeTrackingService.shared
    @State private var elapsedTime: String = "00:00:00"
    @State private var clockErrorMessage: String?
    @State private var showClockError = false

    /// The manager set. `MainEmployeeView` used to carry an identical copy of this
    /// array that nothing read; that copy is deleted, and this is the live one.
    let managerFeatures: [FeatureItem] = [
        FeatureItem(id: "timeOffApprovals", title: "Time Off Approvals", systemImage: "checkmark.circle.fill", description: "Approve or deny time off requests"),
        FeatureItem(id: "flagUser", title: "Flag User", systemImage: "flag.fill", description: "Flag a user in your organization"),
        FeatureItem(id: "unflagUser", title: "Unflag User", systemImage: "flag.slash.fill", description: "Unflag a previously flagged user"),
        FeatureItem(id: "managerMileage", title: "Manager Mileage", systemImage: "car.2.fill", description: "View mileage reports for all employees"),
        FeatureItem(id: "stats", title: "Statistics", systemImage: "chart.bar.fill", description: "View business analytics and statistics"),
        FeatureItem(id: "galleryCreator", title: "Gallery Creator", systemImage: "photo.on.rectangle.angled", description: "Create galleries in Captura and Google Sheets"),
        FeatureItem(id: "jobBoxTracker", title: "Job Box Tracker", systemImage: "cube.box.fill", description: "Track and manage job box status")
    ]

    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            AmbientBackdrop(intensity: 0.7)

            List {
                // THE TITLES ARE ROWS, NOT `Section` HEADERS, and that is not a
                // style preference. `.listStyle(.plain)` PINS a section header, so
                // the converted heading floated over the cards as they scrolled
                // under it — caught on the simulator, not in the code. A plain row
                // scrolls with its section, which is what the design draws.
                Section {
                    AmbientSectionTitle("Employee Features",
                                        trailing: localEditMode == .active ? "drag to reorder" : nil)
                        .textCase(nil)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 2, trailing: 16))
                        // Excluded from the reorder: `onMove` indexes into the
                        // section's rows, so a title inside it would shift every
                        // drop by one.
                        .moveDisabled(true)

                    ForEach(filteredEmployeeFeatures) { feature in
                        featureRow(feature, reorderable: true)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onMove(perform: localEditMode == .active ? moveEmployeeFeatures : nil)
                }

                // Phase 7 RBAC — manager features visible if the user has edit on
                // team management. Unchanged: this is the file's ONLY permission
                // check, and it is section-level.
                if Permissions.has("users", level: .edit) {
                    Section {
                        AmbientSectionTitle("Management Features")
                            .textCase(nil)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 2, trailing: 16))

                        ForEach(managerFeatures) { feature in
                            featureRow(feature, reorderable: false)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        // Room for the floating tab bar (AMB.4). Needed here because this is a
        // PUSHED screen: the shell's clearance insets a navigation container's root,
        // and a pushed view does not inherit it — without this the last row of the
        // list cannot be scrolled clear of the capsule.
        .tabBarClearance()
        .navigationTitle("All Features")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarContent
        }
        .environment(\.editMode, $localEditMode)
        .alert("Clock In/Out Failed", isPresented: $showClockError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(clockErrorMessage ?? "Something went wrong. Your time may not have been recorded — please try again or check your connection.")
        }
        .task {
            await timeTrackingService.refreshUserAndStatus()
            await runElapsedClock()
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func featureRow(_ feature: FeatureItem, reorderable: Bool) -> some View {
        let editing = reorderable && localEditMode == .active

        if editing {
            // No Button in edit mode: a live navigation target inside a drag
            // session is how a reorder turns into an accidental push.
            featureRowBody(feature, trailingSymbol: "line.3.horizontal")
        } else {
            Button {
                tabBarManager.selectedTab = feature.id
                dismiss()
            } label: {
                featureRowBody(feature, trailingSymbol: "chevron.right")
            }
            .buttonStyle(.plain)
        }
    }

    private func featureRowBody(_ feature: FeatureItem, trailingSymbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: feature.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(FeatureTheme.color(for: feature.id)))

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title).font(AmbientDensity.compact.titleFont)
                Text(feature.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: trailingSymbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .ambientCard(density: .compact, fillWidth: true)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feature.title). \(feature.description)")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                Task { await toggleClock() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: timeTrackingService.isClockIn ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 20))

                    if timeTrackingService.isClockIn {
                        Text(elapsedTime)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    } else {
                        Text("Clock In")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                }
                .foregroundStyle(timeTrackingService.isClockIn ? .red : .green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                // ambient-allow: a toolbar control, not a container.
                .background(Capsule().fill(timeTrackingService.isClockIn
                                           ? Color.red.opacity(0.12)
                                           : Color.green.opacity(0.12)))
            }
            .accessibilityLabel(timeTrackingService.isClockIn
                                ? "Clock out. Clocked in for \(elapsedTime)"
                                : "Clock in")
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            if localEditMode == .active {
                Button("Done") {
                    withAnimation { localEditMode = .inactive }
                    viewModel.saveEmployeeFeatureOrder()
                }
            } else {
                Button("Edit") {
                    withAnimation { localEditMode = .active }
                }
            }
        }
    }

    /// The title row sits at index 0 of the same section, so the indices `onMove`
    /// hands back are one ahead of the feature array. Shifting them here keeps the
    /// view model's mover unchanged — the alternative, a second section purely for
    /// the heading, breaks the drag across the boundary.
    private func moveEmployeeFeatures(from source: IndexSet, to destination: Int) {
        let shifted = IndexSet(source.compactMap { $0 > 0 ? $0 - 1 : nil })
        guard !shifted.isEmpty else { return }
        viewModel.moveEmployeeFeatures(from: shifted, to: max(0, destination - 1))
    }

    // MARK: - Clock

    private func toggleClock() async {
        do {
            if timeTrackingService.isClockIn {
                try await timeTrackingService.clockOut()
            } else {
                try await timeTrackingService.clockIn()
            }
        } catch {
            // Clock in/out is payroll data — never fail silently.
            print("Clock in/out error: \(error.localizedDescription)")
            await MainActor.run {
                clockErrorMessage = error.userFacingMessage
                showClockError = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    /// The elapsed readout, as a structured loop rather than a `Timer`.
    ///
    /// The `Timer` version was installed after an `await` with no cancellation
    /// check, so a view that went away mid-refresh left a 1Hz timer running for
    /// the process's lifetime. This loop lives inside `.task` and dies with it.
    ///
    /// `try?` on the sleep swallows the cancellation error, so the `while`
    /// condition — not the throw — is what ends the loop. That is deliberate and
    /// it is why the condition is checked at the TOP: a cancelled sleep costs one
    /// extra iteration, not a spin. (`RootView` had the same `try?` with no such
    /// guard, which is a tight main-actor spin; that one is fixed in its own file
    /// this phase.)
    private func runElapsedClock() async {
        while !Task.isCancelled {
            if timeTrackingService.isClockIn {
                let elapsed = timeTrackingService.elapsedTime
                let hours = Int(elapsed) / 3600
                let minutes = Int(elapsed) % 3600 / 60
                let seconds = Int(elapsed) % 60
                elapsedTime = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    // MARK: - Filtered features

    /// Employee features filtered by the organization's photoshoot-notes flag.
    private var filteredEmployeeFeatures: [FeatureItem] {
        guard organizationService.usePhotoshootNotesOnly else { return viewModel.employeeFeatures }
        return viewModel.employeeFeatures.filter { !FeatureItem.dailyReportIDs.contains($0.id) }
    }
}
