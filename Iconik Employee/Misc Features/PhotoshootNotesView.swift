import SwiftUI

struct PhotoshootNotesView: View {
    // Store an array of photoshoot notes as JSON in AppStorage.
    @AppStorage("photoshootNotes") private var storedNotesData: Data = Data()
    @State private var notes: [PhotoshootNote] = []
    @State private var selectedNote: PhotoshootNote? = nil
    
    // School options loaded from Supabase
    @State private var schoolOptions: [SchoolItem] = []
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""
    @State private var isInitialLoad = true
    
    // For automatically setting the school based on schedule
    @State private var todaySessions: [Session] = []
    @State private var isLoadingSchedule: Bool = false
    @State private var scheduleError: String = ""
    @State private var showSchoolSelectionDialog = false
    @State private var showDeleteNoteConfirmation = false
    @State private var pendingNote: PhotoshootNote? = nil
    
    // User's stored information
    @AppStorage("userFirstName") var storedUserFirstName: String = ""
    @AppStorage("userLastName") var storedUserLastName: String = ""
    @AppStorage("userOrganizationID") private var organizationID: String = ""
    @AppStorage("userID") private var userID: String = ""
    
    // Photo management
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var tempImage: UIImage? = nil
    @State private var isUploadingImage = false

    // Submit and sync management
    @State private var isSubmitting = false
    @State private var showSubmitSuccess = false

    // Submitted notes from server
    @State private var submittedNotes: [PhotoshootNote] = []
    @State private var isLoadingSubmittedNotes = false
    @State private var showSubmittedNotes = false

    // Session service for Supabase operations
    private let sessionService = SessionService.shared
    private let subscriptionId = UUID()

    // Organization service to check feature flags
    @ObservedObject private var organizationService = OrganizationService.shared

