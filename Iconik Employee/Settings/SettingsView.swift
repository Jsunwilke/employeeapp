import SwiftUI

struct SettingsView: View {
    @StateObject private var tabBarManager = TabBarManager.shared
    @StateObject private var mainViewModel = MainEmployeeViewModel()
    @ObservedObject private var authService = SupabaseAuthService.shared
    @ObservedObject private var powerSync = PowerSyncManager.shared

    @State private var showingResyncAlert = false
    @State private var isResyncing = false
    @State private var resyncErrorMessage: String?

    /// User-set name for THIS iPad on the local sync bus. Surfaced in
    /// disconnect alerts on other devices and in the network status
    /// bar's device list. Falls back to UIDevice.current.name (often
    /// just "iPad") when blank — that default is unhelpful on a
    /// multi-iPad shoot.
    @AppStorage("fp_sync_custom_device_name") private var customDeviceName: String = ""

    var body: some View {
        List {
            Section("Account") {
                NavigationLink(destination: EmployeeInfoView()) {
                    Label("Account Info", systemImage: "person.crop.circle")
                }

                NavigationLink(destination: PTOBalanceView()) {
                    Label("PTO Balance", systemImage: "clock.fill")
                }

                NavigationLink(destination: ProfilePhotoView()) {
                    Label("Upload Profile Photo", systemImage: "photo")
                }
            }

            Section("Preferences") {
                NavigationLink(destination: SchoolInfoListView()) {
                    Label("School Info", systemImage: "building.2")
                }

                NavigationLink(destination: TabBarConfigurationView(
                    tabBarManager: tabBarManager,
                    mainViewModel: mainViewModel
                )) {
                    Label("Quick Access Tab Bar", systemImage: "square.grid.2x2")
                }
            }

            Section {
                TextField("e.g. Kiosk, Poser, Camera 2", text: $customDeviceName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)
                    .frame(minHeight: 44)
            } header: {
                Text("Device Name")
            } footer: {
                Text("Shown to other devices on the local network. Use this to tell iPads apart in the disconnect warning and the device list. Leave blank to use the iPad's system name. Reconnect on the Sync sheet (or restart the app) for a name change to take effect.")
            }

            Section {
                HStack {
                    Label("Status", systemImage: syncStatusIcon)
                        .foregroundColor(syncStatusColor)
                    Spacer()
                    Text(syncStatusText)
                        .foregroundColor(.secondary)
                }
                .frame(minHeight: 44)

                if let error = powerSync.lastSyncError {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Last Error", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minHeight: 44)
                    .padding(.vertical, 4)
                }

                if let lastSyncedAt = powerSync.lastSyncedAt {
                    HStack {
                        Label("Last Synced", systemImage: "clock")
                        Spacer()
                        Text(lastSyncedAt, style: .relative)
                            .foregroundColor(.secondary)
                    }
                    .frame(minHeight: 44)
                }

                Button(role: .destructive) {
                    showingResyncAlert = true
                } label: {
                    HStack {
                        Label("Resync Local Data", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        ZStack {
                            ProgressView()
                                .opacity(isResyncing ? 1 : 0)
                        }
                        .frame(width: 20, height: 20)
                    }
                    .frame(minHeight: 44)
                }
                .disabled(isResyncing || !powerSync.isConnected)
            } header: {
                Text("Sync & Cache")
            } footer: {
                if !powerSync.isConnected {
                    Text("Resync is disabled while offline. Connect to Wi-Fi first — clearing the local cache without a connection would leave the device with no data.")
                } else {
                    Text("Use only when this device is missing data that you can see on other devices.")
                }
            }

            Section {
                Button("Logout") {
                    Task {
                        do {
                            try await authService.signOut()
                        } catch {
                            print("Error signing out: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Settings")
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
    }

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
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
