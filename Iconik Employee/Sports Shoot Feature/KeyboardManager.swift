import SwiftUI

class KeyboardManager: ObservableObject {
    static let shared = KeyboardManager()
    
    @Published var isShowingCustomKeyboard = false
    @Published var activeFieldText: Binding<String>?
    @Published var onUp: (() -> Void)?
    @Published var onDown: (() -> Void)?
    @Published var onDismiss: (() -> Void)?
    
    private init() {}
    
    func showKeyboard(for text: Binding<String>, onUp: (() -> Void)? = nil, onDown: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.activeFieldText = text
        self.onUp = onUp
        self.onDown = onDown
        self.onDismiss = onDismiss
        self.isShowingCustomKeyboard = true
    }
    
    func hideKeyboard() {
        // Call onDismiss before clearing
        self.onDismiss?()
        
        self.isShowingCustomKeyboard = false
        self.activeFieldText = nil
        self.onUp = nil
        self.onDown = nil
        self.onDismiss = nil
    }
}

// View modifier to add the keyboard overlay at the root level
struct CustomKeyboardModifier: ViewModifier {
    @StateObject private var keyboardManager = KeyboardManager.shared
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if keyboardManager.isShowingCustomKeyboard,
               let textBinding = keyboardManager.activeFieldText {
                VStack {
                    Spacer()
                    
                    CustomNumberKeyboard(
                        text: textBinding,
                        onDismiss: {
                            keyboardManager.hideKeyboard()
                        },
                        onUp: {
                            keyboardManager.onUp?()
                            keyboardManager.hideKeyboard()
                        },
                        onDown: {
                            keyboardManager.onDown?()
                            keyboardManager.hideKeyboard()
                        }
                    )
                    .transition(.move(edge: .bottom))
                }
                .background(
                    Color.clear
                        .ignoresSafeArea()
                        .onTapGesture {
                            keyboardManager.hideKeyboard()
                        }
                )
                .animation(.easeInOut(duration: 0.25), value: keyboardManager.isShowingCustomKeyboard)
            }
        }
    }
}

extension View {
    func customKeyboardOverlay() -> some View {
        modifier(CustomKeyboardModifier())
    }
}