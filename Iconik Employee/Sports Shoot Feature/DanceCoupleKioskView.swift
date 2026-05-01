//
//  DanceCoupleKioskView.swift
//  Iconik Employee
//
//  Self-service kiosk for dance shoots. Couples (or solo dancers) enter
//  their own info on the iPad. Each submission writes a new FPSubject to
//  PowerSync local SQLite (durable for offline shoots) and broadcasts a
//  WebSocket subject_created so the poser iPad and Surface Pro camera
//  station see the new dancer immediately — no internet required.
//
//  Field mapping per studio convention:
//    - Dancer 1 full name → firstName (verbatim, not split)
//    - Dancer 2 full name → lastName (verbatim, not split)
//    - Dancer 3..13 full names → custom10..custom20
//    - Emails (any count) → joined with ", " into the single email column
//

import SwiftUI

struct DanceCoupleKioskView: View {
    let galleryId: String
    let organizationId: String
    let schoolName: String
    /// 4-digit PIN required to exit kiosk mode. Required — no default
    /// so accidental no-PIN launches can't open a free exit on a
    /// public-facing iPad.
    let kioskPasscode: String

    private let powerSync = PowerSyncManager.shared
    @StateObject private var fpSync = FocalPointSyncClient.shared
    @Environment(\.presentationMode) var presentationMode

    // Capacity matches the FPSubject custom field count: dancer #3 is the
    // first custom slot (custom10) and #13 fills the last (custom20).
    private let maxNames = 13
    private let maxEmails = 10

    @State private var nameInputs: [String] = ["", ""]
    @State private var emailInputs: [String] = [""]

    @State private var nextRosterId: Int = 101
    @State private var totalRegistered: Int = 0
    @State private var showSuccessScreen = false
    @State private var lastAssignedNumber: String = ""
    @State private var isSubmitting = false
    @State private var registrationCount = 0
    @State private var errorMessage = ""
    @State private var showError = false

    // Passcode — separate alert state so the "wrong PIN" title doesn't
    // get reused for form-submit errors.
    @State private var showPasscodeEntry = false
    @State private var passcodeInput = ""
    @State private var showPasscodeError = false

    var body: some View {
        ZStack {
            // Opaque background so the kiosk fully covers the capture view
            // behind the fullScreenCover. Without this, the form is
            // transparent and the underlying PoserStationView shows through.
            Color(.systemBackground).ignoresSafeArea()
            if showSuccessScreen {
                successView
            } else {
                registrationForm
            }
        }
        .background(passcodeAlert)
        .interactiveDismissDisabled(true)
        .onAppear { loadNextId() }
    }

    // MARK: - Registration Form

