import SwiftUI

struct CustomKeyboardTextField: View {
    @Binding var text: String
    var placeholder: String
    var onEnterOrDown: (() -> Void)? = nil
    var onEnterOrUp: (() -> Void)? = nil
    
    @StateObject private var keyboardManager = KeyboardManager.shared
    @State private var isActive = false
    
    var body: some View {
        // Non-editable text field that shows custom keyboard when tapped
        HStack {
            Text(text.isEmpty ? placeholder : text)
                .foregroundColor(text.isEmpty ? .gray : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.systemBackground)))
        )
        .onTapGesture {
            isActive = true
            keyboardManager.showKeyboard(
                for: $text,
                onUp: onEnterOrUp,
                onDown: onEnterOrDown
            )
        }
        .onChange(of: keyboardManager.isShowingCustomKeyboard) { isShowing in
            if !isShowing {
                isActive = false
            }
        }
    }
}