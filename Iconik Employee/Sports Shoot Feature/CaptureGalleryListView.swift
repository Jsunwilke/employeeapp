//
//  CaptureGalleryListView.swift
//  Iconik Employee
//
//  Shows all galleries (all shoot types) for the Capture section.
//  Sports galleries open SportsShootDetailView, non-sports open PoserStationView.
//

import SwiftUI

struct CaptureGalleryListView: View {
    private let powerSync = PowerSyncManager.shared

    @State private var galleries: [SportsShoot] = []
    @State private var isLoading = true
    @State private var watchTask: Task<Void, Never>?
    @State private var searchText = ""

    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""

    var filteredGalleries: [SportsShoot] {
        let active = galleries.filter { !$0.isArchived }
        if searchText.isEmpty { return active }
        let q = searchText.lowercased()
        return active.filter { $0.schoolName.lowercased().contains(q) }
    }

    /// Group galleries by shoot type for display
    var groupedGalleries: [(type: String, label: String, galleries: [SportsShoot])] {
        let typeLabels: [String: String] = [
            "sports": "Sports",
            "underclassFall": "Fall Portraits",
            "springPortraits": "Spring Portraits",
            "graduation": "Graduation",
        ]

        var groups: [String: [SportsShoot]] = [:]
        for g in filteredGalleries {
            let type = g.shootType ?? "other"
            groups[type, default: []].append(g)
        }

        let order = ["sports", "underclassFall", "springPortraits", "graduation", "other"]
        return order.compactMap { type in
            guard let list = groups[type], !list.isEmpty else { return nil }
            let label = typeLabels[type] ?? type.capitalized
            return (type: type, label: label, galleries: list)
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading galleries...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredGalleries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "camera")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No galleries available")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Galleries are created in Focal Point Production and will appear here once synced.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(groupedGalleries, id: \.type) { group in
                            Section(header: Text(group.label)) {
                                ForEach(group.galleries) { gallery in
                                    galleryNavigationLink(gallery)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Capture")
            .searchable(text: $searchText, prompt: "Search galleries...")
            .task {
                await loadGalleries()
                startWatching()
            }
            .onDisappear {
                watchTask?.cancel()
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func galleryNavigationLink(_ gallery: SportsShoot) -> some View {
        let isSports = gallery.shootType == "sports"

        NavigationLink(destination: destinationView(for: gallery)) {
            HStack(spacing: 12) {
                Image(systemName: isSports ? "sportscourt" : "camera")
                    .font(.title3)
                    .foregroundColor(isSports ? .indigo : .blue)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSports ? Color.indigo.opacity(0.12) : Color.blue.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(gallery.schoolName)
                        .font(.body)
                        .fontWeight(.medium)

                    HStack(spacing: 6) {
                        if let type = gallery.shootType {
                            Text(shootTypeLabel(type))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text(gallery.shootDate, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func destinationView(for gallery: SportsShoot) -> some View {
        if gallery.shootType == "sports" {
            SportsShootDetailView(shootID: gallery.id)
        } else {
            PoserStationView(gallery: gallery)
        }
    }

    private func shootTypeLabel(_ type: String) -> String {
        switch type {
        case "sports": return "Sports"
        case "underclassFall": return "Fall Portraits"
        case "springPortraits": return "Spring Portraits"
        case "graduation": return "Graduation"
        default: return type.capitalized
        }
    }

    private func loadGalleries() async {
        isLoading = true
        do {
            galleries = try await powerSync.getCaptureGalleries(forOrg: storedUserOrganizationID)
        } catch {
            print("Failed to load capture galleries: \(error)")
        }
        isLoading = false
    }

    private func startWatching() {
        watchTask?.cancel()
        watchTask = Task {
            let stream = powerSync.watchCaptureGalleries(forOrg: storedUserOrganizationID)
            do {
                for try await updated in stream {
                    if !Task.isCancelled {
                        galleries = updated
                        if isLoading { isLoading = false }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    print("Gallery watch error: \(error)")
                }
            }
        }
    }
}
