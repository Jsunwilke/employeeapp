//
//  PowerSyncDiagnosticsView.swift
//  Iconik Employee
//
//  Diagnostic view to help troubleshoot PowerSync sync issues
//

import SwiftUI

struct PowerSyncDiagnosticsView: View {
    @StateObject private var powerSync = PowerSyncManager.shared
    @State private var diagnosticInfo: [String] = []
    @State private var isRunningDiagnostics = false
    @State private var rosterCount = 0
    @State private var groupCount = 0
    @State private var selectedJobId: UUID?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Connection Status
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Connection Status")
                                .font(.headline)

                            HStack {
                                Circle()
                                    .fill(powerSync.isConnected ? Color.green : Color.red)
                                    .frame(width: 12, height: 12)

                                Text(powerSync.isConnected ? "Connected" : "Disconnected")
                                    .foregroundColor(powerSync.isConnected ? .green : .red)
                            }

                            Text("Database: Initialized")
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }

                    // Job ID Input
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Test Job ID")
                                .font(.headline)

                            TextField("Enter Job UUID", text: Binding(
                                get: { selectedJobId?.uuidString ?? "" },
                                set: { selectedJobId = UUID(uuidString: $0) }
                            ))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)

                            Button(action: {
                                runDiagnostics()
                            }) {
                                HStack {
                                    if isRunningDiagnostics {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text("Run Diagnostics")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(isRunningDiagnostics || selectedJobId == nil)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }

                    // Results
                    if !diagnosticInfo.isEmpty {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Diagnostic Results")
                                    .font(.headline)

                                Text("Roster Entries: \(rosterCount)")
                                Text("Group Images: \(groupCount)")

                                Divider()

                                ForEach(diagnosticInfo, id: \.self) { info in
                                    Text(info)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(
                                            info.contains("❌") ? .red :
                                            info.contains("✅") ? .green :
                                            info.contains("⚠️") ? .orange :
                                            .primary
                                        )
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("PowerSync Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func runDiagnostics() {
        guard let jobId = selectedJobId else { return }

        isRunningDiagnostics = true
        diagnosticInfo = []

        Task {
            await performDiagnostics(jobId: jobId)
            await MainActor.run {
                isRunningDiagnostics = false
            }
        }
    }

    private func performDiagnostics(jobId: UUID) async {
        var logs: [String] = []

        logs.append("🔍 Starting diagnostics for job: \(jobId.uuidString)")
        logs.append("📱 Device: \(UIDevice.current.model)")
        logs.append("📡 Network: \(powerSync.isConnected ? "Connected" : "Disconnected")")

        logs.append("✅ PowerSync manager initialized")

        // Try to fetch roster entries
        do {
            logs.append("🔍 Querying roster_entries table...")
            let entries = try await powerSync.getRosterEntries(forJob: jobId)
            logs.append("✅ Query successful - Found \(entries.count) roster entries")

            await MainActor.run {
                rosterCount = entries.count
            }

            // Show first 3 entries
            for (index, entry) in entries.prefix(3).enumerated() {
                logs.append("  Entry \(index + 1): \(entry.firstName) \(entry.lastName)")
            }

            if entries.isEmpty {
                logs.append("⚠️ No roster entries found in local database")
                logs.append("⚠️ This could mean:")
                logs.append("  • PowerSync hasn't synced down data yet")
                logs.append("  • No data exists in Supabase for this job")
                logs.append("  • Job ID doesn't match (UUID case mismatch?)")
            }
        } catch {
            logs.append("❌ Failed to query roster_entries: \(error.localizedDescription)")
        }

        // Try to fetch group images
        do {
            logs.append("🔍 Querying group_images table...")
            let groups = try await powerSync.getGroupImages(forJob: jobId)
            logs.append("✅ Query successful - Found \(groups.count) group images")

            await MainActor.run {
                groupCount = groups.count
            }

            // Show first 3 groups
            for (index, group) in groups.prefix(3).enumerated() {
                logs.append("  Group \(index + 1): \(group.description)")
            }

            if groups.isEmpty {
                logs.append("⚠️ No group images found in local database")
            }
        } catch {
            logs.append("❌ Failed to query group_images: \(error.localizedDescription)")
        }

        // Check sync status
        logs.append("🔄 Sync Status:")
        logs.append("  Connected: \(powerSync.isConnected ? "Yes" : "No")")

        await MainActor.run {
            diagnosticInfo = logs
        }
    }
}

struct PowerSyncDiagnosticsView_Previews: PreviewProvider {
    static var previews: some View {
        PowerSyncDiagnosticsView()
    }
}
