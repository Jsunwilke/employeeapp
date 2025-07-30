import SwiftUI

struct CustomKeyboardTextField: View {
    @Binding var text: String
    var placeholder: String
    var onEnterOrDown: (() -> Void)? = nil
    var onEnterOrUp: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    
    @StateObject private var keyboardManager = KeyboardManager.shared
    @State private var isActive = false
    @State private var showCursor = false
    @State private var cursorTimer: Timer?
    
    var body: some View {
        // Non-editable text field that shows custom keyboard when tapped
        HStack {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 0) {
                    Text(text)
                        .foregroundColor(.primary)
                    
                    // Blinking cursor
                    if isActive && showCursor {
                        Text("|")
                            .foregroundColor(.blue)
                            .font(.system(size: 16, weight: .light))
                    }
                    
                    Spacer()
                }
            }
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
            startCursorAnimation()
            keyboardManager.showKeyboard(
                for: $text,
                onUp: onEnterOrUp,
                onDown: onEnterOrDown,
                onDismiss: onDismiss
            )
        }
        .onChange(of: keyboardManager.isShowingCustomKeyboard) { isShowing in
            if !isShowing {
                isActive = false
                stopCursorAnimation()
            }
        }
        .onDisappear {
            stopCursorAnimation()
        }
    }
    
    private func startCursorAnimation() {
        showCursor = true
        cursorTimer?.invalidate()
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            showCursor.toggle()
        }
    }
    
    private func stopCursorAnimation() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        showCursor = false
    }
}