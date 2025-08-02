import SwiftUI

struct NFCContainerView: View {
    @State private var selectedFeature: NFCFeature = .scan
    @Namespace private var animation
    
    // For navigation from statistics with filter
    var initialFeature: NFCFeature? = nil
    @State private var initialSearchStatus: String? = nil
    @State private var initialIsJobBoxMode: Bool = false
    
    enum NFCFeature: String, CaseIterable {
        case scan = "Scan"
        case search = "Search"
        case stats = "Stats"
        case writeNFC = "Write NFC"
        case manualEntry = "Manual Entry"
        
        var icon: String {
            switch self {
            case .scan: return "wave.3.right.circle.fill"
            case .search: return "magnifyingglass"
            case .stats: return "chart.bar.fill"
            case .writeNFC: return "pencil.circle.fill"
            case .manualEntry: return "square.and.pencil"
            }
        }
        
        var color: Color {
            switch self {
            case .scan: return .orange
            case .search: return .blue
            case .stats: return .green
            case .writeNFC: return .purple
            case .manualEntry: return .teal
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Main content area
            ZStack {
                switch selectedFeature {
                case .scan:
                    ScanView()
                case .search:
                    SearchView(
                        initialStatus: initialSearchStatus,
                        initialIsJobBoxMode: initialIsJobBoxMode
                    )
                case .stats:
                    NavigationView {
                        StatisticsView(onNavigateToSearch: { status, isJobBox in
                            // Switch to search view with the selected status
                            selectedFeature = .search
                            // Update the search view parameters
                            initialSearchStatus = status
                            initialIsJobBoxMode = isJobBox
                        })
                    }
                case .writeNFC:
                    NavigationView {
                        WriteNFCView()
                    }
                case .manualEntry:
                    NavigationView {
                        ManualEntryView(onCancel: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedFeature = .scan
                            }
                        })
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Vertical toolbar on the right
            VStack(spacing: 0) {
                ForEach(NFCFeature.allCases, id: \.self) { feature in
                    ToolbarButton(
                        feature: feature,
                        isSelected: selectedFeature == feature,
                        namespace: animation
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedFeature = feature
                        }
                    }
                    
                    if feature != NFCFeature.allCases.last {
                        Divider()
                            .background(Color.gray.opacity(0.3))
                    }
                }
                
                Spacer()
            }
            .frame(width: 60)
            .background(
                Color(UIColor.secondarySystemBackground)
                    .overlay(
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 1),
                        alignment: .leading
                    )
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let initial = initialFeature {
                selectedFeature = initial
            }
        }
    }
}

// MARK: - Toolbar Button
struct ToolbarButton: View {
    let feature: NFCContainerView.NFCFeature
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    // Selection indicator
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(feature.color.opacity(0.2))
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                    
                    Image(systemName: feature.icon)
                        .font(.system(size: 24))
                        .foregroundColor(isSelected ? feature.color : .gray)
                        .scaleEffect(isPressed ? 0.85 : 1.0)
                        .animation(.spring(response: 0.1, dampingFraction: 0.6), value: isPressed)
                }
                .frame(width: 44, height: 44)
                
                Text(feature.rawValue)
                    .font(.caption2)
                    .foregroundColor(isSelected ? feature.color : .gray)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 50)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(PressedButtonStyle(isPressed: $isPressed))
        .accessibilityLabel(feature.rawValue)
    }
}

// MARK: - Button Style
struct PressedButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { pressed in
                isPressed = pressed
            }
    }
}

// MARK: - Coming Soon View
struct ComingSoonView: View {
    let feature: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hammer.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("\(feature) Coming Soon")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("This feature is being integrated from the NFC SD Tracker app")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
}

// MARK: - Preview
struct NFCContainerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            NFCContainerView()
        }
    }
}