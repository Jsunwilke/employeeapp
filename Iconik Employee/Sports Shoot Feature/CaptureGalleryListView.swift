//
//  CaptureGalleryListView.swift
//  Iconik Employee
//
//  Shows all galleries (all shoot types) for the Capture section.
//  Sports galleries open CapturaSportsRosterView_iPhone, non-sports open PoserStationView.
//

import SwiftUI

struct CaptureGalleryListView: View {
    private let powerSync = PowerSyncManager.shared

    @State private var galleries: [SportsShoot] = []
    @State private var isLoading = true
    @State private var watchTask: Task<Void, Never>?
    @State private var searchText = ""
    @State private var expandedSections: Set<String> = []

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
            "fall_portraits": "Fall Portraits",
            "spring_portraits": "Spring Portraits",
            "graduation": "Graduation",
            "events": "Events",
            "dance": "Dance",
            "prom": "Prom",
            "preschool": "Preschool",
            "faculty": "Faculty",
        ]

        var groups: [String: [SportsShoot]] = [:]
        for g in filteredGalleries {
            let type = g.shootType ?? "other"
            groups[type, default: []].append(g)
        }

        // Build order from known types + any remaining types found in data
        let knownOrder = ["events", "spring_portraits", "fall_portraits", "graduation", "sports", "dance", "prom", "preschool", "faculty"]
        let allTypes = Set(groups.keys)
        let extraTypes = allTypes.subtracting(knownOrder).sorted()
        let order = knownOrder + extraTypes

        return order.compactMap { type in
            guard let list = groups[type], !list.isEmpty else { return nil }
            let label = typeLabels[type] ?? type.replacingOccurrences(of: "_", with: " ").capitalized
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
                            Section {
                                if isExpanded(group.type) {
                                    ForEach(group.galleries) { gallery in
                                        galleryNavigationLink(gallery)
                                    }
                                }
                            } header: {
                                sectionHeader(for: group)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Capture")
            .homeToolbarItem()
            // Room for the app's floating bar. Applied inside this screen's own
            // navigation container, because the shell cannot reach into a self-nav
            // feature (AMB.4).
            .tabBarClearance()
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

    /// Sections start collapsed so the user lands on a short list of
    /// shoot-type headers and only expands the type they're shooting
    /// today. While a search is active, every section auto-expands so
    /// matches in any group are visible without manual toggling.
    private func isExpanded(_ type: String) -> Bool {
        if !searchText.isEmpty { return true }
        return expandedSections.contains(type)
    }

    private func toggleSection(_ type: String) {
        if expandedSections.contains(type) {
            expandedSections.remove(type)
        } else {
            expandedSections.insert(type)
        }
    }

    @ViewBuilder
    private func sectionHeader(for group: (type: String, label: String, galleries: [SportsShoot])) -> some View {
        let expanded = isExpanded(group.type)
        let searching = !searchText.isEmpty
        Button(action: {
            guard !searching else { return }
            withAnimation(.easeInOut(duration: 0.2)) { toggleSection(group.type) }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                Text(group.label)
                Spacer()
                Text("\(group.galleries.count)")
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(searching)
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
        // All shoot types open in the capture view (PoserStationView). The
        // capture view shows sports-conditional UI (image numbers box, grade
        // badge, roster id + sport on cards) when shootType == "sports".
        // Captura photographers still reach the legacy CapturaSportsRosterView_iPhone
        // through the Sports tab (CapturaSportsView), which is unaffected
        // by this routing change.
        PoserStationView(gallery: gallery)
    }

    private func shootTypeLabel(_ type: String) -> String {
        switch type {
        case "sports": return "Sports"
        case "fall_portraits": return "Fall Portraits"
        case "spring_portraits": return "Spring Portraits"
        case "graduation": return "Graduation"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
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
