//  SchoolInfoListView.swift
//  Iconik Employee — "School Info", converted to Ambient in AMB.12
//
//  WHAT THE CONVERSION ADDED, and why each one is a fix rather than a flourish:
//
//    · SEARCH. There was no search, filter, sort or grouping anywhere in the 14
//      Settings files; the list is alphabetical from the service and that was the
//      whole of it. On an organization with a hundred schools that is a long scroll
//      to reach one address.
//
//    · A FAILURE STATE AND AN OFFLINE STATE. A failed load raised an alert titled
//      "Error" and left the screen showing nothing — the same picture as an
//      organization with no schools. An empty state is a statement of fact about
//      the data; a failure is a statement about the connection, and drawing one as
//      the other tells the user something false.
//
//    · "Mileage: --" IS REPLACED BY A STATED REASON. `--` was drawn both for a
//      genuine zero AND for a per-school query that failed, and the two were
//      indistinguishable.
//
//  ALSO FIXED: the per-school mileage went through an INLINE Supabase query with a
//  locally-declared `struct MileageRecord`, duplicating `getMileageForSchool` which
//  already existed (G25) — and the two disagreed about the date format, this screen
//  comparing a full ISO timestamp against the service's bare date (G26). The screen
//  calls the service now, so the list and the school's own detail screen can no
//  longer report different mileage for the same school.
//
//  NAMED, NOT FIXED: those per-school figures are still an N+1 fan-out, one report
//  query per school (G17), and `SchoolService.getSchools` never filters `is_active`
//  so deactivated schools are listed (G27). Both are service-layer.
//
//  KEPT: the empty state's "No schools found" and its "Add Your First School"
//  button, the toolbar "Add School", the Add School sheet, `.refreshable`, and the
//  "No organization ID found. Please sign in again." guard.

import SwiftUI

struct SchoolInfoListView: View {
    @ObservedObject private var connectivity = OfflineDataManager.shared

    @State private var schools: [School] = []
    @State private var mileageBySchool: [String: SchoolMileage] = [:]
    @State private var errorMessage: String = ""
    @State private var showingAddSchool = false
    @State private var isLoading = false
    @State private var search = ""
    @State private var destination: SchoolRoute?

    // User's organization ID
    @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""

    /// A school's season mileage, with the two outcomes told apart. Absent from the
    /// dictionary means "still in flight", which claims nothing at all.
    private enum SchoolMileage {
        case miles(Double)
        case unavailable
    }

    /// One push target, with an id — the rule since AMB.3.
    private struct SchoolRoute: Identifiable, Hashable {
        let id: String
    }

    private var filtered: [School] {
        guard !search.isEmpty else { return schools }
        return schools.filter { school in
            school.name.localizedCaseInsensitiveContains(search)
                || (school.address ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AmbientSearchField(placeholder: "Search schools", text: $search)
                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
            .refreshable { loadSchools() }
        }
        .tabBarClearance()
        .navigationTitle("School Info")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddSchool = true
                } label: {
                    Label("Add School", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSchool) {
            AddSchoolView()
                .onDisappear {
                    // Reload the school list when the Add School view disappears
                    loadSchools()
                }
        }
        .onAppear(perform: loadSchools)
        .ambientPush(item: $destination) { route in
            SchoolDetailView(schoolId: route.id)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && schools.isEmpty {
            AmbientLoadingRow(message: "Loading schools…")
        } else if !errorMessage.isEmpty {
            // The failure is the whole story here. It is NOT also told as "you have
            // no schools" — that is the shape this screen used to have.
            AmbientFailureCard(message: "Couldn't load schools. \(errorMessage)",
                               action: loadSchools)
        } else if schools.isEmpty && !connectivity.isOnline {
            AmbientFailureCard(message: "You're offline. Connect to Wi-Fi or cellular to load this organization's schools.",
                               systemImage: "wifi.exclamationmark",
                               actionTitle: "Try Again",
                               action: loadSchools)
        } else if schools.isEmpty {
            AmbientEmptyState(title: "No schools found",
                              message: "Schools you add show their address, season mileage and location photos here.",
                              systemImage: "building.2",
                              actionTitle: "Add Your First School",
                              actionIcon: "plus.circle.fill",
                              action: { showingAddSchool = true },
                              actionTint: SettingsStyle.tint)
        } else {
            VStack(alignment: .leading, spacing: AmbientDensity.compact.stackSpacing) {
                if !connectivity.isOnline {
                    // Rows are in memory from an earlier fetch — say so rather than
                    // letting them read as current.
                    AmbientFailureCard(message: "You're offline — this list was loaded earlier and may be out of date.",
                                       systemImage: "wifi.exclamationmark",
                                       action: nil)
                }

                if filtered.isEmpty {
                    // A search that matches nothing is a DIFFERENT state from an
                    // organization with no schools.
                    AmbientEmptyState(title: "No matching schools",
                                      message: "Nothing matches “\(search)”.",
                                      systemImage: "magnifyingglass")
                } else {
                    AmbientSectionTitle("Schools", trailing: "\(filtered.count)")
                    ForEach(filtered) { school in
                        Button {
                            destination = SchoolRoute(id: school.id)
                        } label: {
                            row(school)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(_ school: School) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(school.name)
                    .font(AmbientDensity.compact.titleFont)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                mileageMarker(for: school)
            }

            Text(school.address ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if school.parsedCoordinates == nil {
                Text("Not geocoded — no map, and coordinates cannot be edited from this app.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .ambientCard(density: .compact, fillWidth: true)
    }

    /// Three outcomes, three different things on screen — a real figure, an
    /// explicit zero, or a query that did not answer.
    @ViewBuilder
    private func mileageMarker(for school: School) -> some View {
        switch mileageBySchool[school.id] {
        case .miles(let miles) where miles > 0:
            Text(String(format: "%.1f mi", miles))
                .font(.caption.weight(.semibold))
                .foregroundStyle(SettingsStyle.tint)
        case .miles:
            AmbientBadge(text: "no mileage yet", tint: .secondary)
        case .unavailable:
            AmbientBadge(text: "mileage unavailable", tint: .orange)
        case .none:
            EmptyView()
        }
    }

    // MARK: - Data

    func loadSchools() {
        guard !storedUserOrganizationID.isEmpty else {
            errorMessage = "No organization ID found. Please sign in again."
            return
        }

        isLoading = true
        errorMessage = ""
        mileageBySchool = [:]

        Task {
            do {
                let loadedSchools = try await SchoolService.shared.getSchools(organizationID: storedUserOrganizationID)
                await MainActor.run {
                    self.schools = loadedSchools
                    self.isLoading = false

                    // Load mileage for each school
                    for school in loadedSchools {
                        loadMileage(for: school)
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    /// Through the service, so this screen and the school's own detail screen ask
    /// the same question the same way.
    func loadMileage(for school: School) {
        guard let season = SettingsSeason.currentWindow() else { return }

        Task {
            do {
                let total = try await DailyJobReportService.shared.getMileageForSchool(
                    schoolName: school.name,
                    organizationID: storedUserOrganizationID,
                    startDate: season.start,
                    endDate: season.end
                )
                await MainActor.run { mileageBySchool[school.id] = .miles(total) }
            } catch {
                print("Error loading mileage for \(school.name): \(error.localizedDescription)")
                await MainActor.run { mileageBySchool[school.id] = .unavailable }
            }
        }
    }
}
