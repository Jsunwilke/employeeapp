import SwiftUI
import Firebase
import FirebaseFirestore
import FirebaseStorage

struct PhotoshootNotesView: View {
    // Store an array of photoshoot notes as JSON in AppStorage.
    @AppStorage("photoshootNotes") private var storedNotesData: Data = Data()
    @State private var notes: [PhotoshootNote] = []
    @State private var selectedNote: PhotoshootNote? = nil
    
    // School options loaded from Firestore
    @State private var schoolOptions: [SchoolItem] = []
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""
    @State private var isInitialLoad = true
    
    // For automatically setting the school based on schedule
    @State private var todayEvents: [ICSEvent] = []
    @State private var isLoadingSchedule: Bool = false
    @State private var scheduleError: String = ""
    
    // User's stored information
    @AppStorage("userFirstName") var storedUserFirstName: String = ""
    @AppStorage("userLastName") var storedUserLastName: String = ""
    
    // Photo management
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var tempImage: UIImage? = nil
    @State private var isUploadingImage = false
    
    // Full ICS URL from Sling
    private let icsURL = "https://calendar.getsling.com/564097/18fffd515e88999522da2876933d36a9d9d83a7eeca9c07cd58890a8/Sling_Calendar_all.ics"

    // A simple date/time formatter for the list display.
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 8) {
                // Header with buttons
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
                        Button(action: deleteSelectedNote) {
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
                    
                    if !todayEvents.isEmpty {
                        Spacer()
                        Text("\(todayEvents.count) events today")
                            .padding(6)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(10)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                
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
                                get: {
                                    schoolOptions.first(where: { $0.name == note.school }) ?? schoolOptions.first!
                                },
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
                
                Spacer()
            }
            .navigationBarTitle("", displayMode: .inline)
            .onAppear {
                loadNotes()
                loadSchoolOptions()
                loadScheduleForToday()
            }
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
        let newNote = PhotoshootNote(id: UUID(), timestamp: Date(), school: "", noteText: "", photoURLs: [])
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
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "Could not compress image"
            return
        }
        
        isUploadingImage = true
        let storageRef = Storage.storage().reference()
        
        // Using the path that matches your Firebase rules
        let photoPath = "photoshootNotes/\(note.id.uuidString)/\(UUID().uuidString).jpg"
        let photoRef = storageRef.child(photoPath)
        
        photoRef.putData(imageData, metadata: nil) { metadata, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.isUploadingImage = false
                    self.errorMessage = "Error uploading photo: \(error.localizedDescription)"
                    print("Firebase storage error: \(error)")
                }
                return
            }
            
            photoRef.downloadURL { url, error in
                DispatchQueue.main.async {
                    self.isUploadingImage = false
                    
                    if let error = error {
                        self.errorMessage = "Error getting download URL: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let downloadURL = url else {
                        self.errorMessage = "Failed to get download URL"
                        return
                    }
                    
                    // Update the note with the new photo URL
                    if let index = self.notes.firstIndex(where: { $0.id == note.id }) {
                        var updatedNote = self.notes[index]
                        updatedNote.photoURLs.append(downloadURL.absoluteString)
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
            }
        }
    }
    
    private func deletePhoto(urlString: String, from note: PhotoshootNote) {
        // First try to delete from Firebase Storage
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
        if let url = URL(string: urlString),
           url.pathComponents.count > 1 {
            let storage = Storage.storage()
            // Create a reference directly from the URL string
            let storageRef = storage.reference(forURL: urlString)
            
            storageRef.delete { error in
                if let error = error {
                    print("Error deleting photo from storage: \(error.localizedDescription)")
                } else {
                    print("Photo successfully deleted from storage")
                }
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
        let db = Firestore.firestore()
        db.collection("dropdownData")
            .whereField("type", isEqualTo: "school")
            .getDocuments { snapshot, error in
                if let error = error {
                    errorMessage = error.localizedDescription
                    return
                }
                guard let docs = snapshot?.documents else { return }
                var temp: [SchoolItem] = []
                for doc in docs {
                    let data = doc.data()
                    if let value = data["value"] as? String,
                       let address = data["schoolAddress"] as? String {
                        let item = SchoolItem(id: doc.documentID, name: value, address: address)
                        temp.append(item)
                    }
                }
                temp.sort { $0.name.lowercased() < $1.name.lowercased() }
                schoolOptions = temp
                
                // Try to set school from schedule when we have options loaded
                if let note = selectedNote, note.school.isEmpty {
                    setSchoolFromSchedule(for: note)
                }
            }
    }
    
    // MARK: - Schedule Integration
    
    private func loadScheduleForToday() {
        isLoadingSchedule = true
        scheduleError = ""
        todayEvents = []
        
        // Create date range for today
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // Load ICS file
        guard let url = URL(string: icsURL) else {
            scheduleError = "Invalid schedule URL."
            isLoadingSchedule = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.scheduleError = "Error loading schedule: \(error.localizedDescription)"
                    self.isLoadingSchedule = false
                }
                return
            }
            
            guard let data = data, let content = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    self.scheduleError = "Unable to load schedule data."
                    self.isLoadingSchedule = false
                }
                return
            }
            
            // Parse ICS
            let allEvents = ICSParser.parseICS(from: content)
            
            DispatchQueue.main.async {
                // Filter events for today and current user
                let userFullName = "\(self.storedUserFirstName) \(self.storedUserLastName)".trimmingCharacters(in: .whitespaces)
                let eventsForToday = allEvents.filter { event in
                    guard let eventDate = event.startDate else { return false }
                    let isToday = eventDate >= startOfDay && eventDate < endOfDay
                    let isUserEvent = event.employeeName.lowercased() == userFullName.lowercased()
                    return isToday && isUserEvent
                }
                
                self.todayEvents = eventsForToday
                self.isLoadingSchedule = false
                
                // Try to set school for selected note based on today's schedule
                if let note = self.selectedNote, note.school.isEmpty {
                    self.setSchoolFromSchedule(for: note)
                }
            }
        }.resume()
    }
    
    // Try to set school for a note based on today's schedule
    private func setSchoolFromSchedule(for note: PhotoshootNote) {
        // No events or no school options yet
        if todayEvents.isEmpty || schoolOptions.isEmpty {
            return
        }
        
        // Sort events by start time, so we get the earliest one first
        let sortedEvents = todayEvents.sorted { (a, b) -> Bool in
            guard let aStart = a.startDate, let bStart = b.startDate else { return false }
            return aStart < bStart
        }
        
        // Look for a matching school in our options for the first event
        if let firstEvent = sortedEvents.first,
           let matchIndex = schoolOptions.firstIndex(where: { $0.name == firstEvent.schoolName }) {
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
    }
}
