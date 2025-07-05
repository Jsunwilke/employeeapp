//
//  MultiPhotoRosterImporterView.swift
//  Iconik Employee
//
//  Updated to support sequential Subject IDs and fix UI layout
//

import SwiftUI
import UIKit
import Firebase
import FirebaseFirestore

struct MultiPhotoRosterImporterView: View {
    let shootID: String
    let onComplete: (Bool) -> Void
    
    // State for managing photos and processing
    @State private var capturedImages: [UIImage] = []
    @State private var showDocumentScanner = false
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
    @State private var selectedImage: UIImage? = nil
    @State private var nextSubjectID: Int = 101 // Default starting ID
    
    // Environment objects
    @Environment(\.presentationMode) var presentationMode
    
    // Testing mode flag
    private let useClaudeMock = false  // Set to false for production
    
    var body: some View {
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
        .sheet(isPresented: $showDocumentScanner) {
            DocumentScannerView(onScan: { scannedImages in
                for image in scannedImages {
                    addImage(image)
                }
            })
        }
        .sheet(isPresented: $showPhotoLibrary) {
            ImagePicker(selectedImage: $selectedImage)
                .onDisappear {
                    if let image = selectedImage {
                        addImage(image)
                        selectedImage = nil
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
            loadExistingRoster()
        }
    }
    
    // MARK: - Photo Collection View
    
    private var photoCollectionView: some View {
        VStack(spacing: 16) {
            if capturedImages.isEmpty {
                // Initial empty state when no images added
                emptyStateView
            } else {
                // Subject ID info at the top - now read-only
                HStack {
                    Text("Next athlete will be assigned ID: \(nextSubjectID)")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                
                // Image grid
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(0..<capturedImages.count, id: \.self) { index in
                            imageCell(image: capturedImages[index], index: index)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            // Bottom buttons for adding photos - always visible and at the bottom
            VStack(spacing: 12) {
                Button(action: {
                    showDocumentScanner = true
                }) {
                    HStack {
                        Image(systemName: "doc.viewfinder")
                            .font(.title3)
                        Text("Scan Roster")
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
            .padding(.bottom, 10)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            Text("Import Multiple Team Rosters")
                .font(.title2)
                .fontWeight(.bold)
                
            // Subject ID info - now read-only
            Text("Next athlete will be assigned ID: \(nextSubjectID)")
                .font(.headline)
                .foregroundColor(.blue)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            
            Text("Scan paper rosters or select images from your gallery.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            // Condensed tips
            VStack(alignment: .leading, spacing: 6) {
                Text("Tips for best results:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 4) {
                    bulletPoint("One team roster per scan")
                    bulletPoint("Make sure the entire roster is visible")
                    bulletPoint("Ensure good lighting for clear text")
                    bulletPoint("Hold the device steady during scanning")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .padding()
    }
    
    private func imageCell(image: UIImage, index: Int) -> some View {
        VStack {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .clipped()
                    .cornerRadius(8)
                    .shadow(radius: 2)
                
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
        VStack(spacing: 16) {
            // Processing indicator
            if let index = currentlyProcessingIndex {
                Text("Processing Roster \(index + 1) of \(capturedImages.count)")
                    .font(.headline)
                
                // Show the current image being processed
                if index < capturedImages.count {
                    Image(uiImage: capturedImages[index])
                        .resizable()
                        .scaledToFit()
                        .frame(height: 180)
                        .cornerRadius(8)
                }
            }
            
            ProgressView(value: processingProgress)
                .progressViewStyle(LinearProgressViewStyle())
                .padding(.horizontal)
            
            ProgressView()
                .scaleEffect(1.5)
                .padding()
            
            Text("Using Claude AI to read and process rosters...")
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
            
            Text("This may take a few moments. New athletes will be numbered starting from \(nextSubjectID).")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.horizontal)
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
                                            HStack {
                                                Text("\(entry.lastName)")
                                                    .font(.headline)
                                                
                                                Spacer()
                                                
                                                Text("ID: \(entry.firstName)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            if !entry.group.isEmpty {
                                                Text("Sport/Team: \(entry.group)")
                                                    .font(.caption)
                                            }
                                            
                                            if !entry.teacher.isEmpty {
                                                Text("Special: \(entry.teacher)")
                                                    .font(.caption)
                                            }
                                            
                                            if !entry.email.isEmpty {
                                                Text("Email: \(entry.email)")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
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
                .font(.system(size: 50))
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
        }
        .padding()
    }
    
    // MARK: - Helper Views
    
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(.body)
                .foregroundColor(.blue)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    // MARK: - Image Processing Methods
    
    // Load existing roster to determine next available Subject ID
    private func loadExistingRoster() {
        SportsShootService.shared.fetchSportsShoot(id: shootID) { result in
            switch result {
            case .success(let shoot):
                // Find the highest Subject ID value across all entries
                let highestID = shoot.roster.compactMap { entry -> Int? in
                    return Int(entry.firstName)
                }.max() ?? 100 // Default to 100 if no entries exist
                
                DispatchQueue.main.async {
                    self.nextSubjectID = highestID + 1
                    print("Next available Subject ID: \(self.nextSubjectID)")
                }
                
            case .failure(let error):
                print("Error loading sports shoot: \(error.localizedDescription)")
                // Keep the default starting ID if there's an error
            }
        }
    }
    
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
            // Use Claude API with the next available Subject ID
            ClaudeRosterService.shared.extractRosterFromImage(image, startingSubjectID: nextSubjectID) { result in
                DispatchQueue.main.async {
                    self.handleProcessingResult(result, for: index)
                    self.isProcessing = false
                    self.showPreview = true
                    
                    // Update nextSubjectID based on how many entries were added
                    if case .success(let entries) = result {
                        self.nextSubjectID += entries.count
                    }
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
        
        // Track the current subject ID as we process each image
        var currentSubjectID = nextSubjectID
        
        processNextImage(startingAt: 0, currentSubjectID: currentSubjectID)
    }
    
    private func processNextImage(startingAt index: Int, currentSubjectID: Int) {
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
                    
                    // Calculate next subject ID based on entries added
                    var nextID = currentSubjectID
                    if case .success(let entries) = result {
                        nextID += entries.count
                    }
                    
                    // Process next image with updated subject ID
                    self.processNextImage(startingAt: index + 1, currentSubjectID: nextID)
                }
            }
        } else {
            // Use Claude API with the current subject ID
            ClaudeRosterService.shared.extractRosterFromImage(image, startingSubjectID: currentSubjectID) { result in
                DispatchQueue.main.async {
                    self.handleProcessingResult(result, for: index)
                    
                    // Calculate next subject ID based on entries added
                    var nextID = currentSubjectID
                    if case .success(let entries) = result {
                        nextID += entries.count
                    }
                    
                    // Process next image with updated subject ID
                    self.processNextImage(startingAt: index + 1, currentSubjectID: nextID)
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

struct MultiPhotoRosterImporterView_Previews: PreviewProvider {
    static var previews: some View {
        MultiPhotoRosterImporterView(
            shootID: "previewID",
            onComplete: { _ in }
        )
    }
}
