//  ReportSchoolPickerSheet.swift
//  Iconik Employee — picking a school to put on a report
//
//  The approved design's "Add a school" sheet, in production. Searchable, with
//  the address under each name and a checkmark on the ones already on the
//  report so the same school cannot be added twice.
//
//  WHY IT IS ITS OWN SHEET RATHER THAN `SearchableSchoolPicker`
//      That component is a BUTTON that owns its own sheet and writes back a
//      single selection. The report needs a list of stops, added one at a time
//      from a control that is not itself a school row — so the sheet is the
//      unit, not the button. `SearchableSchoolPicker` stays in the app for
//      NFC/ManualEntryView, which is now its only consumer.
//
//      Everything it did that mattered is here: search over name AND address,
//      the refresh that re-pulls schools from the server, and the address line
//      under each name.
//
//  THE REFRESH IS DELIBERATELY NOT THE ONE THAT COMPONENT USES
//      `DatabaseManager.refreshSchoolsFromServer` calls back only WHEN THE DATA
//      CHANGED, and its own failure path calls back with an EMPTY ARRAY. Both
//      are dangerous here:
//        · refreshing an unchanged list never calls back, so the spinner spins
//          for the life of the sheet and the button stays disabled;
//        · an empty array would REPLACE the school list, and the report stores
//          school IDS that are resolved through it — so a failed refresh would
//          make every school already on the report disappear, with no way to
//          add them back.
//      So this awaits `SchoolService.getSchools` directly, which either returns
//      or throws, and it never assigns an empty result over a non-empty list.

import SwiftUI

struct ReportSchoolPickerSheet: View {
    /// The full school list. A binding so the refresh button can replace it,
    /// exactly as `SearchableSchoolPicker.refreshSchools` does.
    @Binding var schools: [SchoolItem]
    /// Ids already on the report — shown as chosen and not addable again.
    let chosen: [String]
    let organizationID: String
    let onPick: (SchoolItem) -> Void
    let onCancel: () -> Void

    @State private var search = ""
    @State private var isRefreshing = false

    private var results: [SchoolItem] {
        let all = schools.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.address.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if schools.isEmpty {
                    // Loading and "this organisation has no schools" are
                    // different, and only one of them is worth a spinner. The
                    // caller loads schools before this can be opened, so an
                    // empty list here means the load has not landed yet.
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading schools…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    AmbientEmptyState(
                        title: "No schools found",
                        message: "Nothing matches “\(search)”.",
                        systemImage: "magnifyingglass")
                } else {
                    List(results) { school in
                        Button { onPick(school) } label: { row(school) }
                            .buttonStyle(.plain)
                            .disabled(chosen.contains(school.id))
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $search, prompt: "Search schools…")
            .navigationTitle("Add School")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: refresh) {
                        if isRefreshing {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func row(_ school: SchoolItem) -> some View {
        let already = chosen.contains(school.id)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(school.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(already ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !school.address.isEmpty && school.address != school.name {
                    Text(school.address).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if already {
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.green)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private func refresh() {
        guard !isRefreshing, !organizationID.isEmpty else { return }
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            do {
                let fetched = try await SchoolService.shared.getSchools(organizationID: organizationID)
                let items = fetched
                    .map { SchoolItem(id: $0.id, name: $0.name, address: $0.address ?? "",
                                      coordinates: $0.coordinates) }
                    .sorted { $0.name.lowercased() < $1.name.lowercased() }
                // NEVER replace a non-empty list with an empty one. The report
                // stores school IDS and resolves them through this list, so an
                // empty result would erase every school already on the report
                // and leave no way to add them back.
                guard !items.isEmpty || schools.isEmpty else { return }
                schools = items
            } catch {
                print("⚠️ ReportSchoolPickerSheet: refresh failed — \(error.localizedDescription)")
            }
        }
    }
}
