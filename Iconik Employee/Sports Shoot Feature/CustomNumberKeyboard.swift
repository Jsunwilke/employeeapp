import SwiftUI

struct CustomNumberKeyboard: View {
    @Binding var text: String
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
    
    var body: some View {
        VStack(spacing: 10) {
            // Display box at top showing current text and context
            VStack(alignment: .leading, spacing: 4) {
                if !keyboardManager.editingContext.isEmpty {
                    Text(keyboardManager.editingContext)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    // Always show the text binding value
                    Text(displayText.isEmpty ? "Enter image numbers" : displayText)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(displayText.isEmpty ? Color.gray : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.none) // Disable animation to ensure immediate updates
                
                    // Clear button
                    if !displayText.isEmpty {
                        Button(action: {
                            text = ""
                            displayText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
            .padding(.horizontal)
            
            // Number grid and bottom row
            VStack(spacing: 10) {
                // Numbers 1-9 in 3x3 grid
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(1...9, id: \.self) { number in
                        NumberButton(text: "\(number)") {
                            text.append("\(number)")
                            displayText = text  // Update display text
                            print("DEBUG: Appended \(number), text is now: \(text)")
                        }
                    }
                }
                
                // Bottom row - using GeometryReader for proper column sizing
                GeometryReader { geometry in
                    let columnWidth = (geometry.size.width - 20) / 3 // 3 columns with spacing
                    let halfButtonWidth = (columnWidth - 10) / 2 // Half width for - and + buttons
                    
                    HStack(spacing: 10) {
                        // First column: hyphen and plus buttons (each half of column width)
                        HStack(spacing: 10) {
                            Button(action: {
                                text.append("-")
                                displayText = text
                            }) {
                                Text("-")
                                    .font(.system(size: 28, weight: .regular))
                                    .foregroundColor(Color(UIColor.label))
                                    .frame(width: halfButtonWidth, height: 50)
                                    .background(Color(UIColor.systemBackground))
                                    .cornerRadius(8)
                                    .shadow(radius: 1)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                text.append("+")
                                displayText = text
                            }) {
                                Text("+")
                                    .font(.system(size: 28, weight: .regular))
                                    .foregroundColor(Color(UIColor.label))
                                    .frame(width: halfButtonWidth, height: 50)
                                    .background(Color(UIColor.systemBackground))
                                    .cornerRadius(8)
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
                                .font(.system(size: 28, weight: .regular))
                                .foregroundColor(Color(UIColor.label))
                                .frame(width: columnWidth, height: 50)
                                .background(Color(UIColor.systemBackground))
                                .cornerRadius(8)
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
                                .font(.system(size: 24))
                                .foregroundColor(Color(UIColor.label))
                                .frame(width: columnWidth, height: 50)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .frame(height: 50)
            }
            .padding(.horizontal)
            
            // Navigation buttons
            HStack(spacing: 20) {
                // Up arrow
                NavigationButton(systemName: "arrow.up") {
                    onUp?()
                }
                
                // Down arrow
                NavigationButton(systemName: "arrow.down") {
                    onDown?()
                }
                
                Spacer()
                
                // Done button
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 80, height: 44)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)
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
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 28, weight: .regular))
                .foregroundColor(Color(UIColor.label))  // Explicit text color for proper contrast
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemBackground))  // Adaptive background color
                .cornerRadius(8)
                .shadow(radius: 1)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(height: 50)
    }
}

struct NavigationButton: View {
    let systemName: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24))
                .foregroundColor(.blue)
                .frame(width: 50, height: 44)
                .background(Color(UIColor.systemBackground))  // Adaptive background color
                .cornerRadius(8)
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