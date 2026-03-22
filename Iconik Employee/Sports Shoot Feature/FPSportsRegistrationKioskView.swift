//
//  FPSportsRegistrationKioskView.swift
//  Iconik Employee
//
//  Walk-in athlete registration kiosk for FP Sports.
//  Creates FPSubject entries in Production subjects table.
//  Parallel to RegistrationKioskView but uses FPSubject instead of RosterEntry.
//

import SwiftUI

struct FPSportsRegistrationKioskView: View {
    let galleryId: String
    let organizationId: String
    let schoolName: String
    let defaultSportTeam: String
    let defaultGrade: String

    private let powerSync = PowerSyncManager.shared

    @State private var firstNameInput = ""
    @State private var lastNameInput = ""
    @State private var gradeTeam = ""
    @State private var emailInput = ""
    @State private var phoneInput = ""

    @State private var nextRosterId: Int = 101
    @State private var totalRegistered: Int = 0
    @State private var showSuccessScreen = false
    @State private var lastAssignedNumber: String = ""
    @State private var isSubmitting = false
    @State private var isCooldown = false
    @State private var registrationCount = 0
    @State private var errorMessage = ""
    @State private var showError = false

    // Passcode
    @State private var showPasscodeEntry = false
    @State private var passcodeInput = ""
    var kioskPasscode: String = ""

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        ZStack {
            if showSuccessScreen {
                successView
            } else {
                registrationForm
            }
        }
        .background(passcodeAlert)
        .onAppear {
            gradeTeam = defaultGrade
            loadNextId()
        }
    }

    // MARK: - Registration Form

    private var registrationForm: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(schoolName).font(.title2).fontWeight(.bold)
                    Text(defaultSportTeam).font(.headline).foregroundColor(.secondary)
                }
                Spacer()
                Text("\(totalRegistered) Registered").font(.headline)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1)).cornerRadius(8)

                Button(action: { exitKiosk() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30)).foregroundColor(.secondary)
                }.frame(width: 44, height: 44)
            }
            .padding()

            Divider()

            // Form — 2-column layout
            HStack(alignment: .top, spacing: 24) {
                // Left: Required fields
                VStack(spacing: 16) {
                    Text("Enter Your Information").font(.title3).fontWeight(.semibold)

                    VStack(spacing: 12) {
                        TextField("First Name *", text: $firstNameInput)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.title3)
                            .autocapitalization(.words)

                        TextField("Last Name *", text: $lastNameInput)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.title3)
                            .autocapitalization(.words)
                    }

                    Button(action: { submitRegistration() }) {
                        Text("REGISTER")
                            .font(.title2).fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(canSubmit ? Color.green : Color.gray)
                            .cornerRadius(12)
                    }
                    .disabled(!canSubmit || isSubmitting)

                    Spacer()
                }
                .frame(maxWidth: .infinity)

                // Right: Optional fields
                VStack(spacing: 16) {
                    Text("Optional").font(.title3).fontWeight(.semibold).foregroundColor(.secondary)

                    TextField("Grade", text: $gradeTeam)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.title3)

                    TextField("Email", text: $emailInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.title3)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)

                    TextField("Phone", text: $phoneInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.title3)
                        .keyboardType(.phonePad)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 100)).foregroundColor(.green)

            Text("Registered!").font(.largeTitle).fontWeight(.bold)

            Text("Your number is").font(.title2).foregroundColor(.secondary)
            Text(lastAssignedNumber)
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundColor(.blue)

            Text("Please remember this number").font(.headline).foregroundColor(.secondary)

            Spacer()

            Text("Next athlete in 3 seconds...")
                .foregroundColor(.secondary)
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
        !firstNameInput.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastNameInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func loadNextId() {
        Task {
            do {
                let subjects = try await powerSync.getSubjects(forGalleryId: galleryId)
                let highest = subjects.compactMap { Int($0.rosterId) }.max() ?? 100
                await MainActor.run {
                    nextRosterId = highest + 1
                    totalRegistered = subjects.filter { !$0.isBlank }.count
                }
            } catch { }
        }
    }

    private func submitRegistration() {
        guard canSubmit, !isCooldown else { return }
        // Rate limit: max 500 registrations per kiosk session
        guard registrationCount < 500 else {
            errorMessage = "Registration limit reached. Please see a staff member."
            showError = true
            return
        }
        isSubmitting = true

        let fullName = "\(firstNameInput.trimmingCharacters(in: .whitespaces).uppercased()) \(lastNameInput.trimmingCharacters(in: .whitespaces).uppercased())"

        let subject = FPSubject(
            galleryId: galleryId,
            organizationId: organizationId,
            firstName: "",
            lastName: fullName,
            grade: gradeTeam.trimmingCharacters(in: .whitespaces),
            teacher: gradeTeam.trimmingCharacters(in: .whitespaces),
            homeroom: "",
            studentId: "",
            rosterId: String(nextRosterId),
            jerseyNumber: "",
            sport: defaultSportTeam.uppercased(),
            position: "",
            email: emailInput.trimmingCharacters(in: .whitespaces),
            phone: phoneInput.trimmingCharacters(in: .whitespaces),
            updatedAt: Date()
        )

        Task {
            do {
                try await powerSync.saveSubject(subject)
                await MainActor.run {
                    lastAssignedNumber = String(nextRosterId)
                    nextRosterId += 1
                    totalRegistered += 1
                    registrationCount += 1
                    isSubmitting = false
                    isCooldown = true
                    showSuccessScreen = true

                    // Haptic feedback
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
        firstNameInput = ""
        lastNameInput = ""
        emailInput = ""
        phoneInput = ""
        gradeTeam = defaultGrade
        showSuccessScreen = false
        isCooldown = false
    }

    private func exitKiosk() {
        if !kioskPasscode.isEmpty {
            passcodeInput = ""
            showPasscodeEntry = true
        } else {
            presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - Passcode Alert Extension
extension FPSportsRegistrationKioskView {
    @ViewBuilder
    var passcodeAlert: some View {
        EmptyView()
            .alert("Enter Passcode", isPresented: $showPasscodeEntry) {
                TextField("Passcode", text: $passcodeInput)
                Button("Cancel", role: .cancel) { passcodeInput = "" }
                Button("Exit Kiosk") {
                    if passcodeInput == kioskPasscode {
                        presentationMode.wrappedValue.dismiss()
                    } else {
                        passcodeInput = ""
                        errorMessage = "Incorrect passcode"
                        showError = true
                    }
                }
            } message: {
                Text("Enter the passcode to exit kiosk mode")
            }
    }
}
