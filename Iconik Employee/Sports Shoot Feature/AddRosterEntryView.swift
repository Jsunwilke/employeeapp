import SwiftUI
import Combine

struct AddRosterEntryView: View {
    let shootID: UUID
    let organizationId: String
    let existingEntry: RosterEntry?
    let onComplete: (Bool) -> Void

    // PowerSync for offline-first operations
    @StateObject private var powerSync = PowerSyncManager.shared
    @StateObject private var lockManager = LockManager.shared

    @State private var lastName: String = ""
    @State private var firstName: String = ""
    @State private var rosterId: String = ""
    @State private var teacher: String = ""
    @State private var groupName: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var imageNumbers: String = ""
    @State private var notes: String = ""

    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var isLoadingSubjectID = false

    // Lock state for editing existing entries
    @State private var lockAcquired = false
    @State private var lockError: String?
    @State private var isAcquiringLock = false

    // Focus state for keyboard navigation
    @FocusState private var focusedField: String?

    @Environment(\.presentationMode) var presentationMode

    var isEditing: Bool {
        existingEntry != nil
    }

    var body: some View {
        NavigationView {
            // Show lock error if we couldn't get lock
            if let error = lockError {
                lockErrorView(error)
            } else if isAcquiringLock {
                acquiringLockView
            } else {
                formContent
            }
        }
        .task {
            await acquireLockIfNeeded()
        }
        .onDisappear {
            releaseLockIfNeeded()
        }
    }

    // MARK: - Lock Error View

    private func lockErrorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("Cannot Edit")
                .font(.title2)
                .fontWeight(.bold)