    private var registrationForm: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    namesSection
                    Divider()
                    emailsSection
                    submitButton
                        .padding(.top, 12)
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(schoolName).font(.title2).fontWeight(.bold)
                Text("Dance Registration").font(.headline).foregroundColor(.secondary)
            }
            Spacer()
            Text("\(totalRegistered) Registered")
                .font(.headline)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)

            Button(action: { exitKiosk() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.secondary)
            }
            .frame(width: 44, height: 44)
        }
        .padding()
    }

    private var namesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dancer Names").font(.title3).fontWeight(.semibold)
            Text("At least one name required").font(.caption).foregroundColor(.secondary)

            ForEach(nameInputs.indices, id: \.self) { idx in
                HStack(spacing: 8) {
                    TextField(namePlaceholder(for: idx), text: $nameInputs[idx])
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.title3)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)

                    if idx >= 2 {
                        Button(action: { removeName(at: idx) }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Remove dancer \(idx + 1)")
                    }
                }
            }

            if nameInputs.count < maxNames {
                Button(action: { nameInputs.append("") }) {
                    Label("Add another dancer", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    private var emailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Emails (optional)").font(.title3).fontWeight(.semibold)

            ForEach(emailInputs.indices, id: \.self) { idx in
                HStack(spacing: 8) {
                    TextField("Email", text: $emailInputs[idx])
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.title3)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textContentType(.emailAddress)

                    if idx > 0 {
                        Button(action: { removeEmail(at: idx) }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Remove email \(idx + 1)")
                    }
                }
            }

            if emailInputs.count < maxEmails {
                Button(action: { emailInputs.append("") }) {
                    Label("Add another email", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    private var submitButton: some View {
        Button(action: { submit() }) {
            Text("SUBMIT")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(canSubmit && !isSubmitting ? Color.green : Color.gray)
                .cornerRadius(12)
        }
        .disabled(!canSubmit || isSubmitting)
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 100))
                .foregroundColor(.green)
            Text("Registered!").font(.largeTitle).fontWeight(.bold)
            Text("Your number is").font(.title2).foregroundColor(.secondary)
            Text(lastAssignedNumber)
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundColor(.blue)
            Text("Please remember this number")
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
            Text("Next dancer in 3 seconds...").foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                resetForm()
            }
        }
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        nameInputs.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func namePlaceholder(for idx: Int) -> String {
        switch idx {
        case 0: return "Dancer 1 full name *"
        case 1: return "Dancer 2 full name"
        default: return "Dancer \(idx + 1) full name"
        }
    }

    private func removeName(at idx: Int) {
        guard idx >= 2 && idx < nameInputs.count else { return }
        nameInputs.remove(at: idx)
    }

    private func removeEmail(at idx: Int) {
        guard idx > 0 && idx < emailInputs.count else { return }
        emailInputs.remove(at: idx)
    }

    private func loadNextId() {
        Task {
            do {
                let subjects = try await powerSync.getSubjects(forGalleryId: galleryId)
                let highest = subjects.compactMap { Int($0.rosterId) }.max() ?? 100
                await MainActor.run {
                    nextRosterId = max(highest + 1, 101)
                    totalRegistered = subjects.filter { !$0.isBlank }.count
                }
            } catch { }
        }
    }

    private func submit() {
        guard canSubmit, !isSubmitting else { return }
        // Mirrors the sports kiosk: cap a single kiosk session at 500
        // entries to bound runaway state in the unlikely event a stuck
        // form keeps re-submitting. Photographer can dismiss + re-launch
        // if they actually need more than 500 in one go.
        guard registrationCount < 500 else {
            errorMessage = "Registration limit reached. Please see a staff member."
            showError = true
            return
        }
        isSubmitting = true

        let trimmedNames = nameInputs.map { $0.trimmingCharacters(in: .whitespaces) }
        let trimmedEmails = emailInputs
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joinedEmails = trimmedEmails.joined(separator: ", ")

        let firstName = trimmedNames.indices.contains(0) ? trimmedNames[0] : ""
        let lastName = trimmedNames.indices.contains(1) ? trimmedNames[1] : ""
        // Names 3..13 (idx 2..12) → custom10..custom20
        let extraNames = Array(trimmedNames.dropFirst(2))
        func extraName(_ slot: Int) -> String {
            return extraNames.indices.contains(slot) ? extraNames[slot] : ""
        }

        Task {
            do {
                // Re-query roster IDs at submit time so two iPads (or the
                // photographer adding via the roster view in parallel)
                // can't hand out the same number. The receiver only
                // toasts on dup; collision corrupts the printed number
                // we just told the dancer to remember.
                let freshSubjects = (try? await powerSync.getSubjects(forGalleryId: galleryId)) ?? []
                let highest = freshSubjects.compactMap { Int($0.rosterId) }.max() ?? 100
                let assignedRosterId = max(highest + 1, 101)

                let subject = FPSubject(
                    galleryId: galleryId,
                    organizationId: organizationId,
                    firstName: firstName,
                    lastName: lastName,
                    rosterId: String(assignedRosterId),
                    email: joinedEmails,
                    custom10: extraName(0),
                    custom11: extraName(1),
                    custom12: extraName(2),
                    custom13: extraName(3),
                    custom14: extraName(4),
                    custom15: extraName(5),
                    custom16: extraName(6),
                    custom17: extraName(7),
                    custom18: extraName(8),
                    custom19: extraName(9),
                    custom20: extraName(10),
                    updatedAt: Date()
                )
                try await powerSync.saveSubject(subject)
                // Broadcast over LAN so PoserStation and CameraStation see
                // this dancer instantly with no internet round-trip.
                fpSync.broadcastSubjectCreated(
                    rosterEntryId: subject.id.uuidString.lowercased(),
                    firstName: subject.firstName,
                    lastName: subject.lastName,
                    rosterId: subject.rosterId,
                    grade: "",
                    groupName: "",
                    email: subject.email,
                    custom10: subject.custom10,
                    custom11: subject.custom11,
                    custom12: subject.custom12,
                    custom13: subject.custom13,
                    custom14: subject.custom14,
                    custom15: subject.custom15,
                    custom16: subject.custom16,
                    custom17: subject.custom17,
                    custom18: subject.custom18,
                    custom19: subject.custom19,
                    custom20: subject.custom20
                )
                await MainActor.run {
                    lastAssignedNumber = String(assignedRosterId)
                    nextRosterId = assignedRosterId + 1
                    totalRegistered = freshSubjects.filter { !$0.isBlank }.count + 1
                    registrationCount += 1
                    isSubmitting = false
                    showSuccessScreen = true
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Failed to register. Please try again."
                    showError = true
                }
            }
        }
    }

    private func resetForm() {
        nameInputs = ["", ""]
        emailInputs = [""]
        showSuccessScreen = false
    }

    private func exitKiosk() {
        // Always require PIN — kioskPasscode is required at construction
        // so there's no no-PIN escape hatch from a public iPad.
        passcodeInput = ""
        showPasscodeEntry = true
    }
}

// MARK: - Passcode Alert

extension DanceCoupleKioskView {
    @ViewBuilder
    var passcodeAlert: some View {
        EmptyView()
            .alert("Enter Passcode", isPresented: $showPasscodeEntry) {
                // SecureField masks the PIN — keeps dancers from
                // shoulder-surfing the photographer's exit code.
                SecureField("Passcode", text: $passcodeInput)
                    .keyboardType(.numberPad)
                Button("Cancel", role: .cancel) { passcodeInput = "" }
                Button("Exit Kiosk") {
                    if passcodeInput == kioskPasscode {
                        presentationMode.wrappedValue.dismiss()
                    } else {
                        passcodeInput = ""
                        showPasscodeError = true
                    }
                }
            } message: {
                Text("Enter the passcode to exit kiosk mode")
            }
            .alert("Incorrect PIN", isPresented: $showPasscodeError) {
                Button("OK") { }
            } message: {
                Text("The PIN you entered does not match. Try again.")
            }
    }
}
