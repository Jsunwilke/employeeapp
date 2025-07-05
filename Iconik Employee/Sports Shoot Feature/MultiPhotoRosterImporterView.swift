import SwiftUI
import UIKit
import Firebase
import FirebaseFirestore

// Main view for handling multi-photo roster import
struct MultiPhotoRosterImporterView: View {
    let shootID: String
    let onComplete: (Bool) -> Void
    
    // State for managing photos and processing
    @State private var capturedImages: [UIImage] = []
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var isProcessing = false
    @State private var currentlyProcessingIndex: Int? = nil
    @State private var extractedRostersByImage: [Int: [RosterEntry]] = [:]
    @State private var allExtractedRosters: [RosterEntry] = []
    @State private var showPreview = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var processingProgress: Double = 0
    @State private var teamLabels: [Int: String] = [:]
    
    // Environment objects
    @Environment(\.presentationMode) var presentationMode
    
    // Testing mode flag
    private let useClaudeMock = false  // Set to false for production
    
    var body: some View {
        NavigationView {
            VStack {
                if showPreview {
                    rosterPreviewView
                } else if isProcessing {
                    processingView
                } else {
                    photoCollectionView
                }
            }
            .navigationBarTitle("Import Paper Rosters", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                if !isProcessing && !showPreview && !capturedImages.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Process All") {
                            processAllImages()
                        }
                        .disabled(capturedImages.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                ImagePicker(
                    sourceType: .camera,
                    selectedImage: Binding(
                        get: { nil },
                        set: { if let image = $0 { addImage(image) } }
                    ),
                    completionHandler: { _ in
                        showCamera = false
                    }
                )
            }
            .sheet(isPresented: $showPhotoLibrary) {
                ImagePicker(
                    sourceType: .photoLibrary,
                    selectedImage: Binding(
                        get: { nil },
                        set: { if let image = $0 { addImage(image) } }
                    ),
                    completionHandler: { _ in
                        showPhotoLibrary = false
                    }
                )
            }
            .alert(isPresented: $showingErrorAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    // MARK: - Photo Collection View
    
    private var photoCollectionView: some View {
        VStack {
            if capturedImages.isEmpty {
                // Initial empty state
                emptyStateView
            } else {
                // Image grid when we have photos
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                        ForEach(0..<capturedImages.count, id: \.self) { index in
                            imageCell(image: capturedImages[index], index: index)
                        }
                    }
                    .padding()
                }
            }
            
            // Bottom buttons for adding photos
            VStack(spacing: 15) {
                Button(action: {
                    showCamera = true
                }) {
                    HStack {
                        Image(systemName: "camera")
                            .font(.title3)
                        Text("Take Photo")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                Button(action: {
                    showPhotoLibrary = true
                }) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title3)
                        Text("Choose from Library")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.secondary.opacity(0.15))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 30) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 70))
                .foregroundColor(.blue)
            
            Text("Import Multiple Team Rosters")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Take photos of paper rosters or select images from your gallery. You can add multiple photos for different teams.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .foregroundColor(.secondary)
            
            Spacer()
            
            VStack {
                Text("Tips for best results:")
                    .font(.headline)
                    .padding(.bottom, 5)
                
                VStack(alignment: .leading, spacing: 8) {
                    bulletPoint("One team roster per photo")
                    bulletPoint("Make sure the paper roster is well-lit and flat")
                    bulletPoint("Capture the entire document in the frame")
                    bulletPoint("Hold the camera steady and avoid shadows")
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(10)
            .padding()
            
            Spacer()
        }
        .padding()
    }
    
    private func imageCell(image: UIImage, index: Int) -> some View {
        VStack {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .clipped()
                    .cornerRadius(8)
                    .shadow(radius: 3)
                
                // Delete button
                Button(action: {
                    deleteImage(at: index)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.7)))
                }
                .padding(8)
            }
            
