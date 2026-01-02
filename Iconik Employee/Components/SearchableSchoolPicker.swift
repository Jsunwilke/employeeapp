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
        .onAppear {
            // Set initial selection based on string value
            if !selectedSchool.isEmpty {
                selectedSchoolItem = schools.first { $0.name == selectedSchool }
            }
        }
        .onChange(of: selectedSchoolItem) { newValue in
            selectedSchool = newValue?.name ?? ""
        }
    }
}