import SwiftUI
import Firebase
import FirebaseFirestore

struct BatchAddAthletesView: View {
    let shootID: String
    let onComplete: (Bool) -> Void
    
    @State private var sportName: String = ""
    @State private var numberOfAthletes: String = "10"
    @State private var startingSubjectID: Int = 101
    @State private var specialField: String = ""
    
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var isLoadingExisting = true
    
    @Environment(\.presentationMode) var presentationMode
    
    // Computed property for preview entries
    private var previewEntries: [RosterEntry] {
        guard let count = Int(numberOfAthletes),
              count > 0,
              count <= 100 else { return [] }
        
        return (0..<count).map { index in
            RosterEntry(
                id: UUID().uuidString,
                lastName: "",  // Will be filled in later by user
                firstName: "\(startingSubjectID + index)",
                teacher: specialField,
                group: sportName,
                email: "",
                phone: "",
                imageNumbers: "",
                notes: "",
                wasBlank: true,
                isFilledBlank: false
            )
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Batch Configuration")) {
                    TextField("Sport/Team Name", text: $sportName)
                        .autocapitalization(.words)
                    
                    HStack {
                        Text("Number of Athletes")
                        Spacer()
                        TextField("10", text: $numberOfAthletes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                    
                    TextField("Grade/Special (optional)", text: $specialField)
                        .autocapitalization(.words)
                    
                    HStack {
                        Text("Starting Subject ID")
                        Spacer()
                        if isLoadingExisting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("\(startingSubjectID)")
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                        }
                    }
                }
                
                Section(header: Text("Preview (\(previewEntries.count) athletes)")) {
                    if previewEntries.isEmpty {
                        Text("Enter valid number of athletes (1-100)")
                            .foregroundColor(.secondary)
                            .italic()
                    } else if previewEntries.count > 20 {
                        // Show first 5 and last 5 for large batches
                        ForEach(previewEntries.prefix(5)) { entry in
                            previewRow(for: entry)
                        }
                        
                        HStack {
                            Spacer()
                            Text("... \(previewEntries.count - 10) more entries ...")
                                .foregroundColor(.secondary)
                                .italic()
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        
                        ForEach(previewEntries.suffix(5)) { entry in
                            previewRow(for: entry)
                        }
                    } else {
                        ForEach(previewEntries) { entry in
                            previewRow(for: entry)
                        }
                    }
                }
                
                Section(header: Text("Notes")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Athletes will be created with blank names")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("• Subject IDs will auto-increment from \(startingSubjectID)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("• You can edit individual athletes after creation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Creating athletes...")
                        Spacer()
                    }
                }
            }
            .navigationBarTitle("Batch Add Athletes", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add Athletes") {
                        batchAddAthletes()
                    }
                    .fontWeight(.semibold)
                    .disabled(sportName.isEmpty || previewEntries.isEmpty || isLoading)
                }
            }
            .alert(isPresented: $showingErrorAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .onAppear {
            loadHighestSubjectID()
        }
    }
    
    @ViewBuilder
    private func previewRow(for entry: RosterEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("ID: \(entry.firstName)")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                Spacer()
                
                if !entry.group.isEmpty {
                    Text(entry.group)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            if !entry.teacher.isEmpty {
                Text("Special: \(entry.teacher)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("(Name to be added later)")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding(.vertical, 2)
    }
    
    private func loadHighestSubjectID() {
        isLoadingExisting = true
        
        SportsShootService.shared.fetchSportsShoot(id: shootID) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let shoot):
                    // Find the highest Subject ID value
                    let highestID = shoot.roster.compactMap { entry -> Int? in
                        return Int(entry.firstName)
                    }.max() ?? 100
                    
                    self.startingSubjectID = highestID + 1
                    self.isLoadingExisting = false
                    
                case .failure(let error):
                    print("Error loading sports shoot: \(error.localizedDescription)")
                    // Use default starting ID
                    self.startingSubjectID = 101
                    self.isLoadingExisting = false
                }
            }
        }
    }
    
    private func batchAddAthletes() {
        guard !sportName.isEmpty,
              let count = Int(numberOfAthletes),
              count > 0,
              count <= 100 else {
            errorMessage = "Please enter valid sport name and number of athletes (1-100)"
            showingErrorAlert = true
            return
        }
        
        isLoading = true
        
        // Create the roster entries
        let entriesToAdd = previewEntries
        
        // Batch save to Firestore
        SportsShootService.shared.batchAddRosterEntries(shootID: shootID, entries: entriesToAdd) { success, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if success {
                    onComplete(true)
                    presentationMode.wrappedValue.dismiss()
                } else {
                    errorMessage = error?.localizedDescription ?? "Failed to add athletes"
                    showingErrorAlert = true
                }
            }
        }
    }
}

// Preview
struct BatchAddAthletesView_Previews: PreviewProvider {
    static var previews: some View {
        BatchAddAthletesView(shootID: "preview-id") { _ in }
    }
}