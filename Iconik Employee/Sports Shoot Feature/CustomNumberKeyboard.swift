import SwiftUI

struct CustomNumberKeyboard: View {
    @Binding var text: String
    var compactMode: Bool = false
    var showDragHandle: Bool = false
    var onDismiss: () -> Void
    var onUp: (() -> Void)? = nil
    var onDown: (() -> Void)? = nil
    
    @StateObject private var keyboardManager = KeyboardManager.shared
    @State private var displayText: String = ""  // Local state to force updates
    
    // Grid layout for number buttons
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    // Sizing based on mode
    var buttonHeight: CGFloat { compactMode ? 36 : 50 }
    var buttonFont: Font { compactMode ? .system(size: 20, weight: .regular) : .system(size: 28, weight: .regular) }
    var spacing: CGFloat { compactMode ? 6 : 10 }
    var displayFont: Font { compactMode ? .system(size: 16, weight: .medium) : .system(size: 20, weight: .medium) }
    var contextFont: Font { compactMode ? .system(size: 12) : .system(size: 14) }
    var padding: CGFloat { compactMode ? 8 : 12 }
    
    var body: some View {
        VStack(spacing: spacing) {
            // Drag handle indicator
            if showDragHandle {
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 40, height: 5)
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            
            // Display box at top showing current text and context
            VStack(alignment: .leading, spacing: 4) {
                if !keyboardManager.editingContext.isEmpty {
                    Text(keyboardManager.editingContext)
                        .font(contextFont)
                        .foregroundColor(.secondary)
                }
                
                // Display text without clear button
                Text(displayText.isEmpty ? "Enter image numbers" : displayText)
                    .font(displayFont)
                    .foregroundColor(displayText.isEmpty ? Color.gray : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.none, value: displayText) // Disable animation to ensure immediate updates
            }
            .padding(.horizontal, compactMode ? 12 : 16)
            .padding(.vertical, padding)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(compactMode ? 8 : 10)
            .padding(.horizontal, compactMode ? 12 : 16)
            
            // Number grid and bottom row
            VStack(spacing: spacing) {
                // Numbers 1-9 in 3x3 grid
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(1...9, id: \.self) { number in
                        NumberButton(text: "\(number)", compactMode: compactMode) {
                            text.append("\(number)")
                            displayText = text  // Update display text
                            print("DEBUG: Appended \(number), text is now: \(text)")
                        }
                    }
                }
                
                // Bottom row - using GeometryReader for proper column sizing
                GeometryReader { geometry in
                    let columnWidth = (geometry.size.width - spacing * 2) / 3 // 3 columns with spacing
                    let halfButtonWidth = (columnWidth - spacing) / 2 // Half width for - and + buttons
                    
                    HStack(spacing: spacing) {
                        // First column: hyphen and plus buttons (each half of column width)
                        HStack(spacing: spacing) {
                            Button(action: {
                                text.append("-")
                                displayText = text
                            }) {
                                Text("-")
                                    .font(buttonFont)
                                    .foregroundColor(Color(UIColor.label))
                                    .frame(width: halfButtonWidth, height: buttonHeight)
                                    .background(Color(UIColor.systemBackground))
                                    .cornerRadius(compactMode ? 6 : 8)
                                    .shadow(radius: 1)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                text.append("+")
                                displayText = text
                            }) {
                                Text("+")
                                    .font(buttonFont)
                                    .foregroundColor(Color(UIColor.label))
                                    .frame(width: halfButtonWidth, height: buttonHeight)
                                    .background(Color(UIColor.systemBackground))
                                    .cornerRadius(compactMode ? 6 : 8)
                                    .shadow(radius: 1)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .frame(width: columnWidth)
                        
                        // Second column: Zero button (full column width)
                        Button(action: {
                            text.append("0")
                            displayText = text
                        }) {
                            Text("0")
                                .font(buttonFont)
                                .foregroundColor(Color(UIColor.label))
                                .frame(width: columnWidth, height: buttonHeight)
                                .background(Color(UIColor.systemBackground))
                                .cornerRadius(compactMode ? 6 : 8)
                                .shadow(radius: 1)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Third column: Delete button (full column width)
                        Button(action: {
                            if !text.isEmpty {
                                text.removeLast()
                                displayText = text
                            }
                        }) {
                            Image(systemName: "delete.left.fill")
                                .font(.system(size: compactMode ? 18 : 24))
                                .foregroundColor(Color(UIColor.label))
                                .frame(width: columnWidth, height: buttonHeight)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(compactMode ? 6 : 8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .frame(height: buttonHeight)
            }
            .padding(.horizontal)
            
            // Navigation buttons
            HStack(spacing: compactMode ? 12 : 20) {
                // Up arrow
                NavigationButton(systemName: "arrow.up", compactMode: compactMode) {
                    onUp?()
                }
                
                // Down arrow
                NavigationButton(systemName: "arrow.down", compactMode: compactMode) {
                    onDown?()
                }
                
                Spacer()
                
                // Done button
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.system(size: compactMode ? 16 : 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: compactMode ? 70 : 80, height: compactMode ? 36 : 44)
                        .background(Color.blue)
                        .cornerRadius(compactMode ? 6 : 8)
                }
            }
            .padding(.horizontal, compactMode ? 12 : 16)
        }
        .padding(.vertical, 10)
        .background(Color(UIColor.systemGray6))
        .onAppear {
            displayText = text  // Initialize display text with current text value
        }
        .onChange(of: text) { newValue in
            displayText = newValue  // Keep display text in sync
        }
    }
}

struct NumberButton: View {
    let text: String
    var compactMode: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: compactMode ? 20 : 28, weight: .regular))
                .foregroundColor(Color(UIColor.label))  // Explicit text color for proper contrast
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemBackground))  // Adaptive background color
                .cornerRadius(compactMode ? 6 : 8)
                .shadow(radius: 1)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(height: compactMode ? 36 : 50)
    }
}

struct NavigationButton: View {
    let systemName: String
    var compactMode: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: compactMode ? 18 : 24))
                .foregroundColor(.blue)
                .frame(width: compactMode ? 40 : 50, height: compactMode ? 36 : 44)
                .background(Color(UIColor.systemBackground))  // Adaptive background color
                .cornerRadius(compactMode ? 6 : 8)
                .shadow(radius: 1)
        }
    }
}

// Preview
struct CustomNumberKeyboard_Previews: PreviewProvider {
    static var previews: some View {
        CustomNumberKeyboard(text: .constant("123"), onDismiss: {})
            .previewLayout(.sizeThatFits)
    }
}