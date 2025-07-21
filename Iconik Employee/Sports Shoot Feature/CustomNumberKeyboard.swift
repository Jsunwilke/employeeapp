import SwiftUI

struct CustomNumberKeyboard: View {
    @Binding var text: String
    var onDismiss: () -> Void
    var onUp: (() -> Void)? = nil
    var onDown: (() -> Void)? = nil
    
    // Grid layout for number buttons
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(spacing: 10) {
            // Number grid
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(1...9, id: \.self) { number in
                    NumberButton(text: "\(number)") {
                        text.append("\(number)")
                    }
                }
                
                // Hyphen button
                NumberButton(text: "-") {
                    text.append("-")
                }
                
                // Zero button
                NumberButton(text: "0") {
                    text.append("0")
                }
                
                // Delete button
                Button(action: {
                    if !text.isEmpty {
                        text.removeLast()
                    }
                }) {
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 24))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
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
    }
}

struct NumberButton: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 28, weight: .regular))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
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
                .background(Color.white)
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