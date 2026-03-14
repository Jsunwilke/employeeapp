//
//  RegistrationKioskView.swift
//  Iconik Employee
//
//  Self-registration kiosk for athletes
//  Enables athletes to register their own names and contact info
//  Syncs to photographer's iPad via Multipeer Connectivity
//

import SwiftUI
import UIKit

struct RegistrationKioskView: View {

    // MARK: - Properties

    let sportsJobId: UUID
    let organizationId: String
    let schoolName: String
    let defaultSportTeam: String
    let defaultGrade: String

    @StateObject private var multipeerSync = MultipeerRosterSync()
    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var gradeTeam: String = ""
    @State private var emailInput: String = ""
    @State private var phoneInput: String = ""
    @FocusState private var firstNameFocused: Bool
    @FocusState private var lastNameFocused: Bool

    // MARK: - Registration State

    @State private var nextSubjectID: Int = 101
    @State private var totalRegistered: Int = 0
    @State private var showSuccessScreen = false
    @State private var lastAssignedNumber: Int = 0

    // MARK: - Error Handling

    @State private var showError = false
    @State private var errorMessage = ""

    // MARK: - Connection Details

    @State private var showingConnectionDetails = false

    // MARK: - Auto-Advance Timer

    @State private var autoAdvanceTimer: Timer?

    // MARK: - Grade/Team Options

