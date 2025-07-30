import SwiftUI
import Combine

// TextField with autosave functionality - simplified version that works properly
struct AutosaveTextField: View {
    @Binding var text: String
    var placeholder: String
    var onTapOutside: (() -> Void)? = nil
    var onEnterOrDown: (() -> Void)? = nil  // Callback for Enter or Down arrow
    var onEnterOrUp: (() -> Void)? = nil  // Callback for Up arrow
    
    // Focus state
    @FocusState private var isFocused: Bool
    
    // On appear, set focus automatically
    @State private var hasAppeared = false
    
    // Track the previous focus state to detect when focus is lost
    @State private var wasFocused = false
    
    init(text: Binding<String>, placeholder: String, onTapOutside: (() -> Void)? = nil, onEnterOrDown: (() -> Void)? = nil, onEnterOrUp: (() -> Void)? = nil) {
        self._text = text
        self.placeholder = placeholder
        self.onTapOutside = onTapOutside
        self.onEnterOrDown = onEnterOrDown
        self.onEnterOrUp = onEnterOrUp
    }
    
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Use custom keyboard on iPad
            CustomKeyboardTextField(
                text: $text,
                placeholder: placeholder,
                onEnterOrDown: onEnterOrDown,
                onEnterOrUp: onEnterOrUp,
                onDismiss: onTapOutside
            )
            // Auto-focus behavior for custom keyboard
            .onAppear {
                if !hasAppeared {
                    hasAppeared = true
                    // Auto-show keyboard
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        KeyboardManager.shared.showKeyboard(
                            for: $text,
                            onUp: onEnterOrUp,
                            onDown: onEnterOrDown,
                            onDismiss: onTapOutside
                        )
                    }
                }
            }
        } else {
            // Use system keyboard on iPhone
            TextField(placeholder, text: $text)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isFocused)
            .toolbar {
                // Safe toolbar implementation that avoids constraint issues
                if isFocused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        
                        // Up arrow button
                        Button(action: {
                            onEnterOrUp?()
                        }) {
                            Image(systemName: "arrow.up")
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 4)
                        
                        // Down arrow button
                        Button(action: {
                            onEnterOrDown?()
                        }) {
                            Image(systemName: "arrow.down")
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 4)
                        
                        // Hyphen button
                        Button(action: {
                            // Insert hyphen at current cursor position
                            text.append("-")
                        }) {
                            Text("-")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
            .onSubmit {
                // When submit is triggered, go to next field
                onEnterOrDown?()
            }
            // Set up initial focus
            .onAppear {
                print("📝 AutosaveTextField onAppear: text = '\(text)', hasAppeared = \(hasAppeared)")
                
                if !hasAppeared {
                    hasAppeared = true
                    
                    // Auto-focus on all devices for better UX
                    DispatchQueue.main.async {
                        self.isFocused = true
                        self.wasFocused = true
                    }
                }
            }
            // Track changes in focus state
            .onChange(of: isFocused) { newFocus in
                // If focus was lost, trigger the save
                if wasFocused && !newFocus {
                    onTapOutside?()
                }
                wasFocused = newFocus
            }
        }
    }
}
