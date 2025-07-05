import SwiftUI
import Combine

// TextField with autosave functionality
struct AutosaveTextField: View {
    @Binding var text: String
    var placeholder: String
    var onTapOutside: (() -> Void)? = nil
    
    // Focus state
    @FocusState private var isFocused: Bool
    
    // On appear, set focus automatically
    @State private var hasAppeared = false
    
    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.numberPad)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .focused($isFocused)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isFocused = false
                        onTapOutside?()
                    }
                }
            }
            .onSubmit {
                onTapOutside?()
            }
            .onReceive(Just(text)) { newValue in
                // Filter to only allow numbers, commas, hyphens, and spaces
                let filtered = newValue.filter { "0123456789,- ".contains($0) }
                if filtered != newValue {
                    self.text = filtered
                }
            }
            .onAppear {
                // Automatically focus the field when it appears
                // Small delay ensures the view is fully loaded
                if !hasAppeared {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.isFocused = true
                        self.hasAppeared = true
                    }
                }
            }
            .contentShape(Rectangle()) // Makes the entire area tappable
            .onTapGesture {
                if !isFocused {
                    isFocused = true
                }
            }
    }
}