            // Team label input field
            TextField("Team Name", text: Binding(
                get: { teamLabels[index] ?? "" },
                set: { teamLabels[index] = $0 }
            ))
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(5)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            
            // Process single image button
            Button(action: {
                processSingleImage(index: index)
            }) {
                Text("Process")
                    .fontWeight(.medium)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Processing View
    
    private var processingView: some View {
        VStack(spacing: 20) {
            // Processing indicator
            if let index = currentlyProcessingIndex {
                Text("Processing Roster \(index + 1) of \(capturedImages.count)")
                    .font(.headline)
                
                // Show the current image being processed
                if index < capturedImages.count {
                    Image(uiImage: capturedImages[index])
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                        .cornerRadius(8)
                }
            }
            
            ProgressView(value: processingProgress)
                .progressViewStyle(LinearProgressViewStyle())
                .padding(.horizontal)
            
            ProgressView()
                .scaleEffect(1.5)
                .padding()
            
            Text("Using Claude 3.7 Sonnet to read and process rosters...")
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
            
            Text("This may take a few moments. We're analyzing each roster to extract athlete information.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Preview View
    
    private var rosterPreviewView: some View {
        VStack {
            if allExtractedRosters.isEmpty {
                noResultsView
            } else {
                VStack {
                    Text("Extracted \(allExtractedRosters.count) Athletes")
                        .font(.headline)
                        .padding(.top)
                    
                    List {
                        ForEach(Array(extractedRostersByImage.keys).sorted(), id: \.self) { imageIndex in
                            if let entries = extractedRostersByImage[imageIndex], !entries.isEmpty {
                                Section(header: Text(teamLabels[imageIndex] ?? "Roster \(imageIndex + 1)")) {
                                    ForEach(entries) { entry in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(entry.lastName), \(entry.firstName)")
                                                .font(.headline)
                                            
                                            if !entry.group.isEmpty {
                                                Text("Sport/Team: \(entry.group)")
                                                    .font(.caption)
                                            }
                                            
                                            if !entry.teacher.isEmpty {
                                                Text("Special: \(entry.teacher)")
                                                    .font(.caption)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    
                    VStack(spacing: 15) {
                        Button(action: {
                            saveAllImportedRosters()
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                    .font(.title3)
                                Text("Import All Rosters")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        
                        Button(action: {
                            // Reset to photo collection view
                            showPreview = false
                            allExtractedRosters = []
                            extractedRostersByImage = [:]
                        }) {
                            Text("Edit Photos")
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    private var noResultsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("No Data Detected")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("We couldn't extract any roster data from these images. Please try again with clearer images.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Button(action: {
                showPreview = false
            }) {
                Text("Try Again")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.top)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Helper Views
    
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body)
                .foregroundColor(.blue)
            Text(text)
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    // MARK: - Image Processing Methods
    
    private func addImage(_ image: UIImage) {
        capturedImages.append(image)
        teamLabels[capturedImages.count - 1] = ""
    }
    
    private func deleteImage(at index: Int) {
        guard index < capturedImages.count else { return }
        capturedImages.remove(at: index)
        teamLabels.removeValue(forKey: index)
        
        // Reindex team labels
        var newTeamLabels: [Int: String] = [:]
        for (idx, (_, label)) in teamLabels.enumerated() {
            newTeamLabels[idx] = label
        }
        teamLabels = newTeamLabels
        
        // Remove any extracted data for this image
        extractedRostersByImage.removeValue(forKey: index)
    }
    
    private func processSingleImage(index: Int) {
        guard index < capturedImages.count else { return }
        
        isProcessing = true
        currentlyProcessingIndex = index
        processingProgress = 0
        
        let image = capturedImages[index]
        
        if useClaudeMock {
            // Use mock for testing
            ClaudeRosterService.shared.mockExtractRoster { result in
                DispatchQueue.main.async {
                    self.handleProcessingResult(result, for: index)
                    self.isProcessing = false
                    self.showPreview = true
                }
            }
        } else {
            // Use Claude API
            ClaudeRosterService.shared.extractRosterFromImage(image) { result in
                DispatchQueue.main.async {
                    self.handleProcessingResult(result, for: index)
                    self.isProcessing = false
                    self.showPreview = true
                }
            }
        }
    }
    
    private func processAllImages() {
        guard !capturedImages.isEmpty else { return }
        
        isProcessing = true
        currentlyProcessingIndex = 0
        processingProgress = 0
        
        // Clear previous results
        extractedRostersByImage = [:]
        allExtractedRosters = []
        
        processNextImage(startingAt: 0)
    }
    
    private func processNextImage(startingAt index: Int) {
        guard index < capturedImages.count else {
            // All images processed, show preview
            currentlyProcessingIndex = nil
            isProcessing = false
            showPreview = true
            return
        }
        
        currentlyProcessingIndex = index
        processingProgress = Double(index) / Double(capturedImages.count)
        
        let image = capturedImages[index]
        
        if useClaudeMock {
            // Use mock for testing
            ClaudeRosterService.shared.mockExtractRoster { result in
                DispatchQueue.main.async {
                    self.handleProcessingResult(result, for: index)
                    self.processNextImage(startingAt: index + 1)
                }
            }
        } else {
            // Use Claude API
            ClaudeRosterService.shared.extractRosterFromImage(image) { result in
                DispatchQueue.main.async {
                    self.handleProcessingResult(result, for: index)
                    self.processNextImage(startingAt: index + 1)
                }
            }
        }
    }
    
    private func handleProcessingResult(_ result: Result<[RosterEntry], Error>, for index: Int) {
        switch result {
        case .success(var entries):
            // If team name was provided, set it for all entries
            if let teamName = teamLabels[index], !teamName.isEmpty {
                entries = entries.map { entry in
                    var updatedEntry = entry
                    // Only override group if it's empty or if the team name was manually specified
                    if entry.group.isEmpty || !teamName.isEmpty {
                        updatedEntry.group = teamName
                    }
                    return updatedEntry
                }
            }
            
            // Store the results
            extractedRostersByImage[index] = entries
            
            // Add to the complete list
            allExtractedRosters.append(contentsOf: entries)
            
        case .failure(let error):
            print("Error processing image \(index): \(error.localizedDescription)")
            extractedRostersByImage[index] = []
            
            // Show error but continue processing other images
            errorMessage = "Error processing image \(index + 1): \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
    
    private func saveAllImportedRosters() {
        guard !allExtractedRosters.isEmpty else { return }
        
        isProcessing = true
        
        // Use a dispatch group to track all operations
        let group = DispatchGroup()
        var errorOccurred = false
        
        // Add each entry to the sports shoot
        for entry in allExtractedRosters {
            group.enter()
            
            SportsShootService.shared.addRosterEntry(shootID: shootID, entry: entry) { result in
                switch result {
                case .success:
                    // Entry added successfully
                    break
                case .failure:
                    errorOccurred = true
                }
                
                group.leave()
            }
        }
        
        // When all operations are complete
        group.notify(queue: .main) {
            self.isProcessing = false
            
            if errorOccurred {
                self.errorMessage = "Some entries could not be added. Please try again."
                self.showingErrorAlert = true
            } else {
                // Notify completion and dismiss
                self.onComplete(true)
                self.presentationMode.wrappedValue.dismiss()
            }
        }
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    let completionHandler: (Result<UIImage, Error>) -> Void
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
                parent.completionHandler(.success(image))
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            parent.completionHandler(.failure(NSError(domain: "ImagePicker", code: 0, userInfo: [NSLocalizedDescriptionKey: "User cancelled"])))
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // Nothing to update
    }
}

// MARK: - Preview Provider

struct MultiPhotoRosterImporterView_Previews: PreviewProvider {
    static var previews: some View {
        MultiPhotoRosterImporterView(
            shootID: "previewID",
            onComplete: { _ in }
        )
    }
}