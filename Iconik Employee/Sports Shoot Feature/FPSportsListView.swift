//
//  FPSportsListView.swift
//  Iconik Employee
//
//  Top-level list of sports jobs with linked Production galleries.
//  Only shows jobs where gallery_id is set (linked to FP Production).
//  Tapping a job navigates to FPSportsRosterView_iPad for roster management.
//

import SwiftUI

struct FPSportsListView: View {
    private let powerSync = PowerSyncManager.shared
    @AppStorage("userOrganizationID") private var storedOrgId: String = ""

    @State private var sportsJobs: [SportsShoot] = []
    @State private var isLoading = true
    @State private var showArchived = false
    @State private var selectedJob: SportsShoot? = nil
    @State private var watchTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading sports jobs...")
                } else if filteredJobs.isEmpty {
                    emptyState
                } else {
                    jobList
                }
            }
            .navigationTitle("FP Sports")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Toggle("Show Archived", isOn: $showArchived)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task { await loadJobs() }
        .onDisappear { watchTask?.cancel() }
    }

    private var filteredJobs: [SportsShoot] {
        sportsJobs.filter { job in
            // Only show jobs with a linked gallery (FP Sports requirement)
            guard job.galleryId != nil && !job.galleryId!.isEmpty else { return false }
            if !showArchived && job.isArchived { return false }
            return true
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "sportscourt")
                .font(.system(size: 70))
                .foregroundColor(.blue.opacity(0.5))

            Text("No FP Sports Jobs")
                .font(.title2).fontWeight(.bold)

            Text("Sports jobs linked to Production galleries will appear here.\n\nLink a gallery to a sports job in Focal Point Production to get started.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Job List

    private var jobList: some View {
        List {
            ForEach(filteredJobs) { job in
                NavigationLink(destination: FPSportsRosterView_iPad()) {
                    jobRow(job)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadJobs() }
    }

    @ViewBuilder
    private func jobRow(_ job: SportsShoot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.schoolName)
                    .font(.headline)

                Spacer()

                if job.isArchived {
                    Text("Archived")
                        .font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            HStack(spacing: 12) {
                Label(job.sportName, systemImage: "sportscourt")
                    .font(.subheadline)
                    .foregroundColor(.blue)

                if !job.seasonType.isEmpty {
                    Text(job.seasonType)
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                }
            }

            HStack(spacing: 12) {
                Label(job.shootDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !job.location.isEmpty {
                    Label(job.location, systemImage: "mappin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !job.photographer.isEmpty {
                Label(job.photographer, systemImage: "person")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data Loading

    private func loadJobs() async {
        let orgId = storedOrgId
        guard !orgId.isEmpty else {
            await MainActor.run { isLoading = false }
            return
        }

        // Initial load
        do {
            let jobs = try await powerSync.getSportsJobs(forOrg: orgId)
            await MainActor.run {
                sportsJobs = jobs
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }

        // Set up watch for real-time updates
        watchTask?.cancel()
        watchTask = Task {
            do {
                for try await jobs in powerSync.watchSportsJobs(forOrg: orgId) {
                    await MainActor.run { sportsJobs = jobs }
                }
            } catch {
                print("FPSportsListView: Watch failed: \(error)")
            }
        }
    }
}
