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
    
    // Store the initial value to ensure proper display
    @State private var localText: String
    @State private var isInitialized = false
    
    init(text: Binding<String>, placeholder: String, onTapOutside: (() -> Void)? = nil, onEnterOrDown: (() -> Void)? = nil, onEnterOrUp: (() -> Void)? = nil) {
        self._text = text
        self.placeholder = placeholder
        self.onTapOutside = onTapOutside
        self.onEnterOrDown = onEnterOrDown
        self.onEnterOrUp = onEnterOrUp
        // Initialize localText with the current binding value
        self._localText = State(initialValue: text.wrappedValue)
    }
    
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Use custom keyboard on iPad
            CustomKeyboardTextField(
                text: $localText,
                placeholder: placeholder,
                onEnterOrDown: onEnterOrDown,
                onEnterOrUp: onEnterOrUp
            )
            .onChange(of: localText) { newValue in
                handleTextChange(newValue)
            }
            // Auto-focus behavior for custom keyboard
            .onAppear {
                if !hasAppeared {
                    hasAppeared = true
                    // Auto-show keyboard
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        KeyboardManager.shared.showKeyboard(
                            for: $localText,
                            onUp: onEnterOrUp,
                            onDown: onEnterOrDown
                        )
                    }
                }
            }
        } else {
            // Use system keyboard on iPhone
            TextField(placeholder, text: $localText)
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
                            localText.append("-")
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
            // Handle local text changes
            .onChange(of: localText) { newValue in
                handleTextChange(newValue)
            }
            // Sync binding changes to local text
            .onChange(of: text) { newValue in
                if localText != newValue {
                    print("📝 AutosaveTextField syncing binding value: '\(newValue)' (was: '\(localText)')")
                    localText = newValue
                }
            }
            // Set up initial value and focus
            .onAppear {
                print("📝 AutosaveTextField onAppear: text = '\(text)', hasAppeared = \(hasAppeared)")
                
                // Always sync the local text with binding value on appear
                // Force update even if localText thinks it has a value
                if localText != text {
                    localText = text
                }
                
                if !isInitialized {
                    isInitialized = true
                    print("📝 AutosaveTextField initialized with value: '\(localText)'")
                }
                
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
                // If we're gaining focus, ensure localText is synced with the binding
                if !wasFocused && newFocus {
                    if localText != text && !text.isEmpty {
                        print("📝 AutosaveTextField syncing on focus: text='\(text)', localText='\(localText)'")
                        localText = text
                    }
                }
                // If focus was lost, trigger the save
                if wasFocused && !newFocus {
                    onTapOutside?()
                }
                wasFocused = newFocus
            }
        }
    }
    
    private func handleTextChange(_ newValue: String) {
        print("📝 AutosaveTextField localText changed to: '\(newValue)'")
        // Filter to only allow numbers, commas, hyphens, and spaces
        let filtered = newValue.filter { "0123456789,- ".contains($0) }
        if filtered != newValue {
            print("📝 AutosaveTextField filtering '\(newValue)' to '\(filtered)'")
            localText = filtered
        } else {
            // Update the binding when local text changes
            text = filtered
        }
    }
}
