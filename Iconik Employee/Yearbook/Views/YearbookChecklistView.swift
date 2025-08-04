import SwiftUI

struct YearbookChecklistView: View {
    @StateObject private var viewModel: YearbookShootListViewModel
    let sessionContext: YearbookSessionContext?
    
    @State private var showingFilters = false
    @State private var selectedItem: YearbookItem?
    @State private var showingItemDetail = false
    @State private var showingExport = false
    @State private var exportText = ""
    
    init(shootList: YearbookShootList, sessionContext: YearbookSessionContext?) {
        let viewModel = YearbookShootListViewModel(sessionContext: sessionContext)
        viewModel.selectedShootList = shootList
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.sessionContext = sessionContext
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress header
            progressHeader
            
            // Filter bar
            if !viewModel.categories.isEmpty {
                filterBar
            }
            
            // Search bar
            if showingFilters {
                searchBar
            }
            
            // Content
            if viewModel.isLoading && viewModel.selectedShootList == nil {
                ProgressView("Loading checklist...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let shootList = viewModel.selectedShootList {
                if viewModel.filteredItems.isEmpty {
                    emptySearchResults
                } else {
                    checklistContent
                }
            } else {
                Text("Checklist not found")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingFilters.toggle() }) {
                        Label("Filters", systemImage: showingFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    
                    Button(action: exportChecklist) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    
                    if sessionContext != nil {
                        Divider()
                        
                        Button(action: markAllRequired) {
                            Label("Mark All Required Complete", systemImage: "checkmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $selectedItem) { item in
            YearbookItemDetailView(
                item: item,
                listId: viewModel.selectedShootList?.id ?? "",
                viewModel: viewModel
            )
        }
        .sheet(isPresented: $showingExport) {
            ShareSheet(activityItems: [exportText])
        }
    }
    
    // MARK: - Views
    
    private var navigationTitle: String {
        guard let list = viewModel.selectedShootList else { return "Yearbook Checklist" }
        let yearComponents = list.schoolYear.split(separator: "-")
        let shortYear = yearComponents.count == 2 ? "\(yearComponents[0])-\(String(yearComponents[1]).suffix(2))" : list.schoolYear
        return "\(list.schoolName) • \(shortYear)"
    }
    
    private var progressHeader: some View {
        VStack(spacing: 8) {
            if let list = viewModel.selectedShootList {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(list.completedCount) of \(list.totalCount) completed")
                            .font(.headline)
                        
                        Text("\(Int(list.completionPercentage))% Complete")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(list.completionPercentage / 100))
                            .stroke(progressColor(for: list.completionPercentage), lineWidth: 8)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut, value: list.completionPercentage)
                        
                        Text("\(Int(list.completionPercentage))%")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .frame(width: 60, height: 60)
                }
                .padding()
                .background(Color(.systemGray6))
            }
        }
    }
    
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Quick filters
                FilterChip(
                    title: "All",
                    isSelected: !viewModel.showCompletedOnly && !viewModel.showIncompleteOnly,
                    action: { viewModel.applyQuickFilter(.all) }
                )
                
                FilterChip(
                    title: "Incomplete",
                    isSelected: viewModel.showIncompleteOnly,
                    action: { viewModel.applyQuickFilter(.incomplete) }
                )
                
                FilterChip(
                    title: "Completed",
                    isSelected: viewModel.showCompletedOnly,
                    action: { viewModel.applyQuickFilter(.completed) }
                )
                
                Divider()
                    .frame(height: 20)
                
                // Category filters
                ForEach(viewModel.categories, id: \.self) { category in
                    FilterChip(
                        title: category,
                        isSelected: viewModel.selectedCategory == category,
                        action: { viewModel.selectedCategory = category }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGray6))
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search items...", text: $viewModel.searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
    
    private var checklistContent: some View {
        List {
            ForEach(viewModel.groupedFilteredItems, id: \.category) { category, items in
                Section(header: categoryHeader(category: category, items: items)) {
                    ForEach(items) { item in
                        YearbookItemRow(
                            item: item,
                            onToggle: {
                                Task {
                                    await viewModel.toggleItemCompletion(item)
                                }
                            },
                            onTap: {
                                selectedItem = item
                            }
                        )
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
    
    private var emptySearchResults: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No items found")
                .font(.headline)
            
            Text("Try adjusting your search or filters")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Clear Filters") {
                viewModel.clearFilters()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func categoryHeader(category: String, items: [YearbookItem]) -> some View {
        HStack {
            Text(category)
                .font(.headline)
            
            Spacer()
            
            let completed = items.filter { $0.completed }.count
            Text("\(completed)/\(items.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Functions
    
    private func progressColor(for percentage: Double) -> Color {
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
    
    private func markAllRequired() {
        // Implementation for marking all required items as complete
    }
    
    private func exportChecklist() {
        exportText = viewModel.exportCompletedItems()
        showingExport = true
    }
}

// MARK: - Filter Chip Component
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(15)
        }
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview
struct YearbookChecklistView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            YearbookChecklistView(
                shootList: YearbookShootListViewModel.preview.selectedShootList!,
                sessionContext: nil
            )
        }
    }
}