//
//  FPSportsAddSubjectView.swift
//  Iconik Employee
//
//  Add/edit a single FPSubject for FP Sports.
//  Parallel to AddRosterEntryView but writes to Production subjects table.
//

import SwiftUI
import Combine

struct FPSportsAddSubjectView: View {
    let galleryId: String
    let organizationId: String
    let existingSubject: FPSubject?
    let onComplete: (Bool) -> Void

    private let powerSync = PowerSyncManager.shared

    @State private var lastName: String = ""
    @State private var firstName: String = ""
    @State private var rosterId: String = ""
    @State private var teacher: String = ""
    @State private var sport: String = ""
    @State private var grade: String = ""
    @State private var jerseyNumber: String = ""
    @State private var position: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var imageNumbers: String = ""
    @State private var notes: String = ""

    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var isLoadingSubjectID = false

    // Lock state
    @State private var lockAcquired = false
    @State private var lockError: String?
    @State private var isAcquiringLock = false

    @FocusState private var focusedField: String?
    @Environment(\.presentationMode) var presentationMode

    var isEditing: Bool { existingSubject != nil }

    var body: some View {
        NavigationView {
            if let error = lockError {
                lockErrorView(error)
            } else if isAcquiringLock {
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.5)
                    Text("Acquiring lock...").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationBarTitle(isEditing ? "Edit Athlete" : "Add Athlete", displayMode: .inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                    }
                }
            } else {
                formContent
            }
        }
        .task { await acquireLockIfNeeded() }
        .onDisappear { releaseLockIfNeeded() }
    }

    // MARK: - Lock Error View

    private func lockErrorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.system(size: 60)).foregroundColor(.red)
            Text("Cannot Edit").font(.title2).fontWeight(.bold)
            Text(error).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)
            Button("Go Back") { presentationMode.wrappedValue.dismiss() }
                .padding().background(Color.blue).foregroundColor(.white).cornerRadius(10)
        }
        .padding()
        .navigationBarTitle("Locked", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { presentationMode.wrappedValue.dismiss() }
            }
        }
    }

    // MARK: - Form

    private var formContent: some View {
        Form {
            Section(header: Text("Athlete Information")) {
                TextField("Name", text: $lastName)
                    .autocapitalization(.words)
                    .focused($focusedField, equals: "lastName")
                    .submitLabel(.next)
                    .onSubmit { focusedField = "rosterId" }

                TextField("Roster ID", text: $rosterId)
                    .focused($focusedField, equals: "rosterId")
                    .submitLabel(.next)
                    .onSubmit { focusedField = "sport" }

                TextField("Sport/Team", text: $sport)
                    .autocapitalization(.words)
                    .focused($focusedField, equals: "sport")
                    .submitLabel(.next)
                    .onSubmit { focusedField = "teacher" }

                TextField("Special", text: $teacher)
                    .autocapitalization(.words)
                    .focused($focusedField, equals: "teacher")
                    .submitLabel(.next)
                    .onSubmit { focusedField = "grade" }

                TextField("Grade", text: $grade)
                    .focused($focusedField, equals: "grade")
                    .submitLabel(.next)
                    .onSubmit { focusedField = "jerseyNumber" }

                TextField("Jersey Number", text: $jerseyNumber)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: "jerseyNumber")

                TextField("Position", text: $position)
                    .focused($focusedField, equals: "position")
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
            }

            Section(header: Text("Image Information")) {
                TextField("Image Numbers (semicolon-separated)", text: $imageNumbers)
                    .focused($focusedField, equals: "imageNumbers")

                TextView(text: $notes, placeholder: "Notes (optional)")
                    .frame(minHeight: 100)
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .navigationBarTitle(isEditing ? "Edit Athlete" : "Add Athlete", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { presentationMode.wrappedValue.dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Update" : "Save") { saveSubject() }
                    .disabled(isLoading)
            }
        }
        .alert(isPresented: $showingErrorAlert) {
            Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            if let s = existingSubject {
                lastName = s.lastName
                firstName = s.firstName
                rosterId = s.rosterId
                teacher = s.teacher
                sport = s.sport
                grade = s.grade
                jerseyNumber = s.jerseyNumber
                position = s.position
                email = s.email
                phone = s.phone
                imageNumbers = s.imageNumbers
                notes = s.notes
            } else {
                loadNextRosterId()
            }
        }
    }

    // MARK: - Lock Management (uses subjects table, not roster_entries)

    private func acquireLockIfNeeded() async {
        guard let subject = existingSubject else {
            // New subject — no lock needed
            lockAcquired = true
            return
        }
        isAcquiringLock = true
        let acquired = await LockManager.shared.acquireSubjectLock(subjectId: subject.id)
        await MainActor.run {
            isAcquiringLock = false
            if acquired {
                lockAcquired = true
            } else {
                lockError = subject.lockedByName.map { "This athlete is being edited by \($0)." }
                    ?? "This athlete is being edited by another device."
            }
        }
    }

    private func releaseLockIfNeeded() {
        guard let subject = existingSubject, lockAcquired else { return }
        Task { await LockManager.shared.releaseSubjectLock(subjectId: subject.id) }
    }

    // MARK: - Data Loading

    private func loadNextRosterId() {
        isLoadingSubjectID = true
        Task {
            do {
                let subjects = try await powerSync.getSubjects(forGalleryId: galleryId)
                let highestID = subjects.compactMap { Int($0.rosterId) }.max() ?? 100
                await MainActor.run {
                    rosterId = "\(highestID + 1)"
                    isLoadingSubjectID = false
                }
            } catch {
                await MainActor.run {
                    rosterId = "101"
                    isLoadingSubjectID = false
                }
            }
        }
    }

    // MARK: - Save

    private func saveSubject() {
        let subject = FPSubject(
            id: existingSubject?.id ?? UUID(),
            galleryId: galleryId,
            organizationId: organizationId,
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            grade: grade.trimmingCharacters(in: .whitespacesAndNewlines),
            teacher: teacher.trimmingCharacters(in: .whitespacesAndNewlines),
            homeroom: "",
            studentId: "",
            rosterId: rosterId.trimmingCharacters(in: .whitespacesAndNewlines),
            jerseyNumber: jerseyNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            sport: sport.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            position: position.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
            imageNumbers: imageNumbers.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: existingSubject?.createdAt ?? Date(),
            updatedAt: Date()
        )

        isLoading = true
        Task {
            var lastError: Error?
            for attempt in 1...3 {
                do {
                    try await powerSync.saveSubject(subject)
                    if !isEditing {
                        FocalPointSyncClient.shared.broadcastSubjectCreated(
                            rosterEntryId: subject.id.uuidString.lowercased(),
                            firstName: subject.firstName,
                            lastName: subject.lastName,
                            rosterId: subject.rosterId,
                            grade: subject.grade,
                            groupName: subject.sport
                        )
                    } else {
                        FocalPointSyncClient.shared.sendSubjectUpdated(
                            subjectId: subject.id.uuidString.lowercased(),
                            rosterEntryId: subject.id.uuidString.lowercased(),
                            firstName: subject.firstName,
                            lastName: subject.lastName,
                            rosterId: subject.rosterId
                        )
                    }
                    await MainActor.run {
                        onComplete(true)
                        presentationMode.wrappedValue.dismiss()
                    }
                    return
                } catch {
                    lastError = error
                    if attempt < 3 {
                        try? await Task.sleep(nanoseconds: UInt64(500_000_000 * attempt))
                    }
                }
            }
            await MainActor.run {
                errorMessage = "Failed to save: \(lastError?.localizedDescription ?? "Unknown")"
                showingErrorAlert = true
            }
        }
    }
}
