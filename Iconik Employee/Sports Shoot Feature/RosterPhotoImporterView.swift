//
//  RosterPhotoImporterView.swift
//  Iconik Employee
//
//  Updated to support sequential Subject IDs
//

import SwiftUI
import UIKit

struct RosterPhotoImporterView: View {
    let shootID: UUID
    let onComplete: (Bool) -> Void
    
    @State private var showImagePicker = false
    @State private var image: UIImage? = nil
    @State private var isProcessing = false
    @State private var extractedRoster: [RosterEntry] = []
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var nextSubjectID: Int = 101 // Default starting ID
    
    // Environment to dismiss the view
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack {
                if isProcessing {
                    processingView
                } else if let image = image {
                    VStack {
                        Text("Captured Roster Image")
                            .font(.headline)
                            .padding(.top)
                        
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding()
                            .frame(maxHeight: 300)
                        
                        if extractedRoster.isEmpty {
                            VStack(spacing: 20) {
                                TextField("Starting Subject ID", value: $nextSubjectID, formatter: NumberFormatter())
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.numberPad)
                                    .padding(.horizontal)
                                
                                Button(action: {
                                    processImage(image)
                                }) {
                                    Text("Extract Roster")
                                        .bold()
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.blue)
                                        .cornerRadius(10)
                                }
                                .padding(.horizontal)
                            }
                            
                            Button(action: {
                                self.image = nil
                            }) {
                                Text("Choose Different Image")
                                    .foregroundColor(.blue)
                            }
                            .padding(.bottom)
                        } else {
                            rosterPreviewView
                        }
                    }
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("Import Roster from Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImage: $image)
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
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 70))
                .foregroundColor(.blue)
            
            Text("Import Team Roster")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Take a photo of a printed roster or select an image from your gallery. Claude AI will extract the information automatically.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .foregroundColor(.secondary)
            
            // Show next available ID info
            VStack(spacing: 8) {
                Text("Next athlete will be assigned ID: \(nextSubjectID)")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                TextField("Starting Subject ID", value: $nextSubjectID, formatter: NumberFormatter())
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
            }
            .padding(.vertical)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
            
            VStack(spacing: 15) {
                Button(action: {
                    showImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title3)
                        Text("Choose from Library")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                Button(action: {
                    // For future implementation - add camera capture
                    showImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "camera")
                            .font(.title3)
                        Text("Take Photo")
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
            
            Spacer()
        }
        .padding()
    }
    
    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .padding()
            
            Text("Processing Roster...")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("Claude AI is analyzing the image to extract athlete information. This may take a few moments. New athletes will be numbered starting from \(nextSubjectID).")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .padding()
    }
    
    private var rosterPreviewView: some View {
        VStack {
            Text("Extracted \(extractedRoster.count) Athletes")
                .font(.headline)
                .padding(.top)
            
            List {
                ForEach(extractedRoster) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(entry.lastName)")
                                .font(.headline)
                            
                            Spacer()
                            
                            Text("ID: \(entry.firstName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if !entry.groupName.isEmpty {
                            Text("Sport/Team: \(entry.groupName)")
                                .font(.caption)
                        }
                        
                        if !entry.teacher.isEmpty {
                            Text("Grade: \(entry.teacher)")
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
            .frame(maxHeight: 300)
            
            Button(action: {
                saveExtractedRoster()
            }) {
                Text("Import Roster")
                    .bold()
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(10)
            }
            .padding()
            
            Button(action: {
                extractedRoster = []
                image = nil
            }) {
                Text("Start Over")
                    .foregroundColor(.blue)
            }
            .padding(.bottom)
        }
    }
    
    // Load existing roster to determine next available Subject ID
    private func loadExistingRoster() {
        Task {
            do {
                let entries = try await RosterEntryService.shared.fetchEntries(forJob: shootID)
                // Find the highest Subject ID value across all entries
                let highestID = entries.compactMap { entry -> Int? in
                    return Int(entry.firstName)
                }.max() ?? 100 // Default to 100 if no entries exist

                await MainActor.run {
                    self.nextSubjectID = highestID + 1
                }
            } catch {
                // Keep the default starting ID if there's an error
            }
        }
    }
    
    private func processImage(_ image: UIImage) {
        isProcessing = true

        // Use the actual API implementation with the next available Subject ID
        ClaudeRosterService.shared.extractRosterFromImage(image, sportsJobId: shootID, startingSubjectID: nextSubjectID) { result in
            DispatchQueue.main.async {
                isProcessing = false
                
                switch result {
                case .success(let roster):
                    // Sort the roster alphabetically by full name (stored in lastName field)
                    // Since names are in format "FIRSTNAME LASTNAME", this sorts by first name
                    var sortedRoster = roster.sorted { $0.lastName < $1.lastName }
                    // Reassign Subject IDs sequentially after sorting
                    for (index, _) in sortedRoster.enumerated() {
                        sortedRoster[index].firstName = String(nextSubjectID + index)
                    }
                    extractedRoster = sortedRoster
                case .failure(let error):
                    errorMessage = "Failed to extract roster: \(error.localizedDescription)"
                    showingErrorAlert = true
                }
            }
        }
    }
    
    private func saveExtractedRoster() {
        guard !extractedRoster.isEmpty else { return }

        isProcessing = true

        Task {
            do {
                // Ensure all entries have the correct sportsJobId
                let entriesToSave = extractedRoster.map { entry in
                    var newEntry = entry
                    newEntry.sportsJobId = shootID
                    return newEntry
                }

                try await RosterEntryService.shared.createEntries(entriesToSave)

                await MainActor.run {
                    isProcessing = false
                    onComplete(true)
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = "Some entries could not be added. Please try again."
                    showingErrorAlert = true
                }
            }
        }
    }
}

struct RosterPhotoImporterView_Previews: PreviewProvider {
    static var previews: some View {
        RosterPhotoImporterView(
            shootID: UUID(),
            onComplete: { _ in }
        )
    }
}
