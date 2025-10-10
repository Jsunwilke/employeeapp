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
    
    // Persistent storage for keyboard position
    private static var savedKeyboardPosition: CGPoint? = nil
    
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
        // Don't reset keyboardOffset here - we want to remember it
        self.onUp = nil
        self.onDown = nil
        self.onDismiss = nil
    }
    
    func saveKeyboardPosition(_ position: CGPoint) {
        Self.savedKeyboardPosition = position
    }
    
    func getSavedKeyboardPosition() -> CGPoint? {
        return Self.savedKeyboardPosition
    }
}

// View modifier to add the keyboard overlay at the root level
struct CustomKeyboardModifier: ViewModifier {
    @StateObject private var keyboardManager = KeyboardManager.shared
    @State private var keyboardPosition: CGPoint = .zero
    @State private var isDragging = false
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if keyboardManager.isShowingCustomKeyboard,
               let textBinding = keyboardManager.activeFieldText {
                
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
                        .position(keyboardPosition)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isDragging = true
                                    keyboardPosition = value.location
                                }
                                .onEnded { value in
                                    isDragging = false
                                    // Apply bounds checking
                                    let minX: CGFloat = 190
                                    let maxX = geometry.size.width - 190
                                    let minY: CGFloat = 160
                                    let maxY = geometry.size.height - 160
                                    
                                    keyboardPosition.x = min(max(minX, keyboardPosition.x), maxX)
                                    keyboardPosition.y = min(max(minY, keyboardPosition.y), maxY)
                                    
                                    // Save position
                                    keyboardManager.saveKeyboardPosition(keyboardPosition)
                                }
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .onAppear {
                            // Set initial position: use saved position or default to lower-right
                            if let savedPosition = keyboardManager.getSavedKeyboardPosition() {
                                keyboardPosition = savedPosition
                            } else {
                                // Default to lower-right corner
                                keyboardPosition = CGPoint(
                                    x: geometry.size.width - 200,
                                    y: geometry.size.height - 200
                                )
                            }
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