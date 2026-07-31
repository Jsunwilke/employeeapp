import SwiftUI

struct SearchableSchoolPicker: View {
    @Binding var selectedSchool: SchoolItem?
    @Binding var schools: [SchoolItem]
    let title: String
    let disabled: Bool
    let organizationID: String
    
    @State private var showingPicker = false
    @State private var searchText = ""
    @State private var isRefreshing = false
    
    init(selection: Binding<SchoolItem?>, schools: Binding<[SchoolItem]>, title: String = "School", disabled: Bool = false, organizationID: String) {
        self._selectedSchool = selection
        self._schools = schools
        self.title = title
        self.disabled = disabled
        self.organizationID = organizationID
    }
    
    var body: some View {
        Button(action: {
            if !disabled {
                showingPicker = true
            }
        }) {
            HStack {
                Text(selectedSchool?.name ?? "Select School")
                    .foregroundColor(selectedSchool != nil ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .disabled(disabled)
        .sheet(isPresented: $showingPicker) {
            NavigationView {
                SchoolListView(
                    selectedSchool: $selectedSchool,
                    schools: schools,
                    searchText: $searchText,
                    isPresented: $showingPicker
                )
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: refreshSchools) {
                            if isRefreshing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(isRefreshing)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingPicker = false
                        }
                    }
                }
            }
        }
    }
    
    func refreshSchools() {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        DatabaseManager.shared.refreshSchoolsFromServer(forOrgID: organizationID) { schoolItems in
            DispatchQueue.main.async {
                self.schools = schoolItems
                self.isRefreshing = false
            }
        }
    }
}

struct SchoolListView: View {
    @Binding var selectedSchool: SchoolItem?
    let schools: [SchoolItem]
    @Binding var searchText: String
    @Binding var isPresented: Bool
    
    var filteredSchools: [SchoolItem] {
        if searchText.isEmpty {
            return schools.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } else {
            return schools
                .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredSchools) { school in
                Button(action: {
                    selectedSchool = school
                    isPresented = false
                }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(school.name)
                                .foregroundColor(.primary)
                            if !school.address.isEmpty && school.address != school.name {
                                Text(school.address)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if selectedSchool?.id == school.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .searchable(text: $searchText, prompt: "Search schools...")
        .listStyle(PlainListStyle())
    }
}

// For MileageDetailView that uses MileageSchoolItem
struct SearchableMileageSchoolPicker: View {
    @Binding var selectedSchoolName: String
    let schools: [MileageSchoolItem]
    let title: String
    
    @State private var showingPicker = false
    @State private var searchText = ""
    
    init(selectedSchoolName: Binding<String>, schools: [MileageSchoolItem], title: String = "School") {
        self._selectedSchoolName = selectedSchoolName
        self.schools = schools
        self.title = title
    }
    
    var body: some View {
        Button(action: {
            showingPicker = true
        }) {
            HStack {
                Text(selectedSchoolName.isEmpty ? "Select School" : selectedSchoolName)
                    .foregroundColor(selectedSchoolName.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .sheet(isPresented: $showingPicker) {
            NavigationView {
                MileageSchoolListView(
                    selectedSchoolName: $selectedSchoolName,
                    schools: schools,
                    searchText: $searchText,
                    isPresented: $showingPicker
                )
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingPicker = false
                        }
                    }
                }
            }
        }
    }
}

struct MileageSchoolListView: View {
    @Binding var selectedSchoolName: String
    let schools: [MileageSchoolItem]
    @Binding var searchText: String
    @Binding var isPresented: Bool
    
    var filteredSchools: [MileageSchoolItem] {
        if searchText.isEmpty {
            return schools.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } else {
            return schools
                .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredSchools) { school in
                Button(action: {
                    selectedSchoolName = school.name
                    isPresented = false
                }) {
                    HStack {
                        Text(school.name)
                            .foregroundColor(.primary)
                        Spacer()
                        if selectedSchoolName == school.name {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .searchable(text: $searchText, prompt: "Search schools...")
        .listStyle(PlainListStyle())
    }
}

// For compatibility with views that use String binding
struct SearchableSchoolPickerString: View {
    @Binding var selectedSchool: String
    @Binding var schools: [SchoolItem]
    let title: String
    let disabled: Bool
    let organizationID: String
    
    @State private var selectedSchoolItem: SchoolItem?

    /// True while `selectedSchoolItem` is being rewritten to FOLLOW the string
    /// binding, so the item→string `onChange` below knows not to write back.
    /// Without it, an external string with no matching school would be erased to
    /// "" by the very sync that was meant to display it.
    ///
    /// The forced value this repo actually sets — "Iconik", written by
    /// `FormView`/`ManualEntryView` when a card is Cleared or a box is Turned In
    /// — DOES match a real row (verified live 2026-07-30: `schools` holds an
    /// ACTIVE row named "Iconik", id K8RYBzQxUFsrOIjlQ8eu), so that path
    /// resolves to an item and displays it. This guard therefore covers only the
    /// hypothetical no-match case; it is kept because losing a caller's value
    /// silently is the worse failure of the two.
    @State private var syncingFromBinding = false

    init(selection: Binding<String>, schools: Binding<[SchoolItem]>, title: String = "School", disabled: Bool = false, organizationID: String) {
        self._selectedSchool = selection
        self._schools = schools
        self.title = title
        self.disabled = disabled
        self.organizationID = organizationID
    }
    
    var body: some View {
        SearchableSchoolPicker(
            selection: $selectedSchoolItem,
            schools: $schools,
            title: title,
            disabled: disabled,
            organizationID: organizationID
        )
        .onAppear { syncFromBinding() }
        // THE DISPLAY FOLLOWS THE BINDING, not only on appear (audit round).
        // This wrapper used to sync string→item exactly once, in `onAppear`, so
        // any LATER external write to the binding — `FormView`'s "Cleared" rule
        // forcing "Iconik", the schools listener arriving after first paint, a
        // session selection setting the school — left the button showing the
        // PREVIOUS school while the binding held the new one. The screen stated
        // the opposite of what would be stored. Fixing it here fixes every call
        // site.
        .onChange(of: selectedSchool) { _ in syncFromBinding() }
        // The list can arrive after the string: a name that matched nothing at
        // first paint has to be picked up when the schools land.
        .onChange(of: schools) { _ in syncFromBinding() }
        .onChange(of: selectedSchoolItem) { newValue in
            // A programmatic re-sync is NOT a user selection: writing back here
            // would turn "no school in the list is called Iconik" into "the
            // school is now blank", silently discarding the caller's value.
            if syncingFromBinding {
                syncingFromBinding = false
                return
            }
            selectedSchool = newValue?.name ?? ""
        }
    }

    /// Point the displayed item at whatever the string binding now says.
    ///
    /// The equality guard is load-bearing in BOTH directions: it stops this
    /// fighting the item→string sync (a user selection already agrees, so
    /// nothing is assigned and the flag is never raised), and it guarantees that
    /// when the flag IS raised the assignment really changes the value — so the
    /// `onChange` that consumes the flag is certain to run and cannot leave it
    /// set to swallow the next real selection.
    private func syncFromBinding() {
        let match = schools.first { $0.name == selectedSchool }
        guard match?.id != selectedSchoolItem?.id else { return }
        syncingFromBinding = true
        selectedSchoolItem = match
    }
}