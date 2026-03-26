//
//  FPSportsPhotoImporter.swift
//  Iconik Employee
//
//  Single-photo roster import for FP Sports.
//  Parallel to RosterPhotoImporterView but creates FPSubject entries.
//

import SwiftUI
import UIKit

struct FPSportsPhotoImporter: View {
    let galleryId: String
    let organizationId: String
    let onComplete: (Bool) -> Void

    private let powerSync = PowerSyncManager.shared

    @State private var showImagePicker = false
    @State private var showCameraPicker = false
    @State private var image: UIImage? = nil
    @State private var isProcessing = false
    @State private var extractedSubjects: [FPSubject] = []
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var nextRosterId: Int = 101

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack {
                if isProcessing {
                    processingView
                } else if let image = image {
                    VStack {
                        Text("Captured Roster Image").font(.headline).padding(.top)

                        Image(uiImage: image)
                            .resizable().scaledToFit().padding().frame(maxHeight: 300)

                        if extractedSubjects.isEmpty {
                            VStack(spacing: 20) {
                                TextField("Starting Roster ID", value: $nextRosterId, formatter: NumberFormatter())
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.numberPad).padding(.horizontal)

                                Button(action: { processImage(image) }) {
                                    Text("Extract Roster").bold().foregroundColor(.white)
                                        .frame(maxWidth: .infinity).padding()
                                        .background(Color.blue).cornerRadius(10)
                                }.padding(.horizontal)
                            }

                            Button(action: { self.image = nil }) {
                                Text("Choose Different Image").foregroundColor(.blue)
                            }.padding(.bottom)
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
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImage: $image)
            }
            .sheet(isPresented: $showCameraPicker) {
                CameraImagePicker(selectedImage: $image)
            }
            .alert(isPresented: $showingErrorAlert) {
                Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
            }
            .onAppear { loadExisting() }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 70)).foregroundColor(.blue)
            Text("Import Team Roster").font(.title2).fontWeight(.bold)
            Text("Take a photo of a printed roster. Claude AI will extract the information automatically.")
                .multilineTextAlignment(.center).padding(.horizontal).foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("Next athlete will be assigned ID: \(nextRosterId)")
                    .font(.headline).foregroundColor(.blue)
                TextField("Starting Roster ID", value: $nextRosterId, formatter: NumberFormatter())
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad).padding(.horizontal).padding(.bottom, 10)
            }.padding(.vertical).background(Color.blue.opacity(0.1)).cornerRadius(8).padding(.horizontal)

            VStack(spacing: 15) {
                Button(action: { showImagePicker = true }) {
                    HStack {
                        Image(systemName: "photo.on.rectangle").font(.title3)
                        Text("Choose from Library").fontWeight(.semibold)
                    }.frame(maxWidth: .infinity).padding()
                    .background(Color.blue).foregroundColor(.white).cornerRadius(10)
                }
                Button(action: { showCameraPicker = true }) {
                    HStack {
                        Image(systemName: "camera").font(.title3)
                        Text("Take Photo").fontWeight(.semibold)
                    }.frame(maxWidth: .infinity).padding()
                    .background(Color.secondary.opacity(0.15)).foregroundColor(.primary).cornerRadius(10)
                }
            }.padding(.horizontal)
            Spacer()
        }.padding()
    }

    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.5).padding()
            Text("Processing Roster...").font(.title3).fontWeight(.medium)
            Text("Claude AI is analyzing the image. Athletes will be numbered from \(nextRosterId).")
                .multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)
        }.padding()
    }

    private var rosterPreviewView: some View {
        VStack {
            Text("Extracted \(extractedSubjects.count) Athletes").font(.headline).padding(.top)
            List {
                ForEach(extractedSubjects) { subject in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(subject.lastName).font(.headline)
                            Spacer()
                            Text("ID: \(subject.rosterId)").font(.caption).foregroundColor(.secondary)
                        }
                        if !subject.sport.isEmpty { Text("Sport: \(subject.sport)").font(.caption) }
                        if !subject.teacher.isEmpty { Text("Grade: \(subject.teacher)").font(.caption) }
                        if !subject.email.isEmpty { Text("Email: \(subject.email)").font(.caption).foregroundColor(.blue) }
                    }.padding(.vertical, 4)
                }
            }.frame(maxHeight: 300)

            Button(action: { saveExtracted() }) {
                Text("Import Roster").bold().foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.green).cornerRadius(10)
            }.padding()

            Button(action: { extractedSubjects = []; image = nil }) {
                Text("Start Over").foregroundColor(.blue)
            }.padding(.bottom)
        }
    }

    private func loadExisting() {
        Task {
            do {
                let subjects = try await powerSync.getSubjects(forGalleryId: galleryId)
                let highest = subjects.compactMap { Int($0.rosterId) }.max() ?? 100
                await MainActor.run { nextRosterId = highest + 1 }
            } catch { }
        }
    }

    private func processImage(_ image: UIImage) {
        isProcessing = true
        ClaudeRosterService.shared.extractSubjectsFromImage(image, galleryId: galleryId, organizationId: organizationId, startingSubjectID: nextRosterId) { result in
            DispatchQueue.main.async {
                isProcessing = false
                switch result {
                case .success(let subjects):
                    // Sort alphabetically, reassign IDs
                    var sorted = subjects.filter { !$0.lastName.trimmingCharacters(in: .whitespaces).isEmpty }
                        .sorted { $0.lastName < $1.lastName }
                    for (i, _) in sorted.enumerated() {
                        sorted[i].rosterId = String(nextRosterId + i)
                    }
                    // Append blanks
                    let blankStart = nextRosterId + sorted.count
                    for i in 0..<10 {
                        sorted.append(FPSubject(galleryId: galleryId, organizationId: organizationId, firstName: "", lastName: "", grade: "", teacher: "", homeroom: "", studentId: "", rosterId: String(blankStart + i), jerseyNumber: "", sport: sorted.first?.sport ?? ""))
                    }
                    extractedSubjects = sorted
                case .failure(let error):
                    errorMessage = "Failed to extract: \(error.localizedDescription)"
                    showingErrorAlert = true
                }
            }
        }
    }

    private func saveExtracted() {
        guard !extractedSubjects.isEmpty else { return }
        isProcessing = true
        Task {
            var saved = 0
            for subject in extractedSubjects {
                do {
                    try await powerSync.saveSubject(subject)
                    saved += 1
                    // Broadcast to Surface Pro via WebSocket
                    FocalPointSyncClient.shared.broadcastSubjectCreated(
                        rosterEntryId: subject.id.uuidString.lowercased(),
                        firstName: subject.firstName,
                        lastName: subject.lastName,
                        rosterId: subject.rosterId,
                        grade: subject.grade,
                        groupName: subject.sport
                    )
                } catch {
                    print("FPSportsPhotoImporter: Save failed: \(error)")
                }
            }
            await MainActor.run {
                isProcessing = false
                onComplete(saved > 0)
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
}

// MARK: - Camera Picker (sourceType = .camera)
private struct CameraImagePicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) private var presentationMode
    @Binding var selectedImage: UIImage?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraImagePicker
        init(_ parent: CameraImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
