import SwiftUI
import Combine

// TextField with autosave functionality - simplified version that works properly
struct AutosaveTextField: View {
    @Binding var text: String
    var placeholder: String
    var onTapOutside: (() -> Void)? = nil
    var onEnterOrDown: (() -> Void)? = nil  // Callback for Enter or Down arrow
    
    // Focus state
    @FocusState private var isFocused: Bool
    
    // On appear, set focus automatically
    @State private var hasAppeared = false
    
    // Track the previous focus state to detect when focus is lost
    @State private var wasFocused = false
    
    // Store the initial value to ensure proper display
    @State private var localText: String = ""
    @State private var isInitialized = false
    
    var body: some View {
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
                        
                        // Down arrow button
                        Button(action: {
                            onEnterOrDown?()
                        }) {
                            Image(systemName: "arrow.down")
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 4)
                        
                        // Done button
                        Button("Done") {
                            isFocused = false
                            onTapOutside?()
                        }
                    }
                }
            }
            .onSubmit {
                // When submit is triggered, go to next field
                onEnterOrDown?()
            }
            // Handle local text changes
            .onChange(of: localText) { newValue in
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
            // Sync binding changes to local text
            .onChange(of: text) { newValue in
                if localText != newValue {
                    print("📝 AutosaveTextField syncing binding value: '\(newValue)' (was: '\(localText)')")
                    localText = newValue
                    
                    // If we're focused and the value changed significantly, ensure cursor is at end
                    if isFocused && !newValue.isEmpty && localText.isEmpty {
                        // This handles the case where value is set after focus
                        DispatchQueue.main.async {
                            // Force a small UI update to ensure text field shows the new value
                            self.localText = newValue
                        }
                    }
                }
            }
            // Set up initial value and focus
            .onAppear {
                print("📝 AutosaveTextField onAppear: text = '\(text)', hasAppeared = \(hasAppeared)")
                
                // Always sync the local text with binding value on appear
                localText = text
                if !isInitialized {
                    isInitialized = true
                    print("📝 AutosaveTextField initialized with value: '\(localText)'")
                }
                
                if !hasAppeared {
                    hasAppeared = true
                    
                    // Only auto-focus on iPhone, let iPad users tap to focus
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        DispatchQueue.main.async {
                            self.isFocused = true
                            self.wasFocused = true
                        }
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
            .contentShape(Rectangle())
            .onTapGesture {
                if !isFocused {
                    isFocused = true
                }
            }
    }
}
