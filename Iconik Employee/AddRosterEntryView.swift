import SwiftUI
import Firebase
import FirebaseFirestore

struct AddRosterEntryView: View {
    let shootID: String
    let existingEntry: RosterEntry?
    let onComplete: (Bool) -> Void
    
    @State private var lastName: String = ""
    @State private var firstName: String = ""
    @State private var uniformNumber: String = ""
    @State private var grade: String = ""
    @State private var imageNumbers: String = ""
    @State private var notes: String = ""
    
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    
    @Environment(\.presentationMode) var presentationMode
    
    var isEditing: Bool {
        existingEntry != nil
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Athlete Information")) {
                    TextField("Last Name", text: $lastName)
                        .autocapitalization(.words)
                    
                    TextField("First Name", text: $firstName)
                        .autocapitalization(.words)
                    
                    TextField("Number", text: $uniformNumber)
                        .keyboardType(.numberPad)
                    
                    TextField("Grade", text: $grade)
                        .keyboardType(.numbersAndPunctuation)
                }
                
                Section(header: Text("Image Information")) {
                    TextField("Image Numbers", text: $imageNumbers)
                        .keyboardType(.asciiCapable)
                        .autocapitalization(.none)
                    
                    TextView(text: $notes, placeholder: "Notes (optional)")
                        .frame(minHeight: 100)
                }
                
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
            .navigationBarTitle(isEditing ? "Edit Athlete" : "Add Athlete", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Update" : "Save") {
                        saveRosterEntry()
                    }
                    .disabled(lastName.isEmpty || firstName.isEmpty)
                }
            }
            .alert(isPresented: $showingErrorAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                if let entry = existingEntry {
                    lastName = entry.lastName
                    firstName = entry.firstName
                    uniformNumber = entry.uniformNumber
                    grade = entry.grade
                    imageNumbers = entry.imageNumbers
                    notes = entry.notes
                }
            }
        }
    }
    
    private func saveRosterEntry() {
        isLoading = true
        
        let entry = RosterEntry(
            id: existingEntry?.id ?? UUID().uuidString,
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            uniformNumber: uniformNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            grade: grade.trimmingCharacters(in: .whitespacesAndNewlines),
            imageNumbers: imageNumbers.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        if isEditing {
            SportsShootService.shared.updateRosterEntry(shootID: shootID, entry: entry) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    switch result {
                    case .success:
                        self.onComplete(true)
                        self.presentationMode.wrappedValue.dismiss()
                    case .failure(let error):
                        self.errorMessage = "Failed to update athlete: \(error.localizedDescription)"
                        self.showingErrorAlert = true
                    }
                }
            }
        } else {
            SportsShootService.shared.addRosterEntry(shootID: shootID, entry: entry) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    switch result {
                    case .success:
                        self.onComplete(true)
                        self.presentationMode.wrappedValue.dismiss()
                    case .failure(let error):
                        self.errorMessage = "Failed to add athlete: \(error.localizedDescription)"
                        self.showingErrorAlert = true
                    }
                }
            }
        }
    }
}

// Custom TextView for SwiftUI
struct TextView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .default
        textView.backgroundColor = UIColor.clear
        
        if text.isEmpty {
            textView.text = placeholder
            textView.textColor = UIColor.placeholderText
        } else {
            textView.text = text
            textView.textColor = UIColor.label
        }
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        if text.isEmpty && !uiView.isFirstResponder {
            uiView.text = placeholder
            uiView.textColor = UIColor.placeholderText
        } else if uiView.text == placeholder && !text.isEmpty {
            uiView.text = text
            uiView.textColor = UIColor.label
        } else if uiView.text != text && !uiView.isFirstResponder {
            uiView.text = text
            uiView.textColor = UIColor.label
        }
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextView
        
        init(_ parent: TextView) {
            self.parent = parent
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            if textView.text == parent.placeholder {
                textView.text = ""
                textView.textColor = UIColor.label
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = UIColor.placeholderText
            }
        }
        
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}

struct AddRosterEntryView_Previews: PreviewProvider {
    static var previews: some View {
        AddRosterEntryView(
            shootID: "previewID",
            existingEntry: nil,
            onComplete: { _ in }
        )
    }
}