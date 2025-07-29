import SwiftUI

struct BottomTabBar: View {
    @Binding var selectedTab: String
    let items: [TabBarItem]
    let chatManager: ChatManager
    let timeTrackingService: TimeTrackingService
    let showLabels: Bool
    
    @State private var animateSelection = false
    @Namespace private var tabBarNamespace
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.prefix(5)) { item in
                TabBarButton(
                    item: updatedItem(item),
                    isSelected: selectedTab == item.id,
                    showLabel: showLabels,
                    namespace: tabBarNamespace,
                    action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = item.id
                            animateSelection = true
                        }
                        
                        // Haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            Color(.systemBackground)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
        .overlay(
            Divider()
                .background(Color(.separator)),
            alignment: .top
        )
    }
    
    // Update item with current badge values
    private func updatedItem(_ item: TabBarItem) -> TabBarItem {
        var updatedItem = item
        
        switch item.id {
        case "chat":
            updatedItem.badgeType = chatManager.totalUnreadCount > 0 ? .count(chatManager.totalUnreadCount) : .none
        case "timeTracking":
            updatedItem.badgeType = timeTrackingService.isClockIn ? .active : .none
        default:
            break
        }
        
        return updatedItem
    }
}

// MARK: - Tab Bar Button
struct TabBarButton: View {
    let item: TabBarItem
    let isSelected: Bool
    let showLabel: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    // Icon
                    Image(systemName: item.systemImage)
                        .font(.system(size: 24))
                        .foregroundColor(isSelected ? accentColor : .gray)
                        .scaleEffect(isPressed ? 0.85 : (isSelected ? 1.1 : 1.0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
                        .animation(.spring(response: 0.1, dampingFraction: 0.6), value: isPressed)
                    
                    // Badge
                    if let badgeValue = item.badgeValue {
                        Text(badgeValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(10)
                            .offset(x: 12, y: -8)
                            .transition(.scale.combined(with: .opacity))
                    } else if item.showDot {
                        Circle()
                            .fill(item.badgeType == .active ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 10, y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 44, height: 32)
                
                // Label
                if showLabel {
                    Text(item.title)
                        .font(.caption2)
                        .foregroundColor(isSelected ? accentColor : .gray)
                        .lineLimit(1)
                        .scaleEffect(isSelected ? 1.0 : 0.9)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                }
                
                // Selection indicator
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accentColor)
                        .frame(width: 20, height: 3)
                        .matchedGeometryEffect(id: "tabSelection", in: namespace)
                } else {
                    Color.clear
                        .frame(width: 20, height: 3)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(TabButtonStyle(isPressed: $isPressed))
        .accessibilityLabel(item.title)
        .accessibilityHint(item.description)
    }
    
    private var accentColor: Color {
        switch item.id {
        case "timeTracking": return .cyan
        case "chat": return .blue
        case "photoshootNotes": return .purple
        case "dailyJobReport": return .green
        case "sportsShoot": return .indigo
        default: return .blue
        }
    }
}

// MARK: - Tab Button Style
struct TabButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { pressed in
                isPressed = pressed
            }
    }
}

