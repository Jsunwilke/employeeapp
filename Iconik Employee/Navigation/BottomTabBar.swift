import SwiftUI

struct BottomTabBar: View {
    @Binding var selectedTab: String
    @ObservedObject var tabBarManager: TabBarManager
    @ObservedObject var chatManager: ChatManager
    let timeTrackingService: TimeTrackingService
    
    @State private var animateSelection = false
    @Namespace private var tabBarNamespace
    
    var body: some View {
        HStack(spacing: 0) {
            let items = tabBarManager.getQuickAccessItemsExcludingScan()
            let leftItems = Array(items.prefix(3))
            let rightItems = Array(items.dropFirst(3).prefix(3))
            
            Spacer(minLength: 10) // Add space from left edge
            
            // Left side items grouped together
            HStack(spacing: 0) {
                ForEach(leftItems) { item in
                    TabBarButton(
                        item: updatedItem(item),
                        isSelected: selectedTab == item.id,
                        showLabel: tabBarManager.configuration.showLabels,
                        namespace: tabBarNamespace,
                        isScanButton: false,
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
                    .frame(width: 50) // Fixed width for regular buttons
                }
            }
            
            Spacer(minLength: 20) // Space between left group and scan
            
            // Center scan button (always present)
            let scanItem = tabBarManager.getScanItem() ?? TabBarItem(
                id: "scan",
                title: "Scan",
                systemImage: "wave.3.right.circle.fill",
                description: "Scan SD cards and job boxes",
                order: 999,
                isQuickAccess: true
            )
            
            TabBarButton(
                item: updatedItem(scanItem),
                isSelected: selectedTab == scanItem.id,
                showLabel: tabBarManager.configuration.showLabels,
                namespace: tabBarNamespace,
                isScanButton: true,
                action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = scanItem.id
                        animateSelection = true
                    }
                    
                    // Haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                }
            )
            .frame(width: 70) // Slightly wider for scan button
            
            Spacer(minLength: 20) // Space between scan and right group
            
            // Right side items grouped together
            HStack(spacing: 0) {
                ForEach(rightItems) { item in
                    TabBarButton(
                        item: updatedItem(item),
                        isSelected: selectedTab == item.id,
                        showLabel: tabBarManager.configuration.showLabels,
                        namespace: tabBarNamespace,
                        isScanButton: false,
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
                    .frame(width: 50) // Fixed width for regular buttons
                }
            }
            
            Spacer(minLength: 10) // Add space from right edge
        }
        .padding(.top, 4) // Small top padding to push icons down slightly
        .padding(.horizontal, 4) // Reduced from 8 to fit 7 items
        .padding(.bottom, 23) // Positive padding to add space at bottom
        .background(
            Color(.systemBackground)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
        .overlay(
            Divider()
                .background(Color(.separator)),
            alignment: .top
        )
        .id("bottomTabBar_\(chatManager.totalUnreadCount)") // Force redraw when unread count changes
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
    var isScanButton: Bool = false
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) { // Reduced spacing
                ZStack(alignment: isScanButton ? .center : .topTrailing) {
                    // Background for scan button
                    if isScanButton {
                        Circle()
                            .fill(isSelected ? accentColor : Color.gray.opacity(0.2))
                            .frame(width: 50, height: 50)
                            .scaleEffect(isPressed ? 0.9 : 1.0)
                            .animation(.spring(response: 0.1, dampingFraction: 0.6), value: isPressed)
                    }
                    
                    // Icon
                    Image(systemName: item.systemImage)
                        .font(.system(size: isScanButton ? 60 : 24))
                        .foregroundColor(isScanButton && isSelected ? .white : (isSelected ? accentColor : .gray))
                        .scaleEffect(isPressed ? 0.85 : (isSelected && !isScanButton ? 1.1 : 1.0))
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
                .frame(width: isScanButton ? 50 : 44, height: isScanButton ? 50 : 32)
                
                // Label
                if showLabel && !isScanButton { // Hide label for scan button to save space
                    Text(item.title)
                        .font(.system(size: 10)) // Smaller than caption2
                        .foregroundColor(isSelected ? accentColor : .gray)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8) // Allow text to shrink if needed
                        .scaleEffect(isSelected ? 1.0 : 0.9)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                }
                
                // Selection indicator
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accentColor)
                        .frame(width: 20, height: 3)
                        .matchedGeometryEffect(id: "tabSelection", in: namespace)
                }
            } // Removed vertical padding
        }
        .buttonStyle(TabButtonStyle(isPressed: $isPressed))
        .accessibilityLabel(item.title)
        .accessibilityHint(item.description)
    }
    
    private var accentColor: Color {
        switch item.id {
        case "timeTracking": return .cyan
        case "chat": return .blue
        case "scan": return .orange
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
        VStack(spacing: 0) {
                // Header with instructions and count
                VStack(spacing: 8) {
                    Text("Select up to 6 features for quick access")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Scan is always included")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                    
                    Text("\(selectedFeatures.count) of 6 selected")
                        .font(.caption)
                        .foregroundColor(selectedFeatures.count >= 6 ? .red : .secondary)
                        .fontWeight(selectedFeatures.count >= 6 ? .semibold : .regular)
                }
                .padding()
                
                // Single combined list
                List {
                    // Selected features (reorderable)
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
                            
                            // Show minus button
                            Button(action: {
                                removeFeature(item)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.title2)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove(perform: moveSelectedFeatures)
                    
                    // Available features (not selected)
                    ForEach(availableFeatures) { feature in
                        if !selectedFeatures.contains(where: { $0.id == feature.id }) {
                            HStack {
                                Image(systemName: feature.systemImage)
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(featureColorFor(feature.id)))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title)
                                        .font(.headline)
                                    Text(feature.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.leading, 8)
                                
                                Spacer()
                                
                                Button(action: {
                                    addFeature(feature)
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(selectedFeatures.count >= 6 ? .gray : .green)
                                        .font(.title2)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(selectedFeatures.count >= 6)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .environment(\.editMode, $editMode)
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
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            loadFeatures()
        }
    }
    
    private func loadFeatures() {
        // Combine all features but exclude scan since it's always present
        availableFeatures = (mainViewModel.defaultEmployeeFeatures + [
            FeatureItem(id: "chat", title: "Chat", systemImage: "bubble.left.and.bubble.right.fill", description: "Message your team"),
            FeatureItem(id: "timeOffRequests", title: "Time Off", systemImage: "calendar.badge.plus", description: "Request time off")
        ]).filter { $0.id != "scan" } // Exclude scan from available features
        
        // Load current configuration excluding scan
        selectedFeatures = tabBarManager.getQuickAccessItemsExcludingScan()
    }
    
    private func addFeature(_ feature: FeatureItem) {
        guard selectedFeatures.count < 6 else { return }
        
        let tabItem = TabBarItem(
            from: feature,
            order: selectedFeatures.count,
            isQuickAccess: true
        )
        selectedFeatures.append(tabItem)
        saveConfiguration() // Save immediately
    }
    
    private func removeFeature(_ item: TabBarItem) {
        selectedFeatures.removeAll { $0.id == item.id }
        
        // Update order
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
        saveConfiguration() // Save immediately
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
        saveConfiguration() // Save immediately
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
        saveConfiguration() // Save immediately
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
        case "scan": return .orange
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