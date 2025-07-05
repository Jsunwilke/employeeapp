import SwiftUI
import UniformTypeIdentifiers
import Firebase
import FirebaseFirestore

struct CSVImportExportView: View {
    let shootID: String
    let onComplete: (Bool) -> Void
    
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var importedRoster: [RosterEntry] = []
    @State private var currentShoot: SportsShoot?
    @State private var isLoading = true
    
    // Field mapping labels with updated display names
    let fieldMappings = [
        "Name (Last Name) → Name",
        "Subject ID (First Name) → Subject ID",
        "Special (Teacher) → Special",
        "Sport/Team (Group) → Sport/Team"
    ]
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading...")
                } else {
                    Form {
                        Section(header: Text("Import/Export")) {
                            Button(action: {
                                isImporting = true
                            }) {
                                Label("Import CSV", systemImage: "square.and.arrow.down")
                            }
                            
                            Button(action: {
                                if let shoot = currentShoot {
                                    exportCSV(roster: shoot.roster)
                                }
                            }) {
                                Label("Export CSV", systemImage: "square.and.arrow.up")
                            }
                        }
                        
                        Section(header: Text("Field Mapping")) {
                            ForEach(fieldMappings, id: \.self) { mapping in
                                Text(mapping)
                                    .font(.subheadline)
                            }
                            
                            Text("The 'Images' field contains data added by photographers")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                        
                        if !importedRoster.isEmpty {
                            Section(header: Text("Preview")) {
                                ForEach(importedRoster.prefix(5)) { entry in
                                    VStack(alignment: .leading) {
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
                                }
                                
                                if importedRoster.count > 5 {
                                    Text("... and \(importedRoster.count - 5) more entries")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Button(action: {
                                    saveImportedRoster()
                                }) {
                                    Label("Save Imported Roster", systemImage: "checkmark.circle")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("CSV Import/Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onComplete(false)
                    }
                }
            }
            .sheet(isPresented: $isImporting) {
                DocumentPicker(
                    onDocumentPicked: { url in
                        importCSV(from: url)
                    }
                )
            }
            .onAppear {
                loadSportsShoot()
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    private func loadSportsShoot() {
        isLoading = true
        
        SportsShootService.shared.fetchSportsShoot(id: shootID) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(let shoot):
                    currentShoot = shoot
                case .failure(let error):
                    alertTitle = "Error"
                    alertMessage = "Failed to load sports shoot: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    private func importCSV(from url: URL) {
        do {
            let csvData = try String(contentsOf: url)
            
            // Parse CSV using the SportShootService
            importedRoster = SportsShootService.shared.importRosterFromCSV(csvString: csvData)
            
            if importedRoster.isEmpty {
                alertTitle = "Import Error"
                alertMessage = "No valid entries found in the CSV file. Please check the format."
                showAlert = true
            } else {
                alertTitle = "Import Success"
                alertMessage = "Successfully imported \(importedRoster.count) entries. Review and save to confirm."
                showAlert = true
            }
        } catch {
            alertTitle = "Import Error"
            alertMessage = "Failed to read the CSV file: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func saveImportedRoster() {
        guard !importedRoster.isEmpty else { return }
        
        isLoading = true
        
        // Use a dispatch group to track all operations
        let group = DispatchGroup()
        var errorOccurred = false
        
        // Add each entry to the sports shoot
        for entry in importedRoster {
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
            isLoading = false
            
            if errorOccurred {
                alertTitle = "Import Error"
                alertMessage = "Some entries could not be added. Please try again."
                showAlert = true
            } else {
                alertTitle = "Import Complete"
                alertMessage = "Successfully added \(importedRoster.count) entries to the roster."
                showAlert = true
                
                // Clear imported roster after saving
                importedRoster = []
                
                // Notify completion
                onComplete(true)
            }
        }
    }
    
    private func exportCSV(roster: [RosterEntry]) {
        guard !roster.isEmpty else {
            alertTitle = "Export Error"
            alertMessage = "No roster entries to export."
            showAlert = true
            return
        }
        
        // Generate CSV with updated column names
        let csvString = generateCSVWithUpdatedColumnNames(roster: roster)
        
        // Create a temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "Roster_\(Date().timeIntervalSince1970).csv"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Share the file
            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            
            // Present the share sheet
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.present(activityVC, animated: true, completion: nil)
            }
        } catch {
            alertTitle = "Export Error"
            alertMessage = "Failed to create export file: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    // Custom CSV generation with updated column names
    private func generateCSVWithUpdatedColumnNames(roster: [RosterEntry]) -> String {
        // Create header row with mapped fields (display names)
        var csv = "Name,Subject ID,Special,Sport/Team,Email,Phone,Images\n"
        
        // Add entries
        for entry in roster {
            let escapedLastName = escapeCSVField(entry.lastName)
            let escapedFirstName = escapeCSVField(entry.firstName)
            let escapedTeacher = escapeCSVField(entry.teacher)
            let escapedGroup = escapeCSVField(entry.group)
            let escapedEmail = escapeCSVField(entry.email)
            let escapedPhone = escapeCSVField(entry.phone)
            let escapedImageNumbers = escapeCSVField(entry.imageNumbers)
            
            csv += "\(escapedLastName),\(escapedFirstName),\(escapedTeacher),\(escapedGroup),\(escapedEmail),\(escapedPhone),\(escapedImageNumbers)\n"
        }
        
        return csv
    }
    
    // Helper to escape CSV fields
    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
}

// Document Picker for importing CSV files
struct DocumentPicker: UIViewControllerRepresentable {
    var onDocumentPicked: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Use UTType.commaSeparatedText for CSV files
        let csvUTType = UTType.commaSeparatedText
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [csvUTType])
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {
        // Nothing to update
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                // Handle the failure here
                return
            }
            
            // Make sure you release the security-scoped resource when finished
            defer { url.stopAccessingSecurityScopedResource() }
            
            parent.onDocumentPicked(url)
        }
    }
}

extension Date {
    func formatForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: self)
    }
}
