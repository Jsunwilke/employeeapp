import SwiftUI
import Firebase
import FirebaseFirestore
import Combine

struct AddRosterEntryView: View {
    let shootID: String
    let existingEntry: RosterEntry?
    let onComplete: (Bool) -> Void
    
    @State private var lastName: String = ""
    @State private var firstName: String = ""
    @State private var teacher: String = ""
    @State private var group: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var imageNumbers: String = ""
    @State private var notes: String = ""
    
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    
    // Focus state for keyboard navigation
    @FocusState private var focusedField: String?
    
    @Environment(\.presentationMode) var presentationMode
    
    var isEditing: Bool {
        existingEntry != nil
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Athlete Information")) {
                    TextField("Name", text: $lastName)
                        .autocapitalization(.words)
                        .focused($focusedField, equals: "lastName")
                        .submitLabel(.next)
                        .onSubmit { focusedField = "firstName" }
                    
                    TextField("Subject ID", text: $firstName)
                        .autocapitalization(.words)
                        .focused($focusedField, equals: "firstName")
                        .submitLabel(.next)
                        .onSubmit { focusedField = "teacher" }
                    
                    TextField("Special", text: $teacher)
                        .autocapitalization(.words)
                        .focused($focusedField, equals: "teacher")
                        .submitLabel(.next)
                        .onSubmit { focusedField = "group" }
                    
                    TextField("Sport/Team", text: $group)
                        .autocapitalization(.words)
                        .focused($focusedField, equals: "group")
                        .submitLabel(.next)
                        .onSubmit { focusedField = "email" }
                }
                
                Section(header: Text("Contact Information")) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: "email")
                        .submitLabel(.next)
                        .onSubmit { focusedField = "phone" }
                    
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: "phone")
                        .submitLabel(.next)
                        .onSubmit { focusedField = "imageNumbers" }
                }
                
                Section(header: Text("Image Information")) {
                    NumericTextField(
                        text: $imageNumbers,
                        placeholder: "Image Numbers",
                        onCommit: { focusedField = "notes" }
                    )
                    .focused($focusedField, equals: "imageNumbers")
                    .font(.body)
                    .padding(.vertical, 6)
                    .frame(minHeight: 44)
                    
                    TextView(text: $notes, placeholder: "Notes (optional)")
                        .frame(minHeight: 100)
                }
                
                Section(header: Text("Field Mapping Information")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("In Captura Workflow:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Name")
                                .fontWeight(.semibold)
                            Text("→")
                            Text("Name")
                                .foregroundColor(.blue)
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Subject ID")
                                .fontWeight(.semibold)
                            Text("→")
                            Text("Subject ID")
                                .foregroundColor(.blue)
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Special")
                                .fontWeight(.semibold)
                            Text("→")
                            Text("Special")
                                .foregroundColor(.blue)
                        }
                        .font(.caption)
                        
                        HStack {
                            Text("Sport/Team")
                                .fontWeight(.semibold)
                            Text("→")
                            Text("Sport/Team")
                                .foregroundColor(.blue)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 8)
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
                    teacher = entry.teacher
                    group = entry.group
                    email = entry.email
                    phone = entry.phone
                    imageNumbers = entry.imageNumbers
                    notes = entry.notes
                }
            }
        }
    }
    
    private func saveRosterEntry() {
        isLoading = true
        
        let trimmedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLastName = !trimmedLastName.isEmpty
        
        let entry = RosterEntry(
            id: existingEntry?.id ?? UUID().uuidString,
            lastName: trimmedLastName,
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            teacher: teacher.trimmingCharacters(in: .whitespacesAndNewlines),
            group: group.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
            imageNumbers: imageNumbers.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            wasBlank: existingEntry?.wasBlank ?? true,  // New entries always have wasBlank = true
            isFilledBlank: hasLastName  // Set to true if lastName is not empty
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
    var onCommit: (() -> Void)? = nil
    
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
        textView.returnKeyType = .done // Set return key to "Done"
        
        // Add a toolbar with Done button for better keyboard experience
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: context.coordinator, action: #selector(Coordinator.doneButtonTapped))
        toolbar.items = [flexSpace, doneButton]
        textView.inputAccessoryView = toolbar
        
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
        
        // Handle the return key
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                textView.resignFirstResponder()
                parent.onCommit?()
                return false
            }
            return true
        }
        
        @objc func doneButtonTapped() {
            // Get a reference to the first responder
            let keyWindow = UIApplication.shared.windows.filter {$0.isKeyWindow}.first
            if var topController = keyWindow?.rootViewController {
                while let presentedViewController = topController.presentedViewController {
                    topController = presentedViewController
                }
                
                // Find the active text view
                if let activeTextView = topController.view.findFirstResponder() as? UITextView {
                    activeTextView.resignFirstResponder()
                    parent.onCommit?()
                }
            }
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
