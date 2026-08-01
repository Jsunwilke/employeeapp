//  SettingsView.swift
//  Iconik Employee — the Settings root, converted to Ambient in AMB.12
//
//  THREE THINGS THIS SCREEN ARGUES, and they are the approved design's claims 1–3.
//
//    1. SETTINGS HAS A COLOUR, AND IT IS THE COMPANY'S. There is no `"settings"`
//       case in the FeatureTheme map, so this tree would otherwise take the map's
//       `default: .gray`. It takes `AmbientStyle.brand` instead — see
//       `SettingsKit.SettingsStyle`.
//
//    2. THE SYNC BLOCK SAYS WHO IT IS FOR. Device Name, Sync & Cache and Metrics
//       are iPad-sync features shown unconditionally to every iPhone user, three
//       sections deep in the only screen a photographer opens to change their phone
//       number. They STAY — support needs them — but they sit under one heading
//       that says what they are, BELOW the rows people actually touch.
//
//    3. A DESTRUCTIVE ACTION LOOKS DESTRUCTIVE. "Logout" was a plain row with no
//       destructive role, no confirmation and no error path: the failure was
//       swallowed to a `print`, so a sign-out that did not happen looked exactly
//       like one that did — and the local PII purge that goes with it never ran. On
//       a shared iPad that is a PII-retention failure. Meanwhile Resync, which only
//       clears a cache, had both a confirmation and an alert. The two swap places.
//
//  KEPT WORD FOR WORD, because in this tree a sentence IS the feature: both resync
//  footers, the resync confirmation body and its destructive "Clear & Resync", the
//  "Resync Failed" alert, the device-name footer, the metrics footer, every sync
//  status string and its icon+colour mapping, the Last Error row with its
//  `.textSelection(.enabled)`, and Last Synced as a relative date. This is the ONE
//  screen in the tree that understands the device can be offline, and that
//  understanding is kept exactly.
//
//  ALSO FIXED HERE: no tab-bar clearance existed on this screen or on ANY screen it
//  pushes except PTOBalanceView, which insets itself — so the Log out button sat
//  UNDER the floating bar (G15). A safe-area inset only insets the view it is
//  applied to; it does NOT travel into a pushed screen, which is why every pushed
//  Settings screen now carries its own.

import SwiftUI

struct SettingsView: View {
    @StateObject private var tabBarManager = TabBarManager.shared
    @ObservedObject private var authService = SupabaseAuthService.shared
    @ObservedObject private var powerSync = PowerSyncManager.shared

    @State private var destination: SettingsDestination?

    @State private var showingResyncAlert = false
    @State private var isResyncing = false
    @State private var resyncErrorMessage: String?

    @State private var showingLogoutConfirmation = false
    @State private var isLoggingOut = false
    @State private var logoutErrorMessage: String?

    /// Nil until the count lands, and nil again if the query fails — a failed
    /// lookup must never render as "0 schools", which is the arc's law and the
    /// exact shape that hid a dead feature for a year elsewhere in this app.
    @State private var schoolCount: Int?

    // G16 is CLOSED, not worked around. `TabBarConfigurationView` no longer takes
    // a view model at all — the default feature list it needed is a `static`
    // constant now — so opening Settings no longer constructs a second copy of the
    // app's main view model, and no longer starts the second realtime subscription
    // that came with it.

    /// User-set name for THIS iPad on the local sync bus. Surfaced in disconnect
    /// alerts on other devices and in the network status bar's device list. Falls
    /// back to UIDevice.current.name (often just "iPad") when blank — that default
    /// is unhelpful on a multi-iPad shoot.
    @AppStorage("fp_sync_custom_device_name") private var customDeviceName: String = ""
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""

    /// ONE push target per view, with an enum when a screen needs several — the rule
    /// since AMB.3, because two stacked `NavigationLink(isActive:)` is the shape of
    /// AMB.1's dead tap.
    private enum SettingsDestination: Hashable, Identifiable {
        case account, photo, pto, schools, tabBar, appearance, metrics

