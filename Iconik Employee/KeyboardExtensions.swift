import SwiftUI
import Combine

// MARK: - Keyboard Extensions

// Extension to handle keyboard shortcuts
extension View {
    func addKeyboardShortcuts() -> some View {
        self.onAppear {
            // Set up keyboard shortcuts once per view
            #if !targetEnvironment(simulator)
            setupKeyboardShortcuts()
            #endif
        }
    }
    
    // This function would be implemented in a real app to handle keyboard shortcuts
    private func setupKeyboardShortcuts() {
        // Add keyboard shortcut observers in actual implementation
        // This would typically use UIKeyCommand for hardware keyboard support
    }
}

// Extension to find first responder in the view hierarchy
extension UIView {
    func findFirstResponder() -> UIView? {
        if isFirstResponder {
            return self
        }
        
        for subview in subviews {
            if let firstResponder = subview.findFirstResponder() {
                return firstResponder
            }
        }
        
        return nil
    }
}

// This is a custom modifier that allows for easier tab navigation between fields
struct TabNavigationModifier: ViewModifier {
    @FocusState var focusedField: String?
    var fieldID: String
    var nextFieldID: String?
    
    func body(content: Content) -> some View {
        content
            .focused($focusedField, equals: fieldID)
            .onSubmit {
                if let next = nextFieldID {
                    focusedField = next
                }
            }
    }
}

// Extension for number field that only accepts numeric input and handles keyboard properly
struct NumberOnlyViewModifier: ViewModifier {
    @Binding var text: String
    
    func body(content: Content) -> some View {
        content
            .keyboardType(.numberPad)
            .onReceive(Just(text)) { newValue in
                let filtered = newValue.filter { "0123456789,- ".contains($0) }
                if filtered != newValue {
                    self.text = filtered
                }
            }
    }
}

extension TextField {
    func numberOnly(_ text: Binding<String>) -> some View {
        self.modifier(NumberOnlyViewModifier(text: text))
    }
}

// A custom numeric text field that works better with hardware keyboards
struct NumericTextField: View {
    @Binding var text: String
    var placeholder: String
    var onCommit: (() -> Void)? = nil
    
    // Focus state
    @FocusState private var isFocused: Bool
    
    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.numberPad)
            .focused($isFocused)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isFocused = false
                        onCommit?()
                    }
                }
            }
            .onSubmit {
                onCommit?()
            }
            .onReceive(Just(text)) { newValue in
                let filtered = newValue.filter { "0123456789,- ".contains($0) }
                if filtered != newValue {
                    self.text = filtered
                }
            }
    }
}
