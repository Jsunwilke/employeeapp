//
//  FPSportsMultiPhotoImporter.swift
//  Iconik Employee
//
//  Multi-photo roster import for FP Sports.
//  Parallel to MultiPhotoRosterImporterView but creates FPSubject entries.
//

import SwiftUI
import UIKit

struct FPSportsMultiPhotoImporter: View {
    let galleryId: String
    let organizationId: String
    let onComplete: (Bool) -> Void

    private let powerSync = PowerSyncManager.shared

    @State private var capturedImages: [UIImage] = []
    @State private var showDocumentScanner = false
    @State private var showPhotoLibrary = false
    @State private var isProcessing = false
    @State private var currentlyProcessingIndex: Int? = nil
    @State private var extractedSubjectsByImage: [Int: [FPSubject]] = [:]
    @State private var allExtractedSubjects: [FPSubject] = []
    @State private var showPreview = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var processingProgress: Double = 0
    @State private var teamLabels: [Int: String] = [:]
    @State private var selectedImage: UIImage? = nil
    @State private var nextRosterId: Int = 101

    @Environment(\.presentationMode) var presentationMode
    private let useClaudeMock = false

    private struct TeamGroup {
        let team: String
        let subjects: [FPSubject]
    }

    private var groupedByTeam: [TeamGroup] {
        var groups: [String: [FPSubject]] = [:]
        for subject in allExtractedSubjects {
            let key = subject.sport
            groups[key, default: []].append(subject)
        }
        return groups.map { TeamGroup(team: $0.key, subjects: $0.value) }
            .sorted { $0.team < $1.team }
    }

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
                Button("Cancel") { presentationMode.wrappedValue.dismiss() }
            }
            if !isProcessing && !showPreview && !capturedImages.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Process All") { processAllImages() }
                        .disabled(capturedImages.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showDocumentScanner) {
            DocumentScannerView(onScan: { scannedImages in
                for image in scannedImages { addImage(image) }
            })
        }
        .sheet(isPresented: $showPhotoLibrary) {
            ImagePicker(selectedImage: $selectedImage)
                .onDisappear {
                    if let image = selectedImage { addImage(image); selectedImage = nil }
                }
        }
        .alert(isPresented: $showingErrorAlert) {
            Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
        }
        .onAppear { loadExisting() }
        } // NavigationView
    }

    // MARK: - Photo Collection

    private var photoCollectionView: some View {
        VStack(spacing: 16) {
            if capturedImages.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        Text("\(capturedImages.count) Photo(s) Ready").font(.headline)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                            ForEach(Array(capturedImages.enumerated()), id: \.offset) { index, image in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image)
                                        .resizable().scaledToFill()
                                        .frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 8))

                                    Button(action: { removeImage(at: index) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.white).shadow(radius: 2)
                                    }.offset(x: -4, y: 4)

                                }

                                // Team name input under the image
                                TextField("Team Name", text: Binding(
                                    get: { teamLabels[index] ?? "" },
                                    set: { teamLabels[index] = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .frame(width: 120)
                            }
                        }.padding(.horizontal)

                        addMoreButtons
                    }.padding(.vertical)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 70)).foregroundColor(.blue)
            Text("Import Paper Rosters").font(.title2).fontWeight(.bold)
            Text("Scan or photograph multiple roster pages. Each page will be processed separately.")
                .multilineTextAlignment(.center).padding(.horizontal).foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("Roster IDs start from: \(nextRosterId)").font(.headline).foregroundColor(.blue)
            }.padding(.vertical).background(Color.blue.opacity(0.1)).cornerRadius(8).padding(.horizontal)

            addMoreButtons
            Spacer()
        }.padding()
    }

    private var addMoreButtons: some View {
        VStack(spacing: 12) {
            Button(action: { showDocumentScanner = true }) {
                HStack {
                    Image(systemName: "doc.viewfinder").font(.title3)
                    Text("Scan Pages").fontWeight(.semibold)
                }.frame(maxWidth: .infinity).padding()
                .background(Color.blue).foregroundColor(.white).cornerRadius(10)
            }
            Button(action: { showPhotoLibrary = true }) {
                HStack {
                    Image(systemName: "photo.on.rectangle").font(.title3)
                    Text("Choose from Library").fontWeight(.semibold)
                }.frame(maxWidth: .infinity).padding()
                .background(Color.secondary.opacity(0.15)).foregroundColor(.primary).cornerRadius(10)
            }
        }.padding(.horizontal)
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView(value: processingProgress)
                .progressViewStyle(LinearProgressViewStyle()).padding(.horizontal)
            if let idx = currentlyProcessingIndex {
                Text("Processing page \(idx + 1) of \(capturedImages.count)...").font(.headline)
            }
            Text("Claude AI is extracting athlete information.").foregroundColor(.secondary)
        }.padding()
    }

    // MARK: - Preview

    private var rosterPreviewView: some View {
        VStack {
            Text("Extracted \(allExtractedSubjects.count) Athletes").font(.headline).padding(.top)
            List {
                // Group by sport/team for display
                ForEach(groupedByTeam, id: \.team) { group in
                    Section(header: Text(group.team.isEmpty ? "No Team" : group.team)) {
                        ForEach(group.subjects) { subject in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(subject.firstName) \(subject.lastName)".trimmingCharacters(in: .whitespaces))
                                        .font(.headline)
                                    Spacer()
                                    Text("ID: \(subject.rosterId)").font(.caption).foregroundColor(.secondary)
                                }
                                if !subject.teacher.isEmpty { Text("Grade: \(subject.teacher)").font(.caption) }
                            }.padding(.vertical, 2)
                        }
                    }
                }
            }.listStyle(.insetGrouped)

            HStack(spacing: 16) {
                Button(action: { showPreview = false }) {
                    Text("Back").frame(maxWidth: .infinity).padding()
                        .background(Color.secondary.opacity(0.15)).cornerRadius(10)
                }
                Button(action: { saveAll() }) {
                    Text("Import All (\(allExtractedSubjects.count))").bold().foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.green).cornerRadius(10)
                }
            }.padding()
        }
    }

    // MARK: - Actions

    private func addImage(_ image: UIImage) {
        teamLabels[capturedImages.count] = ""
        capturedImages.append(image)
    }

    private func removeImage(at index: Int) {
        capturedImages.remove(at: index)
        teamLabels.removeValue(forKey: index)
        // Reindex team labels
        var newLabels: [Int: String] = [:]
        let sorted = teamLabels.sorted { $0.key < $1.key }
        for (newIdx, (_, label)) in sorted.enumerated() {
            newLabels[newIdx] = label
        }
        teamLabels = newLabels
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

    private func processAllImages() {
        guard !capturedImages.isEmpty else { return }
        isProcessing = true
        processingProgress = 0
        extractedSubjectsByImage = [:]
        allExtractedSubjects = []

        Task {
            var currentId = nextRosterId
            for (index, image) in capturedImages.enumerated() {
                await MainActor.run {
                    currentlyProcessingIndex = index
                    processingProgress = Double(index) / Double(capturedImages.count)
                }

                let subjects = await withCheckedContinuation { continuation in
                    ClaudeRosterService.shared.extractSubjectsFromImage(
                        image, galleryId: galleryId, organizationId: organizationId, startingSubjectID: currentId
                    ) { result in
                        switch result {
                        case .success(let s): continuation.resume(returning: s)
                        case .failure: continuation.resume(returning: [FPSubject]())
                        }
                    }
                }

                let nonBlank = subjects.filter { !$0.isBlank }
                currentId += nonBlank.count

                await MainActor.run {
                    extractedSubjectsByImage[index] = subjects
                }
            }

            // Combine all, reassign IDs sequentially, apply team labels
            var combined: [FPSubject] = []
            var id = nextRosterId
            for i in 0..<capturedImages.count {
                if let subjects = extractedSubjectsByImage[i] {
                    let teamName = teamLabels[i]?.trimmingCharacters(in: .whitespaces) ?? ""
                    for var subject in subjects where !subject.isBlank {
                        subject.rosterId = String(id)
                        // Use team label if set, otherwise keep what Claude extracted
                        if !teamName.isEmpty {
                            subject.sport = teamName.uppercased()
                        }
                        combined.append(subject)
                        id += 1
                    }
                }
            }
            // Append blanks with the last team name
            let lastTeam = combined.last?.sport ?? ""
            for i in 0..<10 {
                combined.append(FPSubject(galleryId: galleryId, organizationId: organizationId, firstName: "", lastName: "", grade: "", teacher: "", homeroom: "", studentId: "", rosterId: String(id + i), jerseyNumber: "", sport: lastTeam))
            }

            await MainActor.run {
                allExtractedSubjects = combined
                isProcessing = false
                processingProgress = 1.0
                showPreview = true
            }
        }
    }

    private func saveAll() {
        guard !allExtractedSubjects.isEmpty else { return }
        isProcessing = true
        Task {
            var saved = 0
            for subject in allExtractedSubjects {
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
                    print("FPSportsMultiPhotoImporter: Save failed: \(error)")
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