        var id: String {
            switch self {
            case .account: return "account"
            case .photo: return "photo"
            case .pto: return "pto"
            case .schools: return "schools"
            case .tabBar: return "tabBar"
            case .appearance: return "appearance"
            case .metrics: return "metrics"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    youSection
                    deviceSection
                    logoutSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .tabBarClearance()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadSchoolCount)
        .alert("Resync Local Data?", isPresented: $showingResyncAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear & Resync", role: .destructive) {
                Task {
                    isResyncing = true
                    do {
                        try await powerSync.clearAndReSync()
                    } catch {
                        resyncErrorMessage = error.localizedDescription
                    }
                    isResyncing = false
                }
            }
        } message: {
            Text("Deletes all cached galleries, subjects, and images on this device, then re-downloads them. Any pending uploads (roster edits, captures, image numbers) that haven't reached the server will be lost. Stay on Wi-Fi until status returns to Synced.")
        }
        .alert("Resync Failed", isPresented: Binding(
            get: { resyncErrorMessage != nil },
            set: { if !$0 { resyncErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { resyncErrorMessage = nil }
        } message: {
            Text(resyncErrorMessage ?? "")
        }
        .confirmationDialog("Log out?", isPresented: $showingLogoutConfirmation, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) { signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Signing out clears this device's cached rosters, chats, schedule and personal details. You'll need your email and password to sign back in.")
        }
        .ambientPush(item: $destination) { destination in
            switch destination {
            case .account:
                EmployeeInfoView()
            case .photo:
                ProfilePhotoView()
            case .pto:
                PTOBalanceView()
            case .schools:
                SchoolInfoListView()
            case .tabBar:
                TabBarConfigurationView(tabBarManager: tabBarManager)
                    .tabBarClearance()
            case .appearance:
                AppearanceView()
            case .metrics:
                MetricsDashboardView()
            }
        }
    }

    // MARK: - You

    /// The rows a photographer actually opens, first — each with one line saying
    /// what is behind it. They were a bare word each ("Account Info", "School
    /// Info"), so the only way to learn what a row held was to open it.
    private var youSection: some View {
        VStack(alignment: .leading, spacing: AmbientDensity.compact.stackSpacing) {
            AmbientSectionTitle("You")

            AmbientNavRow(title: "Account Info",
                          detail: "Name, phone, address, position",
                          systemImage: "person.crop.circle",
                          tint: SettingsStyle.tint) { destination = .account }

            AmbientNavRow(title: "Profile Photo",
                          detail: "Shown on the schedule and in chat",
                          systemImage: "photo",
                          tint: SettingsStyle.tint) { destination = .photo }

            AmbientNavRow(title: "PTO Balance",
                          detail: "Hours available, accrual, projection",
                          systemImage: "clock.fill",
                          tint: SettingsStyle.tint) { destination = .pto }

            AmbientNavRow(title: "School Info",
                          detail: schoolInfoDetail,
                          systemImage: "building.2",
                          tint: SettingsStyle.tint) { destination = .schools }

            AmbientNavRow(title: "Quick Access Tab Bar",
                          detail: "Choose and reorder the bottom bar",
                          systemImage: "square.grid.2x2",
                          tint: SettingsStyle.tint) {
                destination = .tabBar
            }

            AmbientNavRow(title: "Appearance",
                          detail: "System, Light or Dark",
                          systemImage: "paintbrush",
                          tint: SettingsStyle.tint) { destination = .appearance }
        }
    }

    /// The count is dropped rather than guessed while it is unknown. A "0 schools"
    /// drawn over a failed query would be a statement of fact about data that was
    /// never read.
    private var schoolInfoDetail: String {
        guard let schoolCount else { return "Addresses, mileage, location photos" }
        return "\(schoolCount) school\(schoolCount == 1 ? "" : "s") · addresses, mileage, location photos"
    }

    // MARK: - This device

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: AmbientDensity.compact.stackSpacing) {
            AmbientSectionTitle("This device", trailing: syncStatusText.lowercased())

            deviceNameSection
            syncSection

            AmbientNavRow(title: "Metrics",
                          detail: "Live counters and latency for this device's sync activity",
                          systemImage: "chart.bar.xaxis",
                          tint: SettingsStyle.tint) { destination = .metrics }

            Text("Live counters, gauges, and latency histograms for this iPad's sync activity. Useful for support to diagnose connection or command issues.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deviceNameSection: some View {
        AmbientFormSection(title: "Device name",
                           status: customDeviceName.isEmpty ? "system name" : customDeviceName,
                           statusTint: nil) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("e.g. Kiosk, Poser, Camera 2", text: $customDeviceName)
                    .font(.subheadline)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)

                Text("Shown to other devices on the local network. Use this to tell iPads apart in the disconnect warning and the device list. Leave blank to use the iPad's system name. Reconnect on the Sync sheet (or restart the app) for a name change to take effect.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var syncSection: some View {
        AmbientFormSection(title: "Sync & cache",
                           status: syncStatusText,
                           statusTint: syncStatusColor) {
            VStack(alignment: .leading, spacing: 8) {
                // The status string, its icon and its colour together — all three
                // are the shipped mapping and all three are kept.
                HStack(alignment: .firstTextBaseline) {
                    Text("Status").font(.footnote).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Label(syncStatusText, systemImage: syncStatusIcon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(syncStatusColor)
                }

                if let lastSyncedAt = powerSync.lastSyncedAt {
                    HStack(alignment: .firstTextBaseline) {
                        Label("Last Synced", systemImage: "clock")
                            .font(.footnote).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        // Relative, as shipped — "2 minutes ago", not a timestamp.
                        Text(lastSyncedAt, style: .relative)
                            .font(.footnote.weight(.semibold))
                    }
                }

                if let error = powerSync.lastSyncError {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Last Error", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                        // Selectable, as shipped — support asks people to copy this.
                        Text(error)
                            .font(.footnote)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                Text(powerSync.isConnected
                     ? "Use only when this device is missing data that you can see on other devices."
                     : "Resync is disabled while offline. Connect to Wi-Fi first — clearing the local cache without a connection would leave the device with no data.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                // SECONDARY, not destructive. Resync clears a cache and re-downloads
                // it; the destructive treatment on this screen belongs to Log out.
                // The confirmation and its destructive "Clear & Resync" are kept.
                AmbientActionButton(title: "Resync Local Data",
                                    systemImage: "arrow.triangle.2.circlepath",
                                    role: .secondary,
                                    isLoading: isResyncing,
                                    isEnabled: powerSync.isConnected) {
                    showingResyncAlert = true
                }
            }
        }
    }

    // MARK: - Log out

    private var logoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let logoutErrorMessage {
                // The failure used to be a `print`. A sign-out that did not happen
                // now says so, and offers the retry, because the alternative is a
                // shared device that looks signed out and is not.
                AmbientFailureCard(message: logoutErrorMessage,
                                   tint: .red,
                                   actionTitle: "Try Again",
                                   action: signOut)
            }

            AmbientActionButton(title: "Log out",
                                role: .destructive,
                                isLoading: isLoggingOut) {
                showingLogoutConfirmation = true
            }
        }
    }

    // MARK: - Sync status (mapping kept exactly)

    private var syncStatusIcon: String {
        if isResyncing || powerSync.isDownloading { return "arrow.down.circle.fill" }
        if powerSync.isUploading { return "arrow.up.circle.fill" }
        if !powerSync.isConnected { return "wifi.exclamationmark" }
        return "checkmark.circle.fill"
    }

    private var syncStatusColor: Color {
        if isResyncing || powerSync.isDownloading || powerSync.isUploading { return .blue }
        if !powerSync.isConnected { return .orange }
        return .green
    }

    private var syncStatusText: String {
        if isResyncing { return "Resyncing…" }
        if powerSync.isDownloading { return "Downloading…" }
        if powerSync.isUploading { return "Uploading…" }
        if !powerSync.isConnected { return "Offline" }
        if powerSync.hasSynced { return "Synced" }
        return "Not synced"
    }

    // MARK: - Data

    private func loadSchoolCount() {
        guard !storedUserOrganizationID.isEmpty else { return }
        Task {
            let schools = try? await SchoolService.shared.getSchools(
                organizationID: storedUserOrganizationID)
            await MainActor.run {
                // A failed fetch leaves the count nil, so the row simply stops
                // claiming a number rather than claiming a wrong one.
                schoolCount = schools?.count
            }
        }
    }

    private func signOut() {
        logoutErrorMessage = nil
        isLoggingOut = true
        Task {
            do {
                try await authService.signOut()
                await MainActor.run { isLoggingOut = false }
            } catch {
                await MainActor.run {
                    isLoggingOut = false
                    logoutErrorMessage = "Couldn't sign out: \(error.localizedDescription)"
                }
            }
        }
    }
}
