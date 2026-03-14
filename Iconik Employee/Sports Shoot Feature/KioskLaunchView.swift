//
//  KioskLaunchView.swift
//  Iconik Employee
//
//  Kiosk configuration screen
//  Allows photographer to configure default settings before launching registration kiosk
//

import SwiftUI

struct KioskLaunchView: View {

    // MARK: - Properties

    let sportsJobId: UUID
    let organizationId: String
    let schoolName: String

    @Environment(\.dismiss) private var dismiss

    // MARK: - Configuration State

    @State private var defaultSportTeam: String = ""
    @State private var defaultGrade: String = ""
    @State private var kioskPasscode: String = ""

    // MARK: - Navigation State

    @State private var showKioskView = false

    // MARK: - Sport/Team Options

    private let sportOptions = [
        "FOOTBALL",
        "BASKETBALL",
        "SOCCER",
        "VOLLEYBALL",
        "BASEBALL",
        "SOFTBALL",
        "TRACK & FIELD",
        "CROSS COUNTRY",
        "SWIMMING",
        "WRESTLING",
        "TENNIS",
        "GOLF",
        "CHEERLEADING",
        "DANCE"
    ]

    // MARK: - Grade Options

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
            Form {
                Section {
                    Text(schoolName)
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                } header: {
                    Text("School")
                }

                Section {
                    HStack {
                        TextField("e.g. FOOTBALL, Spring Photos, Class of 2025", text: $defaultSportTeam)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.allCharacters)

                        // Quick select menu for common sports
                        Menu {
                            ForEach(sportOptions, id: \.self) { sport in
                                Button(sport) {
                                    defaultSportTeam = sport
                                }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                                .foregroundColor(.blue)
                                .padding(8)
                        }
                    }
                } header: {
                    Text("Default Sport/Team/Event (Required)")
                } footer: {
                    Text("Type anything or use the menu (•••) for common sports. This will be the default groupName for all athletes.")
                }

                Section {
                    HStack {
                        TextField("Leave blank or enter default (optional)", text: $defaultGrade)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.allCharacters)

                        // Quick select menu for grades
                        Menu {
                            Button("None (blank)") {
                                defaultGrade = ""
                            }
                            Divider()
                            ForEach(gradeOptions, id: \.0) { value, label in
                                Button(label) {
                                    defaultGrade = value
                                }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                                .foregroundColor(.blue)
                                .padding(8)
                        }
                    }
                } header: {
                    Text("Default Grade/Level (Optional)")
                } footer: {
                    Text("Athletes can enter their own grade during registration. Leave blank if not needed.")
                }

                Section {
                    SecureField("Enter passcode (optional)", text: $kioskPasscode)
                        .textContentType(.password)
                } header: {
                    Text("Exit Passcode (Optional)")
                } footer: {
                    Text("If set, this passcode will be required to exit kiosk mode. Leave blank for no passcode protection.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Athletes register themselves", systemImage: "person.fill.checkmark")
                        Label("Syncs to photographer iPad via Multipeer", systemImage: "laptopcomputer.and.ipad")
                        Label("Works offline (no internet needed)", systemImage: "wifi.slash")
                        Label("Auto-assigns Subject IDs", systemImage: "number")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                } header: {
                    Text("How It Works")
                }
            }
            .navigationTitle("Configure Kiosk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Start Kiosk") {
                        startKioskMode()
                    }
                    .disabled(defaultSportTeam.isEmpty)
                    .fontWeight(.bold)
                }
            }
            .fullScreenCover(isPresented: $showKioskView) {
                RegistrationKioskView(
                    sportsJobId: sportsJobId,
                    organizationId: organizationId,
                    schoolName: schoolName,
                    defaultSportTeam: defaultSportTeam,
                    defaultGrade: defaultGrade
                )
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Actions

    private func startKioskMode() {
        guard !defaultSportTeam.isEmpty else { return }

        // Launch kiosk view in full screen
        showKioskView = true
    }
}

// MARK: - Preview

struct KioskLaunchView_Previews: PreviewProvider {
    static var previews: some View {
        KioskLaunchView(
            sportsJobId: UUID(),
            organizationId: "",
            schoolName: "Lincoln Elementary"
        )
    }
}
