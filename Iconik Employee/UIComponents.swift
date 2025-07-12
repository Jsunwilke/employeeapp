import SwiftUI

// MARK: - Shared UI Components

struct ModernCheckboxRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.blue : Color.gray, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    
                    if isSelected {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                    }
                }
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ModernSegmentButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(
                    isSelected ?
                        Color.blue.opacity(colorScheme == .dark ? 0.3 : 0.2) :
                        Color.clear
                )
                .foregroundColor(isSelected ? .blue : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}