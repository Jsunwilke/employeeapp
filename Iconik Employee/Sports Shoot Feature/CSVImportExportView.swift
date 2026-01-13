import SwiftUI
import UniformTypeIdentifiers

struct CSVImportExportView: View {
    let shootID: UUID
    let onComplete: (Bool) -> Void

    @State private var isImporting = false
    @State private var isExporting = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var importedRoster: [RosterEntry] = []
    @State private var currentRoster: [RosterEntry] = []
    @State private var isLoading = true

    // New state for photo import
    @State private var showPhotoImport = false
    @State private var showMultiPhotoImport = false

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
                            // New multi-photo import button
                            Button(action: {
                                showMultiPhotoImport = true
                            }) {
                                Label("Import Paper Rosters", systemImage: "doc.viewfinder")
                                    .foregroundColor(.blue)
                            }

                            // Single photo import button
                            Button(action: {
                                showPhotoImport = true
                            }) {
                                Label("Import from Photo", systemImage: "camera")
                                    .foregroundColor(.blue)
                            }

                            Button(action: {
                                isImporting = true
                            }) {
                                Label("Import CSV", systemImage: "square.and.arrow.down")
                            }

                            Button(action: {
                                exportCSV(roster: currentRoster)
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

                                        if !entry.groupName.isEmpty {
                                            Text("Sport/Team: \(entry.groupName)")
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
            .navigationTitle("Import/Export")
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
            .sheet(isPresented: $showPhotoImport) {
                RosterPhotoImporterView(
                    shootID: shootID,
                    onComplete: { success in
                        if success {
                            // If successfully imported via photo, reload roster data
                            loadRosterEntries()
                            onComplete(true)
                        }
                        showPhotoImport = false
                    }
                )
            }
            .sheet(isPresented: $showMultiPhotoImport) {
                MultiPhotoRosterImporterView(
                    shootID: shootID,
                    onComplete: { success in
                        if success {
                            // If successfully imported via multi-photo, reload roster data
                            loadRosterEntries()
                            onComplete(true)
                        }
                        showMultiPhotoImport = false
                    }
                )
            }
            .onAppear {
                loadRosterEntries()
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

    private func loadRosterEntries() {
        isLoading = true

        Task {
            do {
                let entries = try await RosterEntryService.shared.fetchEntries(forJob: shootID)
                await MainActor.run {
                    currentRoster = entries
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    alertTitle = "Error"
                    alertMessage = "Failed to load roster: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    private func importCSV(from url: URL) {
        do {
            let csvData = try String(contentsOf: url)

            // Parse CSV locally
            importedRoster = parseCSV(csvString: csvData)

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

    // Parse CSV string into RosterEntry array
    private func parseCSV(csvString: String) -> [RosterEntry] {
        var entries: [RosterEntry] = []
        let lines = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }

        guard lines.count > 1 else { return entries }

        // Parse header to determine column indices
        let header = parseCSVLine(lines[0])
        let headerLower = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        // Find column indices
        let nameIndex = headerLower.firstIndex(of: "name") ?? headerLower.firstIndex(of: "last_name") ?? headerLower.firstIndex(of: "lastname")
        let subjectIdIndex = headerLower.firstIndex(of: "subject id") ?? headerLower.firstIndex(of: "subjectid") ?? headerLower.firstIndex(of: "first_name") ?? headerLower.firstIndex(of: "firstname")
        let specialIndex = headerLower.firstIndex(of: "special") ?? headerLower.firstIndex(of: "teacher")
        let sportIndex = headerLower.firstIndex(of: "sport/team") ?? headerLower.firstIndex(of: "sport") ?? headerLower.firstIndex(of: "team") ?? headerLower.firstIndex(of: "group") ?? headerLower.firstIndex(of: "group_name")
        let emailIndex = headerLower.firstIndex(of: "email")
        let phoneIndex = headerLower.firstIndex(of: "phone")
        let imagesIndex = headerLower.firstIndex(of: "images") ?? headerLower.firstIndex(of: "image_numbers")

        // Parse data rows
        for i in 1..<lines.count {
            let fields = parseCSVLine(lines[i])
            guard !fields.isEmpty else { continue }

            let entry = RosterEntry(
                sportsJobId: shootID,
                lastName: nameIndex != nil && fields.count > nameIndex! ? fields[nameIndex!] : "",
                firstName: subjectIdIndex != nil && fields.count > subjectIdIndex! ? fields[subjectIdIndex!] : "",
                teacher: specialIndex != nil && fields.count > specialIndex! ? fields[specialIndex!] : "",
                groupName: (sportIndex != nil && fields.count > sportIndex! ? fields[sportIndex!] : "").uppercased(),
                email: emailIndex != nil && fields.count > emailIndex! ? fields[emailIndex!] : "",
                phone: phoneIndex != nil && fields.count > phoneIndex! ? fields[phoneIndex!] : "",
                imageNumbers: imagesIndex != nil && fields.count > imagesIndex! ? fields[imagesIndex!] : "",
                sortOrder: i - 1
            )
            entries.append(entry)
        }

        return entries
    }

    // Parse a single CSV line, handling quoted fields
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var insideQuotes = false

        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                fields.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        fields.append(currentField.trimmingCharacters(in: .whitespaces))

        return fields
    }

    private func saveImportedRoster() {
        guard !importedRoster.isEmpty else { return }

        isLoading = true

        Task {
            do {
                // Use batch create for efficiency
                _ = try await RosterEntryService.shared.createEntries(importedRoster)

                await MainActor.run {
                    isLoading = false
                    alertTitle = "Import Complete"
                    alertMessage = "Successfully added \(importedRoster.count) entries to the roster."
                    showAlert = true

                    // Clear imported roster after saving
                    importedRoster = []

                    // Reload current roster
                    loadRosterEntries()

                    // Notify completion
                    onComplete(true)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    alertTitle = "Import Error"
                    alertMessage = "Failed to save entries: \(error.localizedDescription)"
                    showAlert = true
                }
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
            let escapedGroup = escapeCSVField(entry.groupName)
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