    private let gradeOptions = [
        ("K", "Kindergarten"),
        ("1", "1st Grade"),
        ("2", "2nd Grade"),
        ("3", "3rd Grade"),
        ("4", "4th Grade"),
        ("5", "5th Grade"),
        ("6", "6th Grade"),
        ("7", "7th Grade"),
        ("8", "8th Grade"),
        ("9", "Freshman"),
        ("10", "Sophomore"),
        ("11", "Junior"),
        ("12", "Senior")
    ]

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                if showSuccessScreen {
                    successScreen
                } else {
                    registrationForm
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    connectionIndicator
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Exit Kiosk") {
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingConnectionDetails) {
                connectionDetailsSheet
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            Task {
                await loadNextSubjectID()
                await loadTotalRegistered()
                multipeerSync.startAdvertising(jobId: sportsJobId)
                gradeTeam = defaultGrade
            }
        }
        .onDisappear {
            multipeerSync.disconnect()
            autoAdvanceTimer?.invalidate()
        }
    }

    // MARK: - Registration Form

    private var registrationForm: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text(schoolName.uppercased())
                    .font(.title.bold())
                Text("Registration")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 16)
            .padding(.bottom, 12)

            // 2-Column Layout
            HStack(alignment: .top, spacing: 24) {
                // LEFT COLUMN: Required fields
                VStack(spacing: 16) {
                    // First Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("First Name")
                            .font(.headline)
                        TextField("First", text: $firstName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 22))
                            .padding(4)
                            .focused($firstNameFocused)
                            .submitLabel(.next)
                            .autocapitalization(.words)
                            .autocorrectionDisabled()
                            .onSubmit {
                                lastNameFocused = true
                            }
                    }

                    // Last Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last Name")
                            .font(.headline)
                        TextField("Last", text: $lastName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 22))
                            .padding(4)
                            .focused($lastNameFocused)
                            .submitLabel(.done)
                            .autocapitalization(.words)
                            .autocorrectionDisabled()
                            .onSubmit {
                                lastNameFocused = false
                            }
                    }

                    // Submit button
                    Button {
                        Task { await submitRegistration() }
                    } label: {
                        Text("Submit")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background((firstName.isEmpty || lastName.isEmpty) ? Color.gray : Color.blue)
                            .cornerRadius(12)
                    }
                    .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty || lastName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.top, 8)

                    // Stats
                    Text("Athletes registered: \(totalRegistered)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)

                // RIGHT COLUMN: Optional fields
                VStack(spacing: 16) {
                    // Grade/Team
                    if !gradeTeam.isEmpty || !defaultGrade.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Grade/Level (optional)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("Optional", text: $gradeTeam)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 18))
                        }
                    }

                    // Email
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Parent Email (optional)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("parent@email.com", text: $emailInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 18))
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }

                    // Phone
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Parent Phone (optional)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("555-1234", text: $phoneInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 18))
                            .keyboardType(.phonePad)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Success Screen

    private var successScreen: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("Success!")
                .font(.largeTitle.bold())

            VStack(spacing: 8) {
                Text("You're Athlete #\(lastAssignedNumber)")
                    .font(.title.bold())
                    .foregroundColor(.blue)

                Text("Remember this number for photos!")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                resetForm()
            } label: {
                HStack {
                    Text("Next Athlete")
                    Image(systemName: "arrow.right")
                }
                .font(.title2.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .onAppear {
            // Auto-advance after 3 seconds
            autoAdvanceTimer?.invalidate()
            autoAdvanceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                resetForm()
            }
        }
    }

    // MARK: - Connection Indicator

    private var connectionIndicator: some View {
        Button(action: { showingConnectionDetails = true }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(multipeerSync.isConnected ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    if multipeerSync.isConnected {
                        Text("✓ \(multipeerSync.connectedPeers.count) photographer(s)")
                            .font(.caption)
                            .foregroundColor(.green)
                            .fontWeight(.semibold)
                        Text("Tap for details")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("⏳ Waiting for photographer...")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .fontWeight(.semibold)
                        Text("Bluetooth + WiFi enabled?")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
    }

    private var connectionDetailsSheet: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(multipeerSync.isConnected ? "Connected" : "Not Connected")
                            .foregroundColor(multipeerSync.isConnected ? .green : .orange)
                    }

                    HStack {
                        Text("Service Type")
                        Spacer()
                        Text("iconik-roster")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !multipeerSync.connectedPeers.isEmpty {
                    Section("Connected Photographers (\(multipeerSync.connectedPeers.count))") {
                        ForEach(multipeerSync.connectedPeers, id: \.displayName) { peer in
                            HStack {
                                Image(systemName: "ipad")
                                    .foregroundColor(.blue)
                                Text(peer.displayName)
                                    .font(.body)
                                Spacer()
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                } else {
                    Section {
                        VStack(alignment: .center, spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                            Text("No photographers connected")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Make sure photographer devices have Bluetooth and WiFi enabled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                }
            }
            .navigationTitle("Kiosk Connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingConnectionDetails = false
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadNextSubjectID() async {
        do {
            let entries = try await PowerSyncManager.shared.getRosterEntries(forJob: sportsJobId)
            let subjectIDs = entries.compactMap { Int($0.firstName) }
            nextSubjectID = (subjectIDs.max() ?? 100) + 1
            print("RegistrationKioskView: Next Subject ID set to \(nextSubjectID)")
        } catch {
            print("RegistrationKioskView: Failed to load next subject ID: \(error)")
            errorMessage = "Failed to load roster data: \(error.localizedDescription)"
            showError = true
        }
    }

    private func loadTotalRegistered() async {
        do {
            let entries = try await PowerSyncManager.shared.getRosterEntries(forJob: sportsJobId)
            totalRegistered = entries.count
            print("RegistrationKioskView: Total registered: \(totalRegistered)")
        } catch {
            print("RegistrationKioskView: Failed to load total registered: \(error)")
        }
    }

    // MARK: - Registration Submission

    private func submitRegistration() async {
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespaces)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespaces)

        guard !trimmedFirst.isEmpty && !trimmedLast.isEmpty else {
            errorMessage = "First and last name are required"
            showError = true
            return
        }

        // Combine as "FIRST LAST" format, uppercased
        let formattedName = "\(trimmedFirst) \(trimmedLast)".uppercased()

        // Format emails and phones to Captura format (no spaces after commas)
        let formattedEmail = formatForCaptura(emailInput)
        let formattedPhone = formatForCaptura(phoneInput)

        // Create roster entry
        let entry = RosterEntry(
            id: UUID(),
            sportsJobId: sportsJobId,
            organizationId: organizationId,
            lastName: formattedName,
            firstName: String(nextSubjectID),
            teacher: gradeTeam,
            groupName: defaultSportTeam.uppercased(),
            email: formattedEmail,
            phone: formattedPhone,
            imageNumbers: "",
            notes: "",
            sortOrder: nextSubjectID - 100
        )

        do {
            // Save to PowerSync (local + will sync to Supabase when online)
            try await PowerSyncManager.shared.saveRosterEntry(entry)
            print("RegistrationKioskView: Saved roster entry \(entry.id) for athlete #\(nextSubjectID)")

            // Broadcast to connected peers via Multipeer
            multipeerSync.broadcastRosterEntry(entry)
            print("RegistrationKioskView: Broadcasted roster entry to peers")

            // Update state
            lastAssignedNumber = nextSubjectID
            nextSubjectID += 1
            totalRegistered += 1

            // Show success screen
            withAnimation {
                showSuccessScreen = true
            }

            // Haptic feedback
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        } catch {
            print("RegistrationKioskView: Failed to save registration: \(error)")
            errorMessage = "Failed to save registration: \(error.localizedDescription)"
            showError = true
        }
    }

    // MARK: - Form Management

    private func resetForm() {
        withAnimation {
            showSuccessScreen = false
        }

        // Clear form
        firstName = ""
        lastName = ""
        emailInput = ""
        phoneInput = ""
        gradeTeam = defaultGrade

        // Auto-focus first name field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            firstNameFocused = true
        }

        // Invalidate timer
        autoAdvanceTimer?.invalidate()
    }

    // MARK: - Formatting Helpers

    /// Parse name input and format as "LAST, FIRST"
    private func parseName(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        // If already has comma, keep as is
        if trimmed.contains(",") {
            return trimmed
        }

        // Parse "First Last" → "LAST, FIRST"
        let parts = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            let last = parts.last!
            let first = parts.dropLast().joined(separator: " ")
            return "\(last), \(first)"
        }

        // Single name - return as is
        return trimmed
    }

    /// Format email/phone input to Captura format (comma-separated, no spaces)
    /// Input: "mom@email.com, dad@email.com" or "mom@email.com dad@email.com"
    /// Output: "mom@email.com,dad@email.com"
    private func formatForCaptura(_ input: String) -> String {
        input.components(separatedBy: CharacterSet(charactersIn: ",;\n "))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")  // NO SPACE after comma
    }
}

// MARK: - Preview

struct RegistrationKioskView_Previews: PreviewProvider {
    static var previews: some View {
        RegistrationKioskView(
            sportsJobId: UUID(),
            organizationId: "",
            schoolName: "Lincoln Elementary",
            defaultSportTeam: "FOOTBALL",
            defaultGrade: "8"
        )
    }
}
