import SwiftUI

struct PhotoCritiqueListView: View {
    @StateObject private var critiqueService = PhotoCritiqueService.shared
    // PSH.2: a tapped critique push parks the critique id here; consumed below once the
    // service's listener has the critique.
    @ObservedObject private var tabBarManager = TabBarManager.shared
    @State private var isGridView = true
    @State private var selectedCritique: Critique?
    @State private var isRefreshing = false
    
    // Grid layout
    private let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    private let iPadGridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Statistics Header
                if !critiqueService.isLoading {
                    statisticsHeader
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                
                // Filter and View Toggle
                filterAndViewToggle
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                
                // Content
                if critiqueService.isLoading && critiqueService.critiques.isEmpty {
                    loadingView
                } else if critiqueService.critiques.isEmpty {
                    emptyStateView
                } else if critiqueService.filteredCritiques.isEmpty {
                    noResultsView
                } else {
                    contentView
                }
            }
            .navigationTitle("Training Photos")
            .navigationBarTitleDisplayMode(.large)
            .homeToolbarItem()
            // Room for the app's floating bar. Applied inside this screen's own
            // navigation container, because the shell cannot reach into a self-nav
            // feature (AMB.4).
            .tabBarClearance()
            .onAppear {
                critiqueService.startListening()
                consumePendingCritique(id: tabBarManager.pendingCritiqueId,
                                       in: critiqueService.critiques)
            }
            .onDisappear {
                critiqueService.stopListening()
            }
            // PSH.2 deep link: the push tap usually beats the listener's first load, so
            // re-check whenever either side changes. The EMITTED value is passed in —
            // @Published emits during willSet, so re-reading the property inside its own
            // emission returns the pre-assignment value (fix-round audit, H2).
            .onReceive(tabBarManager.$pendingCritiqueId) { id in
                consumePendingCritique(id: id, in: critiqueService.critiques)
            }
            .onReceive(critiqueService.$critiques) { list in
                consumePendingCritique(id: tabBarManager.pendingCritiqueId, in: list)
            }
            .sheet(item: $selectedCritique) { critique in
                PhotoCritiqueDetailView(critique: critique)
            }
            .refreshable {
                await refreshData()
            }
        }
    }
    
    /// Consume-and-clear a push deep link (the selectedClassGroupJobId pattern). Both
    /// inputs arrive as parameters so a caller inside a @Published emission hands us the
    /// post-assignment value; the mutations hop off the current emission because a
    /// same-property assignment inside its own willSet emission is DISCARDED
    /// (probe-verified by the fix-round audit).
    ///
    /// Deliberately NO drop-on-no-match branch: the singleton service retains the
    /// PREVIOUS visit's list across mounts, so a warm-app tap on a freshly published
    /// critique would consume against stale data and dead-end (third-round audit, F2).
    /// An unmatched id opens nothing and sign-out clears it.
    private func consumePendingCritique(id: String?, in critiques: [Critique]) {
        guard let id else { return }
        guard let match = critiques.first(where: { $0.id.lowercased() == id.lowercased() }) else { return }
        DispatchQueue.main.async {
            tabBarManager.pendingCritiqueId = nil
            selectedCritique = match
        }
    }

    // MARK: - Statistics Header

    private var statisticsHeader: some View {
        let stats = critiqueService.statistics
        
        return HStack(spacing: 8) {
            StatsCard(
                title: "Total",
                value: stats.total,
                icon: "photo.stack",
                color: .blue
            )
            .frame(maxWidth: .infinity)
            
            StatsCard(
                title: "Good",
                value: stats.goodExamples,
                icon: "checkmark.circle",
                color: .green
            )
            .frame(maxWidth: .infinity)
            
            StatsCard(
                title: "Needs Work",
                value: stats.needsImprovement,
                icon: "exclamationmark.triangle",
                color: .orange
            )
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Filter and View Toggle
    
    private var filterAndViewToggle: some View {
        HStack {
            // Filter Segmented Control
            Picker("Filter", selection: $critiqueService.filter) {
                ForEach(PhotoCritiqueService.FilterType.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            Spacer()
            
            // View Toggle
            Button(action: {
                withAnimation {
                    isGridView.toggle()
                }
            }) {
                Image(systemName: isGridView ? "square.grid.2x2" : "list.bullet")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(width: 44, height: 44)
            }
        }
    }
    
    // MARK: - Content Views
    
    private var contentView: some View {
        ScrollView {
            if isGridView {
                LazyVGrid(columns: UIDevice.current.userInterfaceIdiom == .pad ? iPadGridColumns : gridColumns, spacing: 16) {
                    ForEach(critiqueService.filteredCritiques) { critique in
                        CritiqueGridCard(critique: critique)
                            .onTapGesture {
                                selectedCritique = critique
                            }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(critiqueService.filteredCritiques) { critique in
                        CritiqueListCard(critique: critique)
                            .onTapGesture {
                                selectedCritique = critique
                            }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    }
    
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Loading training photos...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "camera.on.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Training Photos Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Your training examples will appear here\nwhen managers submit them.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding()
    }
    
    private var noResultsView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Results")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("No training photos match the selected filter.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Show All") {
                withAnimation {
                    critiqueService.filter = .all
                }
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Helper Functions
    
    private func refreshData() async {
        isRefreshing = true
        critiqueService.refresh()
        
        // Simulate a small delay for better UX
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        isRefreshing = false
    }
}

struct PhotoCritiqueListView_Previews: PreviewProvider {
    static var previews: some View {
        PhotoCritiqueListView()
    }
}