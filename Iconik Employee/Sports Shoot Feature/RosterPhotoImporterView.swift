//
//  RosterPhotoImporterView.swift
//  Iconik Employee
//
//  Created by administrator on 5/16/25.
//

import SwiftUI
import UIKit
import Firebase
import FirebaseFirestore

struct RosterPhotoImporterView: View {
    let shootID: String
    let onComplete: (Bool) -> Void
    
    @State private var showImagePicker = false
    @State private var image: UIImage? = nil
    @State private var isProcessing = false
    @State private var extractedRoster: [RosterEntry] = []
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    
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
                            .padding()
                            
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
                ImagePicker(
                    sourceType: .photoLibrary,
                    selectedImage: $image,
                    completionHandler: { _ in
                        showImagePicker = false
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
            
            Text("Claude AI is analyzing the image to extract athlete information. This may take a few moments.")
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
    
    private func processImage(_ image: UIImage) {
        isProcessing = true
        
        // Use the mock implementation for testing or quick results
        // In production, use the actual API call:
        
        // Option 1: Use mock for testing (fast, no API call)
        // ClaudeRosterService.shared.mockExtractRoster { result in
        
        // Option 2: Use actual API (requires API key)
        ClaudeRosterService.shared.extractRosterFromImage(image) { result in
            DispatchQueue.main.async {
                isProcessing = false
                
                switch result {
                case .success(let roster):
                    extractedRoster = roster
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
        
        // Use a dispatch group to track all operations
        let group = DispatchGroup()
        var errorOccurred = false
        
        // Add each entry to the sports shoot
        for entry in extractedRoster {
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
            isProcessing = false
            
            if errorOccurred {
                errorMessage = "Some entries could not be added. Please try again."
                showingErrorAlert = true
            } else {
                // Notify completion and dismiss
                onComplete(true)
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
}

// Image Picker Component for selecting photos
struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    let completionHandler: (Result<UIImage, Error>) -> Void
    
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: ImagePicker
        
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

struct RosterPhotoImporterView_Previews: PreviewProvider {
    static var previews: some View {
        RosterPhotoImporterView(
            shootID: "previewID",
            onComplete: { _ in }
        )
    }
}