            Text(error)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Button("Go Back") {
                presentationMode.wrappedValue.dismiss()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
        .navigationBarTitle("Locked", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }

    // MARK: - Acquiring Lock View

    private var acquiringLockView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Acquiring lock...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarTitle(isEditing ? "Edit Athlete" : "Add Athlete", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }

    // MARK: - Form Content

    private var formContent: some View {
        Form {
                Section(header: Text("Athlete Information")) {
                    TextField("Name", text: $lastName)
                        .autocapitalization(.words)
                        .focused($focusedField, equals: "lastName")
                        .submitLabel(.next)
                        .onSubmit { focusedField = "firstName" }

                    HStack {
                        TextField("Subject ID", text: $firstName)
                            .autocapitalization(.words)
                            .focused($focusedField, equals: "firstName")
                            .submitLabel(.next)
                            .onSubmit { focusedField = "rosterId" }
                            .disabled(isLoadingSubjectID)

                        if isLoadingSubjectID {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }

                    TextField("Roster ID", text: $rosterId)
                        .focused($focusedField, equals: "rosterId")
                        .submitLabel(.next)
                        .onSubmit { focusedField = "teacher" }

                    TextField("Special", text: $teacher)
                        .autocapitalization(.words)
                        .focused($focusedField, equals: "teacher")
                        .submitLabel(.next)
                        .onSubmit { focusedField = "groupName" }

                    TextField("Sport/Team", text: $groupName)
                        .autocapitalization(.words)
                        .focused($focusedField, equals: "groupName")
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
                    // Editing existing entry - load its values
                    lastName = entry.lastName
                    firstName = entry.firstName
                    rosterId = entry.rosterId
                    teacher = entry.teacher
                    groupName = entry.groupName
                    email = entry.email
                    phone = entry.phone
                    imageNumbers = entry.imageNumbers
                    notes = entry.notes
                } else {
                    // New entry - load next available Subject ID
                    loadNextSubjectID()
                }
            }
    }

    // MARK: - Lock Management

    private func acquireLockIfNeeded() async {
        guard let entry = existingEntry else {
            // New entry - no lock needed
            lockAcquired = true
            return
        }

        isAcquiringLock = true

        // Try to acquire lock
        let acquired = await lockManager.acquireRosterEntryLock(entryId: entry.id)

        await MainActor.run {
            isAcquiringLock = false
            if acquired {
                lockAcquired = true
            } else {
                // Check who has the lock
                if let lockedByName = entry.lockedByName {
                    lockError = "This athlete is being edited by \(lockedByName). Please try again later."
                } else {
                    lockError = "This athlete is being edited by another photographer. Please try again later."
                }
            }
        }
    }

    private func releaseLockIfNeeded() {
        guard let entry = existingEntry, lockAcquired else { return }

        Task {
            await lockManager.releaseRosterEntryLock(entryId: entry.id)
        }
    }

    private func loadNextSubjectID() {
        isLoadingSubjectID = true

        Task {
            do {
                // Fetch roster entries from PowerSync to find the highest Subject ID
                let entries = try await powerSync.getRosterEntries(forJob: shootID)

                // Find the highest Subject ID value
                let highestID = entries.compactMap { entry -> Int? in
                    return Int(entry.rosterId) ?? Int(entry.firstName)
                }.max() ?? 100  // Default to 100 if no entries

                await MainActor.run {
                    // Set the next available ID in both fields for Captura compatibility
                    self.firstName = "\(highestID + 1)"
                    self.rosterId = "\(highestID + 1)"
                    self.isLoadingSubjectID = false
                }
            } catch {
                await MainActor.run {
                    // Use default starting ID on error
                    self.firstName = "101"
                    self.rosterId = "101"
                    self.isLoadingSubjectID = false
                }
            }
        }
    }

    private func saveRosterEntry() {
        let trimmedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Create or update the roster entry with incremented version
        let entry = RosterEntry(
            id: existingEntry?.id ?? UUID(),
            sportsJobId: shootID,
            organizationId: organizationId,
            lastName: trimmedLastName,
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            teacher: teacher.trimmingCharacters(in: .whitespacesAndNewlines),
            groupName: groupName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
            imageNumbers: imageNumbers.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            sortOrder: existingEntry?.sortOrder ?? 0,
            version: (existingEntry?.version ?? 0) + 1,  // Increment version for conflict detection
            updatedAt: Date(),
            updatedBy: nil,
            lockedBy: nil,
            lockedByName: nil,
            lockedAt: nil,
            createdAt: existingEntry?.createdAt ?? Date(),
            rosterId: rosterId.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        // Save to PowerSync with retry (auto-syncs when online)
        Task {
            var retries = 0
            var lastError: Error?
            while retries < 3 {
                do {
                    try await powerSync.saveRosterEntry(entry)
                    if !isEditing {
                        FocalPointSyncClient.shared.broadcastSubjectCreated(
                            rosterEntryId: entry.id.uuidString.lowercased(),
                            firstName: entry.firstName,
                            lastName: entry.lastName,
                            rosterId: entry.rosterId,
                            grade: "",
                            groupName: entry.groupName
                        )
                    } else {
                        FocalPointSyncClient.shared.sendSubjectUpdated(
                            subjectId: entry.subjectId,
                            rosterEntryId: entry.id.uuidString.lowercased(),
                            firstName: entry.firstName,
                            lastName: entry.lastName,
                            rosterId: entry.rosterId
                        )
                    }
                    await MainActor.run {
                        onComplete(true)
                        presentationMode.wrappedValue.dismiss()
                    }
                    return
                } catch {
                    lastError = error
                    retries += 1
                    print("AddRosterEntryView: Save retry \(retries)/3: \(error)")
                    if retries < 3 {
                        try? await Task.sleep(nanoseconds: UInt64(500_000_000 * retries))
                    }
                }
            }
            await MainActor.run {
                errorMessage = "Failed to save after 3 attempts: \(lastError?.localizedDescription ?? "Unknown error")"
                showingErrorAlert = true
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
            let keyWindow = UIApplication.shared.connectedScenes
                .filter { $0.activationState == .foregroundActive }
                .compactMap { $0 as? UIWindowScene }
                .first?.windows
                .filter { $0.isKeyWindow }.first
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
            shootID: UUID(),
            organizationId: "",
            existingEntry: nil,
            onComplete: { _ in }
        )
    }
}
