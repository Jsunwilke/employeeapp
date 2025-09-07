import SwiftUI

class KeyboardManager: ObservableObject {
    static let shared = KeyboardManager()
    
    @Published var isShowingCustomKeyboard = false
    @Published var activeFieldText: Binding<String>?
    @Published var onUp: (() -> Void)?
    @Published var onDown: (() -> Void)?
    @Published var onDismiss: (() -> Void)?
    @Published var editingContext: String = "" // Add context about what's being edited
    @Published var useMiniMode: Bool = false // Use mini mode for iPad
    @Published var keyboardOffset: CGSize = .zero // Track keyboard position when dragged
    
    private init() {}
    
    func showKeyboard(for text: Binding<String>, context: String = "", miniMode: Bool = false, onUp: (() -> Void)? = nil, onDown: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.activeFieldText = text
        self.editingContext = context
        self.useMiniMode = miniMode
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
        self.editingContext = ""
        self.useMiniMode = false
        self.keyboardOffset = .zero // Reset position when keyboard is hidden
        self.onUp = nil
        self.onDown = nil
        self.onDismiss = nil
    }
}

// View modifier to add the keyboard overlay at the root level
struct CustomKeyboardModifier: ViewModifier {
    @StateObject private var keyboardManager = KeyboardManager.shared
    @State private var dragOffset: CGSize = .zero
    @State private var totalOffset: CGSize = .zero
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if keyboardManager.isShowingCustomKeyboard,
               let textBinding = keyboardManager.activeFieldText {
                
                // Background overlay to detect taps outside keyboard
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        keyboardManager.hideKeyboard()
                    }
                    .transition(.opacity)
                
                // Position keyboard based on mode
                if keyboardManager.useMiniMode {
                    // Mini mode: Position on right side with drag capability
                    GeometryReader { geometry in
                        CustomNumberKeyboard(
                            text: textBinding,
                            compactMode: true,
                            showDragHandle: true,
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
                        .frame(width: 380)
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(12)
                        .shadow(radius: 10)
                        .offset(x: totalOffset.width + dragOffset.width,
                                y: totalOffset.height + dragOffset.height)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    // Calculate new position
                                    let newWidth = totalOffset.width + value.translation.width
                                    let newHeight = totalOffset.height + value.translation.height
                                    
                                    // Apply bounds checking
                                    let maxX = geometry.size.width - 380 - 20
                                    let maxY = geometry.size.height - 400
                                    
                                    totalOffset.width = min(max(-20, newWidth), maxX)
                                    totalOffset.height = min(max(20, newHeight), maxY)
                                    
                                    // Save to manager
                                    keyboardManager.keyboardOffset = totalOffset
                                    
                                    // Reset temporary offset
                                    dragOffset = .zero
                                }
                        )
                        .position(x: geometry.size.width - 200, y: geometry.size.height / 2)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .onAppear {
                            // Restore saved position
                            totalOffset = keyboardManager.keyboardOffset
                        }
                    }
                } else {
                    // Standard mode: Position at bottom
                    VStack {
                        Spacer()
                        
                        CustomNumberKeyboard(
                            text: textBinding,
                            compactMode: false,
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
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: keyboardManager.isShowingCustomKeyboard)
    }
}

extension View {
    func customKeyboardOverlay() -> some View {
        modifier(CustomKeyboardModifier())
    }
}