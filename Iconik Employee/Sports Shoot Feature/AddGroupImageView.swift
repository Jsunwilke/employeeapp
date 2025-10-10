//
//  AddGroupImageView.swift
//  Iconik Employee
//
//  Created by administrator on 5/13/25.
//


import SwiftUI
import Firebase
import FirebaseFirestore

struct AddGroupImageView: View {
    let shootID: String
    let existingGroup: GroupImage?
    let sportsShoot: SportsShoot?  // Pass the sports shoot to get available sports
    let onComplete: (Bool) -> Void
    
    @State private var description: String = ""
    @State private var imageNumbers: String = ""
    @State private var notes: String = ""
    @State private var selectedSport: String = ""
    @State private var selectedGender: String = ""
    @State private var selectedTeamLevel: String = ""
    @State private var useCustomDescription: Bool = false
    
    // Gender options
    let genderOptions = ["Boys", "Girls", "Co-ed"]
    
    // Team level options
    let teamLevels = ["Varsity", "Junior Varsity (JV)", "C-Team", "Freshman", "Sophomore", "Modified", "Custom"]
    
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    
    @Environment(\.presentationMode) var presentationMode
    
    var isEditing: Bool {
        existingGroup != nil
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Group Information")) {
                    // Sport selection
                    if let availableSports = availableSports, !availableSports.isEmpty {
                        Picker("Sport/Team", selection: $selectedSport) {
                            Text("Select Sport").tag("")
                            ForEach(availableSports, id: \.self) { sport in
                                Text(sport).tag(sport)
                            }
                        }
                        .onChange(of: selectedSport) { _ in
                            updateDescription()
                        }
                    }
                    
                    // Gender selection
                    if !selectedSport.isEmpty {
                        Picker("Gender", selection: $selectedGender) {
                            Text("Select Gender (Optional)").tag("")
                            ForEach(genderOptions, id: \.self) { gender in
                                Text(gender).tag(gender)
                            }
                        }
                        .onChange(of: selectedGender) { _ in
                            updateDescription()
                        }
                    }
                    
                    // Team level selection
                    if !selectedSport.isEmpty {
                        Picker("Team Level", selection: $selectedTeamLevel) {
                            Text("Select Level").tag("")
                            ForEach(teamLevels, id: \.self) { level in
                                Text(level).tag(level)
                            }
                        }
                        .onChange(of: selectedTeamLevel) { _ in
                            updateDescription()
                        }
                    }
                    
                    // Description field
                    VStack(alignment: .leading) {
                        Toggle("Custom Description", isOn: $useCustomDescription)
                            .font(.caption)
                        
                        TextField("Description", text: $description)
                            .autocapitalization(.sentences)
                            .disabled(!useCustomDescription && !selectedSport.isEmpty)
                    }
                }
                
                Section(header: Text("Image Information")) {
                    TextField("Image Numbers", text: $imageNumbers)
                        .keyboardType(.asciiCapable)
                        .autocapitalization(.none)
                    
                    TextView(text: $notes, placeholder: "Notes (optional)")
                        .frame(minHeight: 100)
                }
                
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
            .navigationBarTitle(isEditing ? "Edit Group" : "Add Group", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Update" : "Save") {
                        saveGroupImage()
                    }
                    .disabled(description.isEmpty)
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
                if let group = existingGroup {
                    description = group.description
                    imageNumbers = group.imageNumbers
                    notes = group.notes
                    selectedSport = group.sport ?? ""
                    selectedGender = group.gender ?? ""
                    selectedTeamLevel = group.teamLevel ?? ""
                    // Check if description was auto-generated
                    useCustomDescription = !isAutoGeneratedDescription()
                } else {
                    // For new groups, check if there's only one sport in the roster
                    if let sports = availableSports, sports.count == 1 {
                        selectedSport = sports[0]
                        updateDescription()
                    }
                }
            }
        }
    }
    
    // Computed property to get available sports from roster
    private var availableSports: [String]? {
        guard let shoot = sportsShoot else { return nil }
        let allGroups = Set(shoot.roster.map { $0.group })
        return Array(allGroups).filter { !$0.isEmpty }.sorted()
    }
    
    // Update description based on selections
    private func updateDescription() {
        guard !useCustomDescription else { return }
        
        if !selectedSport.isEmpty {
            var components = [selectedSport]
            
            if !selectedGender.isEmpty {
                components.append(selectedGender)
            }
            
            if !selectedTeamLevel.isEmpty && selectedTeamLevel != "Custom" {
                components.append(selectedTeamLevel)
            }
            
            description = components.joined(separator: " - ")
        }
    }
    
    // Check if current description matches auto-generated format
    private func isAutoGeneratedDescription() -> Bool {
        if selectedSport.isEmpty { return false }
        
        var components = [selectedSport]
        
        if !selectedGender.isEmpty {
            components.append(selectedGender)
        }
        
        if !selectedTeamLevel.isEmpty && selectedTeamLevel != "Custom" {
            components.append(selectedTeamLevel)
        }
        
        let expectedDescription = components.joined(separator: " - ")
        return description == expectedDescription
    }
    
    private func saveGroupImage() {
        isLoading = true
        
        let group = GroupImage(
            id: existingGroup?.id ?? UUID().uuidString,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            imageNumbers: imageNumbers.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            sport: selectedSport.isEmpty ? nil : selectedSport,
            gender: selectedGender.isEmpty ? nil : selectedGender,
            teamLevel: selectedTeamLevel.isEmpty ? nil : selectedTeamLevel
        )
        
        if isEditing {
            SportsShootService.shared.updateGroupImage(shootID: shootID, groupImage: group) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    switch result {
                    case .success:
                        self.onComplete(true)
                        self.presentationMode.wrappedValue.dismiss()
                    case .failure(let error):
                        self.errorMessage = "Failed to update group: \(error.localizedDescription)"
                        self.showingErrorAlert = true
                    }
                }
            }
        } else {
            SportsShootService.shared.addGroupImage(shootID: shootID, groupImage: group) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    switch result {
                    case .success:
                        self.onComplete(true)
                        self.presentationMode.wrappedValue.dismiss()
                    case .failure(let error):
                        self.errorMessage = "Failed to add group: \(error.localizedDescription)"
                        self.showingErrorAlert = true
                    }
                }
            }
        }
    }
}

struct AddGroupImageView_Previews: PreviewProvider {
    static var previews: some View {
        AddGroupImageView(
            shootID: "previewID",
            existingGroup: nil,
            sportsShoot: nil,
            onComplete: { _ in }
        )
    }
}