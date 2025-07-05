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
    
    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.numberPad)
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
            // Save when text changes - maintains autosave functionality
            .onReceive(Just(text)) { newValue in
                // Filter to only allow numbers, commas, hyphens, and spaces
                let filtered = newValue.filter { "0123456789,- ".contains($0) }
                if filtered != newValue {
                    self.text = filtered
                }
            }
            // Set up auto-focus when appearing
            .onAppear {
                if !hasAppeared {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isFocused = true
                        self.hasAppeared = true
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
            .contentShape(Rectangle())
            .onTapGesture {
                if !isFocused {
                    isFocused = true
                }
            }
    }
}