    // A simple date/time formatter for the list display.
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }

    // Helper to get selected school for a note
    private func getSelectedSchool(for note: PhotoshootNote) -> SchoolItem {
        if let match = schoolOptions.first(where: { $0.name == note.school }) {
            return match
        }
        if let first = schoolOptions.first {
            print("⚠️ School '\(note.school)' not found in options, using first available: '\(first.name)'")
            return first
        }
        print("⚠️ No schools available for note, using fallback 'Unknown' school")
        return SchoolItem(id: "unknown", name: "Unknown", address: "", coordinates: nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with buttons - Keep at top, outside ScrollView
            VStack(spacing: 8) {
                HStack {
                    Text("Photoshoot Notes")
                        .font(.largeTitle)
                        .padding(.leading)
                    
                    Spacer()
                }
                
                // Top button row
                HStack {
                    Button(action: createNewNote) {
                        HStack {
                            Image(systemName: "plus")
                            Text("New...")
                        }
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    
                    if selectedNote != nil {
                        Button(action: { showDeleteNoteConfirmation = true }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete")
                            }
                            .padding()
                            .foregroundColor(.white)
                            .background(Color.red)
                            .cornerRadius(10)
                        }
                    }
                    
                    if !todaySessions.isEmpty {
                        Spacer()
                        Text("\(todaySessions.count) sessions today")
                            .padding(6)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(10)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            // Scrollable content
            ScrollView {
                VStack(spacing: 8) {
                
                // Note list
                if notes.isEmpty {
                    Text("No notes created yet")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(notes) { note in
                                Button(action: {
                                    selectedNote = note
                                }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(dateFormatter.string(from: note.timestamp))
                                            .font(.headline)
                                            .foregroundColor(.blue)
                                        Text(note.school)
                                            .font(.subheadline)
                                            .foregroundColor(.blue)
                                        Text(note.noteText.isEmpty ? "(No content)" : note.noteText)
                                            .lineLimit(1)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    .padding()
                                    .frame(width: 200, height: 80)
                                    .background(Color(.systemBackground))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.blue, lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 100)
                }
                
                if let note = selectedNote {
                    // School selector - Moved ABOVE the note content
                    VStack(alignment: .leading, spacing: 8) {
                        Text("School")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        if schoolOptions.isEmpty {
                            HStack {
                                Text("Loading schools...")
                                Spacer()
                                ProgressView()
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        } else {
                            Picker("", selection: Binding(
                                get: { getSelectedSchool(for: note) },
                                set: { newSchool in
                                    if let index = notes.firstIndex(of: note) {
                                        notes[index].school = newSchool.name
                                        selectedNote = notes[index]
                                        saveNotes()
                                    }
                                }
                            )) {
                                ForEach(schoolOptions, id: \.id) { school in
                                    Text(school.name).tag(school)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }
                    }
                    
                    // Note content editor - Now BELOW the school selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        TextEditor(text: Binding(
                            get: { note.noteText },
                            set: { newValue in
                                if let index = notes.firstIndex(of: note) {
                                    notes[index].noteText = newValue
                                    selectedNote = notes[index]
                                    saveNotes()
                                }
                            }
                        ))
                        .padding(4)
                        .background(Color(.systemBackground))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .frame(height: 150)
                        .padding(.horizontal)
                        
                        HStack {
                            Spacer()
                            Text("\(note.noteText.count) characters")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Photos section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Photos")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        HStack {
                            Button(action: {
                                showingCamera = true
                            }) {
                                HStack {
                                    Image(systemName: "camera")
                                    Text("Camera")
                                }
                                .padding()
                                .foregroundColor(.white)
                                .background(Color.blue)
                                .cornerRadius(8)
                            }
                            .sheet(isPresented: $showingCamera) {
                                ImagePicker(selectedImage: $tempImage, sourceType: .camera)
                                    .onDisappear {
                                        if let image = tempImage {
                                            uploadImage(image: image, for: note)
                                            tempImage = nil
                                        }
                                    }
                            }
                            
                            Button(action: {
                                showingImagePicker = true
                            }) {
                                HStack {
                                    Image(systemName: "photo.on.rectangle")
                                    Text("Library")
                                }
                                .padding()
                                .foregroundColor(.white)
                                .background(Color.green)
                                .cornerRadius(8)
                            }
                            .sheet(isPresented: $showingImagePicker) {
                                ImagePicker(selectedImage: $tempImage, sourceType: .photoLibrary)
                                    .onDisappear {
                                        if let image = tempImage {
                                            uploadImage(image: image, for: note)
                                            tempImage = nil
                                        }
                                    }
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        
                        // Photo display
                        if note.photoURLs.isEmpty {
                            Text("No photos added")
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .padding(.horizontal)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(note.photoURLs, id: \.self) { urlString in
                                        VStack {
                                            ZStack(alignment: .topTrailing) {
                                                AsyncImage(url: URL(string: urlString)) { phase in
                                                    switch phase {
                                                    case .empty:
                                                        ProgressView()
                                                            .frame(width: 100, height: 100)
                                                    case .success(let image):
                                                        image
                                                            .resizable()
                                                            .scaledToFill()
                                                            .frame(width: 100, height: 100)
                                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    case .failure:
                                                        Image(systemName: "photo")
                                                            .frame(width: 100, height: 100)
                                                            .background(Color.gray.opacity(0.2))
                                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    @unknown default:
                                                        EmptyView()
                                                    }
                                                }
                                                
                                                Button(action: {
                                                    deletePhoto(urlString: urlString, from: note)
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.red)
                                                        .background(Circle().fill(Color.white))
                                                }
                                                .padding(4)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .frame(height: 120)
                        }
                        
                        if isUploadingImage {
                            HStack {
                                ProgressView()
                                Text("Uploading photo...")
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Sync Status and Submit Button
                    VStack(spacing: 16) {
                        // Sync status indicator
                        HStack(spacing: 8) {
                            Circle()
                                .fill(note.syncedToServer ? Color.green : Color.orange)
                                .frame(width: 10, height: 10)

                            if note.syncedToServer {
                                if note.status == .submitted {
                                    Text("Submitted")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    if let submittedDate = note.submittedAt {
                                        Text("• \(formatRelativeDate(submittedDate))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Text("Synced to server")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("Local only (not synced)")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }

                            Spacer()
                        }
                        .padding(.horizontal)

                        // Submit button - Only show if organization has photoshoot notes enabled
                        if organizationService.usePhotoshootNotesOnly {
                            if note.status == .draft {
                                Button(action: {
                                    submitNote(note)
                                }) {
                                    HStack {
                                        if isSubmitting {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            Text("Submitting...")
                                        } else {
                                            Image(systemName: "checkmark.circle.fill")
                                            Text("Submit Note")
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .foregroundColor(.white)
                                    .background(note.school.isEmpty || note.noteText.isEmpty ? Color.gray : Color.green)
                                    .cornerRadius(10)
                                }
                                .disabled(note.school.isEmpty || note.noteText.isEmpty || isSubmitting)
                                .padding(.horizontal)
                            } else {
                                HStack {
                                    Image(systemName: "lock.fill")
                                    Text("Note submitted (read-only)")
                                        .font(.callout)
                                }
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                                .padding(.horizontal)
                            }
                        }

                        if showSubmitSuccess {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Note submitted successfully!")
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(8)
                            .padding(.horizontal)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.top, 8)
                } else {
                    Spacer()
                    Text("Select a note to edit or create a new one")
                        .foregroundColor(.gray)
                        .padding()
                    Spacer()
                }
                
                // Show error/success messages
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
                
                if !successMessage.isEmpty {
                    Text(successMessage)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.green.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }

                // Submitted Notes Section
                if organizationService.usePhotoshootNotesOnly {
                    VStack(alignment: .leading, spacing: 12) {
                        // Section Header with Toggle
                        Button(action: {
                            if !showSubmittedNotes {
                                loadSubmittedNotes()
                            }
                            withAnimation {
                                showSubmittedNotes.toggle()
                            }
                        }) {
                            HStack {
                                Image(systemName: showSubmittedNotes ? "chevron.down" : "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text("Submitted Notes")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                if isLoadingSubmittedNotes {
                                    ProgressView()
                                } else if !submittedNotes.isEmpty {
                                    Text("\(submittedNotes.count)")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)

                        // Submitted Notes List
                        if showSubmittedNotes {
                            if isLoadingSubmittedNotes {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Text("Loading submitted notes...")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding()
                            } else if submittedNotes.isEmpty {
                                Text("No submitted notes found")
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding()
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(submittedNotes) { submittedNote in
                                        VStack(alignment: .leading, spacing: 8) {
                                            // Header
                                            HStack {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(submittedNote.school)
                                                        .font(.headline)
                                                    Text(dateFormatter.string(from: submittedNote.timestamp))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }

                                                Spacer()

                                                if let submittedAt = submittedNote.submittedAt {
                                                    VStack(alignment: .trailing, spacing: 4) {
                                                        Text("Submitted")
                                                            .font(.caption)
                                                            .foregroundColor(.green)
                                                        Text(formatRelativeDate(submittedAt))
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                            }

                                            // Note content
                                            Text(submittedNote.noteText)
                                                .font(.body)
                                                .foregroundColor(.primary)
                                                .padding(.vertical, 4)

                                            // Photos
                                            if !submittedNote.photoURLs.isEmpty {
                                                ScrollView(.horizontal, showsIndicators: false) {
                                                    HStack(spacing: 8) {
                                                        ForEach(submittedNote.photoURLs, id: \.self) { urlString in
                                                            AsyncImage(url: URL(string: urlString)) { phase in
                                                                switch phase {
                                                                case .empty:
                                                                    ProgressView()
                                                                        .frame(width: 80, height: 80)
                                                                case .success(let image):
                                                                    image
                                                                        .resizable()
                                                                        .scaledToFill()
                                                                        .frame(width: 80, height: 80)
                                                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                                                case .failure:
                                                                    Image(systemName: "photo")
                                                                        .frame(width: 80, height: 80)
                                                                        .background(Color.gray.opacity(0.2))
                                                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                                                @unknown default:
                                                                    EmptyView()
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                                .frame(height: 90)
                                            }
                                        }
                                        .padding()
                                        .background(Color(.systemBackground))
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.green.opacity(0.3), lineWidth: 2)
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.top, 20)
                }

                    Spacer()
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .navigationBarTitle("", displayMode: .inline)
        .onAppear {
            loadNotes()
            loadSchoolOptions()
            loadScheduleForToday()

            // Start listening to organization settings
            if !organizationID.isEmpty {
                organizationService.startListeningToOrganization(organizationID: organizationID)
            }
        }
        .onDisappear {
            sessionService.stopListeningToSessions(subscriptionId: subscriptionId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            // Re-subscribe when app returns to foreground
            loadScheduleForToday()
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: $showDeleteNoteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Note", role: .destructive) { deleteSelectedNote() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes the note and any attached photos. This can't be undone.")
        }
        .confirmationDialog(
            "Select School for Note",
            isPresented: $showSchoolSelectionDialog,
            titleVisibility: .visible
        ) {
            ForEach(todaySessions.sorted(by: { (a, b) -> Bool in
                guard let aStart = a.startDate, let bStart = b.startDate else { return false }
                return aStart < bStart
            }), id: \.id) { session in
                Button(action: {
                    selectSchoolFromSession(session, for: pendingNote)
                }) {
                    Text(formatSessionOption(session))
                }
            }
            Button("Cancel", role: .cancel) {
                pendingNote = nil
            }
        } message: {
            Text("You have multiple photoshoots today. Which school would you like to use for this note?")
        }
    }
    
    // MARK: - Custom UIImagePicker
    
    struct ImagePicker: UIViewControllerRepresentable {
        @Environment(\.presentationMode) private var presentationMode
        @Binding var selectedImage: UIImage?
        let sourceType: UIImagePickerController.SourceType
        
        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = sourceType
            picker.delegate = context.coordinator
            return picker
        }
        
        func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
        
        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }
        
        class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
            let parent: ImagePicker
            
            init(_ parent: ImagePicker) {
                self.parent = parent
            }
            
            func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
                if let uiImage = info[.originalImage] as? UIImage {
                    parent.selectedImage = uiImage
                }
                parent.presentationMode.wrappedValue.dismiss()
            }
            
            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                parent.presentationMode.wrappedValue.dismiss()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createNewNote() {
        let newNote = PhotoshootNote(
            id: UUID(),
            timestamp: Date(),
            school: "",
            noteText: "",
            photoURLs: [],
            status: .draft,
            submittedAt: nil,
            dailyReportId: nil,
            syncedToServer: false,
            lastSyncedAt: nil,
            photographerName: "\(storedUserFirstName) \(storedUserLastName)".trimmingCharacters(in: .whitespaces),
            photographerID: userID,
            shootType: "photoshoot"
        )
        notes.append(newNote)
        selectedNote = newNote

        // Try to set school from today's schedule
        setSchoolFromSchedule(for: newNote)

        saveNotes()
        successMessage = "New note created"

        // Clear success message after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            successMessage = ""
        }
    }
    
    private func deleteSelectedNote() {
        if let note = selectedNote, let index = notes.firstIndex(of: note) {
            // First delete any photos from storage
            for urlString in note.photoURLs {
                deletePhotoFromStorage(urlString: urlString)
            }
            
            notes.remove(at: index)
            selectedNote = nil
            saveNotes()
            successMessage = "Note deleted"
            
            // Clear success message after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                successMessage = ""
            }
        }
    }
    
    private func uploadImage(image: UIImage, for note: PhotoshootNote) {
        guard let imageData = image.downsampledJPEGData(maxDimension: 2048, quality: 0.8) else {
            errorMessage = "Could not compress image"
            return
        }

        // Get organization ID
        let orgID = UserDefaults.standard.string(forKey: "userOrganizationID") ?? ""
        guard !orgID.isEmpty else {
            errorMessage = "Cannot upload photo: no organization ID found"
            return
        }

        isUploadingImage = true

        Task {
            let supabase = SupabaseManager.shared.client

            // Create unique file path: photoshoot-notes/orgId/noteId/photoId.jpg
            let fileName = "photoshoot-notes/\(orgID)/\(note.id.uuidString)/\(UUID().uuidString).jpg"
            print("📸 Uploading photo to path: \(fileName)")

            do {
                // Upload to Supabase Storage bucket "daily-reports" (shared with DailyJobReportView)
                _ = try await supabase.storage
                    .from("daily-reports")
                    .upload(path: fileName, file: imageData)

                print("📸 Upload complete, getting signed URL...")

                // Get a signed URL for the uploaded file (valid for 1 year)
                let signedURL = try await supabase.storage
                    .from("daily-reports")
                    .createSignedURL(path: fileName, expiresIn: 31536000) // 1 year in seconds

                print("✅ Photo uploaded successfully: \(signedURL.absoluteString.prefix(80))...")

                await MainActor.run {
                    self.isUploadingImage = false

                    // Update the note with the new photo URL
                    if let index = self.notes.firstIndex(where: { $0.id == note.id }) {
                        var updatedNote = self.notes[index]
                        updatedNote.photoURLs.append(signedURL.absoluteString)
                        self.notes[index] = updatedNote
                        self.selectedNote = updatedNote
                        self.saveNotes()
                        self.successMessage = "Photo added successfully"

                        // Clear success message after delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.successMessage = ""
                        }
                    }
                }

            } catch {
                print("❌ Supabase Storage upload failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.isUploadingImage = false
                    self.errorMessage = "Error uploading photo: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func deletePhoto(urlString: String, from note: PhotoshootNote) {
        // Try to delete from Supabase Storage
        deletePhotoFromStorage(urlString: urlString)

        // Remove URL from note
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            var updatedNote = notes[index]
            updatedNote.photoURLs.removeAll { $0 == urlString }
            notes[index] = updatedNote
            selectedNote = updatedNote
            saveNotes()
            successMessage = "Photo removed"

            // Clear success message after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                successMessage = ""
            }
        }
    }

    private func deletePhotoFromStorage(urlString: String) {
        // Check if this is a Supabase Storage URL
        guard urlString.contains("supabase") else {
            // Old URL - can't delete, just log
            print("⚠️ Cannot delete legacy photo: \(urlString.prefix(50))...")
            return
        }

        // Extract path from Supabase signed URL
        // URL format: https://xxx.supabase.co/storage/v1/object/sign/daily-reports/photoshoot-notes/orgId/noteId/photoId.jpg?token=xxx
        guard let url = URL(string: urlString),
              let pathIndex = url.pathComponents.firstIndex(of: "daily-reports"),
              pathIndex + 1 < url.pathComponents.count else {
            print("❌ Could not extract path from Supabase URL")
            return
        }

        // Build the path after the bucket name (includes photoshoot-notes/ prefix)
        let pathComponents = url.pathComponents[(pathIndex + 1)...]
        let filePath = pathComponents.joined(separator: "/")

        print("🗑️ Deleting photo from Supabase Storage: \(filePath)")

        Task {
            do {
                let supabase = SupabaseManager.shared.client
                try await supabase.storage
                    .from("daily-reports")
                    .remove(paths: [filePath])
                print("✅ Photo successfully deleted from Supabase Storage")
            } catch {
                print("❌ Error deleting photo from storage: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Data Loading and Persistence
    
    private func loadNotes() {
        if let decoded = try? JSONDecoder().decode([PhotoshootNote].self, from: storedNotesData) {
            notes = decoded
            if !notes.isEmpty && selectedNote == nil {
                selectedNote = notes.first
            }
        } else {
            notes = []
        }
    }
    
    private func saveNotes() {
        if let encoded = try? JSONEncoder().encode(notes) {
            storedNotesData = encoded
        }
    }
    
    private func loadSchoolOptions() {
        // Get organization ID
        let orgID = UserDefaults.standard.string(forKey: "userOrganizationID") ?? ""
        guard !orgID.isEmpty else {
            print("🔐 Cannot load schools: no organization ID found")
            return
        }

        Task {
            do {
                let schools = try await SchoolService.shared.getSchools(organizationID: orgID)

                // Convert School to SchoolItem for the picker
                let items = schools.map { school in
                    SchoolItem(
                        id: school.id,
                        name: school.name,
                        address: school.address ?? "",
                        coordinates: school.coordinates
                    )
                }

                await MainActor.run {
                    self.schoolOptions = items

                    // Try to set school from schedule when we have options loaded
                    if let note = self.selectedNote, note.school.isEmpty {
                        self.setSchoolFromSchedule(for: note)
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Error loading schools: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Schedule Integration
    
    private func loadScheduleForToday() {
        isLoadingSchedule = true
        scheduleError = ""
        todaySessions = []

        // Create date range for today
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // Get current user ID for filtering
        guard let currentUserID = UserManager.shared.getCurrentUserID() else {
            print("🔐 Cannot filter sessions: no current user ID")
            self.isLoadingSchedule = false
            return
        }

        // Get current user email for fallback matching
        let currentUserEmail = UserDefaults.standard.string(forKey: "userEmail")

        let organizationID = UserDefaults.standard.string(forKey: "userOrganizationID") ?? ""
        guard !organizationID.isEmpty else {
            print("❌ Cannot load sessions: no organization ID")
            self.isLoadingSchedule = false
            return
        }

        // Load sessions from Supabase with real-time updates
        sessionService.startListeningToSessions(
            subscriptionId: subscriptionId,
            organizationID: organizationID,
            includeUnpublished: false  // Regular users see only published
        ) { sessions in
            DispatchQueue.main.async {

                // Filter sessions for today where current user is assigned
                let sessionsForToday = sessions.filter { session in
                    guard let sessionDate = session.startDate else { return false }
                    let isToday = sessionDate >= startOfDay && sessionDate < endOfDay
                    let isUserAssigned = session.isUserAssigned(userID: currentUserID, userEmail: currentUserEmail)
                    return isToday && isUserAssigned
                }

                self.todaySessions = sessionsForToday
                self.isLoadingSchedule = false

                // Try to set school for selected note based on today's schedule
                if let note = self.selectedNote, note.school.isEmpty {
                    self.setSchoolFromSchedule(for: note)
                }
            }
        }
    }
    
    // Try to set school for a note based on today's schedule
    private func setSchoolFromSchedule(for note: PhotoshootNote) {
        // No sessions or no school options yet
        if todaySessions.isEmpty || schoolOptions.isEmpty {
            return
        }
        
        // If there's only one session, auto-select it
        if todaySessions.count == 1 {
            if let session = todaySessions.first,
               let matchIndex = schoolOptions.firstIndex(where: { $0.name == session.schoolName }) {
                // Found a match - update the note
                if let index = notes.firstIndex(where: { $0.id == note.id }) {
                    notes[index].school = schoolOptions[matchIndex].name
                    selectedNote = notes[index]
                    saveNotes()
                    
                    successMessage = "Auto-selected school from your schedule"
                    
                    // Clear success message after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.successMessage = ""
                    }
                }
            }
        } else {
            // Multiple sessions - show selection dialog
            pendingNote = note
            showSchoolSelectionDialog = true
        }
    }
    
    // Select a specific school from a session
    private func selectSchoolFromSession(_ session: Session, for note: PhotoshootNote?) {
        guard let note = note else { return }
        
        if let matchIndex = schoolOptions.firstIndex(where: { $0.name == session.schoolName }) {
            // Found a match - update the note
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index].school = schoolOptions[matchIndex].name
                selectedNote = notes[index]
                saveNotes()
                
                successMessage = "Selected \(session.schoolName) for this note"
                
                // Clear success message after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.successMessage = ""
                }
            }
        }
        pendingNote = nil
    }
    
    // Format session for display in selection dialog
    private func formatSessionOption(_ session: Session) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short

        if let startDate = session.startDate {
            return "\(session.schoolName) - \(timeFormatter.string(from: startDate))"
        } else {
            return session.schoolName
        }
    }

    // MARK: - Submit Note

    private func submitNote(_ note: PhotoshootNote) {
        guard !isSubmitting else { return }

        // Validate required fields
        guard !note.school.isEmpty else {
            errorMessage = "Please select a school before submitting"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                errorMessage = ""
            }
            return
        }

        guard !note.noteText.isEmpty else {
            errorMessage = "Please add some notes before submitting"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                errorMessage = ""
            }
            return
        }

        isSubmitting = true
        errorMessage = ""

        Task {
            do {
                // Get user info
                let photographerName = "\(storedUserFirstName) \(storedUserLastName)".trimmingCharacters(in: .whitespaces)

                // Update note with user info before submitting
                var noteToSubmit = note
                noteToSubmit.photographerName = photographerName.isEmpty ? "Unknown" : photographerName
                noteToSubmit.photographerID = userID
                noteToSubmit.shootType = "photoshoot" // Default type

                // Submit to Supabase
                let submittedNote = try await PhotoshootNoteService.shared.submitNote(
                    noteToSubmit,
                    organizationID: organizationID
                )

                // Remove from local storage since it's now on the server
                await MainActor.run {
                    // Remove the note from local storage
                    notes.removeAll { $0.id == note.id }
                    saveNotes()

                    // Clear selection to close detail view
                    selectedNote = nil

                    isSubmitting = false
                    showSubmitSuccess = true

                    // Hide success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showSubmitSuccess = false
                    }

                    print("✅ Note submitted successfully and removed from local storage: \(submittedNote.id)")
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Failed to submit note: \(error.localizedDescription)"

                    // Clear error after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        errorMessage = ""
                    }

                    print("❌ Failed to submit note: \(error)")
                }
            }
        }
    }

    // Format relative date for display
    private func formatRelativeDate(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }

    // MARK: - Load Submitted Notes from Server

    private func loadSubmittedNotes() {
        guard !isLoadingSubmittedNotes else { return }

        isLoadingSubmittedNotes = true

        Task {
            do {
                // Get date range for last 30 days
                let calendar = Calendar.current
                let endDate = Date()
                guard let startDate = calendar.date(byAdding: .day, value: -30, to: endDate) else {
                    throw PhotoshootNoteError.fetchFailed("Failed to calculate date range")
                }

                // Fetch notes from server
                let fetchedNotes = try await PhotoshootNoteService.shared.fetchNotes(
                    photographerID: userID,
                    startDate: startDate,
                    endDate: endDate
                )

                // Filter for submitted notes only
                let submitted = fetchedNotes.filter { $0.status == .submitted }

                await MainActor.run {
                    submittedNotes = submitted
                    isLoadingSubmittedNotes = false
                    print("✅ Loaded \(submitted.count) submitted notes from server")
                }
            } catch {
                await MainActor.run {
                    isLoadingSubmittedNotes = false
                    errorMessage = "Failed to load submitted notes: \(error.localizedDescription)"

                    // Clear error after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        errorMessage = ""
                    }

                    print("❌ Failed to load submitted notes: \(error)")
                }
            }
        }
    }
}
