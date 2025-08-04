import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct YearbookShootListsView: View {
    @StateObject private var viewModel = YearbookShootListViewModel()
    @ObservedObject private var schoolService = SchoolService.shared
    
    @State private var selectedSchool: School?
    @State private var showingCreateList = false
    @State private var searchText = ""
    @State private var currentOrganizationId: String?
    
    var body: some View {
        VStack {
            if viewModel.isLoading && viewModel.shootLists.isEmpty {
                ProgressView("Loading yearbook lists...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.shootLists.isEmpty {
                emptyStateView
            } else {
                listContent
            }
        }
        .navigationTitle("Yearbook Checklists")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingCreateList = true }) {
                    Image(systemName: "plus")
                }
                .disabled(currentOrganizationId == nil)
            }
        }
        .searchable(text: $searchText)
        .refreshable {
            await loadLists()
        }
        .sheet(isPresented: $showingCreateList) {
            // Create list view would go here
            Text("Create New Yearbook List")
        }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") {
                viewModel.error = nil
            }
        } message: {
            Text(viewModel.error?.localizedDescription ?? "An error occurred")
        }
        .onAppear {
            loadOrganizationAndLists()
        }
    }
    
    // MARK: - Views
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Yearbook Lists")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create your first yearbook checklist to track photo requirements for schools.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: { showingCreateList = true }) {
                Label("Create Yearbook List", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var listContent: some View {
        List {
            ForEach(groupedLists, id: \.key) { schoolName, lists in
                Section(header: schoolHeader(schoolName: schoolName)) {
                    ForEach(lists) { list in
                        NavigationLink(destination: YearbookChecklistView(
                            shootList: list,
                            sessionContext: nil
                        )) {
                            YearbookListRow(shootList: list)
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
    
    private func schoolHeader(schoolName: String) -> some View {
        HStack {
            Image(systemName: "building.2")
                .foregroundColor(.blue)
            Text(schoolName)
                .font(.headline)
        }
    }
    
    // MARK: - Computed Properties
    
    private var filteredLists: [YearbookShootList] {
        if searchText.isEmpty {
            return viewModel.shootLists
        }
        
        return viewModel.shootLists.filter { list in
            list.schoolName.localizedCaseInsensitiveContains(searchText) ||
            list.schoolYear.contains(searchText) ||
            list.items.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    private var groupedLists: [(key: String, value: [YearbookShootList])] {
        let grouped = Dictionary(grouping: filteredLists) { $0.schoolName }
        return grouped.sorted { $0.key < $1.key }
    }
    
    // MARK: - Functions
    
    private func loadOrganizationAndLists() {
        UserManager.shared.getCurrentUserOrganizationID { organizationId in
            guard let orgId = organizationId else {
                print("No organization ID found for current user")
                return
            }
            
            DispatchQueue.main.async {
                self.currentOrganizationId = orgId
                self.viewModel.loadOrganizationLists(organizationId: orgId)
            }
        }
    }
    
    private func loadLists() async {
        guard let orgId = currentOrganizationId else { return }
        viewModel.loadOrganizationLists(organizationId: orgId)
    }
}

// MARK: - List Row Component
struct YearbookListRow: View {
    let shootList: YearbookShootList
    
    private var yearDisplay: String {
        let components = shootList.schoolYear.split(separator: "-")
        if components.count == 2 {
            return "\(components[0])-\(String(components[1]).suffix(2))"
        }
        return shootList.schoolYear
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(yearDisplay)
                    .font(.headline)
                
                if shootList.isActive {
                    Text("CURRENT")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
                
                Spacer()
                
                if shootList.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            // Progress
            HStack {
                ProgressView(value: Double(shootList.completedCount), total: Double(shootList.totalCount))
                    .progressViewStyle(LinearProgressViewStyle(tint: progressColor))
                
                Text("\(shootList.completedCount)/\(shootList.totalCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Categories summary
            if let categorySummary = getCategorySummary() {
                Text(categorySummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            // Last updated
            Text("Updated \(shootList.updatedAt, formatter: RelativeDateTimeFormatter())")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var progressColor: Color {
        let percentage = shootList.completionPercentage
        if percentage == 100 {
            return .green
        } else if percentage >= 75 {
            return .orange
        } else if percentage >= 50 {
            return .yellow
        } else {
            return .red
        }
    }
    
    private func getCategorySummary() -> String? {
        let categories = Set(shootList.items.map { $0.category })
        guard !categories.isEmpty else { return nil }
        
        if categories.count <= 3 {
            return categories.sorted().joined(separator: ", ")
        } else {
            let first3 = Array(categories.sorted().prefix(3))
            return "\(first3.joined(separator: ", ")) +\(categories.count - 3) more"
        }
    }
}

// MARK: - Preview
struct YearbookShootListsView_Previews: PreviewProvider {
    static var previews: some View {
        YearbookShootListsView()
    }
}