// MARK: - Tab Bar Configuration View
struct TabBarConfigurationView: View {
    @ObservedObject var tabBarManager: TabBarManager
    @ObservedObject var mainViewModel: MainEmployeeViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var availableFeatures: [FeatureItem] = []
    @State private var selectedFeatures: [TabBarItem] = []
    @State private var editMode: EditMode = .active
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Instructions
                Text("Select up to 5 features for quick access")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                
                // Selected features (reorderable)
                Section {
                    List {
                        ForEach(selectedFeatures) { item in
                            HStack {
                                Image(systemName: item.systemImage)
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(featureColorFor(item.id)))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.headline)
                                    Text(item.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.leading, 8)
                                
                                Spacer()
                                
                                Image(systemName: "line.3.horizontal")
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 4)
                        }
                        .onMove(perform: moveSelectedFeatures)
                        .onDelete(perform: deleteSelectedFeatures)
                    }
                    .listStyle(InsetGroupedListStyle())
                    .environment(\.editMode, $editMode)
                    .frame(maxHeight: 300)
                } header: {
                    HStack {
                        Text("Quick Access Features")
                            .font(.headline)
                        Spacer()
                        Text("\(selectedFeatures.count)/5")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
                
                Divider()
                
                // Available features
                Section {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(availableFeatures) { feature in
                                if !selectedFeatures.contains(where: { $0.id == feature.id }) {
                                    Button(action: {
                                        addFeature(feature)
                                    }) {
                                        HStack {
                                            Image(systemName: feature.systemImage)
                                                .foregroundColor(.white)
                                                .frame(width: 30, height: 30)
                                                .background(Circle().fill(featureColorFor(feature.id)))
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(feature.title)
                                                    .font(.headline)
                                                    .foregroundColor(.primary)
                                                Text(feature.description)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                            .padding(.leading, 8)
                                            
                                            Spacer()
                                            
                                            Image(systemName: "plus.circle")
                                                .foregroundColor(.blue)
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 8)
                                    }
                                    .disabled(selectedFeatures.count >= 5)
                                    
                                    Divider()
                                        .padding(.leading, 58)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Available Features")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Customize Tab Bar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveConfiguration()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadFeatures()
            }
        }
    }
    
    private func loadFeatures() {
        // Combine all features
        availableFeatures = mainViewModel.defaultEmployeeFeatures + [
            FeatureItem(id: "chat", title: "Chat", systemImage: "bubble.left.and.bubble.right.fill", description: "Message your team"),
            FeatureItem(id: "timeOffRequests", title: "Time Off", systemImage: "calendar.badge.plus", description: "Request time off")
        ]
        
        // Load current configuration
        selectedFeatures = tabBarManager.getQuickAccessItems()
    }
    
    private func addFeature(_ feature: FeatureItem) {
        guard selectedFeatures.count < 5 else { return }
        
        let tabItem = TabBarItem(
            from: feature,
            order: selectedFeatures.count,
            isQuickAccess: true
        )
        selectedFeatures.append(tabItem)
    }
    
    private func moveSelectedFeatures(from source: IndexSet, to destination: Int) {
        selectedFeatures.move(fromOffsets: source, toOffset: destination)
        
        // Update order by creating new items
        selectedFeatures = selectedFeatures.enumerated().map { index, item in
            TabBarItem(
                id: item.id,
                title: item.title,
                systemImage: item.systemImage,
                description: item.description,
                order: index,
                isQuickAccess: true
            )
        }
    }
    
    private func deleteSelectedFeatures(at offsets: IndexSet) {
        selectedFeatures.remove(atOffsets: offsets)
        
        // Update order by creating new items
        selectedFeatures = selectedFeatures.enumerated().map { index, item in
            TabBarItem(
                id: item.id,
                title: item.title,
                systemImage: item.systemImage,
                description: item.description,
                order: index,
                isQuickAccess: true
            )
        }
    }
    
    private func saveConfiguration() {
        // Update all items' quick access status
        var allItems = availableFeatures.map { feature in
            TabBarItem(
                from: feature,
                order: selectedFeatures.firstIndex(where: { $0.id == feature.id }) ?? 999,
                isQuickAccess: selectedFeatures.contains(where: { $0.id == feature.id })
            )
        }
        
        tabBarManager.updateTabBarItems(allItems)
    }
    
    private func featureColorFor(_ id: String) -> Color {
        switch id {
        case "timeTracking": return .cyan
        case "chat": return .blue
        case "photoshootNotes": return .purple
        case "dailyJobReport": return .green
        case "customDailyReports": return .mint
        case "myDailyJobReports": return .green
        case "mileageReports": return .orange
        case "schedule": return .red
        case "locationPhotos": return .pink
        case "sportsShoot": return .indigo
        case "timeOffRequests": return .teal
        default: return .gray
        }
    }
}